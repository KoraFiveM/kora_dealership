local APP_ID = 'qbdealership:creator'
local views = DealershipViews

local selected = nil        -- the currently-open dealership record (server's copy)
local currentView = 'dealerships'
local pendingTool = nil     -- set by onAction, consumed by the open loop below
local vehicleCatalog = nil  -- { { value = model, label = name }, ... }, built once

local function loadCatalog()
    if vehicleCatalog then return vehicleCatalog end
    local shared = exports.qbcore:allShared('vehicles') or {}
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
    local list = QB.callback.trigger('qbdealership:list') or {}
    local items = {}
    for _, entry in ipairs(list) do
        items[#items + 1] = {
            id = entry.id,
            label = entry.label,
            description = entry.type == 'for_sale' and QB.lang('c.creator.for_sale', entry.price or 0)
                or entry.type == 'owned' and QB.lang('c.creator.owned', entry.owner or 'unclaimed')
                or QB.lang('c.creator.public'),
            icon = 'Warehouse',
            action = 'select:' .. entry.id,
        }
    end

    return {
        id = 'dealerships', label = QB.lang('c.creator.dealerLabel'), icon = 'Warehouse',
        content = {
            title = QB.lang('c.creator.dealerLabel'),
            description = QB.lang('c.creator.dealerDesc'),
            blocks = {
                { type = 'list', id = 'dealership-list', items = items, empty = 'No dealerships yet.' },
                {
                    type = 'form', id = 'create', title = QB.lang('c.creator.createDealership'),
                    fields = { { id = 'label', label = QB.lang('c.creator.dealerName'), type = 'text', required = true } },
                    action = { id = 'create', label = QB.lang('c.creator.create') },
                },
            },
        },
    }
end

local function dataView()
    return {
        id = 'data', label = QB.lang('c.creator.data.header'), icon = 'Settings',
        content = {
            title = selected.label, description = QB.lang('c.creator.data.description'),
            blocks = {
                {
                    type = 'form', id = 'data', title = QB.lang('c.creator.data.header'),
                    fields = {
                        { id = 'label', label = QB.lang('c.creator.data.form.name'), type = 'text', default = selected.label, required = true },
                        {
                            id = 'type', label = QB.lang('c.creator.data.form.access'), type = 'select', default = selected.type,
                            options = {
                                { value = 'public', label = QB.lang('c.creator.data.form.public') },
                                { value = 'for_sale', label = QB.lang('c.creator.data.form.for_sale') },
                                { value = 'owned', label = QB.lang('c.creator.data.form.owned') },
                            },
                        },
                        {
                            id = 'price', label = QB.lang('c.creator.data.form.price'), type = 'number',
                            default = selected.price and tonumber(selected.price) or 1,
                        },
                        {
                            id = 'owner', label = QB.lang('c.creator.data.form.owner'), type = 'text',
                            default = selected.owner or '',
                            description = QB.lang('c.creator.data.form.ownerDesc'),
                        },
                    },
                    action = { id = 'data:save', label = QB.lang('c.creator.data.form.save') },
                },
                {
                    type = 'actions', title = QB.lang('c.creator.data.delete.danger'),
                    actions = { { id = 'delete', label = QB.lang('c.creator.data.delete.delete'), variant = 'destructive' } },
                },
            },
        },
    }
end

local function zoneView()
    local zone = selected.zone
    return {
        id = 'zone', label = QB.lang('c.creator.zone.header'), icon = 'MapPin',
        content = {
            title = QB.lang('c.creator.zone.header'), description = QB.lang('c.creator.zone.description'),
            blocks = {
                {
                    type = 'stats',
                    items = {
                        { label = QB.lang('c.creator.zone.stats.points'), value = zone and #zone.points or 0, icon = 'MapPin' },
                        { label = QB.lang('c.creator.zone.stats.thickness'), value = zone and ('%.1fm'):format(zone.thickness) or '—', icon = 'Ruler' },
                    },
                },
                {
                    type = 'actions', title = QB.lang('c.creator.zone.actions.draw'),
                    actions = {
                        { id = 'zone:create', label = zone and QB.lang('c.creator.zone.actions.redraw') or QB.lang('c.creator.zone.actions.draw'), variant = 'primary' },
                        { id = 'zone:clear', label = QB.lang('c.creator.zone.actions.clear'), variant = 'outline', disabled = zone == nil },
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
            description = QB.lang('s.price', tonumber(vehicle.price) or 1),
            icon = 'Car',
            action = 'vehicles:edit:' .. vehicle.model,
            image = fn.getVehicleImage(vehicle.model),
        }
    end

    return {
        id = 'vehicles', label = QB.lang('c.creator.vehicles.header'), icon = 'Car',
        content = {
            title = QB.lang('c.creator.vehicles.header'),
            description = QB.lang('c.creator.vehicles.description'),
            blocks = {
                {
                    type = 'form', id = 'vehicle-add', title = QB.lang('c.creator.vehicles.form.add'),
                    fields = { { id = 'model', label = QB.lang('c.creator.vehicles.form.veh'), type = 'select', options = loadCatalog(), required = true } },
                    action = { id = 'vehicles:add', label = QB.lang('c.creator.vehicles.form.add') },
                },
                
                { type = 'list', id = 'vehicle-list', title = QB.lang('c.creator.vehicles.form.current', #items), layout = 'cards',  items = items, empty = QB.lang('c.creator.vehicles.form.empty') },
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

local refresh, fail = fn.appRefresher(APP_ID, buildNavigation)


local function saveSelected(patch)
    local result, err = QB.callback.trigger('qbdealership:save', selected.id, patch)
    if not result then return fail(err or QB.lang('c.creator.failed')) end
    selected = result
    return refresh(fn.notice('Saved.'))
end

local function createDealership(label)
    local record, err = QB.callback.trigger('qbdealership:create', label)
    if not record then return fail(err or QB.lang('c.creator.failed')) end
    selected, currentView = record, 'data'
    return refresh(fn.notice(QB.lang('c.creator.save')))
end

local function selectDealership(id)
    local record, err = QB.callback.trigger('qbdealership:get', id)
    if not record then return fail(err or QB.lang('c.creator.failed')) end
    selected, currentView = record, 'data'
    return refresh()
end

local function deleteSelected()
    local confirmation = QB.nui.openAlert({
        title = QB.lang('c.creator.delete.title'), message = QB.lang('c.creator.delete.message'),
        confirmLabel = QB.lang('c.creator.delete.confirm'),
    })
    if not confirmation or not confirmation.confirmed then return refresh() end

    local ok, err = QB.callback.trigger('qbdealership:delete', selected.id)
    if not ok then return fail(err or QB.lang('c.creator.delete.fail')) end
    selected, currentView = nil, 'dealerships'
    return refresh(fn.notice(QB.lang('c.creator.delete.pass')))
end

local function addVehicle(model)
    if not model then return fail(QB.lang('c.creator.vehicles.add.vehReq')) end
    if fn.findVehicle(selected.vehicles, model) then return fail(QB.lang('c.creator.vehicles.add.vehExists')) end
    return saveSelected({ vehicles = fn.appended(selected.vehicles, { model = model }) })
end

local function setVehiclePrice(model, price)
    if not model or not price then return fail(QB.lang('c.creator.vehicles.price.vehPrice')) end

    local vehicles = {}
    for _, vehicle in ipairs(selected.vehicles) do
        vehicles[#vehicles + 1] = vehicle.model == model
            and { model = vehicle.model, name = vehicle.name, price = price }
            or vehicle
    end
    return saveSelected({ vehicles = vehicles })
end

local function removeVehicle(model)
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
    if actionId == 'vehicles:price' then return setVehiclePrice(values.model, tonumber(values.price)) end
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

QB.nui.registerApp({
    id = APP_ID,
    title = 'Dealership Creator',
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
        local result = QB.zones.startCreator('poly')
        if result then saveSelected({ zone = result.opts }) end
    else
        fn.runAimTool(tool, selected, saveSelected)
    end
end

local function open()
    while true do
        QB.nui.updateApp(APP_ID, { navigation = buildNavigation() })
        QB.nui.openApp(APP_ID, { viewId = currentView })
        if not pendingTool then break end
        runPendingTool()
    end
end

RegisterCommand(Config.command, function()
    CreateThread(open)
end, false)
