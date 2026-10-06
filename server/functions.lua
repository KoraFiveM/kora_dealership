Dealerships, Swaps, DealerData, Offers, fn = {}, {}, {}, {}, {}
QB.print.debug('qbdealership server/functions.lua loaded.')
local publicStock = 9999
local defaultSettings = { maxPriceOverride = 10, commission = 5, employeeDiscount = 5 }

fn.defaultSettings = defaultSettings

function fn.notify(src, message, class)
    QB.notify.send(src, {title = 'QB Dealerships', message = message, type = class})
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

function fn.isAdmin(src)
    return IsPlayerAceAllowed(src, 'command')
end

function fn.distance(src, coords, dist)
    return QB.distance.player(src, coords, dist)
end

function fn.nearAny(src, points, dist)
    for _, point in ipairs(points or {}) do
        if fn.distance(src, point.coords, dist) then return true end
    end
    return false
end

function fn.nearPlacement(src, record, index, dist)
    local placement = record.placements[math.tointeger(tonumber(index)) or 0]
    return placement ~= nil and fn.distance(src, placement.coords, dist)
end

function fn.citizenId(src)
    local player = exports.qbcore:getPlayerData(src)
    return player and player.citizenid
end

function fn.playerName(src)
    local player = exports.qbcore:getPlayerData(src)
    local info = player and player.charinfo or {}
    local name = ('%s %s'):format(info.firstname or '', info.lastname or ''):match('^%s*(.-)%s*$')
    return name ~= '' and name or ('Player %d'):format(src)
end

function fn.publish()
    GlobalState.Dealerships = Dealerships
end

function fn.publishSwaps()
    GlobalState.DealershipSwaps = Swaps
end


function fn.getVehicleData(model)
    local ok, vehicle = pcall(function()
        return exports.qbcore:getShared('vehicles', model)
    end)
    if not ok or type(vehicle) ~= 'table' then return nil end

    return { model = model, name = vehicle.name or model, price = tonumber(vehicle.price) or 1 }
end

function fn.findVehicle(record, model)
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

function fn.adjustStock(dealer, model, delta)
    local record = Dealerships[dealer]
    local entry = record and fn.findVehicle(record, model)
    if not entry then return false end
    if record.type == 'public' then return true end

    entry.stock = math.max(0, math.floor(tonumber(entry.stock) or 0) + delta)
    fn.saveDealership(record)
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

function fn.deliverVehicle(src, model, spawn)
    local online = true
    local vehicle = fn.createVehicle(model, spawn.coords)
    if not vehicle then return nil end

    local plate = GetVehicleNumberPlateText(vehicle)
    QB.sql.query('INSERT INTO player_vehicles (plate, vehicle, citizenid, state, fuel, engine_health, body_health, balance, paymentamount, paymentsleft, financetime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        plate, model, online and fn.citizenId(src) or src, 'out', 100.0, 1000.0, 1000.0, 0, 0, 0, 0,
    })
    if not online then
        return true
    end
    if type(src) ~= 'number' and #src == 8 then
        online = false
        DeleteEntity(vehicle)
        return nil
    else
        exports.qbvehiclekeys:giveKeys(src, plate)
        TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)
    end
    return NetworkGetNetworkIdFromEntity(vehicle) or nil
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
    return QB.sql.transaction({
        {
            sql = 'UPDATE `qbdealership_management` SET `current_balance` = ?, `income` = ?, `spent` = ?, `sales` = ?, `employees` = ?, `employee_permissions` = ?, `settings` = ? WHERE `dealership_id` = ?',
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
        QB.sql.query('INSERT IGNORE INTO `qbdealership_management` (`dealership_id`) VALUES (?)', { dealer })
    end
    return DealerData[dealer]
end

function fn.updateManagement(dealer, changes)
    local previous = fn.management(dealer)
    local updated = {}
    for key, value in pairs(previous) do updated[key] = value end
    for key, value in pairs(changes) do updated[key] = value end

    DealerData[dealer] = updated
    local ok, err = writeManagement(dealer, updated)
    if not ok then
        print(('[qbdealership] management save FAILED for %s: %s'):format(dealer, tostring(err)))
        DealerData[dealer] = previous
        return false
    end
    return updated
end

function fn.creditSale(dealer, amount)
    if Dealerships[dealer].type ~= 'owned' then return true end
    local data = fn.management(dealer)
    return fn.updateManagement(dealer, { balance = data.balance + amount, income = data.income + amount })
end

local maxSalesLog = 500

function fn.recordSale(dealer, seller, sale)
    local record = Dealerships[dealer]
    if not record or record.type ~= 'owned' then
        print(('[qbdealership] recordSale skipped: %s is not an owned dealership'):format(tostring(dealer)))
        return true, 0
    end
    local data = fn.management(dealer)
    local sellerCid = fn.citizenId(seller)
    local price = math.floor(tonumber(sale.price) or 0)

    local employee = fn.isOwner(seller, dealer) or fn.isEmployee(seller, dealer)
    if not employee then return end

    local commission = data.settings.commission
    commission = math.floor(price * commission / 100)
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
    while #log > maxSalesLog do table.remove(log, 1) end

    local employees = data.employees
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

    if commission > 0 then exports.qbcore:addMoney(seller, 'bank', commission) end
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
    return QB.sql.transaction({
        {
            sql = [[INSERT INTO `qbdealerships` (`id`,`label`,`type`,`price`,`owner`,`zone`,`vehicles`,`placements`,`spawns`,`management_zones`,`sale_zones`)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `type` = VALUES(`type`), `price` = VALUES(`price`),
                    `owner` = VALUES(`owner`), `zone` = VALUES(`zone`), `vehicles` = VALUES(`vehicles`),
                    `placements` = VALUES(`placements`), `spawns` = VALUES(`spawns`),
                    `management_zones` = VALUES(`management_zones`), `sale_zones` = VALUES(`sale_zones`)]],
            params = {
                record.id, record.label, record.type, record.price or QB.sql.NULL, record.owner or QB.sql.NULL,
                record.zone and json.encode(record.zone) or QB.sql.NULL,
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

local function cleanCoords(value, withHeading)
    if type(value) ~= 'table' then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z, w = withHeading and (tonumber(value.w) or 0.0) or nil }
end

local function cleanPoints(list, withHeading, allowedModels)
    local result = {}
    for _, entry in ipairs(list) do
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

local function applyPatch(record, patch)
    record.label = fn.trim(patch.label, 128) or record.label

    if patch.type == 'public' or patch.type == 'for_sale' or patch.type == 'owned' then
        record.type = patch.type
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
        for _, point in ipairs(patch.zone.points) do points[#points + 1] = cleanCoords(point) end
        if #points >= 3 then
            record.zone = { points = points, thickness = tonumber(patch.zone.thickness) or 4.0 }
        end
    end

    if type(patch.vehicles) == 'table' then
        record.vehicles = cleanVehicles(patch.vehicles, record.vehicles, record.type)
        record.placements = cleanPoints(record.placements, true, soldModels(record.vehicles))
    end

    if type(patch.placements) == 'table' then
        record.placements = cleanPoints(patch.placements, true, soldModels(record.vehicles))
    end

    if type(patch.spawns) == 'table' then record.spawns = cleanPoints(patch.spawns, true) end
    if type(patch.managementZones) == 'table' then record.managementZones = cleanPoints(patch.managementZones, false) end
    if type(patch.saleZones) == 'table' then record.saleZones = cleanPoints(patch.saleZones, false) end

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
    if not Swaps[id] then return end
    if placementsChanged then
        Swaps[id] = nil
        return
    end

    local sold = soldModels(record.vehicles)
    for key, model in pairs(Swaps[id]) do
        if not sold[model] then Swaps[id][key] = nil end
    end
    if next(Swaps[id]) == nil then Swaps[id] = nil end
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

CreateThread(function()
    for _, row in ipairs(QB.sql.query('SELECT * FROM `qbdealerships`', {}) or {}) do
        Dealerships[row.id] = rowToRecord(row)
    end

    for _, row in ipairs(QB.sql.query('SELECT * FROM `qbdealership_management`', {}) or {}) do
        DealerData[row.dealership_id] = newManagement(row)
    end

    for _, row in ipairs(QB.sql.query('SELECT * FROM `qbdealership_offers` WHERE `status` = ?', { 'pending' }) or {}) do
        Offers[row.dealership_id] = Offers[row.dealership_id] or {}
        table.insert(Offers[row.dealership_id], {
            model = row.model,
            price = row.offer_price,
            additional = row.offer_text,
            offeror = row.offeror,
            expiry = row.auto_accept_at,
            id = row.id,
        })
    end

    fn.publish()
    fn.publishSwaps()
    fn.publishStaff()
end)

local clearance = 3.0
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
        if not blocked then
            return spawns[i]
        end
    end
    return spawns[1]
end

function fn.getPlayerName(src)
    if type(src) == 'number' then
        local player = exports.qbcore:getPlayer(src)
        return player and player.Charinfo.firstname .. ' ' .. player.Charinfo.lastname
    elseif type(src) == 'string' and #src == 8 then
        local data = QB.sql.query(
            'SELECT CONCAT(JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, "$.firstname")), " ", JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, "$.lastname"))) AS `name` FROM `players` WHERE `citizenid` = ?',
            { src }
        )
        return data and data[1] and data[1].name
    end
end