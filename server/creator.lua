local function slug(value)
    value = type(value) == 'string' and value:lower():gsub('[^a-z0-9_-]', '-') or ''
    value = value:gsub('%-+', '-'):gsub('^%-', ''):gsub('%-$', '')
    return value ~= '' and value:sub(1, 64) or nil
end

local function uniqueId(label)
    local base = slug(label) or 'dealership'
    local id, n = base, 1
    while Dealerships[id] do
        n = n + 1
        id = ('%s-%d'):format(base, n)
    end
    return id
end

local function adminOnly(src)
    if fn.isAdmin(src) then return true end
    return fn.fail('Admin permission required.')
end

Kora.callback.register('qbdealership:list', function(src)
    local allowed, err = adminOnly(src)
    if not allowed then return false, err end

    local list = {}
    for id, record in pairs(Dealerships) do
        list[#list + 1] = { id = id, label = record.label, type = record.type, price = record.price, owner = record.owner }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end)

Kora.callback.register('qbdealership:get', function(src, id)
    local allowed, err = adminOnly(src)
    if not allowed then return false, err end

    local record = type(id) == 'string' and Dealerships[id]
    if not record then return fn.fail('Unknown dealership.') end
    return record
end)

Kora.callback.register('qbdealership:create', function(src, label)
    local allowed, err = adminOnly(src)
    if not allowed then return false, err end

    label = fn.trim(label, 128)
    if not label then return fn.fail('A name is required.') end

    local record, saveErr = fn.commitDealership({
        id = uniqueId(label),
        label = label,
        type = 'public',
        vehicles = {},
        placements = {},
        spawns = {},
        managementZones = {},
        saleZones = {},
    })
    if not record then return false, saveErr or 'Failed to create dealership.' end
    return record
end)

Kora.callback.register('qbdealership:delete', function(src, id)
    local allowed, err = adminOnly(src)
    if not allowed then return false, err end
    if type(id) ~= 'string' or not Dealerships[id] then return fn.fail('Unknown dealership.') end

    local ok, deleteErr = Kora.sql.update('DELETE FROM `qbdealerships` WHERE `id` = ?', { id })
    if not ok then return false, deleteErr or 'Failed to delete dealership.' end

    fn.forgetDealership(id)
    return true
end)

Kora.callback.register('qbdealership:save', function(src, id, patch)
    local allowed, err = adminOnly(src)
    if not allowed then return false, err end
    if type(id) ~= 'string' then return fn.fail('Unknown dealership.') end
    return fn.patchDealership(id, patch)
end)

Kora.callback.register('qbdealership:swap', function(src, dealerId, index, model)
    local record = type(dealerId) == 'string' and Dealerships[dealerId]
    if not record then return fn.fail('Unknown dealership.') end

    local number = tonumber(index)
    index = number and math.tointeger(number)
    local placement = index and record.placements[index]
    if not placement then return fn.fail('Unknown display vehicle.') end

    if model ~= nil then
        if type(model) ~= 'string' then return fn.fail('Invalid vehicle.') end
        model = model:lower()
        if not fn.findVehicle(record, model) then return fn.fail('That vehicle is not sold here.') end
    end

    if not fn.rateLimit(src, 'swap', Config.swapCooldown) then return fn.fail('Slow down.') end

    local near, err = fn.nearPoint(src, record, 'placements', index, Config.swapDistance)
    if not near then return fn.fail(err) end

    local key = tostring(index)
    local forDealer = Swaps[dealerId] or {}
    forDealer[key] = (model and model ~= placement.model) and model or nil
    Swaps[dealerId] = next(forDealer) ~= nil and forDealer or nil

    fn.publishSwaps()
    return true
end)
