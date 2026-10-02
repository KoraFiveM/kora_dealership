local testDrives = {}

local testDriveDistance = 5.0
local testBucketBase = 100000
local testSpawn = vector4(-1574.22, -3008.77, 13.94, 227.21)

local function fail(message)
    return false, message
end

local function createVehicle(model, spawn)
    local vehicle = CreateVehicle(joaat(model), spawn.x, spawn.y, spawn.z, spawn.w, true, true)
    local waited = 0
    while (not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)) and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    return vehicle
end
    
local function endTestDrive(src)
    local data = testDrives[src]
    if not data then return end
    testDrives[src] = nil

    if GetPlayerPed(src) ~= 0 then SetPlayerRoutingBucket(src, data.oldBucket) end
    if data.vehicle and DoesEntityExist(data.vehicle) then DeleteEntity(data.vehicle) end
end

local function vehicleListed(dealerData, model)
    for _, entry in ipairs(dealerData.vehicles or {}) do
        if entry.model == model then return true end
    end
    return false
end

QB.callback.register('qbdealership:testDrive', function(src, dealer, index, model)
    if testDrives[src] then return fail('You are already on a test drive.') end
    assert(src and dealer and index and model, 'Invalid test drive parameters.')
    assert(not testDrives[src], 'You are already on a test drive.')
    assert(Dealerships[dealer], 'Unknown dealership.')
    assert(QB.distance.player(src, Dealerships[dealer].placements[index].coords, testDriveDistance), 'You are too far from the vehicle.')


    if type(model) ~= 'string' or not vehicleListed(Dealerships[dealer], model) then
        return fail('That vehicle is not sold here.')
    end
    local bucket = testBucketBase + src
    local oldBucket = GetPlayerRoutingBucket(src)
    local vehicle = createVehicle(model, testSpawn)
    if not vehicle then
        return fail('Could not spawn the test vehicle.')
    end
    SetEntityRoutingBucket(vehicle, bucket)
    SetPlayerRoutingBucket(src, bucket)

    local plate = ('TD%06d'):format(src)
    SetVehicleNumberPlateText(vehicle, plate)
    testDrives[src] = { oldBucket = oldBucket, bucket = bucket, vehicle = vehicle, plate = plate }

    exports.qbvehiclekeys:giveKeys(src, plate)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        endTestDrive(src)
        return fail('Could not network the test vehicle.')
    end

    return netId
end)

RegisterNetEvent('qbdealership:endTestDrive', function()
    endTestDrive(source)
end)

AddEventHandler('playerDropped', function()
    endTestDrive(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(testDrives) do endTestDrive(src) end
end)

local function getVehicleData(dealer, model)
    for _, entry in ipairs(Dealerships[dealer].vehicles or {}) do
        if entry.model == model then return entry end
    end
    return nil
end

QB.callback.register('qbdealership:confirmPurchase', function(src, dealer, index, model)
    if not QB.distance.player(src, Dealerships[dealer].placements[index].coords, testDriveDistance) then return false end
    if not vehicleListed(Dealerships[dealer], model) then return false end
    local vehicleData = getVehicleData(dealer, model)
    if not vehicleData then return false end
    if vehicleData.stock <= 0 then return false end
    if vehicleData.price <= 0 then return false end
    if not exports.qbcore:removeMoney(src, 'bank', vehicleData.price) then return false end
    vehicleData.stock = vehicleData.stock - 1
    local newVeh = createVehicle(model, Dealerships[dealer].spawns[1].coords)
    QB.sql.query('INSERT INTO player_vehicles (plate, vehicle, citizenid, state, fuel, engine_health, body_health, balance, paymentamount, paymentsleft, financetime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        newVeh and GetVehicleNumberPlateText(newVeh) or '',
        model,
        exports.qbcore:getPlayerData(src).citizenid,
        'out',
        100.0,
        1000.0,
        1000.0,
        0,
        0,
        0,
        0
    })
    exports.qbvehiclekeys:giveKeys(src, GetVehicleNumberPlateText(newVeh))
    return NetworkGetNetworkIdFromEntity(newVeh)
end)

local function autoAcceptAt()
    local days = tonumber(Config.autoConfirmOffersDays)
    if not days or days <= 0 then return nil end
    return os.date('!%Y-%m-%d %H:%M:%S', os.time() + math.floor(days * 86400))
end

local function getOfferPerson(src)
    local data = exports.qbcore:getPlayerData(src)
    return {
        name = data.charinfo.firstname .. ' ' .. data.charinfo.lastname,
        citizenid = data.citizenid,
    }
end
QB.callback.register('qbdealership:makeOffer', function(src, dealer, index, model, amount, terms)
    assert(src and dealer and index and model and amount, 'Invalid offer parameters.')
    assert(QB.distance.player(src, Dealerships[dealer].placements[index].coords, testDriveDistance), 'Player is too far from the dealership.')
    if not vehicleListed(Dealerships[dealer], model) then return false end
    local vehicleData = getVehicleData(dealer, model)
    if not vehicleData then return false end
    if vehicleData.stock <= 0 then return false end
    if vehicleData.price <= 0 then return false end
    QB.sql.query('INSERT INTO qbdealership_offers (dealership_id, model, offer_price, offer_text, auto_accept_at, status, offeror ) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        dealer,
        model,
        amount,
        terms or '',
        autoAcceptAt(),
        'pending',
        getOfferPerson(src)
    })
    return true
end)