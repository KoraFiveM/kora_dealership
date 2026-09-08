-- The dealership's server-authoritative purchase funnel. It never accepts a
-- vehicle record, price, player identity or coordinates from a client: all of
-- those values are resolved here from qbcore, Config and server natives.

Dealership = Dealership or {}
Dealership.api = {}

local api = Dealership.api

local function core(name, ...)
    local resource = exports.qbcore
    local fn = resource and resource[name]
    if type(fn) ~= 'function' then return nil, 'qbcore service unavailable' end

    local args = { ... }
    local ok, value, err = pcall(fn, resource, table.unpack(args))
    if not ok then return nil, 'qbcore service unavailable' end
    return value, err
end

local function dealerFor(id)
    if type(id) ~= 'string' then return nil, 'unknown dealership' end
    local dealer = Config.dealerships[id]
    if type(dealer) ~= 'table' or type(dealer.coords) ~= 'table' then return nil, 'unknown dealership' end
    return dealer
end

local function vehicleFor(dealer, model)
    if type(model) ~= 'string' then return nil, 'unknown vehicle' end
    model = model:lower()
    for _, configured in ipairs(dealer.vehicles or {}) do
        if type(configured) == 'table' and configured.vehicle == model then return configured end
    end
    return nil, 'vehicle is not sold here'
end

local function sharedVehicle(model, priceOverride)
    local vehicle, err = core('getShared', 'vehicles', model)
    if type(vehicle) ~= 'table' or vehicle.model ~= model then
        return nil, err or 'vehicle is no longer available'
    end

    local price = tonumber(priceOverride)
    if price == nil then price = tonumber(vehicle.price) end
    local limit = tonumber(Config.purchase.maxPrice) or 5000000
    if not price or price <= 0 or price ~= math.floor(price) or price > limit then
        return nil, 'vehicle is not for sale'
    end
    return vehicle, price
end

local function nearby(src, dealer)
    if type(GetPlayerPed) ~= 'function' or type(GetEntityCoords) ~= 'function'
        or type(GetPlayerRoutingBucket) ~= 'function' then
        return false, 'dealership validation unavailable'
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetPlayerRoutingBucket(src) ~= (tonumber(dealer.bucket) or 0) then
        return false, 'you cannot use this dealership'
    end

    local position = GetEntityCoords(ped)
    local coords = dealer.coords
    if type(position) ~= 'table' or type(coords.x) ~= 'number' or type(coords.y) ~= 'number' or type(coords.z) ~= 'number' then
        return false, 'dealership validation unavailable'
    end
    local distance = math.sqrt((position.x - coords.x) ^ 2 + (position.y - coords.y) ^ 2 + (position.z - coords.z) ^ 2)
    if distance > (tonumber(dealer.distance) or 3.0) then return false, 'you are too far from the dealership' end
    return true
end

local function plate()
    local prefix = tostring(Config.purchase.platePrefix or 'PDM'):upper():gsub('[^A-Z0-9]', ''):sub(1, 3)
    return ('%s%05d'):format(prefix ~= '' and prefix or 'PDM', math.random(0, 99999))
end

local function availablePlate()
    local attempts = math.max(1, math.floor(tonumber(Config.purchase.plateAttempts) or 12))
    for _ = 1, attempts do
        local candidate = plate()
        local existing = core('getByPlate', candidate)
        if not existing then return candidate end
    end
    return nil, 'could not allocate a vehicle plate'
end

local function publicVehicle(configured)
    local model = configured.vehicle
    local vehicle, price = sharedVehicle(model, configured.price)
    if not vehicle then return nil end
    return {
        model = model,
        name = vehicle.name,
        brand = vehicle.brand,
        price = price,
    }
end

function api.list(src, dealerId)
    local dealer, err = dealerFor(dealerId)
    if not dealer then return nil, err end
    local allowed, accessErr = nearby(src, dealer)
    if not allowed then return nil, accessErr end

    local vehicles = {}
    for _, configured in ipairs(dealer.vehicles or {}) do
        local row = publicVehicle(configured)
        if row then vehicles[#vehicles + 1] = row end
    end
    return { id = dealerId, label = dealer.label, vehicles = vehicles }
end

function api.buy(src, dealerId, requestedModel)
    local dealer, err = dealerFor(dealerId)
    if not dealer then return false, err end
    local allowed, accessErr = nearby(src, dealer)
    if not allowed then return false, accessErr end

    local configured, vehicleErr = vehicleFor(dealer, requestedModel)
    if not configured then return false, vehicleErr end
    local model = configured.vehicle
    local vehicle, priceOrErr = sharedVehicle(model, configured.price)
    if not vehicle then return false, priceOrErr end
    local price = priceOrErr

    local citizenid, citizenErr = core('getPlayerData', src, { 'citizenid' })
    if type(citizenid) ~= 'string' or citizenid == '' then return false, citizenErr or 'character unavailable' end

    local charged, chargeErr = core('removeMoney', src, Config.purchase.account, price, 'dealership-purchase')
    if not charged then return false, chargeErr or 'payment failed' end

    local newPlate, plateErr = availablePlate()
    if not newPlate then
        core('addMoney', src, Config.purchase.account, price, 'dealership-refund', true)
        return false, plateErr
    end

    local created, createErr = core('createVehicle', citizenid, model, newPlate, nil, Config.purchase.vehicle)
    if not created then
        core('addMoney', src, Config.purchase.account, price, 'dealership-refund', true)
        return false, createErr or 'vehicle purchase could not be saved'
    end

    QB.notify.send(src, {
        title = dealer.label,
        message = ('Purchased %s. It is available at a garage.'):format(vehicle.name or model),
        type = 'success',
    })
    return { model = model, plate = newPlate, price = price }
end

exports('GetDealerships', function()
    local out = {}
    for id, dealer in pairs(Config.dealerships) do
        out[id] = { id = id, label = dealer.label, coords = dealer.coords }
    end
    return out
end)
