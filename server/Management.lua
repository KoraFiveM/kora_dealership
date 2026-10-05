
local function authorize(src, dealer, skipDistance)
    local record = Dealerships[dealer]
    if not record then return nil, 'Unknown dealership.' end
    if record.type ~= 'owned' or not fn.isOwner(src, dealer) then
        return nil, 'Only the owner can manage this dealership.'
    end
    if not skipDistance and not fn.nearAny(src, record.managementZones, Config.managementDistance) then
        return nil, 'You are too far from the management point.'
    end
    return record
end

-- Every management callback is owner-only; the handler receives (src, record, ...).
local function register(name, handler, skipDistance)
    QB.callback.register('qbdealership:management:' .. name, function(src, dealer, ...)
        local record, err = authorize(src, dealer, skipDistance)
        if not record then return fn.fail(err) end
        return handler(src, record, ...)
    end)
end

local function findEmployee(data, cid)
    for _, employee in ipairs(data.employees) do
        if employee.citizenid == cid then return employee end
    end
end

-- --- employees, permissions, settings ---------------------------------------------------

register('getEmployees', function(_, record)
    return fn.management(record.id).employees
end)

register('getEmployeePermissions', function(_, record)
    return fn.management(record.id).permissions
end)

register('getSettings', function(_, record)
    return fn.management(record.id).settings
end)

register('addEmployee', function(_, record, serverId)
    local id = math.tointeger(tonumber(serverId))
    if not id or id < 1 then return fn.fail('Enter a valid server ID.') end

    local cid = fn.citizenId(id)
    if not cid then return fn.fail('No online player with that ID.') end
    if cid == record.owner then return fn.fail('The owner cannot be added as an employee.') end

    local data = fn.management(record.id)
    if #data.employees >= Config.maxEmployees then return fn.fail('This dealership has reached its employee limit.') end
    if findEmployee(data, cid) then return fn.fail('That player is already an employee.') end

    local employees = fn.copy(data.employees)
    employees[#employees + 1] = { citizenid = cid, name = fn.playerName(id) }

    if not fn.updateManagement(record.id, { employees = employees }) then return fn.fail('Could not save the employee.') end
    fn.publishStaff()
    return employees
end)

register('removeEmployee', function(_, record, cid)
    local data = fn.management(record.id)
    if not findEmployee(data, cid) then return fn.fail('That employee no longer exists.') end

    local kept = {}
    for _, employee in ipairs(data.employees) do
        if employee.citizenid ~= cid then kept[#kept + 1] = employee end
    end

    local permissions = fn.copy(data.permissions)
    permissions[cid] = nil

    if not fn.updateManagement(record.id, { employees = kept, permissions = permissions }) then
        return fn.fail('Could not remove the employee.')
    end
    fn.publishStaff()
    return kept
end)

register('savePermissions', function(_, record, cid, list)
    if type(list) ~= 'table' then return fn.fail('Invalid permissions.') end

    local data = fn.management(record.id)
    if not findEmployee(data, cid) then return fn.fail('That employee no longer exists.') end

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

    if not fn.updateManagement(record.id, { permissions = permissions }) then return fn.fail('Could not save permissions.') end
    fn.publishStaff()
    return permissions
end)

register('saveSettings', function(_, record, values)
    if type(values) ~= 'table' then return fn.fail('Invalid settings.') end

    local settings = {}
    for key, default in pairs(fn.defaultSettings) do
        local value = tonumber(values[key])
        settings[key] = value and math.max(0, math.min(100, math.floor(value))) or default
    end

    if not fn.updateManagement(record.id, { settings = settings }) then return fn.fail('Could not save settings.') end
    return settings
end)

-- --- placements, spawns and zone points -----------------------------------------------------

-- Ray casting on x/y, then z within the zone's vertical extent (point z range +/- half the thickness).
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

local fieldNames = {
    placements = 'Display vehicles',
    spawns = 'Spawn points',
    managementZones = 'Management zones',
    saleZones = 'Sale zones',
}

-- Only entries that are new must be inside the dealership zone, so removing a point (or editing
-- after an admin redrew the zone) never fails on points that were already saved.
local function validateNewEntries(record, field, list)
    if type(list) ~= 'table' then return false, 'Invalid ' .. field .. '.' end

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

-- The owner may only touch these fields; name, type, price, owner, zone and the vehicle list
-- stay admin-only. No distance check: new points just have to be inside the dealership zone.
register('save', function(_, record, patch)
    if type(patch) ~= 'table' then return fn.fail('Nothing to save.') end

    local allowed = {}
    for field in pairs(fieldNames) do
        if patch[field] ~= nil then
            local valid, reason = validateNewEntries(record, field, patch[field])
            if not valid then return fn.fail(reason) end
            allowed[field] = patch[field]
        end
    end
    if next(allowed) == nil then return fn.fail('Nothing to save.') end

    return fn.patchDealership(record.id, allowed)
end, true)

-- --- funds -----------------------------------------------------------------------------------

register('getBalance', function(_, record)
    local data = fn.management(record.id)
    return { balance = data.balance, income = data.income, spent = data.spent }
end)

-- The owner's own bank account -> the dealership's funds.
register('depositFunds', function(src, record, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return fn.fail('Enter a valid amount.') end
    if not exports.qbcore:removeMoney(src, 'bank', amount) then return fn.fail('Not enough money in your bank account.') end

    local updated = fn.updateManagement(record.id, { balance = fn.management(record.id).balance + amount })
    if not updated then
        exports.qbcore:addMoney(src, 'bank', amount) -- the deposit never landed
        return fn.fail('Could not deposit the funds.')
    end
    return { balance = updated.balance }
end)

-- The dealership's funds -> the owner's own bank account.
register('withdrawFunds', function(src, record, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return fn.fail('Enter a valid amount.') end

    local data = fn.management(record.id)
    if data.balance < amount then return fn.fail('The dealership does not have enough funds.') end

    local updated = fn.updateManagement(record.id, { balance = data.balance - amount })
    if not updated then return fn.fail('Could not withdraw the funds.') end

    exports.qbcore:addMoney(src, 'bank', amount)
    return { balance = updated.balance }
end)

register('orderVehicle', function(_, record, model, quantity)
    local amount = math.tointeger(tonumber(quantity))
    if not amount or amount < 1 or amount > Config.maxOrderQuantity then
        return fn.fail(('Order between 1 and %d vehicles.'):format(Config.maxOrderQuantity))
    end

    model = type(model) == 'string' and model:lower()
    local entry = model and fn.findVehicle(record, model)
    if not entry then return fn.fail('That vehicle is not sold here.') end

    if (tonumber(entry.stock) or 0) + amount > Config.maxStock then
        return fn.fail(('This would exceed the stock limit of %d.'):format(Config.maxStock))
    end

    local cost = DealershipOrders.unitCost(entry.price) * amount
    local data = fn.management(record.id)
    if data.balance < cost then
        return fn.fail(('Not enough dealership funds ($%d needed, $%d available).'):format(cost, data.balance))
    end

    if not fn.updateManagement(record.id, { balance = data.balance - cost, spent = data.spent + cost }) then
        return fn.fail('Could not place the order.')
    end

    fn.adjustStock(record.id, model, amount)
    return { record = Dealerships[record.id], cost = cost, amount = amount }
end)

-- --- offers -----------------------------------------------------------------------------------

-- The Offers page is visible to the owner AND to employees granted 'handleOffers', while every
-- other callback in this file is owner-only, so it does its own authorization.
local function authorizeOffers(src, dealer)
    local record = Dealerships[dealer]
    if not record or record.type ~= 'owned' then return nil, 'This dealership is not owned.' end
    if not fn.canEmployeeDo(src, dealer, 'handleOffers') then return nil, 'You are not permitted to view offers here.' end
    if not fn.nearAny(src, record.managementZones, Config.managementDistance) then
        return nil, 'You are too far from the management point.'
    end
    return record
end

-- offers.auto_accept_at is stored as a UTC string; depending on the SQL wrapper a datetime comes
-- back as a string or as epoch milliseconds, so accept both.
local function formatTime(value)
    if not value or value == QB.sql.NULL then return nil end
    if type(value) == 'number' then
        local seconds = value > 1e11 and math.floor(value / 1000) or math.floor(value)
        return os.date('!%Y-%m-%d %H:%M UTC', seconds)
    end
    return tostring(value):sub(1, 16) .. ' UTC'
end

-- citizenid -> name for everyone online; offline offerors fall back to their citizenid.
local function onlineNames()
    local names = {}
    for _, id in ipairs(GetPlayers()) do
        local player = tonumber(id)
        local cid = player and fn.citizenId(player)
        if cid then names[cid] = fn.playerName(player) end
    end
    return names
end

local function toOffer(record, row, names)
    local entry = fn.findVehicle(record, row.model)
    return {
        id = row.id,
        model = row.model,
        name = entry and entry.name or row.model,
        asking = entry and math.floor(tonumber(entry.price) or 0) or nil,
        price = math.floor(tonumber(row.offer_price) or 0),
        terms = row.offer_text or '',
        offeror = names[row.offeror] or row.offeror,
        status = row.status,
        -- who handled it (the `acceptor` column is set for denials too)
        handledBy = row.acceptor and (names[row.acceptor] or row.acceptor) or nil,
        expiry = formatTime(row.auto_accept_at),
    }
end

local offerColumns = '`id`, `model`, `offer_price`, `offer_text`, `auto_accept_at`, `status`, `offeror`, `acceptor`'

-- pending = waiting on a decision (left); history = everything already accepted or denied (right).
local function loadOffers(record, names)
    local limit = math.max(1, math.floor(tonumber(Config.offersPageLimit) or 50))

    local pendingRows = QB.sql.query(
        'SELECT ' .. offerColumns .. ' FROM `qbdealership_offers` WHERE `dealership_id` = ? AND `status` = ? '
        .. ('ORDER BY `id` DESC LIMIT %d'):format(limit),
        { record.id, 'pending' }
    ) or {}

    local historyRows = QB.sql.query(
        'SELECT ' .. offerColumns .. ' FROM `qbdealership_offers` WHERE `dealership_id` = ? AND `status` IN (?, ?) '
        .. ('ORDER BY `updated_at` DESC, `id` DESC LIMIT %d'):format(limit),
        { record.id, 'accepted', 'denied' }
    ) or {}

    local result = { pending = {}, history = {} }
    for _, row in ipairs(pendingRows) do result.pending[#result.pending + 1] = toOffer(record, row, names) end
    for _, row in ipairs(historyRows) do result.history[#result.history + 1] = toOffer(record, row, names) end
    return result
end

-- The in-memory `Offers` cache only holds pending offers, so rebuild it after one is resolved.
local function refreshOfferCache(dealer)
    Offers[dealer] = nil
    local rows = QB.sql.query('SELECT * FROM `qbdealership_offers` WHERE `dealership_id` = ? AND `status` = ?', { dealer, 'pending' }) or {}
    for _, row in ipairs(rows) do
        Offers[dealer] = Offers[dealer] or {}
        table.insert(Offers[dealer], {
            model = row.model,
            price = row.offer_price,
            additional = row.offer_text,
            offeror = row.offeror,
            expiry = row.auto_accept_at,
        })
    end
end

QB.callback.register('qbdealership:management:getOffers', function(src, dealer)
    local record, err = authorizeOffers(src, dealer)
    if not record then return fn.fail(err) end
    return loadOffers(record, onlineNames())
end)

local decisions = { accept = 'accepted', deny = 'denied' }

local function getOfferData(dealer, offerId)
    for i = 1, #Offers[dealer] do
        QB.print.debug(Offers[dealer][i], offerId)
        if Offers[dealer][i].id == offerId then
            return Offers[dealer][i]
        end
    end
    return nil
end
QB.callback.register('qbdealership:management:resolveOffer', function(src, dealer, offerId, decision)
    local record, err = authorizeOffers(src, dealer)
    if not record then return fn.fail(err) end

    local status = decisions[decision]
    local id = math.tointeger(tonumber(offerId))
    if not status or not id then return fn.fail('Invalid offer.') end
    local row = (QB.sql.query('SELECT `status` FROM `qbdealership_offers` WHERE `id` = ? AND `dealership_id` = ?', { id, record.id }) or {})[1]
    if not row then return fn.fail('That offer no longer exists.') end
    if row.status ~= 'pending' then return fn.fail('That offer has already been handled.') end
--
    local cid = fn.citizenId(src)
    QB.sql.query(
        'UPDATE `qbdealership_offers` SET `status` = ?, `acceptor` = ? WHERE `id` = ? AND `dealership_id` = ? AND `status` = ?',
        { status, cid, id, record.id, 'pending' }
    )
--
    local after = (QB.sql.query('SELECT `status`, `acceptor` FROM `qbdealership_offers` WHERE `id` = ? AND `dealership_id` = ?', { id, record.id }) or {})[1]
    if not after or after.status ~= status or after.acceptor ~= cid then
        return fn.fail('That offer has already been handled.')
    end
    fn.deliverVehicle(getOfferData(dealer, offerId).offeror, getOfferData(dealer, offerId).model, fn.getFreeSpawn(Dealerships[dealer].spawns))
    refreshOfferCache(dealer)
    return loadOffers(record, onlineNames())
end)