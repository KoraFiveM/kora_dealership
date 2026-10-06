fn.waitForDealerships()

local SHOWROOM_APP_ID = 'qbdealership:showroom'
local OFFER_AMOUNT_APP_ID = 'qbdealership:offer-amount'
local OFFER_TERMS_APP_ID = 'qbdealership:offer-terms'
local DEFAULT_VIEW = 'showroom'

local zones = {}      -- dealer -> dealership zone
local vehicles = {}   -- dealer -> { index -> display vehicle entity }
local shown = {}      -- dealer -> { index -> model currently displayed }
local oldGlobal = {}  -- dealer -> the dealership data the world was last synced to

local latest = {
    dealerships = GlobalState.Dealerships,
    swaps = GlobalState.DealershipSwaps or {},
}

local showroomCtx = nil
local viewIdByOrder = {}
local categoryCache = {}
local offerInput, offerVehicle = nil, nil

local function same(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

local function modelFor(dealer, index, placement)
    local forDealer = latest.swaps[dealer]
    return (forDealer and forDealer[tostring(index)]) or placement.model
end

local function categoryOf(model)
    if categoryCache[model] then return categoryCache[model] end

    local hash = joaat(model)
    local category = { order = 999, name = 'Unknown' }
    if IsModelInCdimage(hash) and IsModelAVehicle(hash) then
        local class = GetVehicleClassFromName(hash)
        local name = Config.categories[class + 1]
        if name then category = { order = class, name = name } end
    end

    categoryCache[model] = category
    return category
end

local function currentPlacement(ctx)
    local dealerData = ctx and latest.dealerships[ctx.dealer]
    local placement = dealerData and dealerData.placements and dealerData.placements[ctx.index]
    return dealerData, placement
end

local function vehicleDescriptor(dealerData, dealer, index, model)
    local vehicle = fn.findVehicle(dealerData.vehicles, model)
    if not vehicle then return nil end

    return {
        dealer = dealer, index = index, dealerLabel = dealerData.label or dealer,
        model = model, name = fn.vehicleName(vehicle), price = math.floor(tonumber(vehicle.price) or 1),
    }
end


local function vehicleCard(current, vehicle, categoryName, dealerType)
    local isCurrent = vehicle.model == current
    local name = fn.vehicleName(vehicle)
    local price = math.floor(tonumber(vehicle.price) or 1)

    local card = {
        id = vehicle.model,
        label = QB.lang('c.customer.displayLabel'):format(name, price),
        description = isCurrent and QB.lang('c.customer.currentlyDisplayed') or nil,
        tone = isCurrent and 'success' or nil,
        image = fn.getVehicleImage(vehicle.model),
        metadata = { { label = QB.lang('c.customer.class'), value = categoryName } },
        actions = {
            { id = 'swap:' .. vehicle.model, label = QB.lang('c.customer.buttons.swap'), icon = 'Repeat', variant = 'outline', disabled = isCurrent,
                description = 'Display this vehicle here instead. Everyone sees it; nothing is saved.' },
            { id = 'test:' .. vehicle.model, label = QB.lang('c.customer.buttons.test'), icon = 'Gauge', closeBeforeAction = true },
            { id = 'purchase:' .. vehicle.model, label = QB.lang('c.customer.buttons.purchase'), icon = 'ShoppingCart', variant = 'primary',
                closeBeforeAction = true, confirm = ('Purchase %s for $%d?'):format(name, price) },
        },
    }
    if dealerType == 'owned' then
        table.insert(card.actions, { id = 'offer:' .. vehicle.model, label = QB.lang('c.customer.buttons.offer'), icon = 'DollarSign', closeBeforeAction = true })
    end
    return card
end

local function groupByCategory(dealerVehicles)
    local groups, ordered = {}, {}
    for _, vehicle in ipairs(dealerVehicles or {}) do
        local category = categoryOf(vehicle.model)
        local group = groups[category.order]
        if not group then
            group = { order = category.order, name = category.name, vehicles = {} }
            groups[category.order] = group
            ordered[#ordered + 1] = group
        end
        group.vehicles[#group.vehicles + 1] = vehicle
    end
    table.sort(ordered, function(a, b) return a.order < b.order end)
    return ordered
end

local function showroomNavigation(ctx)
    local dealerData, placement = currentPlacement(ctx)
    if not placement then
        return { fn.emptyView(DEFAULT_VIEW, 'Showroom', 'Car', 'Showroom', 'This display vehicle is no longer available.') }
    end

    local current = modelFor(ctx.dealer, ctx.index, placement)
    local resetAction = {
        id = 'swap:reset', label = QB.lang('c.customer.reset'), icon = 'RotateCcw', variant = 'outline',
        disabled = current == placement.model,
    }

    local navigation = {}
    viewIdByOrder = {}
    for _, group in ipairs(groupByCategory(dealerData.vehicles)) do
        table.sort(group.vehicles, function(a, b)
            return fn.vehicleName(a):lower() < fn.vehicleName(b):lower()
        end)

        local cards = {}
        for _, vehicle in ipairs(group.vehicles) do
            cards[#cards + 1] = vehicleCard(current, vehicle, group.name, dealerData.type)
        end

        local viewId = #navigation == 0 and DEFAULT_VIEW or ('cat-' .. group.order)
        viewIdByOrder[group.order] = viewId

        navigation[#navigation + 1] = {
            id = viewId,
            label = ('%s (%d)'):format(group.name, #cards),
            icon = 'Car',
            content = {
                title = group.name,
                description = dealerData.label or 'Dealership',
                actions = { resetAction },
                blocks = {
                    { type = 'list', id = 'showroom-' .. group.order, layout = 'cards', cardStyle = 'media', columns = 3,
                        searchable = #cards > 6, items = cards, empty = 'No vehicles in this category.' },
                },
            },
        }
    end

    if #navigation == 0 then
        navigation[1] = fn.emptyView(DEFAULT_VIEW, 'Showroom', 'Car', dealerData.label or 'Showroom', 'This dealership has no vehicles.')
    end
    return navigation
end

local function showroomStartView(navigation, ctx)
    local _, placement = currentPlacement(ctx)
    if placement then
        local wanted = viewIdByOrder[categoryOf(modelFor(ctx.dealer, ctx.index, placement)).order]
        for _, view in ipairs(navigation) do
            if view.id == wanted then return wanted end
        end
    end
    return navigation[1].id
end


local function offerAmountNavigation(vehicle)
    return {
        {
            id = 'amount', label = QB.lang('c.customer.offer.label'), icon = 'DollarSign',
            content = {
                title = QB.lang('c.customer.offer.title'),
                description = vehicle and ('%s · ' .. QB.lang('c.customer.offer.asking')):format(vehicle.name, vehicle.price) or '',
                blocks = {
                    {
                        type = 'form', id = 'offer-amount', title = QB.lang('c.customer.offer.step1'),
                        fields = {
                            { id = 'amount', label = QB.lang('c.customer.offer.offerAmt'), type = 'number',
                              min = 1, max = Config.maxPrice, default = vehicle and vehicle.price or 1, required = true },
                        },
                        action = { id = 'offer:amount', label = QB.lang('c.customer.offer.next') },
                    },
                },
            },
        },
    }
end

local function offerTermsNavigation(vehicle)
    local offering = vehicle and offerInput and offerInput.amount
    return {
        {
            id = 'terms', label = QB.lang('c.customer.offer.label'), icon = 'DollarSign',
            content = {
                title = QB.lang('c.customer.offer.title'),
                description = offering and ('%s · ' .. QB.lang('c.customer.offer.asking')):format(vehicle.name, offerInput.amount) or '',
                blocks = {
                    {
                        type = 'form', id = 'offer-terms', title = QB.lang('c.customer.offer.step2'),
                        fields = {
                            { id = 'terms', label = QB.lang('c.customer.offer.terms'), type = 'textarea', default = '', description = QB.lang('c.customer.offer.optional') },
                        },
                        action = { id = 'offer:terms', label = QB.lang('c.customer.offer.submit') },
                    },
                },
            },
        },
    }
end

local function onOfferAmountAction(actionId, context)
    if actionId ~= 'offer:amount' then return {} end

    local amount = tonumber(context and context.value and context.value.amount)
    if not amount or amount < 1 or amount > Config.maxPrice then
        return {
            update = { navigation = offerAmountNavigation(offerVehicle) },
            notice = fn.notice(('Enter an amount between 1 and %d.'):format(Config.maxPrice), 'destructive'),
        }
    end

    offerInput.amount = math.floor(amount)
    return { close = true }
end

local function onOfferTermsAction(actionId, context)
    if actionId ~= 'offer:terms' then return {} end

    local terms = context and context.value and context.value.terms
    terms = type(terms) == 'string' and terms or ''
    offerInput.terms = terms:match('^%s*(.-)%s*$'):sub(1, 500)
    offerInput.submitted = true
    return { close = true }
end

local function registerOfferApp(appId, viewId, navigation, onAction)
    QB.nui.registerApp({
        id = appId, title = QB.lang('c.customer.offer.title'), icon = 'DollarSign', layout = 'compact',
        width = 800, height = 640, defaultView = viewId,
        navigation = navigation, onAction = onAction,
    })
end

registerOfferApp(OFFER_AMOUNT_APP_ID, 'amount', offerAmountNavigation(nil), onOfferAmountAction)
registerOfferApp(OFFER_TERMS_APP_ID, 'terms', offerTermsNavigation(nil), onOfferTermsAction)

local function openOfferStep(appId, viewId, navigation)
    QB.nui.updateApp(appId, { navigation = navigation })
    QB.nui.openApp(appId, { viewId = viewId })
end

local function runOfferFlow(vehicle)
    offerInput, offerVehicle = {}, vehicle

    openOfferStep(OFFER_AMOUNT_APP_ID, 'amount', offerAmountNavigation(vehicle))
    if not offerInput.amount then return end

    openOfferStep(OFFER_TERMS_APP_ID, 'terms', offerTermsNavigation(vehicle))
    if not offerInput.submitted then return end

    QB.callback.trigger('qbdealership:makeOffer', vehicle.dealer, vehicle.index, vehicle.model, offerInput.amount, offerInput.terms)
end

local function startTestDrive(vehicle)
    CreateThread(function()
        local ped = PlayerPedId()
        local origin = GetEntityCoords(ped)
        local originHeading = GetEntityHeading(ped)

        local netId, err = QB.callback.trigger('qbdealership:testDrive', vehicle.dealer, vehicle.index, vehicle.model)
        if not netId then return fn.notify(err or QB.lang('c.customer.test.error')) end

        local testVehicle = fn.waitForNetworkVehicle(netId, 5000)
        if not testVehicle then
            TriggerServerEvent('qbdealership:endTestDrive')
            return fn.notify(QB.lang('c.customer.test.error'))
        end

        fn.notify(QB.lang('c.customer.test.started'), 'info')
        Wait(1500)
        while DoesEntityExist(testVehicle) and GetVehiclePedIsIn(PlayerPedId(), false) == testVehicle do Wait(500) end

        TriggerServerEvent('qbdealership:endTestDrive')
        QB.visuals.fade(origin)
        SetEntityHeading(PlayerPedId(), originHeading)
    end)
end

local function purchaseVehicle(vehicle)
    local netId = QB.callback.trigger('qbdealership:confirmPurchase', vehicle.dealer, vehicle.index, vehicle.model)
    if not netId then return end

    local purchased = fn.waitForNetworkVehicle(netId, 5000)
    if purchased then TaskWarpPedIntoVehicle(PlayerPedId(), purchased, -1) end
end

local vehicleActions = {
    test = startTestDrive,
    purchase = purchaseVehicle,
    offer = runOfferFlow,
}

local function swapDisplay(ctx, model, successMessage, failureMessage)
    local ok, err = QB.callback.trigger('qbdealership:swap', ctx.dealer, ctx.index, model)
    if not ok then return { notice = fn.notice(err or failureMessage, 'destructive') } end
    return { update = { navigation = showroomNavigation(ctx) }, notice = fn.notice(successMessage) }
end

local function onShowroomAction(actionId, context)
    local ctx = context and context.data
    if type(ctx) ~= 'table' or not ctx.dealer then return { close = true } end

    local dealerData, placement = currentPlacement(ctx)
    if not placement then return { close = true } end

    if actionId == 'swap:reset' then
        return swapDisplay(ctx, nil, QB.lang('c.customer.swap.success'), QB.lang('c.customer.swap.error'))
    end

    local kind, model = actionId:match('^(%a+):(.+)$')
    if not kind or not model then return {} end

    if kind == 'swap' then
        return swapDisplay(ctx, model, QB.lang('c.customer.swap.success'), QB.lang('c.customer.swap.error'))
    end

    local vehicle = vehicleDescriptor(dealerData, ctx.dealer, ctx.index, model)
    local run = vehicle and vehicleActions[kind]
    if run then run(vehicle) end
    return {}
end

QB.nui.registerApp({
    id = SHOWROOM_APP_ID,
    title = 'Dealership Showroom',
    icon = 'Car',
    layout = 'standard',
    width = 1200,
    height = 840,
    defaultView = DEFAULT_VIEW,
    navigation = showroomNavigation(nil),
    onAction = onShowroomAction,
})

local function openShowroom(dealer, index)
    if showroomCtx then return end
    showroomCtx = { dealer = dealer, index = index }

    fn.withCleanup(function()
        local navigation = showroomNavigation(showroomCtx)
        QB.nui.updateApp(SHOWROOM_APP_ID, { navigation = navigation })
        QB.nui.openApp(SHOWROOM_APP_ID, {
            viewId = showroomStartView(navigation, showroomCtx),
            data = { dealer = dealer, index = index },
        })
    end, function()
        showroomCtx = nil
    end)
end


local function removeZone(dealer)
    if zones[dealer] then
        zones[dealer].remove()
        zones[dealer] = nil
    end
end

local function addZone(dealer, zone)
    if not zone or not zone.points then return end
    zones[dealer] = QB.zones.poly({
        points = zone.points,
        thickness = zone.thickness or 4.0,
        onEnter = function()  end,
        onExit = function() end,
    })
end

local function removeVehicle(dealer, index)
    local entity = vehicles[dealer] and vehicles[dealer][index]
    if entity then
        QB.entities.remove(entity)
        vehicles[dealer][index] = nil
    end
    if shown[dealer] then shown[dealer][index] = nil end
end

local function attachBrowseTarget(entity, dealer, index)
    exports.qbtarget:addEntity(entity, {
        {
            icon = 'fas fa-car',
            label = QB.lang('c.customer.target'),
            onSelect = function() CreateThread(function() openShowroom(dealer, index) end) end,
        },
    })
end

local function spawnVehicle(dealer, index, placement)
    local model = modelFor(dealer, index, placement)
    local coords = placement.coords

    local entity = QB.entities.create(model, vector3(coords.x, coords.y, coords.z), { freeze = true, invincible = true })
    if not entity or entity == 0 then return end

    SetEntityHeading(entity, coords.w or 0.0)
    attachBrowseTarget(entity, dealer, index)

    vehicles[dealer] = vehicles[dealer] or {}
    shown[dealer] = shown[dealer] or {}
    vehicles[dealer][index] = entity
    shown[dealer][index] = model
end

local function removePlacements(dealer)
    for index in pairs(vehicles[dealer] or {}) do
        removeVehicle(dealer, index)
    end
    vehicles[dealer], shown[dealer] = nil, nil
end

local function syncDealer(dealer, old, new)
    if not new then
        removeZone(dealer)
        removePlacements(dealer)
        return
    end

    if not old or not same(old.zone, new.zone) then
        removeZone(dealer)
        addZone(dealer, new.zone)
    end

    if not old or not same(old.placements, new.placements) then
        removePlacements(dealer)
        for index, placement in ipairs(new.placements or {}) do
            spawnVehicle(dealer, index, placement)
        end
        return
    end

    for index, placement in ipairs(new.placements or {}) do
        if (shown[dealer] and shown[dealer][index]) ~= modelFor(dealer, index, placement) then
            removeVehicle(dealer, index)
            spawnVehicle(dealer, index, placement)
        end
    end
end

local function syncAll()
    local dealerships = latest.dealerships or {}

    for dealer, data in pairs(dealerships) do
        syncDealer(dealer, oldGlobal[dealer], data)
        oldGlobal[dealer] = data
    end

    for dealer, data in pairs(oldGlobal) do
        if not dealerships[dealer] then
            syncDealer(dealer, data, nil)
            oldGlobal[dealer] = nil
        end
    end
end

local dirty, running = false, false
local function queueSync()
    dirty = true
    if running then return end
    running = true
    CreateThread(function()
        while dirty do
            dirty = false
            syncAll()
        end
        running = false
    end)
end

queueSync()

AddStateBagChangeHandler('Dealerships', 'global', function(_, _, value)
    latest.dealerships = value or {}
    queueSync()
end)

AddStateBagChangeHandler('DealershipSwaps', 'global', function(_, _, value)
    latest.swaps = value or {}
    queueSync()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for dealer in pairs(zones) do removeZone(dealer) end
    for dealer in pairs(vehicles) do removePlacements(dealer) end
end)
