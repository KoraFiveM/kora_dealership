fn.waitForDealerships()

local APP_ID = 'qbdealership:sales'

local dealerId = nil
local context = { vehicles = {}, maxPriceOverride = 0, nearby = {} }
local selectedModel = nil
local opening = false

-- Vehicles that are in stock, ordered by name, as select-field options.
local function stockedVehicleOptions()
    local stocked = {}
    for _, vehicle in ipairs(context.vehicles) do
        if fn.toInt(vehicle.stock) > 0 then stocked[#stocked + 1] = vehicle end
    end
    table.sort(stocked, function(a, b)
        local nameA, nameB = fn.vehicleName(a):lower(), fn.vehicleName(b):lower()
        if nameA ~= nameB then return nameA < nameB end
        return a.model < b.model
    end)

    local options = {}
    for _, vehicle in ipairs(stocked) do
        options[#options + 1] = {
            value = vehicle.model,
            label = ('%s  ·  $%d  ·  %d in stock'):format(fn.vehicleName(vehicle), fn.toInt(vehicle.price), fn.toInt(vehicle.stock)),
        }
    end
    return options
end

local function customerOptions()
    local options = {}
    for _, customer in ipairs(context.nearby) do
        options[#options + 1] = { value = tostring(customer.source), label = ('%s (#%d)'):format(customer.name, customer.source) }
    end
    return options
end

local function sellForm(vehicleOptions, customers)
    local model = selectedModel or vehicleOptions[1].value
    local entry = fn.findVehicle(context.vehicles, model)
    local minPrice, maxPrice = 1, 1
    if entry then
        minPrice, maxPrice = DealershipOrders.priceBounds(entry.price, context.maxPriceOverride)
    end

    return {
        type = 'form', id = 'sell', title = 'Sell a vehicle',
        description = entry and ('Allowed price range for this vehicle: $%d - $%d'):format(minPrice, maxPrice) or nil,
        fields = {
            { id = 'customer', label = 'Customer', type = 'select', options = customers, required = true },
            { id = 'model', label = 'Vehicle', type = 'select', options = vehicleOptions, default = model, required = true,
                searchable = true, placeholder = 'Type to search vehicles' },
            { id = 'price', label = 'Price', type = 'range', min = minPrice, max = maxPrice, step = 1,
                default = entry and fn.toInt(entry.price) or minPrice, required = true },
        },
        action = { id = 'sell:confirm', label = 'Offer to customer', confirm = 'Send this offer to the customer? They choose how to pay.' },
    }
end

local function sellView()
    local vehicleOptions, customers = stockedVehicleOptions(), customerOptions()

    local block
    if #vehicleOptions == 0 then
        block = { type = 'empty', title = 'No vehicles in stock right now.' }
    elseif #customers == 0 then
        block = { type = 'empty', title = 'No customers are nearby.' }
    else
        block = sellForm(vehicleOptions, customers)
    end

    return {
        id = 'sell', label = 'Sell vehicle', icon = 'Car',
        content = { title = 'Sell a vehicle', description = 'Pick a nearby customer, a vehicle, and a price.', blocks = { block } },
    }
end

local function buildNavigation()
    return { sellView() }
end

local refresh, fail = fn.appRefresher(APP_ID, buildNavigation)

local function onAction(actionId, actionContext)
    if not dealerId then return { close = true } end
    local values = actionContext and actionContext.value or {}

    if actionId == 'sell:confirm' then
        local sale, err = QB.callback.trigger('qbdealership:sales:confirm', dealerId, values.customer, values.model, values.price)
        if not sale then return fail(err or 'The customer did not complete the purchase.') end

        fn.notify(('Sold to %s for $%d.'):format(sale.customer, sale.amount), 'success')
        return { close = true }
    end

    return refresh()
end

-- Picking another vehicle re-sizes the price slider to that vehicle's allowed range.
local function onChange(actionId, changeContext)
    if actionId ~= 'sell:confirm' then return end

    local newModel = changeContext.value and changeContext.value.model
    if newModel and newModel ~= selectedModel then
        selectedModel = newModel
        return { navigation = buildNavigation() }
    end
end

-- The customer's side of a sale: confirm the price and pick how to pay.
QB.callback.register('qbdealership:sales:confirmPurchase', function(details)
    details = type(details) == 'table' and details or {}
    local answer = QB.nui.openInputDialog({
        { id = 'payment', label = 'Pay with', type = 'select', options = Config.paymentMethods, required = true },
    }, ('Buy the %s for $%d?'):format(details.vehicle or 'vehicle', fn.toInt(details.price)),
        ('%s is offering to sell you this vehicle.'):format(details.seller or 'The dealer'))

    if not answer or answer.cancelled then return { confirmed = false } end
    return { confirmed = true, payment = answer.values.payment }
end)

QB.nui.registerApp({
    id = APP_ID,
    title = 'Sell a Vehicle',
    icon = 'Car',
    layout = 'compact',
    width = 900,
    height = 600,
    defaultView = 'sell',
    navigation = buildNavigation(),
    onAction = onAction,
    onChange = onChange,
})

local function openSales(dealer)
    if opening then return end
    opening = true

    fn.withCleanup(function()
        local result, err = QB.callback.trigger('qbdealership:sales:open', dealer)
        if not result then return fn.notify(err or 'Could not open the sales menu.') end

        dealerId, context = dealer, result
        local firstOption = stockedVehicleOptions()[1]
        selectedModel = firstOption and firstOption.value

        QB.nui.updateApp(APP_ID, { navigation = buildNavigation() })
        QB.nui.openApp(APP_ID, { viewId = 'sell' })
    end, function()
        dealerId, opening = nil, false
    end)
end

fn.keepTargetZones({
    zoneField = 'saleZones',
    radius = Config.saleTargetRadius,
    icon = 'fas fa-tags',
    label = 'Sell a vehicle',
    canInteract = fn.isStaff,
    open = openSales,
})
