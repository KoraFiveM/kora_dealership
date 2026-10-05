local registerCall = QB.callback.register

local function inZoneAndCan(src, dealer, index, ownerOnly)
    assert((ownerOnly and fn.isOwner(src, dealer)) or (not ownerOnly and (fn.isOwner(src, dealer) or fn.isEmployee(src, dealer))), 'Only the employees can open management.')
    assert(QB.distance.player(src, Dealerships[dealer].managementZones[index].coords, Config.managementDistance), 'You are too far from the management point.')
    return true
end

local function findEmployee(data, cid)
    for id, employee in ipairs(data.employees) do
        if employee.citizenid == cid then return employee, id end
    end
end

local function addEmployee(dealer, cid, name)
    if not DealerData[dealer] then return end
    if findEmployee(DealerData[dealer], cid) then return end
    DealerData[dealer].employees[#DealerData[dealer].employees + 1] = { citizenid = cid, name = name }
    DealerData[dealer].permissions[cid] = {}
    QB.sql.query('UPDATE qbdealership_management SET employees = ?, employee_permissions = ? WHERE dealership_id = ?', { json.encode(DealerData[dealer].employees), json.encode(DealerData[dealer].permissions), dealer })
    fn.publishStaff()
    return DealerData[dealer].employees
end

local function removeEmployee(dealer, cid)
    if not DealerData[dealer] then return end
    local data = DealerData[dealer]
    local _, employeeIndex = findEmployee(data, cid)
    if not employeeIndex then return end
    table.remove(data.employees, employeeIndex)
    data.permissions[cid] = nil
    QB.sql.query('UPDATE qbdealership_management SET employees = ?, employee_permissions = ? WHERE dealership_id = ?', { json.encode(data.employees), json.encode(data.permissions), dealer })
    fn.publishStaff()
    return data.employees
end

local function updatePermission(dealer, cid, list)
    local data = DealerData[dealer]
    if not findEmployee(data, cid) then return false end
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
    DealerData[dealer].permissions = permissions
    QB.sql.query('UPDATE qbdealership_management SET employee_permissions = ? WHERE dealership_id = ?', { json.encode(permissions), dealer })
    fn.publishStaff()
    return permissions
end

registerCall('qbdealership:management:openOwnerManagement', function(src, dealer, index)
    if not inZoneAndCan(src, dealer, index, false) then return end
    local data = DealerData[dealer]
    return {
        owner = fn.isOwner(src, dealer),
        employees = data.employees,
        permissions = data.permissions,
        settings = data.settings,
        balance = { balance = data.balance, income = data.income, spent = data.spent }
    }
end)


registerCall('qbdealership:management:addEmployee', function(src, dealer, index, serverId)
    if not inZoneAndCan(src, dealer, index, true) then return end
    local data = DealerData[dealer]
    if #data.employees >= Config.maxEmployees then
        return fn.notify(src, 'This dealership has reached its employee limit.', 'error')
    end
    return addEmployee(dealer, fn.playerCid(tonumber(serverId)), fn.playerName(tonumber(serverId)))
end)

registerCall('qbdealership:management:removeEmployee', function(src, dealer, index, cid)
    if not inZoneAndCan(src, dealer, index, true) then return end
    return removeEmployee(dealer, cid)
end)

registerCall('qbdealership:management:savePermissions', function(src, dealer, index, cid, list)
    if not inZoneAndCan(src, dealer, index, true) then return end
    local permissions = updatePermission(dealer, cid, list)
    if not permissions then return fn.notify(src, 'Could not save permissions.', 'error') end
    return permissions
end)

registerCall('qbdealership:management:saveSettings', function(src, dealer, index, values)
    if not inZoneAndCan(src, dealer, index, true) then return end
    if type(values) ~= 'table' then return fn.notify(src, 'Invalid settings.', 'error') end

    local settings = {}
    for key, default in pairs(fn.defaultSettings) do
        local value = tonumber(values[key])
        settings[key] = value and math.max(0, math.min(100, math.floor(value))) or default
    end

    DealerData[dealer].settings = settings
    QB.sql.query('UPDATE qbdealership_management SET settings = ? WHERE dealership_id = ?', { json.encode(settings), dealer })
    return settings
end)

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

registerCall('qbdealership:management:save', function(src, dealer, index, employee, perm)
    if not inZoneAndCan(src, dealer, index, true) then return end
    if not employee or not perm then return fn.fail('Invalid employee or permission.') end
    return updatePermission(dealer, employee, perm)
end, true)



registerCall('qbdealership:management:depositFunds', function(src, dealer, index, amount)
    if not inZoneAndCan(src, dealer, index, true) then return end
    amount = tonumber(amount) or 0
    if amount < 1 then return fn.fail('Enter a valid amount.') end
    if not exports.qbcore:removeMoney(src, 'bank', amount) then return fn.notify(src, 'Not enough money in your bank account.', 'error') end
    local balance = DealerData[dealer].balance
    balance = balance + amount
    DealerData[dealer].balance = balance
    QB.sql.query('UPDATE dealership_management SET current_balance = ? WHERE dealer = ?', { balance, dealer })

    return { balance = balance }
end)


registerCall('qbdealership:management:withdrawFunds', function(src, dealer, index, amount)
    if not inZoneAndCan(src, dealer, index, true) then return end
    amount = tonumber(amount) or 0
    if amount < 1 then return fn.fail('Enter a valid amount.') end

    local data = DealerData[dealer]
    local balance = data.balance
    if balance < amount then return fn.fail('The dealership does not have enough funds.') end
    balance = balance - amount
    DealerData[dealer].balance = balance
    QB.sql.query('UPDATE dealership_management SET current_balance = ? WHERE dealer = ?', { balance, dealer })
    exports.qbcore:addMoney(src, 'bank', amount)
    return { balance = balance }
end)

registerCall('qbdealership:management:orderVehicle', function(_, dealer, index, model, quantity)
    if not inZoneAndCan(_, dealer, index, false) then return end
    local amount = tonumber(quantity)

    if not amount or amount < 1 or amount > Config.maxOrderQuantity then
        return fn.notify(('Order between 1 and %d vehicles.'):format(Config.maxOrderQuantity), 'error')
    end

    model = type(model) == 'string' and model:lower()

    local entry = model and fn.findVehicle(dealer, model)
    if not entry then return fn.fail('That vehicle is not sold here.') end

    if (tonumber(entry.stock) or 0) + amount > Config.maxStock then
        return fn.fail(('This would exceed the stock limit of %d.'):format(Config.maxStock))
    end

    local cost = DealershipOrders.unitCost(entry.price) * amount
    local data = DealerData[dealer]

    if data.balance < cost then
        return fn.fail(('Not enough dealership funds ($%d needed, $%d available).'):format(cost, data.balance))
    end
    data.balance = data.balance - cost
    QB.sql.query('UPDATE dealership_management SET current_balance = ? WHERE dealer = ?', { data.balance, dealer })
    fn.adjustStock(dealer, model, amount)
    return { record = Dealerships[dealer], cost = cost, amount = amount }
end)

local function authorizeOffers(src, dealer)
    local record = Dealerships[dealer]
    if not record or record.type ~= 'owned' then return nil, 'This dealership is not owned.' end
    if not fn.canEmployeeDo(src, dealer, 'handleOffers') then return nil, 'You are not permitted to view offers here.' end
    if not fn.nearAny(src, record.managementZones, Config.managementDistance) then
        return nil, 'You are too far from the management point.'
    end
    return record
end

local function formatTime(value)
    if not value or value == QB.sql.NULL then return nil end
    if type(value) == 'number' then
        local seconds = value > 1e11 and math.floor(value / 1000) or math.floor(value)
        return os.date('!%Y-%m-%d %H:%M UTC', seconds)
    end
    return tostring(value):sub(1, 16) .. ' UTC'
end

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

registerCall('qbdealership:management:getOffers', function(src, dealer, index)
    assert(src, dealer, index, "missing parameter(s)")

    local record, err = authorizeOffers(src, dealer)
    if not record then return fn.fail(err) end
    return loadOffers(record, onlineNames())
end)

local decisions = { accept = 'accepted', deny = 'denied' }

local function getOfferData(dealer, offerId)
    for i = 1, #Offers[dealer] do
        if Offers[dealer][i].id == offerId then
            return Offers[dealer][i]
        end
    end
    return nil
end

registerCall('qbdealership:management:resolveOffer', function(src, dealer, offerId, decision)
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