repeat Wait(100) until GlobalState.Dealerships ~= nil
local SWAP_APP_ID = 'qbdealership:swap'
local zones = {}
local vehicles = {}
local shown = {}   
local currentDealer = nil
local oldGlobal = {}  

local latest = {
    dealerships = GlobalState.Dealerships,
    swaps = GlobalState.DealershipSwaps or {},
}

local function same(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do
        if not same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function modelFor(dealer, index, placement)
    local forDealer = latest.swaps[dealer]
    return (forDealer and forDealer[tostring(index)]) or placement.model
end

local function notify(message, tone)
    QB.notify.send({ title = 'Dealership', message = message, type = tone or 'error' })
end

local showroomCtx = nil
local categoryCache = {}
local function categoryOf(model)
    local hit = categoryCache[model]
    if hit then return hit end

    local hash = joaat(model)
    local result = { order = 999, name = 'Unknown' }
    if IsModelInCdimage(hash) and IsModelAVehicle(hash) then
        local class = GetVehicleClassFromName(hash)
        local name = Config.categories[class + 1]
        if name then result = { order = class, name = name } end
    end

    categoryCache[model] = result
    return result
end

local DEFAULT_VIEW = 'showroom'
local viewIdByOrder = {}

local function currentPlacement(ctx)
    local dealerData = ctx and latest.dealerships[ctx.dealer]
    local placement = dealerData and dealerData.placements and dealerData.placements[ctx.index]
    return dealerData, placement
end

local function vehicleDescriptor(dealerData, dealer, index, model)
    for _, vehicle in ipairs(dealerData.vehicles or {}) do
        if vehicle.model == model then
            return { dealer = dealer, index = index, dealerLabel = dealerData.label or dealer,
                model = model, name = vehicle.name or model, price = math.floor(tonumber(vehicle.price) or 1) }
        end
    end
end

local function vehicleImage(model)
    return ('https://docs-backend.fivem.net/vehicles/%s.webp'):format(model)
end

local function vehicleCard(current, vehicle, categoryName, dealerType)
    local isCurrent = vehicle.model == current
    local price = math.floor(tonumber(vehicle.price) or 1)
    local tbl =  {
        id = vehicle.model,
        label = ('%s | $%d'):format(vehicle.name or vehicle.model, price),
        description = isCurrent and 'Currently displayed here' or nil,
        tone = isCurrent and 'primary' or nil,
        image = vehicleImage(vehicle.model),
        metadata = { { label = 'Class', value = categoryName } },
        actions = {
            { id = 'swap:' .. vehicle.model, label = 'Swap', icon = 'Repeat', variant = 'outline', disabled = isCurrent,
                description = 'Display this vehicle here instead. Everyone sees it; nothing is saved.' },
            { id = 'test:' .. vehicle.model, label = 'Test drive', icon = 'Gauge', closeBeforeAction = true },
            { id = 'purchase:' .. vehicle.model, label = 'Purchase', icon = 'ShoppingCart', variant = 'primary',
                closeBeforeAction = true, confirm = ('Purchase %s for $%d?'):format(vehicle.name or vehicle.model, price) },
        },
    }
    if dealerType == 'owned' then
        table.insert(tbl.actions, { id = 'offer:' .. vehicle.model, label = 'Make offer', icon = 'DollarSign', closeBeforeAction = true })
    end
    return tbl
end

local function showroomNavigation(ctx)
    local dealerData, placement = currentPlacement(ctx)
    if not placement then
        return {
            {
                id = DEFAULT_VIEW, label = 'Showroom', icon = 'Car',
                content = {
                    title = 'Showroom',
                    blocks = { { type = 'empty', title = 'This display vehicle is no longer available.' } },
                },
            },
        }
    end

    local current = modelFor(ctx.dealer, ctx.index, placement)

    local groups, ordered = {}, {}
    for _, vehicle in ipairs(dealerData.vehicles or {}) do
        local category = categoryOf(vehicle.model)
        local group = groups[category.order]
        if not group then
            group = { order = category.order, name = category.name, vehicles = {} }
            groups[category.order] = group
            ordered[#ordered + 1] = group
        end
        group.vehicles[#group.vehicles + 1] = vehicle
    end
    table.sort(ordered, function(x, y) return x.order < y.order end)

    local resetAction = {
        id = 'swap:reset', label = 'Reset display to default', icon = 'RotateCcw', variant = 'outline',
        disabled = current == placement.model,
    }

    local views = {}
    viewIdByOrder = {}
    for _, group in ipairs(ordered) do
        table.sort(group.vehicles, function(x, y)
            return (x.name or x.model):lower() < (y.name or y.model):lower()
        end)

        local items = {}
        for _, vehicle in ipairs(group.vehicles) do
            items[#items + 1] = vehicleCard(current, vehicle, group.name, dealerData.type)
        end

        local viewId = #views == 0 and DEFAULT_VIEW or ('cat-' .. group.order)
        viewIdByOrder[group.order] = viewId

        views[#views + 1] = {
            id = viewId,
            label = ('%s (%d)'):format(group.name, #items),
            icon = 'Car',
            content = {
                title = group.name,
                description = dealerData.label or 'Dealership',
                actions = { resetAction },
                blocks = {
                    { type = 'list', id = 'showroom-' .. group.order, layout = 'cards',cardStyle='media', columns = 3, searchable = #items > 6,
                        items = items, empty = 'No vehicles in this category.' },
                },
            },
        }
    end

    if #views == 0 then
        views[1] = {
            id = DEFAULT_VIEW, label = 'Showroom', icon = 'Car',
            content = {
                title = dealerData.label or 'Showroom',
                blocks = { { type = 'empty', title = 'This dealership has no vehicles.' } },
            },
        }
    end

    return views
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

local offerInput = nil
local offerVehicle = nil

local SHOWROOM_APP_ID = 'qbdealership:showroom'

local OFFER_AMOUNT_APP_ID = 'qbdealership:offer-amount'
local OFFER_TERMS_APP_ID = 'qbdealership:offer-terms'

local vehicleActions = {
    testDrive = function(v)
        CreateThread(function()
            local ped = PlayerPedId()
            local origin = GetEntityCoords(ped)
            local originHeading = GetEntityHeading(ped)

            local netId, err = QB.callback.trigger('qbdealership:testDrive', v.dealer, v.index, v.model)
            if not netId then return notify(err or 'Could not start the test drive.') end

            local waited = 0
            while not NetworkDoesEntityExistWithNetworkId(netId) and waited < 5000 do
                Wait(50)
                waited = waited + 50
            end
            local vehicle = NetworkDoesEntityExistWithNetworkId(netId) and NetworkGetEntityFromNetworkId(netId) or 0
            if vehicle == 0 or not DoesEntityExist(vehicle) then
                TriggerServerEvent('qbdealership:endTestDrive')
                return notify('The test vehicle did not load.')
            end
            notify('Test drive started. Get out of the vehicle to end it.', 'info')
            Wait(1500)
            while DoesEntityExist(vehicle) and GetVehiclePedIsIn(PlayerPedId(), false) == vehicle do Wait(500) end

            TriggerServerEvent('qbdealership:endTestDrive')
            QB.visuals.fade(origin)
            SetEntityHeading(PlayerPedId(), originHeading)
        end)
    end,
    purchase = function(v)
        local confirm = QB.callback.trigger('qbdealership:confirmPurchase', v.dealer, v.index, v.model)
        if not confirm then return end
        TaskWarpPedIntoVehicle(PlayerPedId(), NetworkGetEntityFromNetworkId(confirm), -1)
    end,
    offer = function(v, amount, terms)
        local confirm = QB.callback.trigger('qbdealership:makeOffer', v.dealer, v.index, v.model, amount, terms)
    end,
}

local function offerAmountNavigation(v)
    return {
        {
            id = 'amount', label = 'Offer', icon = 'DollarSign',
            content = {
                title = 'Make an offer',
                description = v and ('%s · asking $%d'):format(v.name, v.price) or '',
                blocks = {
                    {
                        type = 'form', id = 'offer-amount', title = 'Step 1 of 2: amount',
                        fields = {
                            { id = 'amount', label = 'Offer amount', type = 'number',
                              min = 1, max = Config.maxPrice, default = v and v.price or 1, required = true },
                        },
                        action = { id = 'offer:amount', label = 'Next' },
                    },
                },
            },
        },
    }
end

local function offerTermsNavigation(v)
    return {
        {
            id = 'terms', label = 'Offer', icon = 'DollarSign',
            content = {
                title = 'Make an offer',
                description = v and offerInput and offerInput.amount
                    and ('%s · offering $%d'):format(v.name, offerInput.amount) or '',
                blocks = {
                    {
                        type = 'form', id = 'offer-terms', title = 'Step 2 of 2: additional terms',
                        fields = {
                            { id = 'terms', label = 'Additional terms', type = 'text', default = '',
                              description = 'Optional.' },
                        },
                        action = { id = 'offer:terms', label = 'Submit offer' },
                    },
                },
            },
        },
    }
end

local function onOfferAmountAction(actionId, context)
    if actionId ~= 'offer:amount' then return {} end

    local values = context and context.value
    local amount = tonumber(values and values.amount)
    if not amount or amount < 1 or amount > Config.maxPrice then
        return {
            update = { navigation = offerAmountNavigation(offerVehicle) },
            notice = { tone = 'destructive', message = ('Enter an amount between 1 and %d.'):format(Config.maxPrice) },
        }
    end

    offerInput.amount = math.floor(amount)
    return { close = true }
end

local function onOfferTermsAction(actionId, context)
    if actionId ~= 'offer:terms' then return {} end

    local values = context and context.value
    local terms = type(values and values.terms) == 'string' and values.terms or ''
    offerInput.terms = terms:match('^%s*(.-)%s*$'):sub(1, 500)
    offerInput.submitted = true
    return { close = true }
end

QB.nui.registerApp({
    id = OFFER_AMOUNT_APP_ID, title = 'Make an offer', icon = 'DollarSign', layout = 'standard',
    width = 640, height = 420, defaultView = 'amount',
    navigation = offerAmountNavigation(nil), onAction = onOfferAmountAction,
})

QB.nui.registerApp({
    id = OFFER_TERMS_APP_ID, title = 'Make an offer', icon = 'DollarSign', layout = 'standard',
    width = 640, height = 420, defaultView = 'terms',
    navigation = offerTermsNavigation(nil), onAction = onOfferTermsAction,
})

local function runOfferFlow(v)
    offerInput, offerVehicle = {}, v

    QB.nui.updateApp(OFFER_AMOUNT_APP_ID, { navigation = offerAmountNavigation(v) })
    QB.nui.openApp(OFFER_AMOUNT_APP_ID, { viewId = 'amount' })
    if not offerInput.amount then return end

    QB.nui.updateApp(OFFER_TERMS_APP_ID, { navigation = offerTermsNavigation(v) })
    QB.nui.openApp(OFFER_TERMS_APP_ID, { viewId = 'terms' })
    if not offerInput.submitted then return end

    vehicleActions.offer(v, offerInput.amount, offerInput.terms)
end

local function onShowroomAction(actionId, context)
    local ctx = context and context.data
    if type(ctx) ~= 'table' or not ctx.dealer then return { close = true } end

    local dealerData, placement = currentPlacement(ctx)
    if not placement then return { close = true } end

    if actionId == 'swap:reset' then
        local ok, err = QB.callback.trigger('qbdealership:swap', ctx.dealer, ctx.index, nil)
        if not ok then return { notice = { tone = 'destructive', message = err or 'Could not reset the display vehicle.' } } end
        return { update = { navigation = showroomNavigation(ctx) }, notice = { tone = 'success', message = 'Reset to the default display vehicle.' } }
    end

    local kind, model = actionId:match('^(%a+):(.+)$')
    if not kind or not model then return {} end

    if kind == 'swap' then
        local ok, err = QB.callback.trigger('qbdealership:swap', ctx.dealer, ctx.index, model)
        if not ok then return { notice = { tone = 'destructive', message = err or 'Could not switch the display vehicle.' } } end
        return { update = { navigation = showroomNavigation(ctx) }, notice = { tone = 'success', message = 'Display vehicle updated.' } }
    end

    local vehicle = vehicleDescriptor(dealerData, ctx.dealer, ctx.index, model)
    if not vehicle then return {} end

    if kind == 'test' then vehicleActions.testDrive(vehicle)
    elseif kind == 'purchase' then vehicleActions.purchase(vehicle)
    elseif kind == 'offer' then runOfferFlow(vehicle) end

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

    local ok, err = pcall(function()
        local navigation = showroomNavigation(showroomCtx)
        QB.nui.updateApp(SHOWROOM_APP_ID, { navigation = navigation })
        QB.nui.openApp(SHOWROOM_APP_ID, {
            viewId = showroomStartView(navigation, showroomCtx),
            data = { dealer = dealer, index = index },
        })
    end)

    showroomCtx = nil
    if not ok then error(err, 0) end
end

local function attachDealerCarTarget(veh, dealer, index)
    exports.qbtarget:addEntity(veh, {
        {
            icon = 'fas fa-car',
            label = 'Browse dealership',
            onSelect = function()
                CreateThread(function() openShowroom(dealer, index) end)
            end
        }
    })
end

local function removeZone(dealer)
    if zones[dealer] then
        zones[dealer].remove()
        zones[dealer] = nil
    end
    if currentDealer == dealer then currentDealer = nil end
end

local function addZone(dealer, zone)
    if not zone or not zone.points then return end
    zones[dealer] = QB.zones.poly{
        points = zone.points,
        thickness = zone.thickness or 4.0,
        onEnter = function()
            QB.print.debug('Entered dealership zone:', dealer)
            currentDealer = dealer
        end,
        onExit = function()
            QB.print.debug('Exited dealership zone:', dealer)
            if currentDealer == dealer then currentDealer = nil end
        end
    }
end

local function removeVehicle(dealer, index)
    local veh = vehicles[dealer] and vehicles[dealer][index]
    if veh then
        QB.entities.remove(veh)
        vehicles[dealer][index] = nil
    end
    if shown[dealer] then shown[dealer][index] = nil end
end

local function spawnVehicle(dealer, index, placement)
    local model = modelFor(dealer, index, placement)
    local c = placement.coords

    local veh = QB.entities.create(model, vector3(c.x, c.y, c.z), { freeze = true, invincible = true })
    if not veh or veh == 0 then return end

    SetEntityHeading(veh, c.w or 0.0)
    attachDealerCarTarget(veh, dealer, index)

    vehicles[dealer] = vehicles[dealer] or {}
    shown[dealer] = shown[dealer] or {}
    vehicles[dealer][index] = veh
    shown[dealer][index] = model
end

local function removePlacements(dealer)
    for index in pairs(vehicles[dealer] or {}) do
        removeVehicle(dealer, index)
    end
    vehicles[dealer] = nil
    shown[dealer] = nil
end

local function sync(dealer, old, new)
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
    else
        for index, placement in ipairs(new.placements or {}) do
            if (shown[dealer] and shown[dealer][index]) ~= modelFor(dealer, index, placement) then
                removeVehicle(dealer, index)
                spawnVehicle(dealer, index, placement)
            end
        end
    end
end

local function syncAll()
    local new = latest.dealerships or {}

    for dealer, data in pairs(new) do
        sync(dealer, oldGlobal[dealer], data)
        oldGlobal[dealer] = data
    end

    for dealer, data in pairs(oldGlobal) do
        if not new[dealer] then
            sync(dealer, data, nil)
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