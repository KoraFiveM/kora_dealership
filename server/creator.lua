Dealerships = {}

-- Runtime-only display swaps: Swaps[dealerId][tostring(placementIndex)] = model
-- Never written to the DB. Cleared on resource/server restart, and whenever an
-- admin edit makes an entry stale (see reconcileSwaps).
local Swaps = {}
GlobalState.DealershipSwaps = Swaps -- reset any value left over from a previous run of this resource

local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'command')
end

local function decode(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    return (ok and decoded) or fallback
end

-- the one place GlobalState.Dealerships is written; call after Dealerships has changed
local function publish()
    GlobalState.Dealerships = Dealerships
end

local function publishSwaps()
    GlobalState.DealershipSwaps = Swaps
end

local function samePlacements(a, b)
    a, b = a or {}, b or {}
    if #a ~= #b then return false end
    for i = 1, #a do
        local p, q = a[i], b[i]
        if p.model ~= q.model then return false end
        local c, d = p.coords, q.coords
        if c.x ~= d.x or c.y ~= d.y or c.z ~= d.z or c.w ~= d.w then return false end
    end
    return true
end

-- Drop swaps an admin edit has invalidated. Returns true if anything changed.
--  * placements changed -> indices may have shifted, so forget all swaps for it
--  * otherwise -> drop swaps to vehicles no longer in the dealership's list
local function reconcileSwaps(id, record, placementsChanged)
    if not Swaps[id] then return false end
    if placementsChanged then
        Swaps[id] = nil
        return true
    end

    local allowed = {}
    for _, vehicle in ipairs(record.vehicles) do allowed[vehicle.model] = true end

    local changed = false
    for key, model in pairs(Swaps[id]) do
        if not allowed[model] then
            Swaps[id][key] = nil
            changed = true
        end
    end
    if next(Swaps[id]) == nil then Swaps[id] = nil end
    return changed
end

local function getVehicleData(model)
    local ok, vehicle = pcall(function()
        return exports.qbcore:getShared('vehicles', model)
    end)

    if not ok or type(vehicle) ~= 'table' then return nil end

    return {
        model = model,
        name = vehicle.name or model,
        price = tonumber(vehicle.price) or 1,
    }
end

local function normalizeVehicles(vehicles)
    local result = {}

    for _, entry in ipairs(vehicles or {}) do
        local model = type(entry) == 'string' and entry
            or type(entry) == 'table' and entry.model

        if type(model) == 'string' then
            model = model:lower()

            local shared = getVehicleData(model)

            if shared then
                result[#result + 1] = {
                    model = model,
                    name = shared.name,
                    price = tonumber(type(entry) == 'table' and entry.price)
                        or shared.price
                        or 1,
                    stock = tonumber(type(entry) == 'table' and entry.stock) or 0,
                }
            end
        end
    end

    return result
end

local function rowToRecord(row)
    local vehicles = decode(row.vehicles, {})
    return {
        id = row.id,
        label = row.label,
        type = row.type,
        price = row.price,
        owner = row.owner,
        zone = decode(row.zone, nil),
        vehicles = normalizeVehicles(vehicles),
        placements = decode(row.placements, {}),
        spawns = decode(row.spawns, {}),
    }
end

local function persist(record)
    local ok, err = QB.sql.transaction({
        {
            sql = [[INSERT INTO `qbdealerships` (`id`,`label`,`type`,`price`,`owner`,`zone`,`vehicles`,`placements`,`spawns`)
                VALUES (?,?,?,?,?,?,?,?,?)
                ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `type` = VALUES(`type`), `price` = VALUES(`price`),
                    `owner` = VALUES(`owner`), `zone` = VALUES(`zone`), `vehicles` = VALUES(`vehicles`),
                    `placements` = VALUES(`placements`), `spawns` = VALUES(`spawns`)]],
            params = {
                record.id, record.label, record.type, record.price or QB.sql.NULL, record.owner or QB.sql.NULL,
                record.zone and json.encode(record.zone) or QB.sql.NULL,
                json.encode(record.vehicles), json.encode(record.placements), json.encode(record.spawns),
            },
        },
    })
    return ok, err
end


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

local function validModel(model)
    if type(model) ~= 'string' then return false end
    local ok, shared = pcall(function() return exports['qb-core']:GetShared('Vehicles') end)
    return ok and type(shared) == 'table' and shared[model] ~= nil
end

local function validCoords(value, needsHeading)
    if type(value) ~= 'table' then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not x or not y or not z then return nil end
    local coords = { x = x, y = y, z = z }
    if needsHeading then
        coords.w = tonumber(value.w) or 0.0
    end
    return coords
end

local function applyPatch(record, patch)
    if type(patch.label) == 'string' and patch.label:match('%S') then
        record.label = patch.label:match('^%s*(.-)%s*$'):sub(1, 128)
    end

    if patch.type == 'public' or patch.type == 'for_sale' or patch.type == 'owned' then
        record.type = patch.type
    end

    if record.type == 'for_sale' then
        local price = tonumber(patch.price) or record.price
        if price and price >= 1 and price <= Config.maxPrice then
            record.price = math.floor(price)
        end
    else
        record.price = nil
    end

    if record.type == 'owned' then
        if type(patch.owner) == 'string' and patch.owner:match('%S') then
            record.owner = patch.owner:match('^%s*(.-)%s*$'):sub(1, 50)
        end
    else
        record.owner = nil
    end

    if patch.clearZone then
        record.zone = nil
    end

    if type(patch.zone) == 'table' and type(patch.zone.points) == 'table' and #patch.zone.points >= 3 then
        local points = {}
        for _, point in ipairs(patch.zone.points) do
            local coords = validCoords(point, false)
            if coords then points[#points + 1] = coords end
        end
        if #points >= 3 then
            record.zone = { points = points, thickness = tonumber(patch.zone.thickness) or 4.0 }
        end
    end

    if type(patch.vehicles) == 'table' then
        local vehicles, seen = {}, {}

        for _, entry in ipairs(patch.vehicles) do
            local model = type(entry) == 'string' and entry
                or type(entry) == 'table' and entry.model
            model = type(model) == 'string' and model:lower() or nil
            if model and not seen[model] and validModel(model) then
                seen[model] = true
                local shared = getVehicleData(model)
                if shared then
                    local price = type(entry) == 'table' and tonumber(entry.price) or nil
                    price = math.floor(price or shared.price or 1)
                    price = math.max(1, math.min(price, Config.maxPrice))

                    vehicles[#vehicles + 1] = {
                        model = model,
                        name = shared.name,
                        price = math.floor(price or shared.price or 1),
                        stock = record.type == 'public' and 9999 or 0
                    }
                end
            end
        end
        record.vehicles = vehicles

        -- keep placements consistent with the vehicle list
        local allowedModels = {}
        for _, vehicle in ipairs(vehicles) do allowedModels[vehicle.model] = true end
        local keptPlacements = {}
        for _, placement in ipairs(record.placements or {}) do
            if allowedModels[placement.model] then keptPlacements[#keptPlacements + 1] = placement end
        end
        record.placements = keptPlacements
    end

    if type(patch.placements) == 'table' then
        local allowed = {}
        for _, vehicle in ipairs(record.vehicles) do
            allowed[vehicle.model] = true
        end

        local placements = {}
        for _, entry in ipairs(patch.placements) do
            local model = type(entry.model) == 'string' and entry.model:lower() or nil
            local coords = validCoords(entry.coords, true)
            if model and allowed[model] and coords then
                placements[#placements + 1] = { model = model, coords = coords }
            end
        end
        record.placements = placements
    end

    if type(patch.spawns) == 'table' then
        local spawns = {}
        for _, entry in ipairs(patch.spawns) do
            local coords = validCoords(entry.coords, true)
            if coords then spawns[#spawns + 1] = { coords = coords } end
        end
        record.spawns = spawns
    end
    return record
end


CreateThread(function()
    QB.sql.query([[UPDATE qbdealerships
        SET vehicles = (
            SELECT JSON_ARRAYAGG(
                JSON_SET(vehicle, '$.stock', 999)
            )
            FROM JSON_TABLE(
                qbdealerships.vehicles,
                '$[*]' COLUMNS (
                    vehicle JSON PATH '$'
                )
            ) AS v
        )
        WHERE type = 'public'
          AND vehicles IS NOT NULL;
        ]])
    local rows = QB.sql.query('SELECT * FROM `qbdealerships`') or {}
    for _, row in ipairs(rows) do
        Dealerships[row.id] = rowToRecord(row)
    end
    GlobalState.Dealerships = Dealerships
end)


QB.callback.register('qbdealership:list', function(src)
    if not isAdmin(src) then return false, 'Admin permission required.' end
    local list = {}
    for id, record in pairs(Dealerships) do
        list[#list + 1] = { id = id, label = record.label, type = record.type, price = record.price, owner = record.owner }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end)

QB.callback.register('qbdealership:get', function(src, id)
    if not isAdmin(src) then return false, 'Admin permission required.' end
    local record = type(id) == 'string' and Dealerships[id]
    if not record then return false, 'Unknown dealership.' end
    return record
end)

QB.callback.register('qbdealership:create', function(src, label)
    if not isAdmin(src) then return false, 'Admin permission required.' end
    if type(label) ~= 'string' or not label:match('%S') then return false, 'A name is required.' end

    local record = {
        id = uniqueId(label),
        label = label:match('^%s*(.-)%s*$'):sub(1, 128),
        type = 'public',
        price = nil,
        owner = nil,
        zone = nil,
        vehicles = {},
        placements = {},
        spawns = {},
    }

    local ok, err = persist(record)
    if not ok then return false, err or 'Failed to create dealership.' end

    Dealerships[record.id] = record
    publish()
    return record
end)

QB.callback.register('qbdealership:delete', function(src, id)
    if not isAdmin(src) then return false, 'Admin permission required.' end
    if type(id) ~= 'string' or not Dealerships[id] then return false, 'Unknown dealership.' end

    local ok, err = QB.sql.update('DELETE FROM `qbdealerships` WHERE `id` = ?', { id })
    if not ok then return false, err or 'Failed to delete dealership.' end

    Dealerships[id] = nil
    Swaps[id] = nil
    publishSwaps()
    publish()
    return true
end)

QB.callback.register('qbdealership:save', function(src, id, patch)
    if not isAdmin(src) then return false, 'Admin permission required.' end
    local record = type(id) == 'string' and Dealerships[id]
    if not record then return false, 'Unknown dealership.' end
    if type(patch) ~= 'table' then return false, 'Nothing to save.' end

    local oldPlacements = record.placements

    -- edit a copy so a failed write can't leave memory/GlobalState ahead of the DB
    local working = applyPatch(json.decode(json.encode(record)), patch)

    local ok, err = persist(working)
    if not ok then return false, err or 'Failed to save.' end

    Dealerships[id] = working

    -- swaps first: if the admin edit made them stale, clients should never see
    -- the new placements with an old swap applied on top
    if reconcileSwaps(id, working, not samePlacements(oldPlacements, working.placements)) then
        publishSwaps()
    end
    publish()
    return working
end)

-- --- runtime display swaps (anyone, memory only) ---------------------------------

local lastSwap = {}
AddEventHandler('playerDropped', function() lastSwap[source] = nil end)

-- model == nil resets that placement back to its saved vehicle
QB.callback.register('qbdealership:swap', function(src, dealerId, index, model)
    local record = type(dealerId) == 'string' and Dealerships[dealerId]
    if not record then return false, 'Unknown dealership.' end

    local n = tonumber(index)
    index = n and math.tointeger(n)
    local placement = index and record.placements[index]
    if not placement then return false, 'Unknown display vehicle.' end

    if model ~= nil then
        if type(model) ~= 'string' then return false, 'Invalid vehicle.' end
        model = model:lower()

        local sold = false
        for _, vehicle in ipairs(record.vehicles) do
            if vehicle.model == model then sold = true break end
        end
        if not sold then return false, 'That vehicle is not sold here.' end
    end

    local now = GetGameTimer()
    if lastSwap[src] and now - lastSwap[src] < Config.swapCooldown then
        return false, 'Slow down.'
    end

    local ped = GetPlayerPed(src)
    local c = placement.coords
    if not ped or ped == 0 or #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) > Config.swapDistance then
        return false, 'You are too far from that vehicle.'
    end

    local key = tostring(index) -- string keys: sparse integer keys don't survive state bag packing reliably
    local forDealer = Swaps[dealerId] or {}
    forDealer[key] = (model and model ~= placement.model) and model or nil
    Swaps[dealerId] = next(forDealer) ~= nil and forDealer or nil

    lastSwap[src] = now
    publishSwaps()
    return true
end)
