Dealerships, Swaps, DealerData, fn = {}, {}, {}, {}
Kora.print.debug('kora_dealership server/functions.lua loaded.')

local publicStock = 9999
local maxSalesLog = 500
local clearance = Config.spawnClearance
local defaultSettings = { maxPriceOverride = 10, commission = 5, employeeDiscount = 5 }

fn.defaultSettings = defaultSettings

function fn.notify(src, message, class)
    Kora.notify.send(src, { title = 'Kora Dealerships', message = message, type = class })
end

function fn.fail(message)
    return false, message
end

function fn.decode(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    return (ok and type(decoded) == 'table' and decoded) or fallback
end

function fn.copy(value)
    return json.decode(json.encode(value))
end

function fn.trim(value, max)
    if type(value) ~= 'string' or not value:match('%S') then return nil end
    return value:match('^%s*(.-)%s*$'):sub(1, max)
end

-- Whole-number amount in [1, max], or nil. Rejects floats, NaN, inf and non-numbers.
function fn.toAmount(value, max)
    local number = tonumber(value)
    if not number or number ~= number or number < 1 or number > max then return nil end
    return math.tointeger(math.floor(number))
end

function fn.isAdmin(src)
    return IsPlayerAceAllowed(src, Config.adminPermission or 'admin')
end

-- Validates a client-supplied list index and the player's distance to that point.
-- Returns true, or false and a message. Never raises on bad client input.
function fn.nearPoint(src, record, field, index, dist)
    local list = type(record) == 'table' and record[field]
    local number = tonumber(index)
    index = number and math.tointeger(number)
    local point = list and index and list[index]
    if not point then return false, 'Invalid location.' end
    if not Kora.distance.player(src, point.coords, dist) then return false, 'You are too far away.' end
    return true
end

-- true when `key` is off cooldown for this player (and starts the cooldown).
local cooldowns = {}

function fn.rateLimit(src, key, ms)
    local now = GetGameTimer()
    local byKey = cooldowns[src] or {}
    if byKey[key] and now - byKey[key] < ms then return false end
    byKey[key] = now
    cooldowns[src] = byKey
    return true
end

local function clearCooldowns()
    cooldowns[source] = nil
end

AddEventHandler('playerDropped', clearCooldowns)

function fn.citizenId(src)
    local player = exports.kora_core:getPlayerData(src)
    return player and player.citizenid
end

-- Accepts a server id (online) or an 8-character citizenid (online or offline).
function fn.playerName(who)
    if type(who) == 'number' then
        local player = exports.kora_core:getPlayerData(who)
        local info = player and player.charinfo or {}
        local name = ('%s %s'):format(info.firstname or '', info.lastname or ''):match('^%s*(.-)%s*$')
        return name ~= '' and name or ('Player %d'):format(who)
    end
    if type(who) == 'string' and #who == 8 then
        local rows = Kora.sql.query(
            'SELECT CONCAT(JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, "$.firstname")), " ", JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, "$.lastname"))) AS `name` FROM `players` WHERE `citizenid` = ?',
            { who }
        )
        return rows and rows[1] and rows[1].name
    end
end

function fn.publish()
    GlobalState.Dealerships = Dealerships
end

function fn.publishSwaps()
    GlobalState.DealershipSwaps = Swaps
end

-- Money for a citizenid that may be offline. Cash only.
function fn.takeCash(cid, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    local player = exports.kora_core:getPlayerByCitizenId(cid)
    if player then return player.removeMoney(amount) end

    local result = Kora.sql.query(
        'UPDATE `players` SET `money` = JSON_SET(`money`, "$.cash", JSON_EXTRACT(`money`, "$.cash") - ?) WHERE `citizenid` = ? AND JSON_EXTRACT(`money`, "$.cash") >= ?',
        { amount, cid, amount }
    )
    return result and result.affectedRows == 1
end

function fn.giveCash(cid, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    local player = exports.kora_core:getPlayerByCitizenId(cid)
    if player then return player.addMoney(amount) end

    local result = Kora.sql.query(
        'UPDATE `players` SET `money` = JSON_SET(`money`, "$.cash", JSON_EXTRACT(`money`, "$.cash") + ?) WHERE `citizenid` = ?',
        { amount, cid }
    )
    return result and result.affectedRows == 1
end

local function sharedVehicle(model)
    return exports.kora_core:getShared('vehicles', model)
end

function fn.getVehicleData(model)
    local ok, vehicle = pcall(sharedVehicle, model)
    if not ok or type(vehicle) ~= 'table' then return nil end

    local price = tonumber(vehicle.price)
    if not price or price < 1 then return nil end
    return { model = model, name = vehicle.name or model, price = price }
end

function fn.findVehicle(record, model)
    if type(model) ~= 'string' then return nil end
    model = model:lower()
    for _, entry in ipairs(record.vehicles) do
        if entry.model == model then return entry end
    end
end

local function cleanVehicles(list, current, dealershipType)
    local stock = {}
    for _, entry in ipairs(current) do stock[entry.model] = tonumber(entry.stock) end

    local result, seen = {}, {}
    for _, entry in ipairs(list) do
        local model = type(entry) == 'string' and entry or type(entry) == 'table' and entry.model
        model = type(model) == 'string' and model:lower()

        local shared = model and not seen[model] and fn.getVehicleData(model)
        if shared then
            seen[model] = true
            local price = tonumber(type(entry) == 'table' and entry.price) or shared.price
            result[#result + 1] = {
                model = model,
                name = shared.name,
                price = math.max(1, math.min(math.floor(price), Config.maxPrice)),
                stock = dealershipType == 'public' and publicStock or math.floor(stock[model] or 0),
            }
        end
    end
    return result
end

function fn.inStock(record, entry)
    return record.type == 'public' or (tonumber(entry.stock) or 0) > 0
end

-- Returns false when the vehicle is unknown, there is not enough stock for a decrement,
-- or the save failed (the in-memory stock is restored in both failure cases).
function fn.adjustStock(dealer, model, delta)
    local record = Dealerships[dealer]
    local entry = record and fn.findVehicle(record, model)
    if not entry then return false end
    if record.type == 'public' then return true end

    local previous = math.floor(tonumber(entry.stock) or 0)
    local updated = previous + delta
    if updated < 0 or updated > Config.maxStock then return false end

    entry.stock = updated
    if not fn.saveDealership(record) then
        entry.stock = previous
        return false
    end
    fn.publish()
    return true
end

function fn.createVehicle(model, coords)
    local vehicle = CreateVehicle(joaat(model), coords.x, coords.y, coords.z, coords.w or 0.0, true, true)
    local waited = 0
    while not DoesEntityExist(vehicle) and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end
    return DoesEntityExist(vehicle) and vehicle or nil
end

local plateChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

local function newPlate()
    for _ = 1, 20 do
        local plate = {}
        for i = 1, 8 do
            local n = math.random(#plateChars)
            plate[i] = plateChars:sub(n, n)
        end
        plate = table.concat(plate)
        local rows = Kora.sql.query('SELECT 1 FROM `player_vehicles` WHERE `plate` = ? LIMIT 1', { plate })
        if not rows or not rows[1] then return plate end
    end
end

local function insertOwnedVehicle(cid, model, plate, state)
    return Kora.sql.transaction({
        {
            sql = 'INSERT INTO player_vehicles (plate, vehicle, citizenid, state, fuel, engine_health, body_health, balance, paymentamount, paymentsleft, financetime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            params = { plate, model, cid, state, 100.0, 1000.0, 1000.0, 0, 0, 0, 0 },
        },
    })
end

-- `target` is a server id (the car is spawned at `spawn`, keyed and the player warped in; returns the
-- network id) or a citizenid (a garaged row is written, nothing spawns; returns true). nil on failure.
function fn.deliverVehicle(target, model, spawn)
    local plate = newPlate()
    if not plate then return nil end

    if type(target) ~= 'number' then
        if not insertOwnedVehicle(target, model, plate, Config.offerVehicleState) then return nil end
        TriggerEvent('qb-vehicleshop:server:onVehiclePurchased', target, model, plate)
        return true
    end

    local cid = fn.citizenId(target)
    if not cid or not spawn then return nil end

    local vehicle = fn.createVehicle(model, spawn.coords)
    if not vehicle then return nil end

    SetVehicleNumberPlateText(vehicle, plate)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 or not insertOwnedVehicle(cid, model, plate, 'out') then
        DeleteEntity(vehicle)
        return nil
    end

    exports.kora_vehiclekeys:giveKeys(target, plate)
    TriggerEvent('qb-vehicleshop:server:onVehiclePurchased', cid, model, plate)
    TaskWarpPedIntoVehicle(GetPlayerPed(target), vehicle, -1)
    return netId
end

-- Returns the first spawn with no vehicle within the clearance radius, or nil.
function fn.getFreeSpawn(spawns, radius)
    radius = radius or clearance
    local vehicles = GetAllVehicles()
    for i = 1, #spawns do
        local c = spawns[i].coords
        local point = vec3(c.x, c.y, c.z)
        local blocked = false
        for j = 1, #vehicles do
            if #(GetEntityCoords(vehicles[j]) - point) <= radius then
                blocked = true
                break
            end
        end
        if not blocked then return spawns[i] end
    end
end

local function newManagement(row)
    row = row or {}
    local settings = fn.decode(row.settings, {})
    for key, default in pairs(defaultSettings) do
        settings[key] = tonumber(settings[key]) or default
    end

    return {
        balance = math.floor(tonumber(row.current_balance) or 0),
        income = math.floor(tonumber(row.income) or 0),
        spent = math.floor(tonumber(row.spent) or 0),
        sales = fn.decode(row.sales, {}),
        employees = fn.decode(row.employees, {}),
        permissions = fn.decode(row.employee_permissions, {}),
        settings = settings,
    }
end

local function writeManagement(dealer, data)
    return Kora.sql.transaction({
        {
            sql = 'UPDATE `kora_dealership_management` SET `current_balance` = ?, `income` = ?, `spent` = ?, `sales` = ?, `employees` = ?, `employee_permissions` = ?, `settings` = ? WHERE `dealership_id` = ?',
            params = {
                data.balance, data.income, data.spent, json.encode(data.sales),
                json.encode(data.employees), json.encode(data.permissions), json.encode(data.settings), dealer,
            },
        },
    })
end

function fn.management(dealer)
    if not DealerData[dealer] then
        DealerData[dealer] = newManagement()
        Kora.sql.query(
            'INSERT IGNORE INTO `kora_dealership_management` (`dealership_id`, `sales`, `employees`, `employee_permissions`, `settings`) VALUES (?, ?, ?, ?, ?)',
            { dealer, '[]', '[]', '{}', json.encode(defaultSettings) }
        )
    end
    return DealerData[dealer]
end

-- Callers must pass new tables for any field they change (never mutate the cached ones), so a
-- failed write can restore the previous state. Returns the new data or false.
function fn.updateManagement(dealer, changes)
    local previous = fn.management(dealer)
    local updated = {}
    for key, value in pairs(previous) do updated[key] = value end
    for key, value in pairs(changes) do updated[key] = value end

    DealerData[dealer] = updated
    local ok, err = writeManagement(dealer, updated)
    if not ok then
        print(('[kora_dealership] management save FAILED for %s: %s'):format(dealer, tostring(err)))
        DealerData[dealer] = previous
        return false
    end
    return updated
end

-- Credits (or, with a negative amount, reverses) a sale for the dealership. true or false.
function fn.creditSale(dealer, amount)
    local record = Dealerships[dealer]
    if not record then return false end
    if record.type ~= 'owned' then return true end

    local data = fn.management(dealer)
    return fn.updateManagement(dealer, { balance = data.balance + amount, income = data.income + amount }) ~= false
end

function fn.recordSale(dealer, seller, sale)
    local record = Dealerships[dealer]
    if not record or record.type ~= 'owned' then return true, 0 end
    if not fn.isEmployee(seller, dealer) then return false end

    local data = fn.management(dealer)
    local sellerCid = fn.citizenId(seller)
    local price = math.floor(tonumber(sale.price) or 0)
    local commission = math.floor(price * data.settings.commission / 100)

    local log = fn.copy(data.sales)
    log[#log + 1] = {
        model = sale.model,
        vehicle = sale.vehicle,
        price = price,
        commission = commission,
        seller = sellerCid,
        sellerName = fn.playerName(seller),
        customer = sale.customer,
        customerName = sale.customerName,
        time = os.time(),
    }
    if #log > maxSalesLog then table.remove(log, 1) end

    local employees = fn.copy(data.employees)
    for i = 1, #employees do
        if employees[i].citizenid == sellerCid then
            employees[i].sales = (tonumber(employees[i].sales) or 0) + 1
            employees[i].income = (tonumber(employees[i].income) or 0) + price
        end
    end

    local dealerShare = price - commission
    local updated = fn.updateManagement(dealer, {
        balance = data.balance + dealerShare,
        income = data.income + dealerShare,
        sales = log,
        employees = employees,
    })
    if not updated then return false end

    if commission > 0 then exports.kora_core:addMoney(seller, 'bank', commission) end
    return true, commission
end

local function hasPermission(dealer, cid, action)
    local record = Dealerships[dealer]
    if not record or not cid then return false end
    if cid == record.owner then return true end

    for _, permission in ipairs(fn.management(dealer).permissions[cid] or {}) do
        if permission == action then return true end
    end
    return false
end

function fn.isOwner(src, dealer)
    local record = Dealerships[dealer]
    return record ~= nil and record.owner ~= nil and record.owner == fn.citizenId(src)
end

-- The owner counts as an employee.
function fn.isEmployee(src, dealer)
    local cid = fn.citizenId(src)
    if not cid or not Dealerships[dealer] then return false end
    if fn.isOwner(src, dealer) then return true end

    for _, employee in ipairs(fn.management(dealer).employees) do
        if employee.citizenid == cid then return true end
    end
    return false
end

function fn.canEmployeeDo(src, dealer, action)
    return hasPermission(dealer, fn.citizenId(src), action)
end

function fn.publishStaff()
    local staff, offerStaff = {}, {}
    for dealer, record in pairs(Dealerships) do
        if record.type == 'owned' and record.owner then
            staff[dealer] = { [record.owner] = true }
            offerStaff[dealer] = { [record.owner] = true }
            for _, employee in ipairs(fn.management(dealer).employees) do
                if hasPermission(dealer, employee.citizenid, 'sellVehicles') then
                    staff[dealer][employee.citizenid] = true
                end
                if hasPermission(dealer, employee.citizenid, 'handleOffers') then
                    offerStaff[dealer][employee.citizenid] = true
                end
            end
        end
    end
    GlobalState.DealershipStaff = staff
    GlobalState.DealershipOfferStaff = offerStaff -- who may open the management Offers page
end

function fn.saveDealership(record)
    return Kora.sql.transaction({
        {
            sql = [[INSERT INTO `kora_dealerships` (`id`,`label`,`type`,`price`,`owner`,`zone`,`vehicles`,`placements`,`spawns`,`management_zones`,`sale_zones`)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `type` = VALUES(`type`), `price` = VALUES(`price`),
                    `owner` = VALUES(`owner`), `zone` = VALUES(`zone`), `vehicles` = VALUES(`vehicles`),
                    `placements` = VALUES(`placements`), `spawns` = VALUES(`spawns`),
                    `management_zones` = VALUES(`management_zones`), `sale_zones` = VALUES(`sale_zones`)]],
            params = {
                record.id, record.label, record.type, record.price or Kora.sql.NULL, record.owner or Kora.sql.NULL,
                record.zone and json.encode(record.zone) or Kora.sql.NULL,
                json.encode(record.vehicles), json.encode(record.placements), json.encode(record.spawns),
                json.encode(record.managementZones), json.encode(record.saleZones),
            },
        },
    })
end

function fn.commitDealership(record)
    local ok, err = fn.saveDealership(record)
    if not ok then return false, err or 'Failed to save.' end

    Dealerships[record.id] = record
    fn.publish()
    fn.publishStaff()
    return record
end

-- Drops every cached trace of a deleted dealership so a re-created one with the same id starts clean.
function fn.forgetDealership(id)
    Dealerships[id] = nil
    DealerData[id] = nil
    Swaps[id] = nil
    fn.publish()
    fn.publishSwaps()
    fn.publishStaff()
end

local function cleanCoords(value, withHeading)
    if type(value) ~= 'table' then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z, w = withHeading and (tonumber(value.w) or 0.0) or nil }
end

local function cleanPoints(list, withHeading, allowedModels, limit)
    local result = {}
    for _, entry in ipairs(list) do
        if #result >= limit then break end
        if type(entry) == 'table' then
            local coords = cleanCoords(entry.coords, withHeading)
            local model = allowedModels and type(entry.model) == 'string' and entry.model:lower()
            if coords and (not allowedModels or allowedModels[model]) then
                result[#result + 1] = { model = model or nil, coords = coords }
            end
        end
    end
    return result
end

local function soldModels(vehicles)
    local set = {}
    for _, vehicle in ipairs(vehicles) do set[vehicle.model] = true end
    return set
end

fn.fieldLimits = {
    placements = Config.maxPlacements,
    spawns = Config.maxSpawns,
    managementZones = Config.maxZones,
    saleZones = Config.maxZones,
}

local function applyPatch(record, patch)
    local previousType = record.type
    record.label = fn.trim(patch.label, 128) or record.label

    if patch.type == 'public' or patch.type == 'for_sale' or patch.type == 'owned' then
        record.type = patch.type
    end

    -- Stock only means something for non-public dealerships: a public one holds 9999 of everything.
    if record.type ~= previousType then
        if previousType == 'public' then
            for _, entry in ipairs(record.vehicles) do entry.stock = 0 end
        end
        record.vehicles = cleanVehicles(record.vehicles, record.vehicles, record.type)
    end

    if record.type == 'for_sale' then
        local price = tonumber(patch.price)
        if price and price >= 1 and price <= Config.maxPrice then record.price = math.floor(price) end
    else
        record.price = nil
    end

    if record.type == 'owned' then
        record.owner = fn.trim(patch.owner, 50) or record.owner
    else
        record.owner = nil
    end

    if patch.clearZone then record.zone = nil end

    if type(patch.zone) == 'table' and type(patch.zone.points) == 'table' then
        local points = {}
        for _, point in ipairs(patch.zone.points) do
            if #points >= Config.maxZonePoints then break end
            points[#points + 1] = cleanCoords(point)
        end
        if #points >= 3 then
            record.zone = { points = points, thickness = tonumber(patch.zone.thickness) or 4.0 }
        end
    end

    if type(patch.vehicles) == 'table' then
        record.vehicles = cleanVehicles(patch.vehicles, record.vehicles, record.type)
        record.placements = cleanPoints(record.placements, true, soldModels(record.vehicles), Config.maxPlacements)
    end

    local limits = fn.fieldLimits
    if type(patch.placements) == 'table' then
        record.placements = cleanPoints(patch.placements, true, soldModels(record.vehicles), limits.placements)
    end
    if type(patch.spawns) == 'table' then record.spawns = cleanPoints(patch.spawns, true, nil, limits.spawns) end
    if type(patch.managementZones) == 'table' then
        record.managementZones = cleanPoints(patch.managementZones, false, nil, limits.managementZones)
    end
    if type(patch.saleZones) == 'table' then
        record.saleZones = cleanPoints(patch.saleZones, false, nil, limits.saleZones)
    end

    return record
end

local function samePlacements(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        local p, q = a[i], b[i]
        if p.model ~= q.model then return false end
        local c, d = p.coords, q.coords
        if c.x ~= d.x or c.y ~= d.y or c.z ~= d.z or c.w ~= d.w then return false end
    end
    return true
end

local function reconcileSwaps(id, record, placementsChanged)
    local swaps = Swaps[id]
    if not swaps then return end
    if placementsChanged then
        Swaps[id] = nil
        return
    end

    local sold = soldModels(record.vehicles)
    for key, model in pairs(swaps) do
        if not sold[model] then swaps[key] = nil end
    end
    if next(swaps) == nil then Swaps[id] = nil end
end

function fn.patchDealership(id, patch)
    local record = Dealerships[id]
    if not record then return fn.fail('Unknown dealership.') end
    if type(patch) ~= 'table' then return fn.fail('Nothing to save.') end

    local working = applyPatch(fn.copy(record), patch)
    local saved, err = fn.commitDealership(working)
    if not saved then return false, err end

    reconcileSwaps(id, working, not samePlacements(record.placements, working.placements))
    fn.publishSwaps()
    return saved
end

local function rowToRecord(row)
    local vehicles = fn.decode(row.vehicles, {})
    return {
        id = row.id,
        label = row.label,
        type = row.type,
        price = row.price,
        owner = row.owner,
        zone = fn.decode(row.zone, nil),
        vehicles = cleanVehicles(vehicles, vehicles, row.type),
        placements = fn.decode(row.placements, {}),
        spawns = fn.decode(row.spawns, {}),
        managementZones = fn.decode(row.management_zones, {}),
        saleZones = fn.decode(row.sale_zones, {}),
    }
end

local function load()
    for _, row in ipairs(Kora.sql.query('SELECT * FROM `kora_dealerships`', {}) or {}) do
        Dealerships[row.id] = rowToRecord(row)
    end

    for _, row in ipairs(Kora.sql.query('SELECT * FROM `kora_dealership_management`', {}) or {}) do
        DealerData[row.dealership_id] = newManagement(row)
    end
    fn.publish()
    fn.publishSwaps()
    fn.publishStaff()
end

CreateThread(function()
    if not Kora.sql.ready(60000) then
        print('^1[kora_dealership]^7 kora_sql was unavailable; dealerships are not loaded until restart.')
        return
    end
    if not Config.UsePDM then KoraDealershipSchema[1].seed = nil end
    local reports, schemaErr = Kora.sql.ensureTables(KoraDealershipSchema)
    if schemaErr then
        print(('^1[kora_dealership]^7 schema failed: %s'):format(tostring(schemaErr)))
        return
    end
    for _, report in ipairs(reports or {}) do
        for _, warning in ipairs(report.warnings or {}) do
            print(('^3[kora_dealership]^7 %s: %s'):format(tostring(report.table), tostring(warning)))
        end
    end
    load()
end)

