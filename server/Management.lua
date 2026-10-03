local busy = {}

local defaultSettings = { maxPriceOverride = 10, commission = 5, employeeDiscount = 5 }

local function fail(message)
    return false, message
end

local function decode(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    return (ok and type(decoded) == 'table' and decoded) or fallback
end

local function citizenId(src)
    local data = exports.qbcore:getPlayerData(src)
    return data and data.citizenid or nil
end

-- Every management callback goes through here: owned dealership and the caller is the owner.
-- Unless skipDistance is set, the caller must also be standing at one of its management points.
local function authorize(src, dealer, skipDistance)
    local record = type(dealer) == 'string' and Dealerships[dealer]
    if not record then return nil, 'Unknown dealership.' end
    if record.type ~= 'owned' or not record.owner then return nil, 'This dealership is not owned.' end
    if citizenId(src) ~= record.owner then return nil, 'Only the owner can manage this dealership.' end
    if skipDistance then return record end

    for _, zone in ipairs(record.managementZones or {}) do
        if QB.distance.player(src, zone.coords, Config.managementDistance) then return record end
    end
    return nil, 'You are too far from the management point.'
end

local function loadRow(dealer)
    QB.sql.query('INSERT IGNORE INTO `qbdealership_management` (`dealership_id`) VALUES (?)', { dealer })
    local rows = QB.sql.query(
        'SELECT * FROM `qbdealership_management` WHERE `dealership_id` = ?',
        { dealer }
    )
    return rows and rows[1]
end

local function readEmployees(row)
    local list = {}
    for _, entry in ipairs(decode(row.employees, {})) do
        if type(entry) == 'table' and type(entry.citizenid) == 'string' then
            list[#list + 1] = { citizenid = entry.citizenid, name = tostring(entry.name or entry.citizenid) }
        end
    end
    return list
end Z9FH4ATU

local function readSettings(row)
    local stored = decode(row.settings, {})
    local settings = {}
    for key, default in pairs(defaultSettings) do
        settings[key] = tonumber(stored[key]) or default
    end
    return settings
end

local function writeColumn(dealer, column, value)
    return QB.sql.update(
        'UPDATE `qbdealership_management` SET `' .. column .. '` = ? WHERE `dealership_id` = ?',
        { json.encode(value), dealer }
    )
end

local function copy(value)
    return json.decode(json.encode(value))
end

local function findVehicle(record, model)
    for _, entry in ipairs(record.vehicles or {}) do
        if entry.model == model then return entry end
    end
end

-- --- employees / settings / permissions -----------------------------------------

QB.callback.register('qbdealership:management:getEmployees', function(src, dealer)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end
    local row = loadRow(dealer)
    if not row then return fail('Could not load employees.') end
    return readEmployees(row)
end)

QB.callback.register('qbdealership:management:getSettings', function(src, dealer)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end
    local row = loadRow(dealer)
    if not row then return fail('Could not load settings.') end
    return readSettings(row)
end)

QB.callback.register('qbdealership:management:getEmployeePermissions', function(src, dealer)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end
    local row = loadRow(dealer)
    if not row then return fail('Could not load permissions.') end
    return decode(row.employee_permissions, {})
end)

QB.callback.register('qbdealership:management:addEmployee', function(src, dealer, serverId)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end

    local id = math.tointeger(tonumber(serverId))
    if not id or id < 1 then return fail('Enter a valid server ID.') end

    local target = exports.qbcore:getPlayerData(id)
    local cid = target and target.citizenid
    if not cid then return fail('No online player with that ID.') end
    if cid == record.owner then return fail('The owner cannot be added as an employee.') end

    local row = loadRow(dealer)
    if not row then return fail('Could not load employees.') end
    local employees = readEmployees(row)

    if #employees >= Config.maxEmployees then return fail('This dealership has reached its employee limit.') end
    for _, employee in ipairs(employees) do
        if employee.citizenid == cid then return fail('That player is already an employee.') end
    end

    local info = target.charinfo or {}
    local name = ('%s %s'):format(info.firstname or '', info.lastname or ''):match('^%s*(.-)%s*$')
    employees[#employees + 1] = { citizenid = cid, name = name ~= '' and name or cid }

    if not writeColumn(dealer, 'employees', employees) then return fail('Could not save the employee.') end
    return employees
end)

QB.callback.register('qbdealership:management:removeEmployee', function(src, dealer, cid)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end
    if type(cid) ~= 'string' then return fail('Invalid employee.') end

    local row = loadRow(dealer)
    if not row then return fail('Could not load employees.') end

    local kept, found = {}, false
    for _, employee in ipairs(readEmployees(row)) do
        if employee.citizenid == cid then found = true else kept[#kept + 1] = employee end
    end
    if not found then return fail('That employee no longer exists.') end

    local permissions = decode(row.employee_permissions, {})
    permissions[cid] = nil

    if not writeColumn(dealer, 'employees', kept) then return fail('Could not remove the employee.') end
    writeColumn(dealer, 'employee_permissions', permissions)
    return kept
end)

QB.callback.register('qbdealership:management:savePermissions', function(src, dealer, cid, list)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end
    if type(cid) ~= 'string' or type(list) ~= 'table' then return fail('Invalid permissions.') end

    local row = loadRow(dealer)
    if not row then return fail('Could not load permissions.') end

    local isEmployee = false
    for _, employee in ipairs(readEmployees(row)) do
        if employee.citizenid == cid then isEmployee = true break end
    end
    if not isEmployee then return fail('That employee no longer exists.') end

    local allowed = {}
    for _, entry in ipairs(Config.employeePermissions) do allowed[entry.value] = true end

    local granted, seen = {}, {}
    for _, permission in ipairs(list) do
        if type(permission) == 'string' and allowed[permission] and not seen[permission] then
            seen[permission] = true
            granted[#granted + 1] = permission
        end
    end

    local permissions = decode(row.employee_permissions, {})
    permissions[cid] = granted

    if not writeColumn(dealer, 'employee_permissions', permissions) then return fail('Could not save permissions.') end
    return permissions
end)

QB.callback.register('qbdealership:management:saveSettings', function(src, dealer, values)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end
    if type(values) ~= 'table' then return fail('Invalid settings.') end

    local settings = {}
    for key, default in pairs(defaultSettings) do
        local value = tonumber(values[key])
        settings[key] = value and math.max(0, math.min(100, math.floor(value))) or default
    end

    loadRow(dealer)
    if not writeColumn(dealer, 'settings', settings) then return fail('Could not save settings.') end
    return settings
end)

-- --- placements / spawns / zone points ------------------------------------------

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
    if not x or not y or not z then return false end
    if not insidePolygon(x, y, zone.points) then return false end

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

-- Only entries that are new in the patch must be inside the dealership zone, so removing a point
-- (or editing after an admin redrew the zone) never fails on points that were already saved.
local function validateNewEntries(record, field, list)
    if type(list) ~= 'table' then return false, 'Invalid ' .. field .. '.' end

    local existing = {}
    for _, entry in ipairs(record[field] or {}) do
        if type(entry) == 'table' and type(entry.coords) == 'table' then existing[coordKey(entry.coords)] = true end
    end

    for _, entry in ipairs(list) do
        local coords = type(entry) == 'table' and entry.coords
        if type(coords) ~= 'table' then return false, 'Invalid ' .. field .. '.' end
        if not existing[coordKey(coords)] then
            if not record.zone then
                return false, 'This dealership has no zone yet. Ask an admin to draw it first.'
            end
            if not insideZone(record.zone, coords) then
                return false, ('%s must be inside the dealership zone.'):format(fieldNames[field])
            end
        end
    end
    return true
end

-- The owner may only touch these fields; label, type, price, owner, zone and the
-- vehicle list stay admin-only.
local ownerEditable = { 'placements', 'spawns', 'managementZones', 'saleZones' }

QB.callback.register('qbdealership:management:save', function(src, dealer, patch)
    local record, err = authorize(src, dealer, true)
    if not record then return fail(err) end
    if type(patch) ~= 'table' then return fail('Nothing to save.') end

    local allowedPatch = {}
    for _, key in ipairs(ownerEditable) do allowedPatch[key] = patch[key] end
    if next(allowedPatch) == nil then return fail('Nothing to save.') end

    for field, list in pairs(allowedPatch) do
        local valid, reason = validateNewEntries(record, field, list)
        if not valid then return fail(reason) end
    end

    return SaveDealership(dealer, allowedPatch)
end)

-- --- funds ------------------------------------------------------------------------

local function readBalance(row)
    return math.floor(tonumber(row.current_balance) or 0)
end

QB.callback.register('qbdealership:management:getBalance', function(src, dealer)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end
    local row = loadRow(dealer)
    if not row then return fail('Could not load the balance.') end
    QB.print.debug(row)
    return {
        balance = readBalance(row),
        income = math.floor(tonumber(row.income) or 0),
        spent = math.floor(tonumber(row.spent) or 0),
    }
end)

-- Moves money from the owner's own bank account into the dealership's funds. Like every
-- other management action, the owner still has to be standing at a management point.
QB.callback.register('qbdealership:management:depositFunds', function(src, dealer, amount)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end

    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return fail('Enter a valid amount.') end

    if not exports.qbcore:removeMoney(src, 'bank', amount) then
        return fail('Not enough money in your bank account.')
    end

    loadRow(dealer)
    if not QB.sql.update('UPDATE `qbdealership_management` SET `current_balance` = `current_balance` + ? WHERE `dealership_id` = ?', { amount, dealer }) then
        exports.qbcore:addMoney(src, 'bank', amount) -- refund -- the deposit never landed
        return fail('Could not deposit the funds.')
    end

    local row = loadRow(dealer)
    return { balance = row and readBalance(row) or nil }
end)

-- Moves money from the dealership's funds back into the owner's own bank account.
QB.callback.register('qbdealership:management:withdrawFunds', function(src, dealer, amount)
    local record, err = authorize(src, dealer)
    if not record then return fail(err) end

    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return fail('Enter a valid amount.') end

    local row = loadRow(dealer)
    if not row then return fail('Could not load the balance.') end
    if readBalance(row) < amount then return fail('The dealership does not have enough funds.') end

    if not QB.sql.update('UPDATE `qbdealership_management` SET `current_balance` = `current_balance` - ? WHERE `dealership_id` = ? AND `current_balance` >= ?', { amount, dealer, amount }) then
        return fail('Could not withdraw the funds.')
    end

    exports.qbcore:addMoney(src, 'bank', amount)

    local updated = loadRow(dealer)
    return { balance = updated and readBalance(updated) or nil }
end)

-- --- ordering stock ---------------------------------------------------------------

QB.callback.register('qbdealership:management:orderVehicle', function(src, dealer, model, quantity)
    if busy[src] then return fail('Please wait.') end
    busy[src] = true

    local ok, result, message = pcall(function()
        local record, err = authorize(src, dealer)
        if not record then return fail(err) end

        model = type(model) == 'string' and model:lower() or nil
        local amount = math.tointeger(tonumber(quantity))
        if not model or not amount or amount < 1 or amount > Config.maxOrderQuantity then
            return fail(('Order between 1 and %d vehicles.'):format(Config.maxOrderQuantity))
        end

        local entry = findVehicle(record, model)
        if not entry then return fail('That vehicle is not sold here.') end

        local stock = math.floor(tonumber(entry.stock) or 0)
        if stock + amount > Config.maxStock then
            return fail(('This would exceed the stock limit of %d.'):format(Config.maxStock))
        end

        local cost = DealershipOrders.unitCost(entry.price) * amount

        local fundsRow = loadRow(dealer)
        if not fundsRow then return fail('Could not load the dealership funds.') end
        local balance = readBalance(fundsRow)
        if balance < cost then
            return fail(('Not enough dealership funds ($%d needed, $%d available).'):format(cost, balance))
        end

        -- Add the stock first, then take payment from the dealership's funds; if payment
        -- fails, take that stock back off the *current* record so a concurrent sale is
        -- never overwritten.
        local working = copy(record)
        findVehicle(working, model).stock = stock + amount
        local committed, commitErr = CommitDealership(working)
        if not committed then return fail(commitErr or 'Could not place the order.') end

        local paid = QB.sql.update(
            'UPDATE `qbdealership_management` SET `current_balance` = `current_balance` - ?, `spent` = `spent` + ? WHERE `dealership_id` = ? AND `current_balance` >= ?',
            { cost, cost, dealer, cost }
        )
        if not paid then
            local current = copy(Dealerships[dealer])
            local currentEntry = findVehicle(current, model)
            if currentEntry then
                currentEntry.stock = math.max(0, math.floor(tonumber(currentEntry.stock) or 0) - amount)
            end
            return fail(('Not enough dealership funds ($%d needed).'):format(cost))
        end

        return { record = Dealerships[dealer], cost = cost, amount = amount }
    end)

    busy[src] = nil
    if not ok then
        print(('[qbdealership] order error for %s: %s'):format(src, tostring(result)))
        return fail('Could not place the order.')
    end
    return result, message
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)