local fieldNames = {
    placements = Kora.lang('s.fields.placements'),
    spawns = Kora.lang('s.fields.spawns'),
    managementZones = Kora.lang('s.fields.managementZones'),
    saleZones = Kora.lang('s.fields.saleZones'),
}

local decisions = { accept = 'accepted', deny = 'denied' }

local nameSql = 'CONCAT(JSON_UNQUOTE(JSON_EXTRACT(%s.`charinfo`, "$.firstname")), " ", JSON_UNQUOTE(JSON_EXTRACT(%s.`charinfo`, "$.lastname")))'
local offerSelect = ([[SELECT o.*, %s AS `offeror_name`, %s AS `acceptor_name`,
        DATE_FORMAT(o.`auto_accept_at`, '%%Y-%%m-%%d %%H:%%i') AS `expiry_text`
    FROM `kora_dealership_offers` o
    LEFT JOIN `players` p ON p.`citizenid` = o.`offeror` COLLATE utf8mb4_unicode_ci
    LEFT JOIN `players` a ON a.`citizenid` = o.`acceptor` COLLATE utf8mb4_unicode_ci
    WHERE o.`dealership_id` = ? AND o.`status` {op} ? ORDER BY o.`id` DESC LIMIT ?]]):format(nameSql:format('p', 'p'), nameSql:format('a', 'a'))

-- requirement: 'owner', 'employee' (owner included), or a permission value from Config.employeePermissions.
-- Returns the dealership record, or false and a message. Validates the client-supplied dealer and index.
local function authorize(src, dealer, index, requirement)
    local record = type(dealer) == 'string' and Dealerships[dealer]
    if not record or record.type ~= 'owned' then return fn.fail(Kora.lang('s.errors.not_owned')) end

    local allowed
    if requirement == 'owner' then
        allowed = fn.isOwner(src, dealer)
    elseif requirement == 'employee' then
        allowed = fn.isEmployee(src, dealer)
    else
        allowed = fn.canEmployeeDo(src, dealer, requirement)
    end
    if not allowed then return fn.fail(Kora.lang('s.errors.not_permitted')) end

    local near, err = fn.nearPoint(src, record, 'managementZones', index, Config.managementDistance)
    if not near then return fn.fail(err) end
    return record
end

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
    if #data.employees >= Config.maxEmployees then return fn.fail(Kora.lang('s.errors.employee_limit')) end

    local number = tonumber(serverId)
    local target = number and math.tointeger(number)
    if not target or target == src or GetPlayerPed(target) == 0 then return fn.fail(Kora.lang('s.errors.player_unavailable')) end

    local close = Kora.distance.coords(GetEntityCoords(GetPlayerPed(src)), GetEntityCoords(GetPlayerPed(target)), Config.nearbyCustomerDistance)
    if not close then return fn.fail(Kora.lang('s.errors.player_too_far')) end

    local cid = fn.citizenId(target)
    if not cid then return fn.fail(Kora.lang('s.errors.player_unavailable')) end
    if cid == record.owner then return fn.fail(Kora.lang('s.errors.owner_cannot_be_employee')) end
    if findEmployee(data, cid) then return fn.fail(Kora.lang('s.errors.already_employee')) end

    local employees = fn.copy(data.employees)
    employees[#employees + 1] = { citizenid = cid, name = fn.playerName(target) }
    local permissions = fn.copy(data.permissions)
    permissions[cid] = {}

    if not fn.updateManagement(dealer, { employees = employees, permissions = permissions }) then
        return fn.fail(Kora.lang('s.errors.employee_save_failed'))
    end
    fn.publishStaff()
    return employees
end

local function removeEmployee(src, dealer, index, cid)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end

    local data = fn.management(dealer)
    local _, position = findEmployee(data, cid)
    if not position then return fn.fail(Kora.lang('s.errors.employee_missing')) end

    local employees = fn.copy(data.employees)
    table.remove(employees, position)
    local permissions = fn.copy(data.permissions)
    permissions[cid] = nil

    if not fn.updateManagement(dealer, { employees = employees, permissions = permissions }) then
        return fn.fail(Kora.lang('s.errors.employee_remove_failed'))
    end
    fn.publishStaff()
    return employees
end

local function savePermissions(src, dealer, index, cid, list)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end

    local data = fn.management(dealer)
    if not findEmployee(data, cid) or type(list) ~= 'table' then return fn.fail(Kora.lang('s.errors.permissions_save_failed')) end

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
    if not fn.updateManagement(dealer, { permissions = permissions }) then return fn.fail(Kora.lang('s.errors.permissions_save_failed')) end

    fn.publishStaff()
    return permissions
end

local function saveSettings(src, dealer, index, values)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end
    if type(values) ~= 'table' then return fn.fail(Kora.lang('s.errors.settings_invalid')) end

    local settings = {}
    for key, default in pairs(fn.defaultSettings) do
        local value = tonumber(values[key])
        settings[key] = value and value == value and math.max(0, math.min(100, math.floor(value))) or default
    end

    if not fn.updateManagement(dealer, { settings = settings }) then return fn.fail(Kora.lang('s.errors.settings_save_failed')) end
    return settings
end

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
    if type(list) ~= 'table' then return false, Kora.lang('s.errors.invalid_list', fieldNames[field]) end
    if #list > fn.fieldLimits[field] then
        return false, Kora.lang('s.errors.list_limit', fieldNames[field], fn.fieldLimits[field])
    end

    local existing = {}
    for _, entry in ipairs(record[field]) do existing[coordKey(entry.coords)] = true end

    for _, entry in ipairs(list) do
        local coords = type(entry) == 'table' and entry.coords
        if type(coords) ~= 'table' then return false, Kora.lang('s.errors.invalid_list', fieldNames[field]) end

        if not existing[coordKey(coords)] then
            if not record.zone then return false, Kora.lang('s.errors.no_zone') end
            if not insideZone(record.zone, coords) then
                return false, Kora.lang('s.errors.inside_zone', fieldNames[field])
            end
        end
    end
    return true
end

local function savePlacement(src, dealer, index, patch)
    local record, err = authorize(src, dealer, index, 'employee')
    if not record then return fn.fail(err) end
    if type(patch) ~= 'table' then return fn.fail(Kora.lang('s.errors.nothing_to_save')) end

    local owner = fn.isOwner(src, dealer)
    local allowed = {}
    for field in pairs(fieldNames) do
        if patch[field] ~= nil then
            if not owner and not (field == 'placements' and fn.canEmployeeDo(src, dealer, 'manageDisplay')) then
                return fn.fail(Kora.lang('s.errors.not_permitted_edit'))
            end

            local valid, reason = validateNewEntries(record, field, patch[field])
            if not valid then return fn.fail(reason) end

            -- Management zones are the only way in to this menu, so the last one can never be removed.
            if field == 'managementZones' and #patch[field] < 1 then
                return fn.fail(Kora.lang('s.errors.keep_management_zone'))
            end
            allowed[field] = patch[field]
        end
    end
    if next(allowed) == nil then return fn.fail(Kora.lang('s.errors.nothing_to_save')) end

    return fn.patchDealership(dealer, allowed)
end

local function depositFunds(src, dealer, index, amount)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end
    if not fn.rateLimit(src, 'funds', Config.rateLimits.funds) then return fn.fail(Kora.lang('s.errors.slow_down')) end

    amount = fn.toAmount(amount, Config.maxBalance)
    if not amount then return fn.fail(Kora.lang('s.errors.amount_invalid')) end
    if fn.management(dealer).balance + amount > Config.maxBalance then
        return fn.fail(Kora.lang('s.errors.balance_limit'))
    end

    if not exports.kora_core:removeMoney(src, 'bank', amount) then return fn.fail(Kora.lang('s.errors.bank_funds')) end

    local data = fn.management(dealer)
    if not fn.updateManagement(dealer, { balance = data.balance + amount }) then
        exports.kora_core:addMoney(src, 'bank', amount)
        return fn.fail(Kora.lang('s.errors.deposit_failed'))
    end
    return { balance = data.balance + amount }
end

local function withdrawFunds(src, dealer, index, amount)
    local record, err = authorize(src, dealer, index, 'owner')
    if not record then return fn.fail(err) end
    if not fn.rateLimit(src, 'funds', Config.rateLimits.funds) then return fn.fail(Kora.lang('s.errors.slow_down')) end

    amount = fn.toAmount(amount, Config.maxBalance)
    if not amount then return fn.fail(Kora.lang('s.errors.amount_invalid')) end

    local data = fn.management(dealer)
    if data.balance < amount then return fn.fail(Kora.lang('s.errors.dealership_funds')) end

    local balance = data.balance - amount
    if not fn.updateManagement(dealer, { balance = balance }) then return fn.fail(Kora.lang('s.errors.withdrawal_failed')) end

    exports.kora_core:addMoney(src, 'bank', amount)
    return { balance = balance }
end

local function orderVehicle(src, dealer, index, model, quantity)
    local record, err = authorize(src, dealer, index, 'orderVehicles')
    if not record then return fn.fail(err) end

    local amount = fn.toAmount(quantity, Config.maxOrderQuantity)
    if not amount then return fn.fail(Kora.lang('s.errors.order_quantity', Config.maxOrderQuantity)) end

    local entry = fn.findVehicle(record, model)
    if not entry then return fn.fail(Kora.lang('s.errors.vehicle_not_sold')) end
    if (tonumber(entry.stock) or 0) + amount > Config.maxStock then
        return fn.fail(Kora.lang('s.errors.stock_limit', Config.maxStock))
    end

    local cost = DealershipOrders.unitCost(entry.price) * amount
    local data = fn.management(dealer)
    if data.balance < cost then
        return fn.fail(Kora.lang('s.errors.order_funds', cost, data.balance))
    end

    if not fn.updateManagement(dealer, { balance = data.balance - cost, spent = data.spent + cost }) then
        return fn.fail(Kora.lang('s.errors.order_save_failed'))
    end

    if not fn.adjustStock(dealer, entry.model, amount) then
        fn.updateManagement(dealer, { balance = data.balance, spent = data.spent })
        return fn.fail(Kora.lang('s.errors.stock_add_failed'))
    end
    return { record = Dealerships[dealer], cost = cost, amount = amount }
end

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
        handledBy = row.acceptor == 'system' and Kora.lang('c.management.offers.autoAccepted') or row.acceptor_name or row.acceptor,
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
        'UPDATE `kora_dealership_offers` SET `status` = ?, `acceptor` = ? WHERE `id` = ? AND `dealership_id` = ? AND `status` = ?',
        { status, acceptor, id, dealer, from }
    )
    return result ~= nil and result.affectedRows == 1
end

local function settleOffer(dealer, id, decision, acceptor)
    local record = Dealerships[dealer]
    if not record or record.type ~= 'owned' then return fn.fail(Kora.lang('s.errors.not_owned')) end

    local rows = Kora.sql.query(
        'SELECT * FROM `kora_dealership_offers` WHERE `id` = ? AND `dealership_id` = ? AND `status` = ?',
        { id, dealer, 'pending' }
    )
    local offer = rows and rows[1]
    if not offer then return fn.fail(Kora.lang('s.errors.offer_handled')) end

    if decision == 'deny' then
        if not claimOffer(id, dealer, 'pending', 'denied', acceptor) then return fn.fail(Kora.lang('s.errors.offer_handled')) end
        return true
    end

    local entry = fn.findVehicle(record, offer.model)
    if not entry then return fn.fail(Kora.lang('s.errors.vehicle_no_longer_sold')) end
    if not fn.inStock(record, entry) then return fn.fail(Kora.lang('s.errors.stock_empty')) end

    if not claimOffer(id, dealer, 'pending', 'accepted', acceptor) then return fn.fail(Kora.lang('s.errors.offer_handled')) end

    local price = math.floor(tonumber(offer.offer_price) or 0)
    local function release()
        claimOffer(id, dealer, 'accepted', 'pending', Kora.sql.NULL)
    end

    if not fn.takeCash(offer.offeror, price) then
        release()
        return fn.fail(Kora.lang('s.errors.offeror_cannot_afford'))
    end

    if not fn.adjustStock(dealer, offer.model, -1) then
        fn.giveCash(offer.offeror, price)
        release()
        return fn.fail(Kora.lang('s.errors.stock_empty'))
    end

    if not fn.creditSale(dealer, price) then
        fn.adjustStock(dealer, offer.model, 1)
        fn.giveCash(offer.offeror, price)
        release()
        return fn.fail(Kora.lang('s.errors.dealership_credit_failed'))
    end

    if not fn.deliverVehicle(offer.offeror, offer.model) then
        fn.creditSale(dealer, -price)
        fn.adjustStock(dealer, offer.model, 1)
        fn.giveCash(offer.offeror, price)
        release()
        return fn.fail(Kora.lang('s.errors.offer_delivery_failed'))
    end
    return true
end

local function resolveOffer(src, dealer, index, offerId, decision)
    local record, err = authorize(src, dealer, index, 'handleOffers')
    if not record then return fn.fail(err) end

    local number = tonumber(offerId)
    local id = number and math.tointeger(number)
    if not decisions[decision] or not id then return fn.fail(Kora.lang('s.errors.offer_invalid')) end

    local ok, reason = settleOffer(dealer, id, decision, fn.citizenId(src))
    if not ok then return fn.fail(reason) end
    return loadOffers(record)
end

-- Offers past their auto-accept time are accepted; one that can no longer be completed is denied.
local function processDueOffers()
    local due = Kora.sql.query(
        'SELECT `id`, `dealership_id` FROM `kora_dealership_offers` WHERE `status` = ? AND `auto_accept_at` IS NOT NULL AND `auto_accept_at` <= NOW() LIMIT 20',
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
        if not ok then print(('^1[kora_dealership] auto-accept failed: %s^7'):format(tostring(err))) end
    end
end

CreateThread(autoAcceptLoop)

Kora.callback.register('kora_dealership:management:openOwnerManagement', openOwnerManagement)
Kora.callback.register('kora_dealership:management:addEmployee', addEmployee)
Kora.callback.register('kora_dealership:management:removeEmployee', removeEmployee)
Kora.callback.register('kora_dealership:management:savePermissions', savePermissions)
Kora.callback.register('kora_dealership:management:saveSettings', saveSettings)
Kora.callback.register('kora_dealership:management:savePlacement', savePlacement)
Kora.callback.register('kora_dealership:management:depositFunds', depositFunds)
Kora.callback.register('kora_dealership:management:withdrawFunds', withdrawFunds)
Kora.callback.register('kora_dealership:management:orderVehicle', orderVehicle)
Kora.callback.register('kora_dealership:management:getOffers', getOffers)
Kora.callback.register('kora_dealership:management:resolveOffer', resolveOffer)
