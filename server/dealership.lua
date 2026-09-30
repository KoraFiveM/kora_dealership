-- Server-authoritative vehicle, money, stock and offer operations.

local State = Dealership.state
local Schema = Dealership.schema
local Api = {}
Dealership.api = Api
local settlementLocks = {}
local testDrives = {}

local function sharedVehicle(model)
    local vehicle = type(model) == 'string' and exports.qbcore:getShared('vehicles', model) or nil
    if type(vehicle) ~= 'table' or vehicle.model ~= model then return nil, 'Unknown vehicle.' end
    local price = math.floor(tonumber(vehicle.price) or 0)
    if price < 1 or price > Config.maxPrice then return nil, 'Vehicle is not priced for sale.' end
    return vehicle, price
end

local function configuredVehicle(dealer, model)
    for _, allowed in ipairs(dealer.vehicles) do
        if allowed == model then return sharedVehicle(model) end
    end
    return nil, 'Vehicle is not sold here.'
end

local function salePrice(dealer, model)
    local vehicle, basePrice = configuredVehicle(dealer, model)
    if not vehicle then return nil, basePrice end
    return math.floor(dealer.prices[model] or basePrice), vehicle, basePrice
end

local function canAutomaticallyAccept(dealer, offer)
    if not Config.AutoAccept.enabled or not dealer.autoAccept or offer.terms then return false end
    local amount = tonumber(offer.amount)
    if not amount or amount < 1 then return false end
    if offer.direction == 'buy' then
        local price = salePrice(dealer, offer.model)
        return price ~= nil and amount >= price
    end
    if offer.direction ~= 'sell' then return false end
    local vehicle, basePrice = sharedVehicle(offer.model)
    if not vehicle then return false end
    local ceiling = math.min(basePrice, dealer.prices[offer.model] or basePrice)
    return amount <= ceiling
end

local function playerIdentity(src)
    local player = State.player(src)
    if not player or type(player.citizenid) ~= 'string' then return nil, 'Character unavailable.' end
    local info = player.charinfo or {}
    local name = (('%s %s'):format(info.firstname or '', info.lastname or '')):match('^%s*(.-)%s*$')
    return { citizenid = player.citizenid, source = player.source or src, name = name ~= '' and name or player.name or player.citizenid }
end

local function notifyPlayer(src, dealer, message, kind)
    QB.notify.send(src, { title = dealer.label, message = message, type = kind or 'info' })
end

local function allocatePlate()
    local prefix = tostring(Config.platePrefix or 'DLR'):upper():gsub('[^A-Z0-9]', ''):sub(1, 3)
    for _ = 1, Config.plateAttempts do
        local candidate = ('%s%05d'):format(prefix ~= '' and prefix or 'DLR', math.random(0, 99999))
        if not exports.qbcore:getByPlate(candidate) then return candidate end
    end
    return nil, 'Could not allocate a vehicle plate.'
end

local function debitDealer(dealer, amount, reason)
    if not dealer.job then return true end
    if GetResourceState('qbbossmenu') ~= 'started' then return false, 'Business account service unavailable.' end
    return exports.qbbossmenu:removeBusinessMoney(dealer.job, amount, reason)
end

local function creditDealer(dealer, amount, reason)
    if not dealer.job then return true end
    if GetResourceState('qbbossmenu') ~= 'started' then return false, 'Business account service unavailable.' end
    return exports.qbbossmenu:addBusinessMoney(dealer.job, amount, reason)
end

local function takeStock(dealer, model)
    if not dealer.job then return { source = 'npc' } end
    local row = QB.sql.single([[SELECT `id`,`plate`,`source` FROM `qbdealership_stock`
        WHERE `dealership` = ? AND `model` = ? ORDER BY `id` LIMIT 1]], { dealer.id, model })
    if not row then return nil, 'This vehicle is out of stock.' end
    return row
end

local function restoreStock(dealer, model, row)
    if not row or row.source == 'npc' then return end
    QB.sql.execute([[INSERT IGNORE INTO `qbdealership_stock` (`id`,`dealership`,`model`,`plate`,`source`)
        VALUES (?,?,?,?,?)]], { row.id, dealer.id, model, row.plate or QB.sql.NULL, row.source })
end

local function deliverVehicle(citizenid, model, stock)
    if stock.plate then
        local affected, err = QB.sql.update([[UPDATE `player_vehicles` SET `citizenid` = ?, `job` = NULL,
            `state` = 'garaged', `deleted_at` = NULL WHERE `plate` = ? AND `deleted_at` IS NOT NULL]],
            { citizenid, stock.plate })
        if err or affected ~= 1 then return nil, err or 'Traded vehicle could not be transferred.' end
        return stock.plate
    end
    local newPlate, plateErr = allocatePlate()
    if not newPlate then return nil, plateErr end
    local created, createErr = exports.qbcore:createVehicle(citizenid, model, newPlate, nil, Config.vehicle)
    if not created then return nil, createErr or 'Vehicle could not be saved.' end
    return newPlate
end

local function purchaseFor(src, dealer, model, amount, skipNearby)
    if not skipNearby then
        local nearby, nearErr = State.near(src, dealer)
        if not nearby then return false, nearErr end
    end
    local price, vehicleOrErr = salePrice(dealer, model)
    if not price then return false, vehicleOrErr end
    if amount == nil then amount = price end
    amount = math.floor(tonumber(amount) or 0)
    local identity, identityErr = playerIdentity(src)
    if not identity then return false, identityErr end
    local stock, stockErr = takeStock(dealer, model)
    if not stock then return false, stockErr end
    if amount > 0 then
        local charged, chargeErr = exports.qbcore:removeMoney(src, Config.account, amount, 'dealership-purchase')
        if not charged then return false, chargeErr or 'Payment failed.' end
        local credited, creditErr = creditDealer(dealer, amount, 'vehicle-sale')
        if not credited then
            exports.qbcore:addMoney(src, Config.account, amount, 'dealership-refund', true)
            return false, creditErr
        end
    end
    if stock.id then
        local removed, removeErr = QB.sql.update('DELETE FROM `qbdealership_stock` WHERE `id` = ?', { stock.id })
        if removeErr or removed ~= 1 then
            if amount > 0 and dealer.job then debitDealer(dealer, amount, 'vehicle-sale-rollback') end
            if amount > 0 then exports.qbcore:addMoney(src, Config.account, amount, 'dealership-refund', true) end
            return false, removeErr or 'Stock changed before the sale completed.'
        end
    end
    local newPlate, deliveryErr = deliverVehicle(identity.citizenid, model, stock)
    if not newPlate then
        restoreStock(dealer, model, stock)
        if amount > 0 and dealer.job then debitDealer(dealer, amount, 'vehicle-sale-rollback') end
        if amount > 0 then exports.qbcore:addMoney(src, Config.account, amount, 'dealership-refund', true) end
        return false, deliveryErr
    end
    if GetResourceState('qbvehiclekeys') == 'started' then exports.qbvehiclekeys:giveKeys(src, newPlate) end
    local networkId
    if not skipNearby and dealer.purchaseSpawnCoords then
        networkId = exports.qbcore:spawnVehicle(src, newPlate, dealer.purchaseSpawnCoords, dealer.purchaseSpawnCoords.w)
    end
    return { model = model, plate = newPlate, price = amount, networkId = networkId }
end

local function buyPersonalVehicle(src, dealer, model, requestedPlate, amount)
    local identity, identityErr = playerIdentity(src)
    if not identity then return false, identityErr end
    local row = exports.qbcore:getByPlate(requestedPlate)
    if not row or row.citizenid ~= identity.citizenid or row.model ~= model then return false, 'You no longer own that vehicle.' end
    if row.state ~= 'garaged' then return false, 'Store the vehicle in a garage before selling it.' end
    amount = math.floor(tonumber(amount) or 0)
    if amount > 0 then
        local paid, payErr = debitDealer(dealer, amount, 'vehicle-trade-in')
        if not paid then return false, payErr end
        local credited, creditErr = exports.qbcore:addMoney(src, Config.account, amount, 'dealership-trade-in', true)
        if not credited then
            if dealer.job then creditDealer(dealer, amount, 'vehicle-trade-in-rollback') end
            return false, creditErr or 'Payout failed.'
        end
    end
    local ok, sqlErr = QB.sql.transaction({
        { sql = [[UPDATE `player_vehicles` SET `deleted_at` = NOW() WHERE `plate` = ? AND `citizenid` = ?
            AND `state` = 'garaged' AND `deleted_at` IS NULL]], params = { row.plate, identity.citizenid } },
        { sql = [[INSERT INTO `qbdealership_stock` (`dealership`,`model`,`plate`,`source`) VALUES (?,?,?,'trade')]],
            params = { dealer.id, model, row.plate } },
    })
    if not ok then
        if amount > 0 then exports.qbcore:removeMoney(src, Config.account, amount, 'dealership-trade-in-rollback') end
        if amount > 0 and dealer.job then creditDealer(dealer, amount, 'vehicle-trade-in-rollback') end
        return false, sqlErr or 'Ownership transfer failed.'
    end
    if GetResourceState('qbvehiclekeys') == 'started' then exports.qbvehiclekeys:removeKeys(src, row.plate) end
    local listed = false
    for _, allowed in ipairs(dealer.vehicles) do
        if allowed == model then listed = true; break end
    end
    if not listed then
        local candidate = json.decode(json.encode(dealer))
        candidate.vehicles[#candidate.vehicles + 1] = model
        local saved, saveErr = State.persist(candidate)
        if not saved then
            print(('^3[qbdealership]^7 traded stock %s was acquired but catalogue update failed: %s')
                :format(row.plate, tostring(saveErr)))
        end
    end
    return { model = model, plate = row.plate, price = amount }
end

local function offerRow(id)
    return QB.sql.single('SELECT * FROM `qbdealership_offers` WHERE `id` = ?', { id })
end

local function settle(row, useCounter)
    local expectedStatus = useCounter and 'countered' or 'pending'
    if not row or row.status ~= expectedStatus then
        return false, 'Offer is no longer pending.'
    end
    if tonumber(row.settling) == 1 or settlementLocks[row.id] then return false, 'Offer settlement is already in progress.' end
    local dealer = State.get(row.dealership)
    if not dealer then return false, 'Dealership no longer exists.' end
    local player = exports.qbcore:getPlayerByCitizenId(row.citizenid)
    if not player or not player.source then return false, 'Customer must be online to complete the offer.' end
    settlementLocks[row.id] = true
    -- Claim before effects so a restart or failed completion write cannot replay them.
    local claimed, claimErr = QB.sql.update([[UPDATE `qbdealership_offers` SET `settling` = 1
        WHERE `id` = ? AND `status` = ? AND `settling` = 0]], { row.id, expectedStatus })
    if claimErr or claimed ~= 1 then
        settlementLocks[row.id] = nil
        return false, claimErr or 'Offer changed.'
    end
    local amount = tonumber(useCounter and row.counter_amount or row.amount) or 0
    local ok, result, err
    if row.direction == 'buy' then ok, result, err = pcall(purchaseFor, player.source, dealer, row.model, amount, true)
    else ok, result, err = pcall(buyPersonalVehicle, player.source, dealer, row.model, row.plate, amount) end
    if not ok then
        settlementLocks[row.id] = nil
        print(('^1[qbdealership]^7 offer %s settlement errored; claim retained for review: %s'):format(row.id, tostring(result)))
        return false, 'Offer settlement failed; contact a server administrator.'
    end
    if not result then
        local released, releaseErr = QB.sql.update([[UPDATE `qbdealership_offers` SET `settling` = 0
            WHERE `id` = ? AND `status` = ? AND `settling` = 1]], { row.id, expectedStatus })
        settlementLocks[row.id] = nil
        if releaseErr or released ~= 1 then
            print(('^1[qbdealership]^7 offer %s failed but claim release failed: %s'):format(row.id, tostring(releaseErr or 'Offer changed.')))
        end
        return false, err
    end
    local affected, updateErr = QB.sql.update([[UPDATE `qbdealership_offers` SET `status` = 'accepted', `settling` = 0
        WHERE `id` = ? AND `status` = ? AND `settling` = 1]], { row.id, expectedStatus })
    settlementLocks[row.id] = nil
    if updateErr or affected ~= 1 then
        print(('^1[qbdealership]^7 offer %s settled but status update failed; claim retained for review: %s')
            :format(row.id, tostring(updateErr or 'Offer changed.')))
        return result, err
    end
    notifyPlayer(player.source, dealer, ('Your %s offer for %s was accepted.'):format(
        row.direction == 'buy' and 'purchase' or 'sale', row.model), 'success')
    TriggerClientEvent('qbdealership:client:offerUpdated', -1, row.id, 'accepted')
    return result, err
end

function Api.catalogue(src, dealerId)
    local dealer = State.get(dealerId)
    if not dealer or (not dealer.enabled and not State.canManage(src, dealer)) then return nil, 'Unknown dealership.' end
    if not State.canManage(src, dealer) then
        local nearby, nearErr = State.near(src, dealer)
        if not nearby then return nil, nearErr end
    end
    local stock, vehicles = State.stock(dealer.id), {}
    for _, model in ipairs(dealer.vehicles) do
        local price, vehicle, basePrice = salePrice(dealer, model)
        if price then
            vehicles[#vehicles + 1] = { model = model, name = vehicle.name, brand = vehicle.brand,
                price = price, basePrice = basePrice, stock = dealer.job and (stock[model] or 0) or nil }
        end
    end
    return { id = dealer.id, label = dealer.label, dealership = dealer, vehicles = vehicles, stock = stock }
end

function Api.purchase(src, dealerId, model)
    local dealer = State.get(dealerId)
    if not dealer or not dealer.enabled then return false, 'Unknown dealership.' end
    return purchaseFor(src, dealer, model)
end

function Api.testDrive(src, dealerId, model)
    local dealer = State.get(dealerId)
    if not dealer or not dealer.enabled or not dealer.testDriveCoords then return false, 'Test drives are unavailable.' end
    local nearby, nearErr = State.near(src, dealer)
    if not nearby then return false, nearErr end
    local vehicle, vehicleErr = configuredVehicle(dealer, model)
    if not vehicle then return false, vehicleErr end
    if testDrives[src] then return false, 'You already have an active test drive.' end

    local coords = dealer.testDriveCoords
    local entity = CreateVehicle(joaat(model), coords.x, coords.y, coords.z, coords.w, true, false)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false, 'Test-drive vehicle could not be created.' end
    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    local plateText = ('TST%05d'):format(math.random(0, 99999))
    SetVehicleNumberPlateText(entity, plateText)
    local networkId = NetworkGetNetworkIdFromEntity(entity)
    if not networkId or networkId == 0 then DeleteEntity(entity); return false, 'Test-drive vehicle could not be networked.' end
    testDrives[src] = { entity = entity, plate = plateText }
    if GetResourceState('qbvehiclekeys') == 'started' then exports.qbvehiclekeys:giveKeys(src, plateText) end
    SetTimeout(Config.testDriveSeconds * 1000, function()
        local session = testDrives[src]
        if session and session.entity == entity then
            if DoesEntityExist(entity) then DeleteEntity(entity) end
            if GetResourceState('qbvehiclekeys') == 'started' then exports.qbvehiclekeys:removeKeys(src, plateText) end
            testDrives[src] = nil
            TriggerClientEvent('qbdealership:client:testDriveEnded', src)
        end
    end)
    return { networkId = networkId, plate = plateText, seconds = Config.testDriveSeconds }
end

AddEventHandler('playerDropped', function()
    local session = testDrives[source]
    if session and DoesEntityExist(session.entity) then DeleteEntity(session.entity) end
    testDrives[source] = nil
end)

function Api.submitOffer(src, dealerId, payload)
    local dealer = State.get(dealerId)
    if not dealer or not dealer.enabled then return false, 'Unknown dealership.' end
    local nearby, nearErr = State.near(src, dealer)
    if not nearby then return false, nearErr end
    local offer, offerErr = Schema.offer(payload)
    if not offer then return false, offerErr end
    local vehicle, vehicleErr
    if offer.direction == 'sell' then vehicle, vehicleErr = sharedVehicle(offer.model)
    else vehicle, vehicleErr = configuredVehicle(dealer, offer.model) end
    if not vehicle then return false, vehicleErr end
    local identity, identityErr = playerIdentity(src)
    if not identity then return false, identityErr end
    local requestedPlate
    if offer.direction == 'sell' then
        requestedPlate = type(payload.plate) == 'string' and payload.plate:upper():match('^%s*(.-)%s*$') or nil
        local owned = requestedPlate and exports.qbcore:getByPlate(requestedPlate)
        if not owned or owned.citizenid ~= identity.citizenid or owned.model ~= offer.model then return false, 'Select a vehicle you own.' end
    end
    local automatic = canAutomaticallyAccept(dealer, offer)
    local autoDelay = math.max(1, math.floor(tonumber(Config.AutoSellTime) or 1))
    local expiryDelay = math.max(autoDelay, math.floor(tonumber(Config.offerExpirySeconds) or autoDelay))
    local id, insertErr = QB.sql.insert([[INSERT INTO `qbdealership_offers`
        (`dealership`,`direction`,`model`,`plate`,`citizenid`,`customer_name`,`amount`,`terms`,`auto_at`,`expires_at`)
        VALUES (?,?,?,?,?,?,?,?,IF(? = 1, DATE_ADD(NOW(), INTERVAL ? SECOND), NULL),DATE_ADD(NOW(), INTERVAL ? SECOND))]],
        { dealer.id, offer.direction, offer.model, requestedPlate or QB.sql.NULL, identity.citizenid, identity.name,
            offer.amount or QB.sql.NULL, offer.terms or QB.sql.NULL, automatic and 1 or 0, autoDelay, expiryDelay })
    if not id then return false, insertErr or 'Offer could not be saved.' end
    TriggerClientEvent('qbdealership:client:offerUpdated', -1, id, 'pending')
    return { id = id, automatic = automatic, manual = not automatic }
end

function Api.manageOffer(src, id, action, payload)
    local row = offerRow(math.floor(tonumber(id) or 0))
    local dealer = row and State.get(row.dealership)
    if not dealer or not State.canManage(src, dealer) then return false, 'You do not manage this dealership.' end
    if action == 'accept' then return settle(row, false) end
    if row.status ~= 'pending' then return false, 'Offer is no longer pending.' end
    if tonumber(row.settling) == 1 then return false, 'Offer settlement is already in progress.' end
    if action == 'decline' then
        local affected, err = QB.sql.update("UPDATE `qbdealership_offers` SET `status` = 'declined' WHERE `id` = ? AND `status` = 'pending' AND `settling` = 0", { row.id })
        if err or affected ~= 1 then return false, err or 'Offer changed.' end
        local customer = exports.qbcore:getPlayerByCitizenId(row.citizenid)
        if customer and customer.source then notifyPlayer(customer.source, dealer, ('Your offer for %s was declined.'):format(row.model), 'error') end
        TriggerClientEvent('qbdealership:client:offerUpdated', -1, row.id, 'declined')
        return true
    end
    if action == 'counter' then
        local counter, counterErr = Schema.offer({ direction = row.direction, model = row.model,
            amount = payload and payload.amount, terms = payload and payload.terms })
        if not counter then return false, counterErr end
        local affected, err = QB.sql.update([[UPDATE `qbdealership_offers` SET `status` = 'countered',
            `counter_amount` = ?, `counter_terms` = ?, `auto_at` = NULL WHERE `id` = ? AND `status` = 'pending' AND `settling` = 0]],
            { counter.amount or QB.sql.NULL, counter.terms or QB.sql.NULL, row.id })
        if err or affected ~= 1 then return false, err or 'Offer changed.' end
        local customer = exports.qbcore:getPlayerByCitizenId(row.citizenid)
        if customer and customer.source then notifyPlayer(customer.source, dealer, ('You received a counteroffer for %s.'):format(row.model), 'info') end
        TriggerClientEvent('qbdealership:client:offerUpdated', -1, row.id, 'countered')
        return true
    end
    return false, 'Unknown offer action.'
end

function Api.acceptCounter(src, id)
    local identity = playerIdentity(src)
    local row = offerRow(math.floor(tonumber(id) or 0))
    if not identity or not row or row.citizenid ~= identity.citizenid then return false, 'Unknown offer.' end
    return settle(row, true)
end

function Api.processOffers()
    local expired = QB.sql.update("UPDATE `qbdealership_offers` SET `status` = 'expired' WHERE `status` IN ('pending','countered') AND `settling` = 0 AND `expires_at` <= NOW()")
    if expired and expired > 0 then TriggerClientEvent('qbdealership:client:offerUpdated', -1, 0, 'expired') end
    if not Config.AutoAccept.enabled then return end
    local rows = QB.sql.query([[SELECT * FROM `qbdealership_offers` WHERE `status` = 'pending' AND `settling` = 0
        AND `terms` IS NULL AND `auto_at` IS NOT NULL AND `auto_at` <= NOW() LIMIT 25]]) or {}
    for _, row in ipairs(rows) do
        local dealer = State.get(row.dealership)
        if not dealer or not canAutomaticallyAccept(dealer, row) then
            QB.sql.execute("UPDATE `qbdealership_offers` SET `auto_at` = NULL WHERE `id` = ? AND `status` = 'pending' AND `settling` = 0", { row.id })
        elseif not settle(row, false) then
            QB.sql.execute("UPDATE `qbdealership_offers` SET `auto_at` = DATE_ADD(NOW(), INTERVAL ? SECOND) WHERE `id` = ? AND `status` = 'pending' AND `settling` = 0",
                { Config.AutoAccept.retrySeconds, row.id })
        end
    end
end

function Api.wholesale(src, dealerId, model, quantity)
    local dealer = State.get(dealerId)
    if not dealer or not State.canManage(src, dealer) then return false, 'You do not manage this dealership.' end
    if not dealer.job then return false, 'NPC dealerships do not require stock.' end
    local vehicle, basePrice = configuredVehicle(dealer, model)
    if not vehicle then return false, basePrice end
    quantity = math.floor(tonumber(quantity) or 1)
    if quantity < 1 or quantity > 25 then return false, 'Quantity must be between 1 and 25.' end
    local unitPrice = math.max(1, math.floor(basePrice * Config.WholesalePrice))
    local total = unitPrice * quantity
    local paid, payErr = debitDealer(dealer, total, 'vehicle-wholesale')
    if not paid then return false, payErr end
    local statements = {}
    for _ = 1, quantity do
        statements[#statements + 1] = { sql = [[INSERT INTO `qbdealership_stock`
            (`dealership`,`model`,`source`) VALUES (?,?,'wholesale')]], params = { dealer.id, model } }
    end
    local saved, saveErr = QB.sql.transaction(statements)
    if not saved then creditDealer(dealer, total, 'vehicle-wholesale-refund'); return false, saveErr end
    return { quantity = quantity, unitPrice = unitPrice, total = total }
end

function Api.setPrice(src, dealerId, model, price)
    local dealer = State.get(dealerId)
    if not dealer or not State.canManage(src, dealer) then return false, 'You do not manage this dealership.' end
    local vehicle, vehicleErr = configuredVehicle(dealer, model)
    if not vehicle then return false, vehicleErr end
    price = math.floor(tonumber(price) or 0)
    if price < 1 or price > Config.maxPrice then return false, 'Sale price is invalid.' end
    local candidate = json.decode(json.encode(dealer))
    candidate.prices[model] = price
    return State.persist(candidate)
end

function Api.setDisplay(src, dealerId, placementId, model)
    local dealer = State.get(dealerId)
    if not dealer or not State.canManage(src, dealer) then return false, 'You do not manage this dealership.' end
    local vehicle, vehicleErr = configuredVehicle(dealer, model)
    if not vehicle then return false, vehicleErr end
    local candidate = json.decode(json.encode(dealer))
    for _, placement in ipairs(candidate.placements) do
        if placement.id == placementId then
            placement.model = model
            return State.persist(candidate)
        end
    end
    return false, 'Display position no longer exists.'
end

function Api.setAutoAccept(src, dealerId, enabled)
    local dealer = State.get(dealerId)
    if not dealer or not State.canManage(src, dealer) then return false, 'You do not manage this dealership.' end
    local candidate = json.decode(json.encode(dealer))
    candidate.autoAccept = enabled == true
    return State.persist(candidate)
end

function Api.ownedVehicles(src)
    local identity, err = playerIdentity(src)
    if not identity then return nil, err end
    local rows = exports.qbcore:getByOwner(identity.citizenid) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local vehicle = exports.qbcore:getShared('vehicles', row.model)
        if vehicle then out[#out + 1] = { plate = row.plate, model = row.model, name = vehicle.name or row.model, state = row.state } end
    end
    return out
end

function Api.offersFor(src, dealerId, management)
    local dealer = State.get(dealerId)
    local identity = playerIdentity(src)
    if management == true and dealer and State.canManage(src, dealer) then
        return QB.sql.query([[SELECT * FROM `qbdealership_offers` WHERE `dealership` = ?
            ORDER BY FIELD(`status`,'pending','countered','accepted','declined','expired'), `id` DESC LIMIT 100]], { dealer.id }) or {}
    end
    if not identity then return nil, 'Character unavailable.' end
    return QB.sql.query('SELECT * FROM `qbdealership_offers` WHERE `citizenid` = ? ORDER BY `id` DESC LIMIT 50',
        { identity.citizenid }) or {}
end

function Api.saveDealership(src, payload)
    if not State.isAdmin(src) then return false, 'You cannot create dealerships.' end
    if type(payload) ~= 'table' then return false, 'Invalid dealership.' end
    local dealer, err = Schema.normaliseDealership(payload)
    if not dealer then return false, err end
    if dealer.job and not exports.qbcore:getShared('jobs', dealer.job) then return false, 'That job does not exist.' end
    for _, model in ipairs(dealer.vehicles) do
        if not sharedVehicle(model) then return false, ('Unknown or unpriced vehicle: %s'):format(model) end
    end
    return State.persist(dealer)
end

function Api.deleteDealership(src, dealerId)
    local dealer = State.get(dealerId)
    if not dealer or not State.isAdmin(src) then return false, 'You cannot delete this dealership.' end
    return State.remove(dealer.id)
end

function Api.vehicleRegistry(src)
    if not State.isAdmin(src) then return nil, 'You cannot create dealerships.' end
    local vehicles = {}
    for _, vehicle in ipairs(exports.qbcore:allShared('vehicles') or {}) do
        if tonumber(vehicle.price) and tonumber(vehicle.price) > 0 then
            vehicles[#vehicles + 1] = { model = vehicle.model, name = vehicle.name, brand = vehicle.brand, price = vehicle.price }
        end
    end
    table.sort(vehicles, function(a, b) return (a.name or a.model) < (b.name or b.model) end)
    return vehicles
end
