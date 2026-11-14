-- Run from kora_dealership: lua5.4 test/catalog.lua
local app, reads = nil, 0
local confirmRemoval = false
exports = { kora_core = { allShared = function(_, registry)
    assert(registry == 'vehicles')
    reads = reads + 1
    return { { model = 'sultan', name = 'Sultan' }, { model = 'adder', name = 'Adder' }, { model = 'bison' } }
end } }
Config = { command = 'dealership', maxPrice = 5000000 }
local record = { id = 'shop', label = 'Shop', type = 'public', vehicles = {
    { model = 'sultan', name = 'Sultan', price = 12000 },
    { model = 'adder', name = 'Adder', price = 25000 },
} }
local function emptyView() return {} end
DealershipViews = { placements = emptyView, spawns = emptyView, pointZones = emptyView }
fn = {
    appRefresher = function(_, build)
        return function() return { navigation = build() } end, error
    end,
    vehicleName = function(vehicle) return vehicle.name end,
    findVehicle = function(vehicles, model)
        for _, vehicle in ipairs(vehicles) do
            if vehicle.model == model then return vehicle end
        end
    end,
    getVehicleImage = function() end,
    notice = function(message) return { message = message } end,
}
Kora = {
    lang = function(key) return key end,
    callback = { trigger = function(name, id, patch)
        if name == 'kora_dealership:list' then return {} end
        assert(id == record.id)
        if name == 'kora_dealership:save' then
            record.vehicles = patch.vehicles
        else
            assert(name == 'kora_dealership:get')
        end
        return record
    end },
    nui = {
        registerApp = function(definition) app = definition end,
        updateApp = function() end,
        openAlert = function() return { confirmed = confirmRemoval } end,
    },
}
RegisterCommand = function() end
dofile('client/creator.lua')
local function options()
    local picker = app.onAction('select:shop', {}).navigation[4].content.blocks[1].fields[1]
    assert(picker.searchable, 'the catalog picker supports search')
    return picker.options
end
local catalog = options()
assert(#catalog == 3)
assert(catalog[1].value == 'adder' and catalog[1].label == 'Adder')
assert(catalog[2].value == 'sultan' and catalog[3].value == 'bison' and catalog[3].label == 'bison')
assert(options() == catalog and reads == 1, 'the existing catalog cache is retained')
print('kora_dealership: native vehicle records retain model values, labels, sorting and caching')

local blocks = app.onAction('select:shop', {}).navigation[4].content.blocks
assert(blocks[2].layout == 'list' and blocks[2].pageSize == 12, 'the vehicle list uses paginated rows')
local priceAction = blocks[2].items[1].actions[1]
assert(priceAction.fields[1].default == 12000 and priceAction.fields[1].max == Config.maxPrice)
local updated = app.onAction(priceAction.id, { value = { price = 15000 } })
assert(record.vehicles[1].model == 'sultan' and record.vehicles[1].price == 15000)
assert(record.vehicles[2].model == 'adder' and record.vehicles[2].price == 25000)
assert(updated.navigation[4].content.blocks[2].items[1].actions[1].fields[1].default == 15000)
print('kora_dealership: creator vehicle card saves and refreshes the selected price')

local removeAction = updated.navigation[4].content.blocks[2].items[1].actions[2]
app.onAction(removeAction.id, {})
assert(#record.vehicles == 2, 'cancelling keeps both vehicles')
confirmRemoval = true
app.onAction(removeAction.id, {})
assert(#record.vehicles == 1 and record.vehicles[1].model == 'adder', 'confirmation removes the chosen vehicle')
