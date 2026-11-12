-- Run from the resource root: lua test/purchased_event.lua
local events, keys = {}, {}
CreateThread = function() end
AddEventHandler = function() end
Config = { spawnClearance = 3.0, offerVehicleState = 'garaged' }
Kora = {
    print = { debug = function() end },
    sql = {
        query = function() return {} end,
        transaction = function() return true end,
    },
}
exports = { kora_vehiclekeys = { giveKeys = function(_, src, plate) keys[#keys + 1] = plate end } }
TriggerEvent = function(name, ...) events[#events + 1] = { name = name, args = { ... } } end
SetVehicleNumberPlateText = function() end
NetworkGetNetworkIdFromEntity = function() return 7 end
TaskWarpPedIntoVehicle = function() end
GetPlayerPed = function() return 1 end
DeleteEntity = function() end
dofile('server/functions.lua')
fn.citizenId = function() return 'CID1' end
local created = true
fn.createVehicle = function() return created and 5 or nil end

assert(fn.deliverVehicle(2, 'sultan', { coords = {} }) == 7)
assert(#events == 1 and events[1].name == 'qb-vehicleshop:server:onVehiclePurchased')
assert(events[1].args[1] == 'CID1' and events[1].args[2] == 'sultan' and #events[1].args[3] == 8)
assert(events[1].args[3] == keys[1], 'event plate matches the keyed plate')

events = {}
assert(fn.deliverVehicle('CID2', 'adder') == true)
assert(#events == 1 and events[1].args[1] == 'CID2' and events[1].args[2] == 'adder')

events = {}
created = false
assert(fn.deliverVehicle(2, 'sultan', { coords = {} }) == nil and #events == 0, 'failed deliveries emit nothing')
Kora.sql.transaction = function() return false end
assert(fn.deliverVehicle('CID2', 'adder') == nil and #events == 0, 'failed inserts emit nothing')
print('purchased event tests passed')
