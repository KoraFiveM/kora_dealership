QB.print.debug('qbdealership server/customer.lua loaded.')
local testDrives = {}

local testDriveDistance = 5.0
local testBucketBase = 100000
local testSpawn = vector4(-1574.22, -3008.77, 13.94, 227.21)

local function checkCustomer(src, dealer, index, model)
    local record = Dealerships[dealer]
    if not record then return nil, 'Unknown dealership.' end
    if not fn.nearPlacement(src, record, index, testDriveDistance) then return nil, 'You are too far from the vehicle.' end

    local entry = type(model) == 'string' and fn.findVehicle(record, model)
    if not entry then return nil, 'That vehicle is not sold here.' end
    return record, entry
end

local function endTestDrive(src)
    local data = testDrives[src]
    if not data then return end
    testDrives[src] = nil

    if GetPlayerPed(src) ~= 0 then SetPlayerRoutingBucket(src, data.oldBucket) end
    if DoesEntityExist(data.vehicle) then DeleteEntity(data.vehicle) end
end

QB.callback.register('qbdealership:testDrive', function(src, dealer, index, model)
    if testDrives[src] then return fn.fail('You are already on a test drive.') end
    assert(QB.distance.player(src, Dealerships[dealer].placements[index].coords, testDriveDistance), 'You are too far from the vehicle.')
    assert(fn.findVehicle(Dealerships[dealer], model), 'That vehicle is not sold here.')

    local vehicle = fn.createVehicle(model, testSpawn)
    if not vehicle then return fn.fail('Could not spawn the test vehicle.') end
    local bucket = testBucketBase + src
    testDrives[src] = { oldBucket = GetPlayerRoutingBucket(src), vehicle = vehicle }
    SetEntityRoutingBucket(vehicle, bucket)
    SetPlayerRoutingBucket(src, bucket)

    local plate = ('TD%06d'):format(src)
    SetVehicleNumberPlateText(vehicle, plate)
    exports.qbvehiclekeys:giveKeys(src, plate)
    TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then
        endTestDrive(src)
        return fn.fail('Could not network the test vehicle.')
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


QB.callback.register('qbdealership:confirmPurchase', function(src, dealer, index, model)
    assert(QB.distance.player(src, Dealerships[dealer].placements[index].coords, testDriveDistance), 'You are too far from the vehicle.')
    assert(fn.findVehicle(Dealerships[dealer], model), 'That vehicle is not sold here.')
    local vehData = fn.findVehicle(Dealerships[dealer], model)
    if not vehData then return fn.notify(src, 'That vehicle is not sold here.', 'error') end
    if not vehData.stock or vehData.stock <= 0 then return fn.notify(src, 'That vehicle is out of stock.', 'error') end

    local spawn = fn.getFreeSpawn(Dealerships[dealer].spawns)
    if not spawn then return fn.notify(src, 'This dealership has no spawn point.', 'error') end

    local price = vehData.price
    if not exports.qbcore:removeMoney(src, 'bank', price) then
        return fn.notify(src, 'Not enough money in your bank account.', 'error')
    end

    fn.adjustStock(dealer, model, -1)
    local netId = fn.deliverVehicle(src, model, spawn)
    if not netId then
        fn.adjustStock(dealer, model, 1)
        exports.qbcore:addMoney(src, 'bank', price)
        return fn.notify(src, 'Could not spawn your vehicle. You were refunded.', 'error')
    end

    fn.creditSale(dealer, price)
    fn.notify(src, 'Purchase successful!', 'success')
    return netId
end)


local function autoAcceptAt()
    local days = tonumber(Config.autoConfirmOffersDays)
    if not days or days <= 0 then return nil end
    return os.date('!%Y-%m-%d %H:%M:%S', os.time() + math.floor(days * 86400))
end

QB.callback.register('qbdealership:makeOffer', function(src, dealer, index, model, amount, terms)
    assert(QB.distance.player(src, Dealerships[dealer].placements[index].coords, testDriveDistance), 'You are too far from the vehicle.')

    if not fn.findVehicle(Dealerships[dealer], model) then return fn.notify(src, 'That vehicle is not sold here.', 'error') end
    if not fn.inStock(record, entry) then return fn.notify(src, 'That vehicle is out of stock.', 'error') end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > Config.maxPrice then return fn.notify(src, 'Enter a valid offer.', 'error') end

    terms = type(terms) == 'string' and terms:sub(1, 500) or ''

    local offeror = fn.citizenId(src)
    local expiry = autoAcceptAt()

    QB.sql.query('INSERT INTO `qbdealership_offers` (`dealership_id`, `model`, `offer_price`, `offer_text`, `auto_accept_at`, `status`, `offeror`) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        dealer, model, amount, terms, expiry or QB.sql.NULL, 'pending', offeror,
    })
    
    Offers[dealer] = Offers[dealer] or {}
    table.insert(Offers[dealer], { model = model, price = amount, additional = terms, offeror = offeror, expiry = expiry })
    return true
end)
