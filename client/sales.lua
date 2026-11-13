fn.waitForDealerships()

local APP_ID = 'kora_dealership:sales'

local dealerId, indexId = nil, nil
local context = { vehicles = {}, maxPriceOverride = 0, nearby = {} }
local selectedModel = nil
local opening = false

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
            label = Kora.lang('c.sales.stockItem', fn.vehicleName(vehicle), fn.toInt(vehicle.price), fn.toInt(vehicle.stock)),
        }
    end
    return options
end

local function customerOptions()
    local options = {}
    for _, customer in ipairs(context.nearby) do
        options[#options + 1] = { value = tostring(customer.source), label = Kora.lang('c.sales.customerLabel', customer.name, customer.source) }
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
        type = 'form', id = 'sell', title = Kora.lang('c.sales.header'),
        description = entry and Kora.lang('c.sales.allowedPriceRange', minPrice, maxPrice) or nil,
        fields = {
            { id = 'customer', label = Kora.lang('c.sales.customer'), type = 'select', options = customers, required = true },
            { id = 'model', label = Kora.lang('c.sales.vehicle'), type = 'select', options = vehicleOptions, default = model, required = true,
                searchable = true, placeholder = Kora.lang('c.sales.searchPlaceholder') },
            { id = 'price', label = Kora.lang('c.sales.price'), type = 'range', min = minPrice, max = maxPrice, step = 1,
                default = entry and fn.toInt(entry.price) or minPrice, required = true },
        },
        action = { id = 'sell:confirm', label = Kora.lang('c.sales.offerToCustomer'), confirm = Kora.lang('c.sales.confirmOffer') },
    }
end

local function sellView()
    local vehicleOptions, customers = stockedVehicleOptions(), customerOptions()

    local block
    if #vehicleOptions == 0 then
        block = { type = 'empty', title = Kora.lang('c.sales.emptyVeh') }
    elseif #customers == 0 then
        block = { type = 'empty', title = Kora.lang('c.sales.emptyCustomer') }
    else
        block = sellForm(vehicleOptions, customers)
    end

    return {
        id = 'sell', label = Kora.lang('c.sales.header'), icon = 'Car',
        content = { title = Kora.lang('c.sales.header'), description = Kora.lang('c.sales.description'), blocks = { block } },
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
        local sale, err = Kora.callback.trigger('kora_dealership:sales:confirm', dealerId, indexId, values.customer, values.model, values.price)
        if not sale then return fail(err or Kora.lang('c.sales.noComplete')) end

        fn.notify(Kora.lang('c.sales.sold', sale.customer, sale.amount), 'success')
        return { close = true }
    end

    return refresh()
end

local function onChange(actionId, changeContext)
    if actionId ~= 'sell:confirm' then return end

    local newModel = changeContext.value and changeContext.value.model
    if newModel and newModel ~= selectedModel then
        selectedModel = newModel
        return { navigation = buildNavigation() }
    end
end

Kora.callback.register('kora_dealership:sales:confirmPurchase', function(details)
    details = type(details) == 'table' and details or {}
    local answer = Kora.nui.openInputDialog({
        { id = 'payment', label = Kora.lang('c.sales.payWith'), type = 'select', options = Config.paymentMethods, required = true },
    }, Kora.lang('c.sales.buy', details.vehicle or Kora.lang('c.sales.vehicleFallback'), details.price),
       Kora.lang('c.sales.isOffering', details.seller or Kora.lang('c.sales.dealerFallback')))

    if not answer or answer.cancelled then return { confirmed = false } end
    return { confirmed = true, payment = answer.values.payment }
end)

Kora.nui.registerApp({
    id = APP_ID,
    title = Kora.lang('c.sales.header'),
    icon = 'Car',
    layout = 'compact',
    width = 900,
    height = 600,
    defaultView = 'sell',
    navigation = buildNavigation(),
    onAction = onAction,
    onChange = onChange,
})

local function openSales(dealer, index)
    if opening then return end
    opening = true

    fn.withCleanup(function()
        local result, err = Kora.callback.trigger('kora_dealership:sales:open', dealer, index)
        if not result then return fn.notify(err or Kora.lang('c.sales.cantOpen')) end

        dealerId, context, indexId = dealer, result, index
        local firstOption = stockedVehicleOptions()[1]
        selectedModel = firstOption and firstOption.value

        Kora.nui.updateApp(APP_ID, { navigation = buildNavigation() })
        Kora.nui.openApp(APP_ID, { viewId = 'sell' })
    end, function()
        dealerId, opening, indexId = nil, false, nil
    end)
end

fn.keepTargetZones({
    zoneField = 'saleZones',
    radius = Config.saleTargetRadius,
    icon = 'fas fa-tags',
    label = Kora.lang('c.sales.target'),
    canInteract = fn.isStaff,
    open = openSales,
})
