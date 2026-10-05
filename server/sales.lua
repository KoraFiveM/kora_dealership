
local busy = {}

local function authorizeSale(src, dealer)
    local record = Dealerships[dealer]
    if not record or record.type ~= 'owned' then return nil, 'This dealership is not owned.' end
    if not fn.canEmployeeDo(src, dealer, 'sellVehicles') then return nil, 'You are not permitted to sell vehicles here.' end
    if not fn.nearAny(src, record.saleZones, Config.saleDistance) then return nil, 'You are too far from a sale point.' end
    return record
end

QB.callback.register('qbdealership:sales:open', function(src, dealer)
    local record, err = authorizeSale(src, dealer)
    if not record then return fn.fail(err) end

    local sellerCoords = GetEntityCoords(GetPlayerPed(src))
    local nearby = {}
    for _, playerId in ipairs(GetPlayers()) do
        local customer = tonumber(playerId)
        local ped = GetPlayerPed(customer)
        if ped ~= 0 and QB.distance.coords(sellerCoords, GetEntityCoords(ped), Config.nearbyCustomerDistance) then
            nearby[#nearby + 1] = { source = customer, name = fn.playerName(customer) }
        end
    end
    table.sort(nearby, function(a, b) return a.name < b.name end)

    return {
        vehicles = record.vehicles,
        maxPriceOverride = fn.management(dealer).settings.maxPriceOverride,
        nearby = nearby,
    }
end)


local function sell(src, dealer, customerSource, model, price)
    local record, err = authorizeSale(src, dealer)
    if not record then return fn.fail(err) end

    local customer = math.tointeger(tonumber(customerSource))
    if not customer or GetPlayerPed(customer) == 0 then return fn.fail('That customer is not available.') end

    model = type(model) == 'string' and model:lower()
    local entry = model and fn.findVehicle(record, model)
    if not entry then return fn.fail('That vehicle is not sold here.') end
    if not fn.inStock(record, entry) then return fn.fail('That vehicle is out of stock.') end

    local spawn = fn.getFreeSpawn(record.spawns)
    if not spawn then return fn.fail('This dealership has no spawn point.') end

    local minPrice, maxPrice = DealershipOrders.priceBounds(entry.price, fn.management(dealer).settings.maxPriceOverride)
    local finalPrice = math.tointeger(math.floor(tonumber(price) or -1))
    if not finalPrice or finalPrice < minPrice or finalPrice > maxPrice then
        return fn.fail(('Price must be between $%d and $%d.'):format(minPrice, maxPrice))
    end

    local answer = QB.callback.trigger(customer, 'qbdealership:sales:confirmPurchase', {
        seller = fn.playerName(src),
        vehicle = entry.name or model,
        price = finalPrice,
    })
    if type(answer) ~= 'table' or not answer.confirmed then return fn.fail('The customer declined the sale.') end

    local account = answer.payment == 'cash' and 'cash' or answer.payment == 'card' and 'bank'
    if not account then return fn.fail('The customer did not choose a payment method.') end

    record = Dealerships[dealer]
    entry = record and fn.findVehicle(record, model)
    if not entry or not fn.inStock(record, entry) then return fn.fail('That vehicle is no longer available.') end

    if not exports.qbcore:removeMoney(customer, account, finalPrice) then
        return fn.fail(('The customer does not have enough %s ($%d needed).'):format(account == 'cash' and 'cash' or 'money on their card', finalPrice))
    end

    fn.adjustStock(dealer, model, -1)
    local netId = fn.deliverVehicle(customer, model, spawn)
    if not netId then
        fn.adjustStock(dealer, model, 1)
        exports.qbcore:addMoney(customer, account, finalPrice)
        return fn.fail('Could not spawn the vehicle. The customer was refunded.')
    end

    local recorded, commission = fn.recordSale(dealer, src, {
        model = model,
        vehicle = entry.name or model,
        price = finalPrice,
        customer = fn.citizenId(customer),
        customerName = fn.playerName(customer),
    })
    if not recorded then
        print(('[qbdealership] failed to record sale of %s at %s for $%d'):format(model, dealer, finalPrice))
    end

    return {
        amount = finalPrice,
        commission = commission or 0,
        customer = fn.playerName(customer),
        vehicleNetId = netId,
        record = Dealerships[dealer],
    }
end

QB.callback.register('qbdealership:sales:confirm', function(src, ...)
    if busy[src] then return fn.fail('Please wait.') end

    busy[src] = true
    local ok, result, message = pcall(sell, src, ...)
    busy[src] = nil

    if not ok then
        print(('[qbdealership] sale error for %s: %s'):format(src, tostring(result)))
        return fn.fail('Could not complete the sale.')
    end
    return result, message
end)

AddEventHandler('playerDropped', function() busy[source] = nil end)
