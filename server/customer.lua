Kora.print.debug('kora_dealership server/customer.lua loaded.')
local testDrives = {}

local function endTestDrive(src)
    local data = testDrives[src]
    if not data then return end
    testDrives[src] = nil

    if GetPlayerPed(src) ~= 0 then SetPlayerRoutingBucket(src, data.oldBucket) end
    if DoesEntityExist(data.vehicle) then DeleteEntity(data.vehicle) end
    if data.plate then
        local ok, err = pcall(function() return exports.kora_vehiclekeys:removeKeys(src, data.plate) end)
        if not ok then
            print(('[kora_dealership] could not revoke test-drive keys for %s: %s'):format(data.plate, tostring(err)))
        end
    end
end

-- Resolves the dealership, validates the player is at the display vehicle, and finds the model.
local function checkCustomer(src, dealer, index, model)
    local record = type(dealer) == 'string' and Dealerships[dealer]
    if not record then return nil, Kora.lang('s.errors.unknown_dealership') end

    local near, err = fn.nearPoint(src, record, 'placements', index, Config.testDriveDistance)
    if not near then return nil, err end

    local entry = fn.findVehicle(record, model)
    if not entry then return nil, Kora.lang('s.errors.vehicle_not_sold') end
    return record, entry
end

local function expireTestDrive(src, data)
    if testDrives[src] == data then endTestDrive(src) end
end

local function testDrive(src, dealer, index, model)
    if testDrives[src] then return fn.fail(Kora.lang('s.errors.test_drive_active')) end
    if not fn.rateLimit(src, 'testDrive', Config.rateLimits.testDrive) then return fn.fail(Kora.lang('s.errors.slow_down')) end

    local record, entry = checkCustomer(src, dealer, index, model)
    if not record then return fn.fail(entry) end

    local vehicle = fn.createVehicle(entry.model, Config.testSpawn)
    if not vehicle then return fn.fail(Kora.lang('s.errors.test_vehicle_spawn_failed')) end

    local bucket = Config.testBucketBase + src
    local data = { oldBucket = GetPlayerRoutingBucket(src), vehicle = vehicle }
    testDrives[src] = data
    SetEntityRoutingBucket(vehicle, bucket)
    SetPlayerRoutingBucket(src, bucket)

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then
        endTestDrive(src)
        return fn.fail(Kora.lang('s.errors.test_vehicle_network_failed'))
    end

    local plate = ('TD%06d'):format(src)
    data.plate = plate
    SetVehicleNumberPlateText(vehicle, plate)

    SetTimeout(Config.testDriveSeconds * 1000, function() expireTestDrive(src, data) end)
    local ok, granted = pcall(function() return exports.kora_vehiclekeys:giveKeys(src, plate) end)
    if not ok or not granted then
        expireTestDrive(src, data)
        return fn.fail(Kora.lang('s.errors.test_vehicle_keys_failed'))
    end

    if testDrives[src] ~= data then return fn.fail(Kora.lang('s.errors.test_vehicle_spawn_failed')) end
    TaskWarpPedIntoVehicle(GetPlayerPed(src), vehicle, -1)
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
    if not fn.rateLimit(src, 'purchase', Config.rateLimits.purchase) then return fn.fail(Kora.lang('s.errors.slow_down')) end

    local record, entry = checkCustomer(src, dealer, index, model)
    if not record then return fn.fail(entry) end
    if not fn.inStock(record, entry) then return fn.fail(Kora.lang('s.errors.stock_empty')) end

    local spawn = fn.getFreeSpawn(record.spawns)
    if not spawn then return fn.fail(Kora.lang('s.errors.spawn_unavailable')) end

    local price = priceFor(src, dealer, record, entry)
    local statements = {}
    local stock = fn.stageStock(dealer, entry.model, -1, statements)
    if not stock then return fn.fail(Kora.lang('s.errors.stock_empty')) end
    local management
    if record.type == 'owned' then
        local data = fn.management(dealer)
        management = fn.stageManagement(dealer, { balance = data.balance + price, income = data.income + price }, statements)
    end
    local cid = fn.citizenId(src)
    if not cid or not exports.kora_core:removeMoney(src, 'bank', price, 'Dealership purchase', true) then
        return fn.fail(Kora.lang('s.errors.purchase_funds'))
    end

    local netId, reason = fn.deliverSale(dealer, src, entry.model, spawn, statements, stock, management, cid)
    if not netId then
        if reason ~= 'indeterminate' and fn.creditPlayer(dealer, src, cid, 'bank', price, 'Dealership refund') then
            return fn.fail(Kora.lang('s.errors.purchase_failed_refunded'))
        end
        fn.flagSettlement(dealer, ('purchase, buyer %s, bank %d'):format(cid, price))
        return fn.fail(Kora.lang('s.errors.sale_failed'))
    end

    fn.notify(src, Kora.lang('s.success.purchase'), 'success')
    return netId
end

local function makeOffer(src, dealer, index, model, amount, terms)
    if not fn.rateLimit(src, 'offer', Config.rateLimits.offer) then return fn.fail(Kora.lang('s.errors.slow_down')) end

    local record, entry = checkCustomer(src, dealer, index, model)
    if not record then return fn.fail(entry) end
    if record.type ~= 'owned' then return fn.fail(Kora.lang('s.errors.offers_owned_only')) end
    if not fn.inStock(record, entry) then return fn.fail(Kora.lang('s.errors.stock_empty')) end

    amount = fn.toAmount(amount, Config.maxPrice)
    if not amount then return fn.fail(Kora.lang('s.errors.offer_invalid_amount')) end

    terms = type(terms) == 'string' and terms:sub(1, 500) or ''

    local offeror = fn.citizenId(src)
    if not offeror then return fn.fail(Kora.lang('s.errors.offer_identity_failed')) end

    local open = Kora.sql.query(
        'SELECT COUNT(*) AS `total` FROM `kora_dealership_offers` WHERE `offeror` = ? AND `status` = ?',
        { offeror, 'pending' }
    )
    if open and open[1] and (tonumber(open[1].total) or 0) >= Config.maxPendingOffers then
        return fn.fail(Kora.lang('s.errors.offer_limit', Config.maxPendingOffers))
    end

    local days = tonumber(Config.autoConfirmOffersDays)
    local seconds = days and days > 0 and math.floor(days * 86400) or Kora.sql.NULL

    local ok = Kora.sql.transaction({
        {
            sql = 'INSERT INTO `kora_dealership_offers` (`dealership_id`, `model`, `offer_price`, `offer_text`, `auto_accept_at`, `status`, `offeror`) VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND), ?, ?)',
            params = { dealer, entry.model, amount, terms, seconds, 'pending', offeror },
        },
    })
    if not ok then return fn.fail(Kora.lang('s.errors.offer_save_failed')) end
    return true
end

Kora.callback.register('kora_dealership:testDrive', testDrive)
Kora.callback.register('kora_dealership:confirmPurchase', fn.dealerWriter(confirmPurchase))
Kora.callback.register('kora_dealership:makeOffer', makeOffer)

RegisterNetEvent('kora_dealership:server:testDriveEnded', onTestDriveEnded)
AddEventHandler('playerDropped', onPlayerDropped)
AddEventHandler('onResourceStop', onResourceStop)
