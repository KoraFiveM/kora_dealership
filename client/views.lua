
local function deleteAction(id)
    return { id = id, label = 'Delete', icon = 'Trash2', variant = 'destructive' }
end

local function coordsLabel(coords)
    return ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z)
end

local function placementsView(record)
    local items = {}
    for index, placement in ipairs(record.placements) do
        items[#items + 1] = {
            id = tostring(index), label = placement.model, icon = 'Car',
            description = coordsLabel(placement.coords),
            actions = { deleteAction('placements:remove:' .. index) },
        }
    end

    local vehicleOptions = fn.vehicleOptions(record.vehicles)
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
            description = coordsLabel(spawn.coords),
            actions = { deleteAction('spawns:remove:' .. index) },
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

local function pointZonesView(spec, record)
    local items = {}
    for index, entry in ipairs(record[spec.field] or {}) do
        items[#items + 1] = {
            id = tostring(index), label = ('%s %d'):format(spec.noun, index), icon = 'MapPin',
            description = coordsLabel(entry.coords),
            actions = { deleteAction(spec.id .. ':remove:' .. index) },
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

DealershipViews = {
    placements = placementsView,
    spawns = spawnsView,
    pointZones = pointZonesView,
    managementSpec = managementSpec,
    saleSpec = saleSpec,
}
