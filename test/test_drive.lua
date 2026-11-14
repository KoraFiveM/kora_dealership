-- Run from the resource root: lua test/test_drive.lua
local callbacks, events, timers = {}, {}, {}
local bucket, vehicleExists, hasKey, warped = 42, false, false, false
local grantMode = 'success'

Config = { testBucketBase = 100000, testDriveSeconds = 120, rateLimits = {}, testSpawn = {} }
Dealerships = { shop = {} }
Kora = {
    print = { debug = function() end },
    lang = function(key) return key end,
    callback = { register = function(name, handler) callbacks[name] = handler end },
}
fn = {
    fail = function(message) return false, message end,
    dealerWriter = function(action) return action end,
    rateLimit = function() return true end,
    nearPoint = function() return true end,
    findVehicle = function() return { model = 'sultan' } end,
    createVehicle = function() vehicleExists = true; return 10 end,
}
exports = { kora_vehiclekeys = {
    giveKeys = function(_, src, plate)
        assert(src == 7 and plate == 'TD000007' and #timers > 0)
        if grantMode == 'refused' then return false end
        hasKey = true
        if grantMode == 'throws' then error('key export failed after granting') end
        return true
    end,
    removeKeys = function(_, src, plate)
        assert(src == 7 and plate == 'TD000007')
        hasKey = false
        return true
    end,
} }
function RegisterNetEvent(name, handler) events[name] = handler end
function AddEventHandler(name, handler) events[name] = handler end
function GetInvokingResource() return nil end
function GetCurrentResourceName() return 'kora_dealership' end
function GetPlayerPed() return 1 end
function GetPlayerRoutingBucket() return bucket end
function SetPlayerRoutingBucket(_, value) bucket = value end
function SetEntityRoutingBucket() end
function DoesEntityExist() return vehicleExists end
function DeleteEntity() vehicleExists = false end
function NetworkGetNetworkIdFromEntity() return 20 end
function SetVehicleNumberPlateText() end
function TaskWarpPedIntoVehicle() warped = true end
function SetTimeout(ms, action)
    assert(ms == 120000)
    timers[#timers + 1] = action
end

dofile('server/customer.lua')
source = 7
local function start()
    warped = false
    return callbacks['kora_dealership:testDrive'](source, 'shop', 1, 'sultan')
end
local function assertClean()
    assert(bucket == 42 and not vehicleExists and not hasKey)
end

assert(start() == 20 and bucket == 100007 and vehicleExists and hasKey and warped)
events['kora_dealership:server:testDriveEnded']()
assertClean()

assert(start() == 20)
timers[1]()
assert(vehicleExists and hasKey, 'an old timeout must leave the new drive alone')
timers[2]()
assertClean()

for _, mode in ipairs({ 'refused', 'throws' }) do
    grantMode = mode
    local result, err = start()
    assert(result == false and err == 's.errors.test_vehicle_keys_failed' and not warped)
    assertClean()
end

grantMode = 'success'
assert(start() == 20)
events.onResourceStop('kora_dealership')
assertClean()
assert(start() == 20)
events.playerDropped()
assertClean()
print('kora_dealership: test-drive cleanup revokes keys and handles failed grants')
