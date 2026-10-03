local APP_ID = 'qbdealership:creator'

local selected = nil   -- the currently-open dealership record (server's copy)
local currentView = 'dealerships'
local pendingTool = nil -- set by onAction, consumed by the open loop below
local vehicleCatalog = nil -- { {value=model, label=name}, ... }, built once

local function notify(message, tone)
    QB.notify.send({ title = 'Dealership Creator', message = message, type = tone or 'error' })
end

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

-- --- views -----------------------------------------------------------------

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
            label = vehicle.name or vehicle.model,
            description = ('$%d'):format(tonumber(vehicle.price) or 1),
            icon = 'Car',
            action = 'vehicles:edit:' .. vehicle.model,
        }
    end

    local vehicleOptions = {}

    for _, vehicle in ipairs(selected.vehicles or {}) do
        vehicleOptions[#vehicleOptions + 1] = {
            value = vehicle.model,
            label = vehicle.name or vehicle.model,
        }
    end

    return {
        id = 'vehicles',
        label = 'Vehicles',
        icon = 'Car',
        content = {
            title = 'Dealership vehicles',
            description = 'Vehicles this dealership can display, place, and sell.',
            blocks = {
                {
                    type = 'form',
                    id = 'vehicle-add',
                    title = 'Add vehicle',
                    fields = {
                        {
                            id = 'model',
                            label = 'Vehicle',
                            type = 'select',
                            options = loadCatalog(),
                            required = true,
                        },
                    },
                    action = {
                        id = 'vehicles:add',
                        label = 'Add Vehicle',
                    },
                },
                {
                    type = 'form',
                    id = 'vehicle-price',
                    title = 'Vehicle price',
                    fields = {
                        {
                            id = 'model',
                            label = 'Vehicle',
                            type = 'select',
                            options = vehicleOptions,
                            required = true,
                        },
                        {
                            id = 'price',
                            label = 'Sale Price',
                            type = 'number',
                            min = 1,
                            max = Config.maxPrice,
                            required = true,
                        },
                    },
                    action = {
                        id = 'vehicles:price',
                        label = 'Save Price',
                    },
                },
                {
                    type = 'list',
                    id = 'vehicle-list',
                    title = 'Current vehicles',
                    items = items,
                    empty = 'No vehicles added yet.',
                },
            },
        },
    }
end

local function placementsView(record)
    local items = {}
    for index, placement in ipairs(record.placements) do
        items[#items + 1] = {
            id = tostring(index), label = placement.model, icon = 'Car',
            description = ('%.1f, %.1f, %.1f'):format(placement.coords.x, placement.coords.y, placement.coords.z),
            action = 'placements:remove:' .. index,
        }
    end

    local vehicleOptions = {}
    for _, vehicle in ipairs(record.vehicles) do
        vehicleOptions[#vehicleOptions + 1] = {
            value = vehicle.model,
            label = vehicle.name or vehicle.model,
        }
    end

    local blocks = {}
    if #vehicleOptions > 0 then
        blocks[#blocks + 1] = {
            type = 'form', id = 'place', title = 'Place display vehicle',
            description = 'Pick a vehicle, then aim at where it should appear in the world.',
            fields = { { id = 'model', label = 'Vehicle', type = 'select', options = vehicleOptions, required = true } },
            action = { id = 'placements:add', label = 'Place display vehicle' },
        }
    else
        blocks[#blocks + 1] = { type = 'empty', title = 'Add a vehicle on the Vehicles tab first.' }
    end
    blocks[#blocks + 1] = { type = 'list', id = 'placement-list', title = 'Current placements', items = items, empty = 'No vehicles placed yet.' }

    return {
        id = 'placements', label = 'Placements', icon = 'MapPin',
        content = { title = 'Display placements', description = 'Showroom vehicles customers see but can\'t take.', blocks = blocks },
    }
end

local function spawnsView(record)
    local items = {}
    for index, spawn in ipairs(record.spawns) do
        items[#items + 1] = {
            id = tostring(index), label = ('Spawn %d'):format(index), icon = 'MapPin',
            description = ('%.1f, %.1f, %.1f'):format(spawn.coords.x, spawn.coords.y, spawn.coords.z),
            action = 'spawns:remove:' .. index,
        }
    end

    return {
        id = 'spawns', label = 'Spawns', icon = 'MapPin',
        content = {
            title = 'Vehicle spawn points', description = 'Where a purchased/display vehicle is actually created. Add as many as you like.',
            blocks = {
                { type = 'actions', actions = { { id = 'spawns:add', label = 'Add spawn point', variant = 'primary' } } },
                { type = 'list', id = 'spawn-list', title = 'Current spawn points', items = items, empty = 'No spawn points yet.' },
            },
        },
    }
end

-- Raycast picker for management/sale points: no preview model, just a coordinate.
local function getCoords()
    return QB.raycast.getCoords({})
end

local function pointZonesView(spec, record)
    local items = {}
    for index, entry in ipairs(record[spec.field] or {}) do
        items[#items + 1] = {
            id = tostring(index), label = ('%s %d'):format(spec.noun, index), icon = 'MapPin',
            description = ('%.1f, %.1f, %.1f'):format(entry.coords.x, entry.coords.y, entry.coords.z),
            action = spec.id .. ':remove:' .. index,
        }
    end

    return {
        id = spec.id, label = spec.label, icon = spec.icon,
        content = {
            title = spec.title, description = spec.description,
            blocks = {
                { type = 'actions', actions = { { id = spec.id .. ':add', label = spec.addLabel, variant = 'primary' } } },
                { type = 'list', id = spec.id .. '-list', title = spec.listTitle, items = items, empty = spec.empty },
            },
        },
    }
end

local managementSpec = {
    id = 'management', field = 'managementZones', noun = 'Management zone', label = 'Management', icon = 'Briefcase',
    title = 'Management zones', description = 'Where the dealership owner and staff manage the business. Add as many as you like.',
    addLabel = 'Add management zone', listTitle = 'Current management zones', empty = 'No management zones yet.',
}

local saleSpec = {
    id = 'sales', field = 'saleZones', noun = 'Sale zone', label = 'Sales', icon = 'Tag',
    title = 'Sale zones', description = 'Where vehicles are sold to customers. Add as many as you like.',
    addLabel = 'Add sale zone', listTitle = 'Current sale zones', empty = 'No sale zones yet.',
}

-- Shared with client/management.lua (the owner portal reuses these pages).
DealershipViews = {
    placements = placementsView,
    spawns = spawnsView,
    pointZones = pointZonesView,
    managementSpec = managementSpec,
    saleSpec = saleSpec,
}

local function buildNavigation()
    local views = { dealershipsView() }
    if selected then
        views[#views + 1] = dataView()
        views[#views + 1] = zoneView()
        views[#views + 1] = vehiclesView()
        views[#views + 1] = placementsView(selected)
        views[#views + 1] = spawnsView(selected)
        views[#views + 1] = pointZonesView(managementSpec, selected)
        views[#views + 1] = pointZonesView(saleSpec, selected)
    end
    return views
end

local function refresh(notice)
    QB.nui.updateApp(APP_ID, { navigation = buildNavigation() })
    return { update = { navigation = buildNavigation() }, notice = notice }
end

-- --- actions -----------------------------------------------------------------

local function saveSelected(patch)
    local result, err = QB.callback.trigger('qbdealership:save', selected.id, patch)
    if not result then
        return refresh({ tone = 'destructive', message = err or 'Save failed.' })
    end
    selected = result
    return refresh({ tone = 'success', message = 'Saved.' })
end

local function onAction(actionId, context)
    local values = context and context.value

    if actionId == 'create' then
        local record, err = QB.callback.trigger('qbdealership:create', values and values.label)
        if not record then return refresh({ tone = 'destructive', message = err or 'Could not create dealership.' }) end
        selected, currentView = record, 'data'
        return refresh({ tone = 'success', message = 'Dealership created.' })
    end

    local selectId = actionId:match('^select:(.+)$')
    if selectId then
        local record, err = QB.callback.trigger('qbdealership:get', selectId)
        if not record then return refresh({ tone = 'destructive', message = err or 'Could not open dealership.' }) end
        selected, currentView = record, 'data'
        return refresh()
    end

    if not selected then return refresh() end

    if actionId == 'delete' then
        local confirmation = QB.nui.openAlert({
            title = 'Delete dealership', message = ('Delete "%s"? This cannot be undone.'):format(selected.label),
            confirmLabel = 'Delete',
        })
        if not confirmation or not confirmation.confirmed then return refresh() end
        local ok, err = QB.callback.trigger('qbdealership:delete', selected.id)
        if not ok then return refresh({ tone = 'destructive', message = err or 'Delete failed.' }) end
        selected, currentView = nil, 'dealerships'
        return refresh({ tone = 'success', message = 'Dealership deleted.' })
    end

    if actionId == 'data:save' then
        return saveSelected({ label = values.label, type = values.type, price = tonumber(values.price), owner = values.owner })
    end

    if actionId == 'zone:create' then
        pendingTool = { kind = 'zone' }
        return { close = true }
    end
    if actionId == 'zone:clear' then
        return saveSelected({ clearZone = true, zone = nil })
    end

    if actionId == 'vehicles:add' then
        local model = values.model
        if not model then
            return refresh({
                tone = 'destructive',
                message = 'Vehicle is required.'
            })
        end
        local vehicles = {}
        for _, vehicle in ipairs(selected.vehicles or {}) do
            if vehicle.model == model then
                return refresh({
                    tone = 'destructive',
                    message = 'That vehicle is already added.'
                })
            end
            vehicles[#vehicles + 1] = vehicle
        end
        vehicles[#vehicles + 1] = {
            model = model,
        }
    
        return saveSelected({ vehicles = vehicles })
    end
    if actionId == 'vehicles:price' then
        local model = values.model
        local price = tonumber(values.price)

        if not model or not price then
            return refresh({
                tone = 'destructive',
                message = 'Vehicle and price are required.'
            })
        end

        local vehicles = {}

        for _, vehicle in ipairs(selected.vehicles) do
            if vehicle.model == model then
                vehicles[#vehicles + 1] = {
                    model = vehicle.model,
                    name = vehicle.name,
                    price = price,
                }
            else
                vehicles[#vehicles + 1] = vehicle
            end
        end

        return saveSelected({ vehicles = vehicles })
    end
    local removeModel = actionId:match('^vehicles:remove:(.+)$')
    if removeModel then
        local vehicles = {}
        for _, model in ipairs(selected.vehicles) do
            if model ~= removeModel then vehicles[#vehicles + 1] = model end
        end
        return saveSelected({ vehicles = vehicles })
    end

    if actionId == 'placements:add' then
        pendingTool = { kind = 'placement', model = values.model }
        return { close = true }
    end
    local removePlacement = actionId:match('^placements:remove:(%d+)$')
    if removePlacement then
        local placements = {}
        for index, placement in ipairs(selected.placements) do
            if tostring(index) ~= removePlacement then placements[#placements + 1] = placement end
        end
        return saveSelected({ placements = placements })
    end

    if actionId == 'spawns:add' then
        pendingTool = { kind = 'spawn' }
        return { close = true }
    end
    local removeSpawn = actionId:match('^spawns:remove:(%d+)$')
    if removeSpawn then
        local spawns = {}
        for index, spawn in ipairs(selected.spawns) do
            if tostring(index) ~= removeSpawn then spawns[#spawns + 1] = spawn end
        end
        return saveSelected({ spawns = spawns })
    end

    for _, spec in ipairs({ managementSpec, saleSpec }) do
        if actionId == spec.id .. ':add' then
            pendingTool = { kind = 'point', spec = spec }
            currentView = spec.id
            return { close = true }
        end
        local removeIndex = actionId:match('^' .. spec.id .. ':remove:(%d+)$')
        if removeIndex then
            local kept = {}
            for index, entry in ipairs(selected[spec.field] or {}) do
                if tostring(index) ~= removeIndex then kept[#kept + 1] = entry end
            end
            return saveSelected({ [spec.field] = kept })
        end
    end

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
    elseif tool.kind == 'spawn' then
        local result = QB.raycast.getCoords({ type = 'object', object = 'asbo' })
        if result then
            local spawns = {}
            for _, spawn in ipairs(selected.spawns) do spawns[#spawns + 1] = spawn end
            spawns[#spawns + 1] = { coords = result.coords }
            saveSelected({ spawns = spawns })
        end
    elseif tool.kind == 'point' then
        local field = tool.spec.field
        local result = getCoords()
        if result then
            local list = {}
            for _, entry in ipairs(selected[field] or {}) do list[#list + 1] = entry end
            list[#list + 1] = { coords = result.coords }
            saveSelected({ [field] = list })
        end
    elseif tool.kind == 'placement' then
        local result = QB.raycast.getCoords({ type = 'object', object = tool.model })
        if result then
            local placements = {}
            for _, placement in ipairs(selected.placements) do placements[#placements + 1] = placement end
            placements[#placements + 1] = { model = tool.model, coords = result.coords }
            saveSelected({ placements = placements })
        end
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