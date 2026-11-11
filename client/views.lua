
local function deleteAction(id)
    return { id = id, label = Kora.lang('s.delete'), icon = 'Trash2', variant = 'destructive' }
end

local function coordsLabel(coords)
    return Kora.lang('s.coords'):format(coords.x, coords.y, coords.z)
end

local function placementsView(record)
    local items = {}
    for index, placement in ipairs(record.placements) do
        items[#items + 1] = {
            id = tostring(index), label = placement.model, icon = 'Car',
            description = coordsLabel(placement.coords),
            actions = { deleteAction('placements:remove:' .. index) },
            image = fn.getVehicleImage(placement.model)
        }
    end

    local vehicleOptions = fn.vehicleOptions(record.vehicles)
    local blocks = {}
    if #vehicleOptions > 0 then
        blocks[#blocks + 1] = {
            type = 'form', id = 'place', title = Kora.lang('c.creator.placement.form.place'),
            description = Kora.lang('c.creator.placement.form.description'),
            fields = { { id = 'model', label = Kora.lang('c.creator.placement.form.veh'), type = 'select', options = vehicleOptions, required = true } },
            action = { id = 'placements:add', label = Kora.lang('c.creator.placement.form.place') },
        }
    else
        blocks[#blocks + 1] = { type = 'empty', title = Kora.lang('c.creator.placement.empty') }
    end
    blocks[#blocks + 1] = { type = 'list', id = 'placement-list', layout = 'cards', title = Kora.lang('c.creator.placement.listTitle'), items = items, empty = Kora.lang('c.creator.placement.emptyList') }

    return {
        id = 'placements', label = Kora.lang('c.creator.placement.header'), icon = 'MapPin',
        content = { title = Kora.lang('c.creator.placement.header'), description = Kora.lang('c.creator.placement.description'), blocks = blocks },
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
        id = 'spawns', label = Kora.lang('c.creator.spawns.header'), icon = 'MapPin',
        content = {
            title = Kora.lang('c.creator.spawns.header'), description = Kora.lang('c.creator.spawns.description'),
            blocks = {
                { type = 'actions', actions = { { id = 'spawns:add', label = Kora.lang('c.creator.spawns.form.add'), variant = 'primary' } } },
                { type = 'list', id = 'spawn-list', layout = 'cards', title = Kora.lang('c.creator.spawns.listTitle'), items = items, empty = Kora.lang('c.creator.spawns.empty') },
            },
        },
    }
end

local function pointZonesView(spec, record, keepLast)
    local items = {}
    local entries = record[spec.field] or {}
    for index, entry in ipairs(entries) do
        items[#items + 1] = {
            id = tostring(index), label = ('%s %d'):format(spec.noun, index), icon = 'MapPin',
            description = coordsLabel(entry.coords),
            -- keepLast hides the delete button on the final remaining entry
            actions = not (keepLast and #entries <= 1) and { deleteAction(spec.id .. ':remove:' .. index) } or nil,
        }
    end

    return {
        id = spec.id, label = spec.label, icon = spec.icon,
        content = {
            title = spec.title, description = spec.description,
            blocks = {
                { type = 'actions', actions = { { id = spec.id .. ':add', label = spec.addLabel, variant = 'primary' } } },
                { type = 'list',layout = 'cards', id = spec.id .. '-list', title = spec.listTitle, items = items, empty = spec.empty },
            },
        },
    }
end

local managementSpec = {
    id = 'management', field = 'managementZones', noun = Kora.lang('c.creator.management.header'), label = Kora.lang('c.creator.management.header'), icon = 'Briefcase',
    title = Kora.lang('c.creator.management.header'), description = Kora.lang('c.creator.management.description'),
    addLabel = Kora.lang('c.creator.management.addLabel'), listTitle = Kora.lang('c.creator.management.listTitle'), empty = Kora.lang('c.creator.management.empty'),
}

local saleSpec = {
    id = 'sales', field = 'saleZones', noun = Kora.lang('c.creator.sales.header'), label = Kora.lang('c.creator.sales.header'), icon = 'Tag',
    title = Kora.lang('c.creator.sales.header'), description = Kora.lang('c.creator.sales.description'),
    addLabel = Kora.lang('c.creator.sales.addLabel'), listTitle = Kora.lang('c.creator.sales.listTitle'), empty = Kora.lang('c.creator.sales.empty'),
}

DealershipViews = {
    placements = placementsView,
    spawns = spawnsView,
    pointZones = pointZonesView,
    managementSpec = managementSpec,
    saleSpec = saleSpec,
}
