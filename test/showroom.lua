-- Run from the resource root: lua test/showroom.lua
local apps, stateHandlers, events = {}, {}, {}
local tasks, removals, targets = {}, {}, {}
local nextEntity, showroomOpen, updates = 0, false, 0
local showroom = 'kora_dealership:showroom'
local ctx = { dealer = 'shop', index = 1 }

GlobalState = { Dealerships = { shop = {
    label = 'Shop', type = 'public',
    vehicles = { { model = 'sultan', price = 100 }, { model = 'adder', price = 200 } },
    placements = { { model = 'sultan', coords = { x = 0, y = 0, z = 0 } } },
} } }
Config = { categories = { 'Sports' } }
fn = {
    waitForDealerships = function() end,
    vehicleName = function(vehicle) return vehicle.model end,
    getVehicleImage = function() end,
    emptyView = function(id) return { id = id } end,
    notice = function(message) return message end,
    withCleanup = function(body, cleanup) body(); cleanup() end,
}
Kora = {
    lang = function(key) return key end,
    cache = { onChange = function() end },
    callback = { trigger = function(name) assert(name == 'kora_dealership:swap'); return true end },
    entities = {
        create = function() nextEntity = nextEntity + 1; return nextEntity end,
        remove = function(entity) removals[#removals + 1] = 'vehicle:' .. entity end,
    },
    nui = {
        registerApp = function(app) apps[app.id] = app end,
        isAppOpen = function(id) return id == showroom and showroomOpen end,
        updateApp = function(id, patch)
            assert(id == showroom)
            apps[id].navigation = patch.navigation
            updates = updates + 1
        end,
        openApp = function(id)
            assert(id == showroom)
            showroomOpen = true
            coroutine.yield()
            showroomOpen = false
        end,
    },
}
exports = { kora_target = {
    addEntity = function(_, entity, options)
        targets[entity] = options[1].onSelect
        return 100 + entity
    end,
    removeEntity = function(_, entity, targetId)
        assert(targets[entity] and targetId == 100 + entity)
        targets[entity] = nil
        removals[#removals + 1] = 'target:' .. entity
    end,
} }
function CreateThread(action) tasks[#tasks + 1] = coroutine.create(action) end
function AddStateBagChangeHandler(name, _, handler) stateHandlers[name] = handler end
function AddEventHandler(name, handler) events[name] = handler end
function GetCurrentResourceName() return 'kora_dealership' end
function PlayerPedId() return 1 end
function GetVehiclePedIsIn() return 0 end
function joaat(model) return model end
function IsModelInCdimage() return true end
function IsModelAVehicle() return true end
function GetVehicleClassFromName() return 0 end
function vector3(x, y, z) return { x = x, y = y, z = z } end
function SetEntityHeading() end

local function step(task)
    local ok, err = coroutine.resume(task)
    assert(ok, err)
end

local function assertDisplay(model, resetDisabled)
    local content = apps[showroom].navigation[1].content
    assert(content.actions[1].disabled == resetDisabled)
    for _, card in ipairs(content.blocks[1].items) do
        assert((card.badge ~= nil) == (card.id == model))
    end
end

dofile('client/customer.lua')
step(tasks[1])
targets[1]()
step(tasks[2])
assertDisplay('sultan', true)

local response = apps[showroom].onAction('swap:adder', { data = ctx })
assert(response.notice and not response.update)
assertDisplay('sultan', true)
stateHandlers.DealershipSwaps(nil, nil, { shop = { ['1'] = 'adder' } })
assertDisplay('adder', false)
step(tasks[3])
assert(removals[1] == 'target:1' and removals[2] == 'vehicle:1' and targets[2])

stateHandlers.DealershipSwaps(nil, nil, { shop = { ['1'] = 'adder' }, other = { ['1'] = 'sultan' } })
assert(updates == 2, 'a swap at another dealership does not refresh the showroom')
stateHandlers.DealershipSwaps(nil, nil, {})
assertDisplay('sultan', true)
step(tasks[4])
assert(removals[3] == 'target:2' and removals[4] == 'vehicle:2')
step(tasks[2])

events.onClientResourceStop('kora_dealership')
assert(removals[5] == 'target:3' and removals[6] == 'vehicle:3')
assert(next(targets) == nil)
print('kora_dealership: showroom follows swap replication and cleans up browse targets')
