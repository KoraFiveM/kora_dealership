Dealership = Dealership or {}

local Schema = {}
Dealership.schema = Schema

local function number(value, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value < minimum or value > maximum then return nil end
    return value + 0.0
end

local function text(value, maximum, optional)
    if value == nil and optional then return nil end
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    if value == '' then return nil end
    return value:sub(1, maximum)
end

function Schema.slug(value)
    value = type(value) == 'string' and value:lower():gsub('[^a-z0-9_-]', '-') or ''
    value = value:gsub('%-+', '-'):gsub('^%-', ''):gsub('%-$', '')
    return value ~= '' and value:sub(1, 64) or nil
end

function Schema.coords(value, heading)
    if type(value) ~= 'table' then return nil end
    local coords = {
        x = number(value.x, -10000, 10000),
        y = number(value.y, -10000, 10000),
        z = number(value.z, -2000, 3000),
    }
    if not coords.x or not coords.y or not coords.z then return nil end
    if heading then
        coords.w = number(value.w or value.heading or 0, -360, 360)
        if not coords.w then return nil end
    end
    return coords
end

local function normaliseModels(value)
    local out, seen = {}, {}
    if type(value) ~= 'table' then return out, seen end
    for _, raw in ipairs(value) do
        local model = type(raw) == 'table' and (raw.model or raw.vehicle) or raw
        model = type(model) == 'string' and model:lower():match('^[%w_-]+$') or nil
        if model and not seen[model] then
            seen[model] = true
            out[#out + 1] = model:sub(1, 60)
        end
    end
    return out, seen
end

function Schema.normaliseDealership(value)
    if type(value) ~= 'table' then return nil, 'Dealership must be an object.' end
    local id = Schema.slug(value.id)
    local label = text(value.label, 128)
    if not id or not label then return nil, 'A valid id and name are required.' end

    local zone = type(value.zone) == 'table' and value.zone or {}
    -- Compatibility with the original config shape.
    if not zone.coords and value.coords then zone = {
        coords = value.coords, size = value.size, rotation = value.rotation,
        distance = value.distance, bucket = value.bucket,
    } end
    local zoneCoords = Schema.coords(zone.coords)
    local size = type(zone.size) == 'table' and {
        x = number(zone.size.x, 0.5, 500), y = number(zone.size.y, 0.5, 500), z = number(zone.size.z, 0.5, 100),
    } or nil
    if not zoneCoords or not size or not size.x or not size.y or not size.z then
        return nil, 'A valid dealership box zone is required.'
    end

    local vehicles, allowed = normaliseModels(value.vehicles)
    local prices = {}
    for model, rawPrice in pairs(type(value.prices) == 'table' and value.prices or {}) do
        local price = number(rawPrice, 1, Config.maxPrice)
        if allowed[model] and price and price == math.floor(price) then prices[model] = price end
    end
    -- Original rows may carry an inline override; store it in the shared map.
    for _, raw in ipairs(type(value.vehicles) == 'table' and value.vehicles or {}) do
        if type(raw) == 'table' and raw.price then
            local model = raw.model or raw.vehicle
            local price = number(raw.price, 1, Config.maxPrice)
            if allowed[model] and price and price == math.floor(price) then prices[model] = price end
        end
    end

    local placements, placementIds = {}, {}
    for _, raw in ipairs(type(value.placements) == 'table' and value.placements or {}) do
        local placementId = Schema.slug(raw.id)
        local model = type(raw.model) == 'string' and raw.model:lower() or nil
        local coords = Schema.coords(raw.coords, true)
        if placementId and not placementIds[placementId] and allowed[model] and coords then
            placementIds[placementId] = true
            placements[#placements + 1] = { id = placementId, model = model, coords = coords }
        end
    end

    return {
        id = id,
        label = label,
        job = text(value.job, 64, true),
        enabled = value.enabled ~= false,
        autoAccept = value.autoAccept ~= false,
        zone = {
            coords = zoneCoords,
            size = size,
            deleted = zone.deleted == true,
            rotation = number(zone.rotation or 0, -360, 360) or 0.0,
            distance = number(zone.distance or 3, 1, 20) or 3.0,
            bucket = math.floor(number(zone.bucket or 0, 0, 100000) or 0),
        },
        vehicles = vehicles,
        prices = prices,
        placements = placements,
        testDriveCoords = value.testDriveCoords and Schema.coords(value.testDriveCoords, true) or nil,
        purchaseSpawnCoords = value.purchaseSpawnCoords and Schema.coords(value.purchaseSpawnCoords, true) or nil,
    }
end

function Schema.offer(value)
    if type(value) ~= 'table' then return nil, 'Offer must be an object.' end
    local direction = value.direction == 'buy' and 'buy' or value.direction == 'sell' and 'sell' or nil
    local model = type(value.model) == 'string' and value.model:lower():match('^[%w_-]+$') or nil
    local amount = value.amount ~= nil and math.floor(tonumber(value.amount) or 0) or nil
    local terms = text(value.terms, 1000, true)
    if not direction or not model then return nil, 'Offer direction and vehicle are required.' end
    if amount and (amount < 1 or amount > Config.maxPrice) then return nil, 'Offer amount is invalid.' end
    if not amount and not terms then return nil, 'Enter cash, other terms, or both.' end
    return { direction = direction, model = model, amount = amount, terms = terms }
end
