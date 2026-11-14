local APP_ID = 'kora_dealership:creator'
local views = DealershipViews

local selected = nil        -- the currently-open dealership record (server's copy)
local currentView = 'dealerships'
local pendingTool = nil     -- set by onAction, consumed by the open loop below
local vehicleCatalog = nil  -- { { value = model, label = name }, ... }, built once

local function loadCatalog()
    if vehicleCatalog then return vehicleCatalog end
    local shared = exports.kora_core:allShared('vehicles') or {}
    local list = {}
    for _, data in ipairs(shared) do
        local model = data.model
        list[#list + 1] = { value = model, label = (type(data) == 'table' and data.name) or model }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    vehicleCatalog = list
    return list
end

local function dealershipsView()
    local list = Kora.callback.trigger('kora_dealership:list') or {}
    local items = {}
    for _, entry in ipairs(list) do
        local description = entry.type == 'for_sale' and Kora.lang('c.creator.for_sale', entry.price or 0)
            or entry.type == 'owned' and Kora.lang('c.creator.owned', entry.owner or Kora.lang('c.creator.ownerUnclaimed'))
            or Kora.lang('c.creator.public')
        if selected and selected.id == entry.id then
            description = Kora.lang('c.creator.editingDescription', Kora.lang('c.creator.editing'), description)
        end
        items[#items + 1] = {
            id = entry.id,
            label = entry.label,
            description = description,
            icon = 'Warehouse',
            action = 'select:' .. entry.id,
        }
    end

    return {
        id = 'dealerships', label = Kora.lang('c.creator.dealerLabel'), icon = 'Warehouse',
        content = {
            title = Kora.lang('c.creator.dealerLabel'),
            description = Kora.lang('c.creator.dealerDesc'),
            blocks = {
                { type = 'list', id = 'dealership-list', items = items, empty = Kora.lang('c.creator.noDealerships') },
                {
                    type = 'form', id = 'create', title = Kora.lang('c.creator.createDealership'),
                    fields = { { id = 'label', label = Kora.lang('c.creator.dealerName'), type = 'text', required = true } },
                    action = { id = 'create', label = Kora.lang('c.creator.create') },
                },
            },
        },
    }
end

local function dataView()
    return {
        id = 'data', label = Kora.lang('c.creator.data.header'), icon = 'Settings',
        content = {
            title = selected.label, description = Kora.lang('c.creator.data.description'),
            blocks = {
                {
                    type = 'form', id = 'data', title = Kora.lang('c.creator.data.header'),
                    fields = {
                        { id = 'label', label = Kora.lang('c.creator.data.form.name'), type = 'text', default = selected.label, required = true },
                        {
                            id = 'type', label = Kora.lang('c.creator.data.form.access'), type = 'select', default = selected.type,
                            options = {
                                { value = 'public', label = Kora.lang('c.creator.data.form.public') },
                                { value = 'for_sale', label = Kora.lang('c.creator.data.form.for_sale') },
                                { value = 'owned', label = Kora.lang('c.creator.data.form.owned') },
                            },
                        },
                        {
                            id = 'price', label = Kora.lang('c.creator.data.form.price'), type = 'number',
                            default = selected.price and tonumber(selected.price) or 1,
                        },
                        {
                            id = 'owner', label = Kora.lang('c.creator.data.form.owner'), type = 'text',
                            default = selected.owner or '',
                            description = Kora.lang('c.creator.data.form.ownerDesc'),
                        },
                    },
                    action = { id = 'data:save', label = Kora.lang('c.creator.data.form.save') },
                },
                {
                    type = 'actions', title = Kora.lang('c.creator.data.delete.danger'),
                    actions = { { id = 'delete', label = Kora.lang('c.creator.data.delete.delete'), variant = 'destructive' } },
                },
            },
        },
    }
end

local function zoneView()
    local zone = selected.zone
    return {
        id = 'zone', label = Kora.lang('c.creator.zone.header'), icon = 'MapPin',
        content = {
            title = Kora.lang('c.creator.zone.header'), description = Kora.lang('c.creator.zone.description'),
            blocks = {
                {
                    type = 'stats',
                    items = {
                        { label = Kora.lang('c.creator.zone.stats.points'), value = zone and #zone.points or 0, icon = 'MapPin' },
                        { label = Kora.lang('c.creator.zone.stats.thickness'), value = zone and Kora.lang('c.creator.zone.stats.thicknessValue', zone.thickness) or '—', icon = 'Ruler' },
                    },
                },
                {
                    type = 'actions', title = Kora.lang('c.creator.zone.actions.draw'),
                    actions = {
                        { id = 'zone:create', label = zone and Kora.lang('c.creator.zone.actions.redraw') or Kora.lang('c.creator.zone.actions.draw'), variant = 'primary' },
                        { id = 'zone:clear', label = Kora.lang('c.creator.zone.actions.clear'), variant = 'outline', disabled = zone == nil },
                    },
                },
            },
        },
    }
end

local function vehiclesView()
    local items = {}
    for _, vehicle in ipairs(selected.vehicles or {}) do
        items[#items + 1] = {
            id = vehicle.model,
            label = fn.vehicleName(vehicle),
            description = Kora.lang('s.price', tonumber(vehicle.price) or 1),
            icon = 'Car',
            actions = {
                {
                    id = 'vehicles:price:' .. vehicle.model,
                    label = Kora.lang('c.creator.vehicles.form.sale'),
                    submitLabel = Kora.lang('c.creator.vehicles.form.save'),
                    fields = {
                        {
                            id = 'price',
                            type = 'number',
                            label = Kora.lang('c.creator.vehicles.form.sale'),
                            default = tonumber(vehicle.price) or 1,
                            min = 1,
                            max = Config.maxPrice,
                            required = true,
                        },
                    },
                },
                {
                    id = 'vehicles:remove:' .. vehicle.model,
                    label = Kora.lang('c.creator.vehicles.remove.confirm'),
                    variant = 'destructive',
                },
            },
            image = fn.getVehicleImage(vehicle.model),
        }
    end

    return {
        id = 'vehicles', label = Kora.lang('c.creator.vehicles.header'), icon = 'Car',
        content = {
            title = Kora.lang('c.creator.vehicles.header'),
            description = Kora.lang('c.creator.vehicles.description'),
            blocks = {
                {
                    type = 'form', id = 'vehicle-add', title = Kora.lang('c.creator.vehicles.form.add'),
                    fields = {
                        {
                            id = 'model', label = Kora.lang('c.creator.vehicles.form.veh'), type = 'select',
                            options = loadCatalog(), searchable = true, required = true,
                        },
                    },
                    action = { id = 'vehicles:add', label = Kora.lang('c.creator.vehicles.form.add') },
                },
                {
                    type = 'list', id = 'vehicle-list', title = Kora.lang('c.creator.vehicles.form.current', #items),
                    layout = 'list', imageFit = 'contain', imageAspect = 'wide', searchable = #items > 6, pageSize = 12,
                    items = items, empty = Kora.lang('c.creator.vehicles.form.empty'),
                },
            },
        },
    }
end

local function buildNavigation()
    local navigation = { dealershipsView() }
    if selected then
        navigation[#navigation + 1] = dataView()
        navigation[#navigation + 1] = zoneView()
        navigation[#navigation + 1] = vehiclesView()
        navigation[#navigation + 1] = views.placements(selected)
        navigation[#navigation + 1] = views.spawns(selected)
        navigation[#navigation + 1] = views.pointZones(views.managementSpec, selected)
        navigation[#navigation + 1] = views.pointZones(views.saleSpec, selected)
    end
    return navigation
end

local baseRefresh = fn.appRefresher(APP_ID, buildNavigation)

local function appTitle()
    if selected then return Kora.lang('c.creator.titleEditing', selected.label) end
    return Kora.lang('c.creator.title')
end

local function refresh(notice)
    local title = appTitle()
    Kora.nui.updateApp(APP_ID, { title = title })
    local response = baseRefresh(notice)
    if response.update then response.update.title = title end
    return response
end

local function fail(message)
    return refresh(fn.notice(message, 'destructive'))
end

local function saveSelected(patch)
    local result, err = Kora.callback.trigger('kora_dealership:save', selected.id, patch)
    if not result then return fail(err or Kora.lang('c.creator.failed')) end
    selected = result
    return refresh(fn.notice(Kora.lang('c.creator.save')))
end

local function createDealership(label)
    local record, err = Kora.callback.trigger('kora_dealership:create', label)
    if not record then return fail(err or Kora.lang('c.creator.failed')) end
    selected, currentView = record, 'data'
    return refresh(fn.notice(Kora.lang('c.creator.save')))
end

local function selectDealership(id)
    local record, err = Kora.callback.trigger('kora_dealership:get', id)
    if not record then return fail(err or Kora.lang('c.creator.failed')) end
    selected, currentView = record, 'data'
    return refresh()
end

local function deleteSelected()
    local confirmation = Kora.nui.openAlert({
        title = Kora.lang('c.creator.delete.title'), message = Kora.lang('c.creator.delete.message'),
        confirmLabel = Kora.lang('c.creator.delete.confirm'),
    })
    if not confirmation or not confirmation.confirmed then return refresh() end

    local ok, err = Kora.callback.trigger('kora_dealership:delete', selected.id)
    if not ok then return fail(err or Kora.lang('c.creator.delete.fail')) end
    selected, currentView = nil, 'dealerships'
    return refresh(fn.notice(Kora.lang('c.creator.delete.pass')))
end

local function addVehicle(model)
    if not model then return fail(Kora.lang('c.creator.vehicles.add.vehReq')) end
    if fn.findVehicle(selected.vehicles, model) then return fail(Kora.lang('c.creator.vehicles.add.vehExists')) end
    return saveSelected({ vehicles = fn.appended(selected.vehicles, { model = model }) })
end

local function setVehiclePrice(model, price)
    if not model or not price then return fail(Kora.lang('c.creator.vehicles.price.vehPrice')) end

    local vehicles = {}
    for _, vehicle in ipairs(selected.vehicles) do
        vehicles[#vehicles + 1] = vehicle.model == model
            and { model = vehicle.model, name = vehicle.name, price = price }
            or vehicle
    end
    return saveSelected({ vehicles = vehicles })
end

local function removeVehicle(model)
    local vehicle = fn.findVehicle(selected.vehicles, model)
    if not vehicle then return refresh() end
    local confirmation = Kora.nui.openAlert({
        title = Kora.lang('c.creator.vehicles.remove.title'),
        message = Kora.lang('c.creator.vehicles.remove.message', fn.vehicleName(vehicle)),
        confirmLabel = Kora.lang('c.creator.vehicles.remove.confirm'),
    })
    if not confirmation or not confirmation.confirmed then return refresh() end

    local vehicles = {}
    for _, vehicle in ipairs(selected.vehicles) do
        if vehicle.model ~= model then vehicles[#vehicles + 1] = vehicle end
    end
    return saveSelected({ vehicles = vehicles })
end

local function onAction(actionId, context)
    local values = context and context.value or {}

    if actionId == 'create' then return createDealership(values.label) end

    local selectId = actionId:match('^select:(.+)$')
    if selectId then return selectDealership(selectId) end

    if not selected then return refresh() end

    if actionId == 'delete' then return deleteSelected() end

    if actionId == 'data:save' then
        return saveSelected({ label = values.label, type = values.type, price = tonumber(values.price), owner = values.owner })
    end

    if actionId == 'zone:create' then
        pendingTool = { kind = 'zone' }
        return { close = true }
    end
    if actionId == 'zone:clear' then return saveSelected({ clearZone = true, zone = nil }) end

    if actionId == 'vehicles:add' then return addVehicle(values.model) end
    local priceModel = actionId:match('^vehicles:price:(.+)$')
    if priceModel then return setVehiclePrice(priceModel, tonumber(values.price)) end
    local removeModel = actionId:match('^vehicles:remove:(.+)$')
    if removeModel then return removeVehicle(removeModel) end

    local tool, viewId = fn.aimToolFor(actionId, values)
    if tool then
        pendingTool, currentView = tool, viewId
        return { close = true }
    end

    local field, kept = fn.removeFromList(actionId, selected)
    if field then return saveSelected({ [field] = kept }) end

    return refresh()
end

Kora.nui.registerApp({
    id = APP_ID,
    title = Kora.lang('c.creator.title'),
    icon = 'Warehouse',
    layout = 'standard',
    width = 1200,
    height = 800,
    defaultView = 'dealerships',
    navigation = buildNavigation(),
    onAction = onAction,
})

local function runPendingTool()
    local tool = pendingTool
    pendingTool = nil

    if tool.kind == 'zone' then
        local result = Kora.zones.startCreator('poly')
        if result then saveSelected({ zone = result.opts }) end
    else
        fn.runAimTool(tool, selected, saveSelected)
    end
end

local function open()
    while true do
        Kora.nui.updateApp(APP_ID, { navigation = buildNavigation(), title = appTitle() })
        Kora.nui.openApp(APP_ID, { viewId = currentView })
        if not pendingTool then break end
        runPendingTool()
    end
end

RegisterCommand(Config.command, function()
    CreateThread(open)
end, false)
