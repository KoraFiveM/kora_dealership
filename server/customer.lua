Kora.print.debug('qbdealership server/customer.lua loaded.')
local testDrives = {}

local function endTestDrive(src)
    local data = testDrives[src]
    if not data then return end
    testDrives[src] = nil

    if GetPlayerPed(src) ~= 0 then SetPlayerRoutingBucket(src, data.oldBucket) end
    if DoesEntityExist(data.vehicle) then DeleteEntity(data.vehicle) end
end

-- Resolves the dealership, validates the player is at the display vehicle, and finds the model.
local function checkCustomer(src, dealer, index, model)
    local record = type(dealer) == 'string' and Dealerships[dealer]
    if not record then return nil, 'Unknown dealership.' end

    local near, err = fn.nearPoint(src, record, 'placements', index, Config.testDriveDistance)
    if not near then return nil, err end

    local entry = fn.findVehicle(record, model)
    if not entry then return nil, 'That vehicle is not sold here.' end
    return record, entry
end

local function expireTestDrive(src, data)
    if testDrives[src] == data then endTestDrive(src) end
end

local function testDrive(src, dealer, index, model)
    if testDrives[src] then return fn.fail('You are already on a test drive.') end
    if not fn.rateLimit(src, 'testDrive', Config.rateLimits.testDrive) then return fn.fail('Slow down.') end

    local record, entry = checkCustomer(src, dealer, index, model)
    if not record then return fn.fail(entry) end

    local vehicle = fn.createVehicle(entry.model, Config.testSpawn)
    if not vehicle then return fn.fail('Could not spawn the test vehicle.') end

    local bucket = Config.testBucketBase + src
    local data = { oldBucket = GetPlayerRoutingBucket(src), vehicle = vehicle }
    testDrives[src] = data
    SetEntityRoutingBucket(vehicle, bucket)
    SetPlayerRoutingBucket(src, bucket)

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then
        endTestDrive(src)
        return fn.fail('Could not network the test vehicle.')
    end

    local plate = ('TD%06d'):format(src)
    SetVehicleNumberPlateText(vehicle, plate)
    exports.kora_vehiclekeys:giveKeys(src, plate)
    TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)

    local function expire() expireTestDrive(src, data) end
    SetTimeout(Config.testDriveSeconds * 1000, expire)
    return netId
end

local function onTestDriveEnded()
    if GetInvokingResource() then return end
    endTestDrive(source)
end

local function onPlayerDropped()
    endTestDrive(source)
end

local function onResourceStop(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(testDrives) do endTestDrive(src) end
end

-- Employees of an owned dealership pay the discounted price.
local function priceFor(src, dealer, record, entry)
    local price = entry.price
    if record.type == 'owned' and fn.isEmployee(src, dealer) then
        local discount = fn.management(dealer).settings.employeeDiscount
        price = math.max(1, math.floor(price * (100 - discount) / 100))
    end
    return price
end

local function confirmPurchase(src, dealer, index, model)
    if not fn.rateLimit(src, 'purchase', Config.rateLimits.purchase) then return fn.fail('Slow down.') end

    local record, entry = checkCustomer(src, dealer, index, model)
    if not record then return fn.fail(entry) end
    if not fn.inStock(record, entry) then return fn.fail('That vehicle is out of stock.') end

    local spawn = fn.getFreeSpawn(record.spawns)
    if not spawn then return fn.fail('There is no free spawn point right now. Try again shortly.') end

    local price = priceFor(src, dealer, record, entry)
    if not exports.kora_core:removeMoney(src, 'bank', price) then return fn.fail('Not enough money in your bank account.') end

    local function refund(restoreStock, reverseCredit)
        if reverseCredit then fn.creditSale(dealer, -price) end
        if restoreStock then fn.adjustStock(dealer, entry.model, 1) end
        exports.kora_core:addMoney(src, 'bank', price)
    end

    if not fn.adjustStock(dealer, entry.model, -1) then
        refund(false, false)
        return fn.fail('That vehicle is out of stock.')
    end

    if not fn.creditSale(dealer, price) then
        refund(true, false)
        return fn.fail('Could not complete the purchase. You were refunded.')
    end

    local netId = fn.deliverVehicle(src, entry.model, spawn)
    if not netId then
        refund(true, true)
        return fn.fail('Could not spawn your vehicle. You were refunded.')
    end

    fn.notify(src, 'Purchase successful!', 'success')
    return netId
end

local function makeOffer(src, dealer, index, model, amount, terms)
    if not fn.rateLimit(src, 'offer', Config.rateLimits.offer) then return fn.fail('Slow down.') end

    local record, entry = checkCustomer(src, dealer, index, model)
    if not record then return fn.fail(entry) end
    if record.type ~= 'owned' then return fn.fail('Offers can only be made at owned dealerships.') end
    if not fn.inStock(record, entry) then return fn.fail('That vehicle is out of stock.') end

    amount = fn.toAmount(amount, Config.maxPrice)
    if not amount then return fn.fail('Enter a valid offer.') end

    terms = type(terms) == 'string' and terms:sub(1, 500) or ''

    local offeror = fn.citizenId(src)
    if not offeror then return fn.fail('Could not identify you.') end

    local open = Kora.sql.query(
        'SELECT COUNT(*) AS `total` FROM `kora_dealership_offers` WHERE `offeror` = ? AND `status` = ?',
        { offeror, 'pending' }
    )
    if open and open[1] and (tonumber(open[1].total) or 0) >= Config.maxPendingOffers then
        return fn.fail(('You can only have %d open offers at a time.'):format(Config.maxPendingOffers))
    end

    local days = tonumber(Config.autoConfirmOffersDays)
    local seconds = days and days > 0 and math.floor(days * 86400) or Kora.sql.NULL

    local ok = Kora.sql.transaction({
        {
            sql = 'INSERT INTO `kora_dealership_offers` (`dealership_id`, `model`, `offer_price`, `offer_text`, `auto_accept_at`, `status`, `offeror`) VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND), ?, ?)',
            params = { dealer, entry.model, amount, terms, seconds, 'pending', offeror },
        },
    })
    if not ok then return fn.fail('Could not save your offer.') end
    return true
end

Kora.callback.register('qbdealership:testDrive', testDrive)
Kora.callback.register('qbdealership:confirmPurchase', confirmPurchase)
Kora.callback.register('qbdealership:makeOffer', makeOffer)

RegisterNetEvent('qbdealership:server:testDriveEnded', onTestDriveEnded)
AddEventHandler('playerDropped', onPlayerDropped)
AddEventHandler('onResourceStop', onResourceStop)
