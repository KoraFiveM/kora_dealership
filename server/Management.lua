local fieldNames = {
    placements = 'Display vehicles',
    spawns = 'Spawn points',
    managementZones = 'Management zones',
    saleZones = 'Sale zones',
}

local decisions = { accept = 'accepted', deny = 'denied' }

local nameSql = 'CONCAT(JSON_UNQUOTE(JSON_EXTRACT(%s.`charinfo`, "$.firstname")), " ", JSON_UNQUOTE(JSON_EXTRACT(%s.`charinfo`, "$.lastname")))'
local offerSelect = ([[SELECT o.*, %s AS `offeror_name`, %s AS `acceptor_name`,
        DATE_FORMAT(o.`auto_accept_at`, '%%Y-%%m-%%d %%H:%%i') AS `expiry_text`
    FROM `qbdealership_offers` o
    LEFT JOIN `players` p ON p.`citizenid` = o.`offeror` COLLATE utf8mb4_unicode_ci
    LEFT JOIN `players` a ON a.`citizenid` = o.`acceptor` COLLATE utf8mb4_unicode_ci
    WHERE o.`dealership_id` = ? AND o.`status` {op} ? ORDER BY o.`id` DESC LIMIT ?]]):format(nameSql:format('p', 'p'), nameSql:format('a', 'a'))

-- Authorisation

-- requirement: 'owner', 'employee' (owner included), or a permission value from Config.employeePermissions.
-- Returns the dealership record, or false and a message. Validates the client-supplied dealer and index.
local function authorize(src, dealer, index, requirement)
    local record = type(dealer) == 'string' and Dealerships[dealer]
    if not record or record.type ~= 'owned' then return fn.fail('This dealership is not owned.') end

    local allowed
    if requirement == 'owner' then
        allowed = fn.isOwner(src, dealer)
    elseif requirement == 'employee' then
        allowed = fn.isEmployee(src, dealer)
    else
        allowed = fn.canEmployeeDo(src, dealer, requirement)
    end
    if not allowed then return fn.fail('You are not permitted to do that here.') end

    local near, err = fn.nearPoint(src, record, 'managementZones', index, Config.managementDistance)
    if not near then return fn.fail(err) end
    return record
end

-- Employees

local function findEmployee(data, cid)
    for id, employee in ipairs(data.employees) do
        if employee.citizenid == cid then return employee, id end
    end
end

local function openOwnerManagement(src, dealer, index)
    local record, err = authorize(src, dealer, index, 'employee')
    if not record then return fn.fail(err) end

    local data = fn.management(dealer)
    local owner = fn.isOwner(src, dealer)
    local cid = fn.citizenId(src)

    return {
        owner = owner,
        employees = data.employees,
        permissions = owner and data.permissions or { [cid] = data.permissions[cid] or {} },
        settings = data.settings,
        balance = { balance = data.balance, income = data.income, spent = data.spent },
    }
end

local function addEmployee(src, dealer, index, serverId)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end

    local data = fn.management(dealer)
    if #data.employees >= Config.maxEmployees then return fn.fail('This dealership has reached its employee limit.') end

    local number = tonumber(serverId)
    local target = number and math.tointeger(number)
    if not target or target == src or GetPlayerPed(target) == 0 then return fn.fail('That player is not available.') end

    local close = Kora.distance.coords(GetEntityCoords(GetPlayerPed(src)), GetEntityCoords(GetPlayerPed(target)), Config.nearbyCustomerDistance)
    if not close then return fn.fail('That player is too far away.') end

    local cid = fn.citizenId(target)
    if not cid then return fn.fail('That player is not available.') end
    if cid == record.owner then return fn.fail('The owner cannot be added as an employee.') end
    if findEmployee(data, cid) then return fn.fail('That player already works here.') end

    local employees = fn.copy(data.employees)
    employees[#employees + 1] = { citizenid = cid, name = fn.playerName(target) }
    local permissions = fn.copy(data.permissions)
    permissions[cid] = {}

    if not fn.updateManagement(dealer, { employees = employees, permissions = permissions }) then
        return fn.fail('Could not save the employee.')
    end
    fn.publishStaff()
    return employees
end

local function removeEmployee(src, dealer, index, cid)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end

    local data = fn.management(dealer)
    local _, position = findEmployee(data, cid)
    if not position then return fn.fail('That employee does not exist.') end

    local employees = fn.copy(data.employees)
    table.remove(employees, position)
    local permissions = fn.copy(data.permissions)
    permissions[cid] = nil

    if not fn.updateManagement(dealer, { employees = employees, permissions = permissions }) then
        return fn.fail('Could not remove the employee.')
    end
    fn.publishStaff()
    return employees
end

local function savePermissions(src, dealer, index, cid, list)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end

    local data = fn.management(dealer)
    if not findEmployee(data, cid) or type(list) ~= 'table' then return fn.fail('Could not save permissions.') end

    local allowed = {}
    for _, entry in ipairs(Config.employeePermissions) do allowed[entry.value] = true end

    local granted, seen = {}, {}
    for _, permission in ipairs(list) do
        if allowed[permission] and not seen[permission] then
            seen[permission] = true
            granted[#granted + 1] = permission
        end
    end

    local permissions = fn.copy(data.permissions)
    permissions[cid] = granted
    if not fn.updateManagement(dealer, { permissions = permissions }) then return fn.fail('Could not save permissions.') end

    fn.publishStaff()
    return permissions
end

local function saveSettings(src, dealer, index, values)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end
    if type(values) ~= 'table' then return fn.fail('Invalid settings.') end

    local settings = {}
    for key, default in pairs(fn.defaultSettings) do
        local value = tonumber(values[key])
        settings[key] = value and value == value and math.max(0, math.min(100, math.floor(value))) or default
    end

    if not fn.updateManagement(dealer, { settings = settings }) then return fn.fail('Could not save settings.') end
    return settings
end

-- Placements, spawns and zones

local function insidePolygon(x, y, points)
    local inside = false
    local j = #points
    for i = 1, #points do
        local a, b = points[i], points[j]
        if (a.y > y) ~= (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function insideZone(zone, coords)
    if type(zone) ~= 'table' or type(zone.points) ~= 'table' or #zone.points < 3 then return false end

    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not (x and y and z) or not insidePolygon(x, y, zone.points) then return false end

    local half = (tonumber(zone.thickness) or 4.0) / 2
    local minZ, maxZ = math.huge, -math.huge
    for _, point in ipairs(zone.points) do
        minZ = math.min(minZ, tonumber(point.z) or 0.0)
        maxZ = math.max(maxZ, tonumber(point.z) or 0.0)
    end
    return z >= minZ - half and z <= maxZ + half
end

local function coordKey(coords)
    return ('%.3f,%.3f,%.3f'):format(tonumber(coords.x) or 0, tonumber(coords.y) or 0, tonumber(coords.z) or 0)
end

local function validateNewEntries(record, field, list)
    if type(list) ~= 'table' then return false, 'Invalid ' .. field .. '.' end
    if #list > fn.fieldLimits[field] then
        return false, ('%s are limited to %d.'):format(fieldNames[field], fn.fieldLimits[field])
    end

    local existing = {}
    for _, entry in ipairs(record[field]) do existing[coordKey(entry.coords)] = true end

    for _, entry in ipairs(list) do
        local coords = type(entry) == 'table' and entry.coords
        if type(coords) ~= 'table' then return false, 'Invalid ' .. field .. '.' end

        if not existing[coordKey(coords)] then
            if not record.zone then return false, 'This dealership has no zone yet. Ask an admin to draw it first.' end
            if not insideZone(record.zone, coords) then
                return false, ('%s must be inside the dealership zone.'):format(fieldNames[field])
            end
        end
    end
    return true
end

local function savePlacement(src, dealer, index, patch)
    local record, err = authorize(src, dealer, index, 'employee')
    if not record then return fn.fail(err) end
    if type(patch) ~= 'table' then return fn.fail('Nothing to save.') end

    local owner = fn.isOwner(src, dealer)
    local allowed = {}
    for field in pairs(fieldNames) do
        if patch[field] ~= nil then
            if not owner and not (field == 'placements' and fn.canEmployeeDo(src, dealer, 'manageDisplay')) then
                return fn.fail('You are not permitted to edit that.')
            end

            local valid, reason = validateNewEntries(record, field, patch[field])
            if not valid then return fn.fail(reason) end

            -- Management zones are the only way in to this menu, so the last one can never be removed.
            if field == 'managementZones' and #patch[field] < 1 then
                return fn.fail('A dealership must keep at least one management zone.')
            end
            allowed[field] = patch[field]
        end
    end
    if next(allowed) == nil then return fn.fail('Nothing to save.') end

    return fn.patchDealership(dealer, allowed)
end

-- Funds

local function depositFunds(src, dealer, index, amount)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end
    if not fn.rateLimit(src, 'funds', Config.rateLimits.funds) then return fn.fail('Slow down.') end

    amount = fn.toAmount(amount, Config.maxBalance)
    if not amount then return fn.fail('Enter a valid amount.') end
    if fn.management(dealer).balance + amount > Config.maxBalance then
        return fn.fail('That would exceed the maximum dealership balance.')
    end

    if not exports.kora_core:removeMoney(src, 'bank', amount) then return fn.fail('Not enough money in your bank account.') end

    local data = fn.management(dealer)
    if not fn.updateManagement(dealer, { balance = data.balance + amount }) then
        exports.kora_core:addMoney(src, 'bank', amount)
        return fn.fail('Could not save the deposit. You were refunded.')
    end
    return { balance = data.balance + amount }
end

local function withdrawFunds(src, dealer, index, amount)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end
    if not fn.rateLimit(src, 'funds', Config.rateLimits.funds) then return fn.fail('Slow down.') end

    amount = fn.toAmount(amount, Config.maxBalance)
    if not amount then return fn.fail('Enter a valid amount.') end

    local data = fn.management(dealer)
    if data.balance < amount then return fn.fail('The dealership does not have enough funds.') end

    local balance = data.balance - amount
    if not fn.updateManagement(dealer, { balance = balance }) then return fn.fail('Could not save the withdrawal.') end

    exports.kora_core:addMoney(src, 'bank', amount)
    return { balance = balance }
end

local function orderVehicle(src, dealer, index, model, quantity)
    local record, err = authorize(src, dealer, index, 'orderVehicles')
    if not record then return fn.fail(err) end

    local amount = fn.toAmount(quantity, Config.maxOrderQuantity)
    if not amount then return fn.fail(('Order between 1 and %d vehicles.'):format(Config.maxOrderQuantity)) end

    local entry = fn.findVehicle(record, model)
    if not entry then return fn.fail('That vehicle is not sold here.') end
    if (tonumber(entry.stock) or 0) + amount > Config.maxStock then
        return fn.fail(('This would exceed the stock limit of %d.'):format(Config.maxStock))
    end

    local cost = DealershipOrders.unitCost(entry.price) * amount
    local data = fn.management(dealer)
    if data.balance < cost then
        return fn.fail(('Not enough dealership funds ($%d needed, $%d available).'):format(cost, data.balance))
    end

    if not fn.updateManagement(dealer, { balance = data.balance - cost, spent = data.spent + cost }) then
        return fn.fail('Could not save the order.')
    end

    if not fn.adjustStock(dealer, entry.model, amount) then
        fn.updateManagement(dealer, { balance = data.balance, spent = data.spent })
        return fn.fail('Could not add the stock. You were not charged.')
    end
    return { record = Dealerships[dealer], cost = cost, amount = amount }
end

-- Offers

local function offerView(record, row)
    local entry = fn.findVehicle(record, row.model)
    return {
        id = row.id,
        model = row.model,
        name = entry and entry.name or row.model,
        asking = entry and math.floor(tonumber(entry.price) or 0) or nil,
        price = math.floor(tonumber(row.offer_price) or 0),
        terms = row.offer_text or '',
        offeror = row.offeror_name or row.offeror,
        status = row.status,
        handledBy = row.acceptor == 'system' and 'Auto-accepted' or row.acceptor_name or row.acceptor,
        expiry = row.expiry_text,
    }
end

local function loadOffers(record)
    local limit = math.max(1, math.floor(tonumber(Config.offersPageLimit) or 50))
    local result = { pending = {}, history = {} }

    local pending = Kora.sql.query(offerSelect:gsub('{op}', '='), { record.id, 'pending', limit }) or {}
    for _, row in ipairs(pending) do result.pending[#result.pending + 1] = offerView(record, row) end

    local history = Kora.sql.query(offerSelect:gsub('{op}', '<>'), { record.id, 'pending', limit }) or {}
    for _, row in ipairs(history) do result.history[#result.history + 1] = offerView(record, row) end

    return result
end

local function getOffers(src, dealer, index)
    local record, err = authorize(src, dealer, index, 'handleOffers')
    if not record then return fn.fail(err) end
    return loadOffers(record)
end

-- Moves a pending offer to `status`. Exactly one caller can win; affectedRows says whether it was us.
local function claimOffer(id, dealer, from, status, acceptor)
    local result = Kora.sql.query(
        'UPDATE `qbdealership_offers` SET `status` = ?, `acceptor` = ? WHERE `id` = ? AND `dealership_id` = ? AND `status` = ?',
        { status, acceptor, id, dealer, from }
    )
    return result ~= nil and result.affectedRows == 1
end

local function settleOffer(dealer, id, decision, acceptor)
    local record = Dealerships[dealer]
    if not record or record.type ~= 'owned' then return fn.fail('This dealership is not owned.') end

    local rows = Kora.sql.query(
        'SELECT * FROM `qbdealership_offers` WHERE `id` = ? AND `dealership_id` = ? AND `status` = ?',
        { id, dealer, 'pending' }
    )
    local offer = rows and rows[1]
    if not offer then return fn.fail('That offer has already been handled.') end

    if decision == 'deny' then
        if not claimOffer(id, dealer, 'pending', 'denied', acceptor) then return fn.fail('That offer has already been handled.') end
        return true
    end

    local entry = fn.findVehicle(record, offer.model)
    if not entry then return fn.fail('That vehicle is no longer sold here.') end
    if not fn.inStock(record, entry) then return fn.fail('That vehicle is out of stock.') end

    if not claimOffer(id, dealer, 'pending', 'accepted', acceptor) then return fn.fail('That offer has already been handled.') end

    local price = math.floor(tonumber(offer.offer_price) or 0)
    local function release()
        claimOffer(id, dealer, 'accepted', 'pending', Kora.sql.NULL)
    end

    if not fn.takeCash(offer.offeror, price) then
        release()
        return fn.fail('The offeror cannot afford this offer.')
    end

    if not fn.adjustStock(dealer, offer.model, -1) then
        fn.giveCash(offer.offeror, price)
        release()
        return fn.fail('That vehicle is out of stock.')
    end

    if not fn.creditSale(dealer, price) then
        fn.adjustStock(dealer, offer.model, 1)
        fn.giveCash(offer.offeror, price)
        release()
        return fn.fail('Could not credit the dealership.')
    end

    if not fn.deliverVehicle(offer.offeror, offer.model) then
        fn.creditSale(dealer, -price)
        fn.adjustStock(dealer, offer.model, 1)
        fn.giveCash(offer.offeror, price)
        release()
        return fn.fail('Could not deliver the vehicle. The offeror was refunded.')
    end
    return true
end

local function resolveOffer(src, dealer, index, offerId, decision)
    local record, err = authorize(src, dealer, index, 'handleOffers')
    if not record then return fn.fail(err) end

    local number = tonumber(offerId)
    local id = number and math.tointeger(number)
    if not decisions[decision] or not id then return fn.fail('Invalid offer.') end

    local ok, reason = settleOffer(dealer, id, decision, fn.citizenId(src))
    if not ok then return fn.fail(reason) end
    return loadOffers(record)
end

-- Offers past their auto-accept time are accepted; one that can no longer be completed is denied.
local function processDueOffers()
    local due = Kora.sql.query(
        'SELECT `id`, `dealership_id` FROM `qbdealership_offers` WHERE `status` = ? AND `auto_accept_at` IS NOT NULL AND `auto_accept_at` <= NOW() LIMIT 20',
        { 'pending' }
    ) or {}

    for _, row in ipairs(due) do
        local ok = settleOffer(row.dealership_id, row.id, 'accept', 'system')
        if not ok then claimOffer(row.id, row.dealership_id, 'pending', 'denied', 'system') end
    end
end

local function autoAcceptLoop()
    while true do
        Wait(math.max(10, tonumber(Config.autoConfirmCheckSeconds) or 60) * 1000)
        local ok, err = pcall(processDueOffers)
        if not ok then print(('^1[qbdealership] auto-accept failed: %s^7'):format(tostring(err))) end
    end
end

CreateThread(autoAcceptLoop)

Kora.callback.register('qbdealership:management:openOwnerManagement', openOwnerManagement)
Kora.callback.register('qbdealership:management:addEmployee', addEmployee)
Kora.callback.register('qbdealership:management:removeEmployee', removeEmployee)
Kora.callback.register('qbdealership:management:savePermissions', savePermissions)
Kora.callback.register('qbdealership:management:saveSettings', saveSettings)
Kora.callback.register('qbdealership:management:savePlacement', savePlacement)
Kora.callback.register('qbdealership:management:depositFunds', depositFunds)
Kora.callback.register('qbdealership:management:withdrawFunds', withdrawFunds)
Kora.callback.register('qbdealership:management:orderVehicle', orderVehicle)
Kora.callback.register('qbdealership:management:getOffers', getOffers)
Kora.callback.register('qbdealership:management:resolveOffer', resolveOffer)
