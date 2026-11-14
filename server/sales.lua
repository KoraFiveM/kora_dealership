local busy = {}
local finishSale

local function authorizeSale(src, dealer, index)
    local record = type(dealer) == 'string' and Dealerships[dealer]
    if not record or record.type ~= 'owned' then return nil, Kora.lang('s.errors.not_owned') end
    if not fn.canEmployeeDo(src, dealer, 'sellVehicles') then return nil, Kora.lang('s.errors.not_permitted') end

    local near, err = fn.nearPoint(src, record, 'saleZones', index, Config.saleDistance)
    if not near then return nil, err end
    return record
end

local function isNearbyCustomer(src, customer)
    local sellerPed, customerPed = GetPlayerPed(src), GetPlayerPed(customer)
    if sellerPed == 0 or customerPed == 0 then return false end
    return Kora.distance.coords(GetEntityCoords(sellerPed), GetEntityCoords(customerPed), Config.nearbyCustomerDistance)
end

local function openSales(src, dealer, index)
    local record, err = authorizeSale(src, dealer, index)
    if not record then return fn.fail(err) end

    local nearby = {}
    for _, playerId in ipairs(GetPlayers()) do
        local customer = tonumber(playerId)
        if customer ~= src and isNearbyCustomer(src, customer) then
            nearby[#nearby + 1] = { source = customer, name = fn.playerName(customer) }
        end
    end
    table.sort(nearby, function(a, b) return a.name < b.name end)

    return {
        vehicles = record.vehicles,
        maxPriceOverride = fn.management(dealer).settings.maxPriceOverride,
        nearby = nearby,
    }
end

local function priceWithinBounds(dealer, entry, price)
    local minPrice, maxPrice = DealershipOrders.priceBounds(entry.price, fn.management(dealer).settings.maxPriceOverride)
    local finalPrice = math.floor(tonumber(price) or -1)
    if finalPrice < minPrice or finalPrice > maxPrice then
        return nil, Kora.lang('s.errors.sale_price_range', minPrice, maxPrice)
    end
    return finalPrice
end

-- request = { dealer, index, customer, model, price }
local function sell(src, request)
    local record, err = authorizeSale(src, request.dealer, request.index)
    if not record then return fn.fail(err) end
    local dealer = request.dealer

    local number = tonumber(request.customer)
    local customer = number and math.tointeger(number)
    if not customer or customer == src or not isNearbyCustomer(src, customer) then
        return fn.fail(Kora.lang('s.errors.customer_unavailable'))
    end

    local entry = fn.findVehicle(record, request.model)
    if not entry then return fn.fail(Kora.lang('s.errors.vehicle_not_sold')) end
    if not fn.inStock(record, entry) then return fn.fail(Kora.lang('s.errors.stock_empty')) end

    if not fn.getFreeSpawn(record.spawns) then return fn.fail(Kora.lang('s.errors.spawn_unavailable')) end

    local finalPrice, priceErr = priceWithinBounds(dealer, entry, request.price)
    if not finalPrice then return fn.fail(priceErr) end
    local customerCid = fn.citizenId(customer)
    if not customerCid then return fn.fail(Kora.lang('s.errors.customer_unavailable')) end

    local answer = Kora.callback.trigger(customer, 'kora_dealership:sales:confirmPurchase', {
        seller = fn.playerName(src),
        vehicle = entry.name,
        price = finalPrice,
    })
    if type(answer) ~= 'table' or not answer.confirmed then return fn.fail(Kora.lang('s.errors.customer_declined')) end

    local account = answer.payment == 'cash' and 'cash' or answer.payment == 'card' and 'bank'
    if not account then return fn.fail(Kora.lang('s.errors.payment_unselected')) end

    return fn.withDealerWrite(dealer, function()
        return finishSale(src, request, customer, customerCid, account, finalPrice)
    end)
end

finishSale = function(src, request, customer, customerCid, account, finalPrice)
    local dealer = request.dealer
    local record, err = authorizeSale(src, dealer, request.index)
    if not record then return fn.fail(err) end
    if fn.citizenId(customer) ~= customerCid or not isNearbyCustomer(src, customer) then
        return fn.fail(Kora.lang('s.errors.customer_unavailable'))
    end

    local entry = fn.findVehicle(record, request.model)
    if not entry or not fn.inStock(record, entry) then return fn.fail(Kora.lang('s.errors.vehicle_unavailable')) end
    local priceErr
    finalPrice, priceErr = priceWithinBounds(dealer, entry, finalPrice)
    if not finalPrice then return fn.fail(priceErr) end

    local spawn = fn.getFreeSpawn(record.spawns)
    if not spawn then return fn.fail(Kora.lang('s.errors.spawn_unavailable')) end
    local statements = {}
    local stock = fn.stageStock(dealer, entry.model, -1, statements)
    if not stock then return fn.fail(Kora.lang('s.errors.vehicle_unavailable')) end
    local sellerCid, customerName = fn.citizenId(src), fn.playerName(customer)
    local management, commission = fn.stageStaffSale(dealer, src, {
        model = entry.model,
        vehicle = entry.name,
        price = finalPrice,
        customer = customerCid,
        customerName = customerName,
    }, statements)
    if not exports.kora_core:removeMoney(customer, account, finalPrice, 'Dealership sale', true) then
        return fn.fail(Kora.lang('s.errors.customer_funds', Kora.lang(account == 'cash' and 's.errors.customer_payment_cash' or 's.errors.customer_payment_card'), finalPrice))
    end

    local netId, reason = fn.deliverSale(dealer, customer, entry.model, spawn, statements, stock, management, customerCid)
    if not netId then
        if reason ~= 'indeterminate'
            and fn.creditPlayer(dealer, customer, customerCid, account, finalPrice, 'Dealership refund') then
            return fn.fail(Kora.lang('s.errors.vehicle_spawn_failed'))
        end
        fn.flagSettlement(dealer, ('staff sale, buyer %s, %s %d'):format(customerCid, account, finalPrice))
        return fn.fail(Kora.lang('s.errors.sale_failed'))
    end

    if commission > 0 and not fn.creditPlayer(dealer, src, sellerCid, 'bank', commission, 'Dealership commission') then
        return fn.fail(Kora.lang('s.errors.sale_commission_pending'))
    end

    return {
        amount = finalPrice,
        commission = commission,
        customer = customerName,
        vehicleNetId = netId,
        record = Dealerships[dealer],
    }
end

local function confirmSale(src, dealer, index, customer, model, price)
    local lockedAt = busy[src]
    if lockedAt and GetGameTimer() - lockedAt < Config.saleConfirmTimeout * 1000 then return fn.fail(Kora.lang('s.errors.sale_wait')) end

    local lock = GetGameTimer()
    busy[src] = lock
    local ok, result, message = pcall(sell, src, { dealer = dealer, index = index, customer = customer, model = model, price = price })
    if busy[src] == lock then busy[src] = nil end

    if not ok then
        print(('[kora_dealership] sale error for %s: %s'):format(src, tostring(result)))
        return fn.fail(Kora.lang('s.errors.sale_failed'))
    end
    return result, message
end

local function onPlayerDropped()
    busy[source] = nil
end

Kora.callback.register('kora_dealership:sales:open', openSales)
Kora.callback.register('kora_dealership:sales:confirm', confirmSale)
AddEventHandler('playerDropped', onPlayerDropped)
