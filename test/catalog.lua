-- Run from qbdealership: lua5.4 test/catalog.lua
local app, reads = nil, 0
exports = { kora_core = { allShared = function(_, registry)
    assert(registry == 'vehicles')
    reads = reads + 1
    return { { model = 'sultan', name = 'Sultan' }, { model = 'adder', name = 'Adder' }, { model = 'bison' } }
end } }
Config = { command = 'dealership' }
local function emptyView() return {} end
DealershipViews = { placements = emptyView, spawns = emptyView, pointZones = emptyView }
fn = { appRefresher = function(_, build)
    return function() return { navigation = build() } end, error
end }
Kora = {
    lang = function(key) return key end,
    callback = { trigger = function(name)
        if name == 'qbdealership:list' then return {} end
        assert(name == 'qbdealership:get')
        return { id = 'shop', label = 'Shop', type = 'public', vehicles = {} }
    end },
    nui = { registerApp = function(definition) app = definition end, updateApp = function() end },
}
RegisterCommand = function() end
dofile('client/creator.lua')
local function options()
    return app.onAction('select:shop', {}).navigation[4].content.blocks[1].fields[1].options
end
local catalog = options()
assert(#catalog == 3)
assert(catalog[1].value == 'adder' and catalog[1].label == 'Adder')
assert(catalog[2].value == 'sultan' and catalog[3].value == 'bison' and catalog[3].label == 'bison')
assert(options() == catalog and reads == 1, 'the existing catalog cache is retained')
print('qbdealership: native vehicle records retain model values, labels, sorting and caching')
