repeat Wait(100) until GlobalState.Dealerships ~= nil

local appId = 'qbdealership:sales'

local latest = GlobalState.Dealerships or {}
local targets = {}      -- dealer -> { zone ids }
local signatures = {}   -- dealer -> what the current targets were built from

local dealerId = nil
local context = { vehicles = {}, maxPriceOverride = 0, nearby = {} }
local selectedModel = nil
local opening = false

local function notify(message, tone)
    QB.notify.send({ title = 'Dealership Sales', message = message, type = tone or 'error' })
end

local function findVehicleLocal(model)
    for _, vehicle in ipairs(context.vehicles or {}) do
        if vehicle.model == model then return vehicle end
    end
end

-- --- page -------------------------------------------------------------------------

-- In-stock vehicles as select options, sorted by name so a long list is easy to scan.
-- The Vehicle field is `searchable`, so typing part of a label filters this list in the
-- browser; nothing is re-sent to Lua while the employee types.
local function stockedVehicleOptions()
    local options = {}
    for _, vehicle in ipairs(context.vehicles or {}) do
        local stock = math.floor(tonumber(vehicle.stock) or 0)
        if stock > 0 then
            local name = vehicle.name or vehicle.model
            options[#options + 1] = {
                value = vehicle.model,
                label = ('%s  ·  $%d  ·  %d in stock'):format(name, math.floor(tonumber(vehicle.price) or 0), stock),
                sortKey = tostring(name):lower(),
            }
        end
    end
    table.sort(options, function(a, b)
        if a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
        return a.value < b.value
    end)
    for _, option in ipairs(options) do option.sortKey = nil end
    return options
end

local function sellView()
    local vehicleOptions, customerOptions = stockedVehicleOptions(), {}
    for _, customer in ipairs(context.nearby or {}) do
        customerOptions[#customerOptions + 1] = { value = tostring(customer.source), label = ('%s (#%d)'):format(customer.name, customer.source) }
    end

    local model = selectedModel or (vehicleOptions[1] and vehicleOptions[1].value)
    local entry = model and findVehicleLocal(model)

    local blocks = {}
    if #vehicleOptions == 0 then
        blocks[#blocks + 1] = { type = 'empty', title = 'No vehicles in stock right now.' }
    elseif #customerOptions == 0 then
        blocks[#blocks + 1] = { type = 'empty', title = 'No customers are nearby.' }
    else
        local minPrice, maxPrice = 1, 1
        if entry then
            minPrice, maxPrice = DealershipOrders.priceBounds(entry.price, context.maxPriceOverride)
        end

        blocks[#blocks + 1] = {
            type = 'form', id = 'sell', title = 'Sell a vehicle',
            description = entry and ('Allowed price range for this vehicle: $%d - $%d'):format(minPrice, maxPrice) or nil,
            fields = {
                { id = 'customer', label = 'Customer', type = 'select', options = customerOptions, required = true },
                { id = 'model', label = 'Vehicle', type = 'select', options = vehicleOptions, default = model, required = true,
                    searchable = true, placeholder = 'Type to search vehicles' },
                { id = 'price', label = 'Price', type = 'range', min = minPrice, max = maxPrice, step = 1,
                    default = entry and math.floor(tonumber(entry.price) or minPrice) or minPrice, required = true },
            },
            action = { id = 'sell:confirm', label = 'Offer to customer', confirm = 'Send this offer to the customer? They choose how to pay.' },
        }
    end

    return {
        id = 'sell', label = 'Sell vehicle', icon = 'Car',
        content = { title = 'Sell a vehicle', description = 'Pick a nearby customer, a vehicle, and a price.', blocks = blocks },
    }
end

local function buildNavigation()
    return { sellView() }
end

local function refresh(notice)
    QB.nui.updateApp(appId, { navigation = buildNavigation() })
    return { update = { navigation = buildNavigation() }, notice = notice }
end

local function fail(message)
    return refresh({ tone = 'destructive', message = message })
end

-- --- actions ------------------------------------------------------------------------

local function onAction(actionId, ctx)
    if not dealerId then return { close = true } end
    local values = ctx and ctx.value or {}

    if actionId == 'sell:confirm' then
        local result, err = QB.callback.trigger('qbdealership:sales:confirm', dealerId, values.customer, values.model, values.price)
        if not result then return fail(err or 'The customer did not complete the purchase.') end
        notify(('Sold to %s for $%d.'):format(result.customer, result.amount), 'success')
        return { close = true }
    end

    return refresh()
end

-- Recomputes the price slider's range/default the moment the chosen vehicle changes,
-- rather than letting a stale range from the previous vehicle linger.
local function onChange(actionId, ctx)
    if actionId ~= 'sell:confirm' then return end
    local newModel = ctx.value and ctx.value.model
    if newModel and newModel ~= selectedModel then
        selectedModel = newModel
        return { navigation = buildNavigation() }
    end
end

-- Answered on whichever client the server addresses: the customer being offered a
-- vehicle, not the employee selling it. They choose cash or card, or decline.
QB.callback.register('qbdealership:sales:confirmPurchase', function(details)
    details = type(details) == 'table' and details or {}
    local result = QB.nui.openInputDialog({
        { id = 'payment', label = 'Pay with', type = 'select', options = Config.paymentMethods, required = true },
    }, ('Buy the %s for $%d?'):format(details.vehicle or 'vehicle', math.floor(tonumber(details.price) or 0)),
        ('%s is offering to sell you this vehicle.'):format(details.seller or 'The dealer'))

    if not result or result.cancelled then return { confirmed = false } end
    return { confirmed = true, payment = result.values.payment }
end)

QB.nui.registerApp({
    id = appId,
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

    local ok, err = pcall(function()
        local result, fetchErr = QB.callback.trigger('qbdealership:sales:open', dealer)
        if not result then
            notify(fetchErr or 'Could not open the sales menu.')
            return
        end

        dealerId = dealer
        context = result
        local firstOption = stockedVehicleOptions()[1]
        selectedModel = firstOption and firstOption.value or nil

        QB.nui.updateApp(appId, { navigation = buildNavigation() })
        QB.nui.openApp(appId, { viewId = 'sell' })
    end)

    dealerId = nil
    opening = false
    if not ok then error(err, 0) end
end

-- --- sale point targets --------------------------------------------------------------

-- GlobalState.DealershipStaff[dealer] is the owner's citizenid plus any employee
-- granted 'sellVehicles' (published by server/Management.lua). The server re-checks
-- this on every callback -- this is only what decides whether the prompt shows.
local function isSeller(dealer)
    local data = exports.qbcore:getPlayerData()
    local staff = GlobalState.DealershipStaff
    local set = staff and staff[dealer]
    return data ~= nil and data.citizenid ~= nil and set ~= nil and set[data.citizenid] == true
end

local function addSaleTarget(dealer, coords)
    return exports.qbtarget:addSphereZone({
        coords = vector3(coords.x, coords.y, coords.z),
        radius = Config.saleTargetRadius,
        options = {
            {
                icon = 'fas fa-tags',
                label = 'Sell a vehicle',
                canInteract = function() return isSeller(dealer) end,
                onSelect = function() CreateThread(function() openSales(dealer) end) end,
            },
        },
    })
end

local function removeTargets(dealer)
    for _, id in ipairs(targets[dealer] or {}) do
        pcall(function() exports.qbtarget:removeZone(id) end)
    end
    targets[dealer] = nil
    signatures[dealer] = nil
end

local function syncTargets()
    for dealer, data in pairs(latest) do
        local signature = data.type == 'owned' and json.encode(data.saleZones or {}) or nil
        if signature ~= signatures[dealer] then
            removeTargets(dealer)
            if signature then
                signatures[dealer] = signature
                targets[dealer] = {}
                for _, zone in ipairs(data.saleZones or {}) do
                    local ok, id = pcall(addSaleTarget, dealer, zone.coords)
                    if ok and id then
                        targets[dealer][#targets[dealer] + 1] = id
                    elseif not ok then
                        print(('[qbdealership] could not add a sale target: %s'):format(tostring(id)))
                    end
                end
            end
        end
    end

    for dealer in pairs(signatures) do
        if not latest[dealer] then removeTargets(dealer) end
    end
end

syncTargets()

AddStateBagChangeHandler('Dealerships', 'global', function(_, _, value)
    latest = value or {}
    syncTargets()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for dealer in pairs(targets) do removeTargets(dealer) end
end)
