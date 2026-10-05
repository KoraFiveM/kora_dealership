local APP_ID = 'qbdealership:creator'
local views = DealershipViews

local selected = nil        -- the currently-open dealership record (server's copy)
local currentView = 'dealerships'
local pendingTool = nil     -- set by onAction, consumed by the open loop below
local vehicleCatalog = nil  -- { { value = model, label = name }, ... }, built once

local function loadCatalog()
    if vehicleCatalog then return vehicleCatalog end
    local shared = exports['qb-core']:GetShared('Vehicles') or {}
    local list = {}
    for model, data in pairs(shared) do
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
            description = entry.type == 'for_sale' and ('For sale · $%d'):format(entry.price or 0)
                or entry.type == 'owned' and ('Owned · %s'):format(entry.owner or 'unclaimed')
                or 'Public',
            icon = 'Warehouse',
            action = 'select:' .. entry.id,
        }
    end

    return {
        id = 'dealerships', label = 'Dealerships', icon = 'Warehouse',
        content = {
            title = 'Dealerships',
            description = 'Pick one to edit, or create a new one.',
            blocks = {
                { type = 'list', id = 'dealership-list', items = items, empty = 'No dealerships yet.' },
                {
                    type = 'form', id = 'create', title = 'Create dealership',
                    fields = { { id = 'label', label = 'Name', type = 'text', required = true } },
                    action = { id = 'create', label = 'Create' },
                },
            },
        },
    }
end

local function dataView()
    return {
        id = 'data', label = 'Data', icon = 'Settings',
        content = {
            title = selected.label, description = 'Public, for sale at a set price, or owned by a player.',
            blocks = {
                {
                    type = 'form', id = 'data', title = 'Dealership data',
                    fields = {
                        { id = 'label', label = 'Name', type = 'text', default = selected.label, required = true },
                        {
                            id = 'type', label = 'Access', type = 'select', default = selected.type,
                            options = {
                                { value = 'public', label = 'Public' },
                                { value = 'for_sale', label = 'For sale' },
                                { value = 'owned', label = 'Owned' },
                            },
                        },
                        {
                            id = 'price', label = 'Price (if for sale)', type = 'number',
                            default = selected.price and tonumber(selected.price) or 1,
                        },
                        {
                            id = 'owner', label = 'Owner citizenid (if owned)', type = 'text',
                            default = selected.owner or '',
                            description = 'Only kept while Access is set to Owned -- cleared otherwise.',
                        },
                    },
                    action = { id = 'data:save', label = 'Save' },
                },
                {
                    type = 'actions', title = 'Danger zone',
                    actions = { { id = 'delete', label = 'Delete dealership', variant = 'destructive' } },
                },
            },
        },
    }
end

local function zoneView()
    local zone = selected.zone
    return {
        id = 'zone', label = 'Zone', icon = 'MapPin',
        content = {
            title = 'Dealership zone', description = 'The polygon customers must be inside to use this dealership.',
            blocks = {
                {
                    type = 'stats',
                    items = {
                        { label = 'Points', value = zone and #zone.points or 0, icon = 'MapPin' },
                        { label = 'Thickness', value = zone and ('%.1fm'):format(zone.thickness) or '—', icon = 'Ruler' },
                    },
                },
                {
                    type = 'actions', title = 'Draw zone',
                    actions = {
                        { id = 'zone:create', label = zone and 'Redraw zone' or 'Draw zone', variant = 'primary' },
                        { id = 'zone:clear', label = 'Clear zone', variant = 'outline', disabled = zone == nil },
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
            description = ('$%d'):format(tonumber(vehicle.price) or 1),
            icon = 'Car',
            action = 'vehicles:edit:' .. vehicle.model,
        }
    end

    return {
        id = 'vehicles', label = 'Vehicles', icon = 'Car',
        content = {
            title = 'Dealership vehicles',
            description = 'Vehicles this dealership can display, place, and sell.',
            blocks = {
                {
                    type = 'form', id = 'vehicle-add', title = 'Add vehicle',
                    fields = { { id = 'model', label = 'Vehicle', type = 'select', options = loadCatalog(), required = true } },
                    action = { id = 'vehicles:add', label = 'Add Vehicle' },
                },
                {
                    type = 'form', id = 'vehicle-price', title = 'Vehicle price',
                    fields = {
                        { id = 'model', label = 'Vehicle', type = 'select', options = fn.vehicleOptions(selected.vehicles), required = true },
                        { id = 'price', label = 'Sale Price', type = 'number', min = 1, max = Config.maxPrice, required = true },
                    },
                    action = { id = 'vehicles:price', label = 'Save Price' },
                },
                { type = 'list', id = 'vehicle-list', title = 'Current vehicles', items = items, empty = 'No vehicles added yet.' },
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
    if not result then return fail(err or 'Save failed.') end
    selected = result
    return refresh(fn.notice('Saved.'))
end

local function createDealership(label)
    local record, err = QB.callback.trigger('qbdealership:create', label)
    if not record then return fail(err or 'Could not create dealership.') end
    selected, currentView = record, 'data'
    return refresh(fn.notice('Dealership created.'))
end

local function selectDealership(id)
    local record, err = QB.callback.trigger('qbdealership:get', id)
    if not record then return fail(err or 'Could not open dealership.') end
    selected, currentView = record, 'data'
    return refresh()
end

local function deleteSelected()
    local confirmation = QB.nui.openAlert({
        title = 'Delete dealership', message = ('Delete "%s"? This cannot be undone.'):format(selected.label),
        confirmLabel = 'Delete',
    })
    if not confirmation or not confirmation.confirmed then return refresh() end

    local ok, err = QB.callback.trigger('qbdealership:delete', selected.id)
    if not ok then return fail(err or 'Delete failed.') end
    selected, currentView = nil, 'dealerships'
    return refresh(fn.notice('Dealership deleted.'))
end

local function addVehicle(model)
    if not model then return fail('Vehicle is required.') end
    if fn.findVehicle(selected.vehicles, model) then return fail('That vehicle is already added.') end
    return saveSelected({ vehicles = fn.appended(selected.vehicles, { model = model }) })
end

local function setVehiclePrice(model, price)
    if not model or not price then return fail('Vehicle and price are required.') end

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
