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

local function resume(thread)
    local ok, result = coroutine.resume(thread)
    assert(ok, result)
    return result
end

Config.maxStock = 10
GlobalState = {}
json = { encode = function() return '[]' end }
Dealerships.shop = { id = 'shop', type = 'owned', vehicles = { { model = 'sultan', stock = 2 } } }
DealerData.shop = { balance = 500, income = 0, spent = 0, sales = {}, employees = {}, permissions = {}, settings = {} }
Kora.lang = function(key) return key end
local success = false
Kora.sql.transactionChecked = function(writes)
    assert(#writes == 3 and writes[1].sql:find('player_vehicles', 1, true))
    assert(writes[2].sql:find('kora_dealerships', 1, true))
    assert(writes[3].sql:find('kora_dealership_management', 1, true))
    coroutine.yield()
    return success and { success = true } or { success = false, code = 'unavailable' }
end
local function settle()
    return fn.withDealerWrite('shop', function()
        local writes = {}
        local stock = assert(fn.stageStock('shop', 'sultan', -1, writes))
        local account = fn.stageManagement('shop', { balance = 600, income = 100 }, writes)
        return fn.deliverSale('shop', 'CID2', 'sultan', nil, writes, stock, account)
    end)
end
local failed = coroutine.create(settle)
resume(failed)
assert(settle() == false, 'a second write cannot start while the first awaits SQL')
assert(resume(failed) == nil and #events == 0)
assert(Dealerships.shop.vehicles[1].stock == 2 and DealerData.shop.balance == 500)
success = true
local committed = coroutine.create(settle)
resume(committed)
assert(resume(committed) == true and #events == 1)
assert(Dealerships.shop.vehicles[1].stock == 1 and DealerData.shop.balance == 600)

local online, offline
local sessions = { [2] = 'OTHER', [3] = 'REJOINED' }
fn.citizenId = function(src) return sessions[src] end
exports.kora_core = {
    getPlayerByCitizenId = function(_, cid)
        if cid == 'REJOINED' then return { source = 3 } end
    end,
    addMoney = function(_, src, account, amount, reason, ignoreTax)
        assert(ignoreTax and account == 'bank' and amount == 50)
        online = src
        return true
    end,
    addOfflineMoney = function(_, cid, account, amount)
        assert(cid == 'OFFLINE' and account == 'bank' and amount == 50)
        offline = cid
        return true
    end,
}
assert(fn.creditPlayer('shop', 2, 'OFFLINE', 'bank', 50, 'Dealership refund'))
assert(offline == 'OFFLINE' and online == nil, 'a reused source must not receive the refund')
assert(fn.creditPlayer('shop', 2, 'REJOINED', 'bank', 50, 'Dealership commission'))
assert(online == 3, 'a returning character receives credit in their current session')
assert(fn.creditPlayer('shop', 3, 'REJOINED', 'bank', 50, 'Dealership withdrawal'))
offline = nil
assert(not fn.creditPlayer('cash-shop', 2, 'OFFLINE', 'cash', 50, 'Dealership refund'))
assert(offline == nil, 'cash credits must not fall back to stored money')

local callbacks, threads = {}, {}
Kora.callback = { register = function(name, callback) callbacks[name] = callback end }
CreateThread = function(callback) threads[#threads + 1] = coroutine.create(callback) end
Wait = coroutine.yield
Config.maxOrderQuantity = 10
Config.orderPriceMultiplier = 0.7
Dealerships.shop.vehicles[1].price = 100
fn.canEmployeeDo = function() return true end
fn.nearPoint = function() return true end
dofile('shared/functions.lua')
dofile('server/Management.lua')

Kora.sql.transactionChecked = function(writes)
    assert(#writes == 2, 'the order batches its stock and balance changes')
    return { success = false, code = 'unavailable' }
end
assert(callbacks['kora_dealership:management:orderVehicle'](2, 'shop', 1, 'sultan', 1) == false)
assert(Dealerships.shop.vehicles[1].stock == 1 and DealerData.shop.balance == 600)

local autoOffer = { id = 9, dealership_id = 'shop', model = 'sultan', offeror = 'CID2', offer_price = 100 }
local decision, refunds
fn.takeCash = function() return true end
fn.giveCash = function() refunds = (refunds or 0) + 1; return true end
Kora.sql.query = function(sql)
    if sql:find('kora_dealership_offers', 1, true) then return { autoOffer } end
    return {}
end
Kora.sql.transactionChecked = function(writes)
    for _, write in ipairs(writes) do
        if write.sql:find('kora_dealership_offers', 1, true) then decision = write.params[1] end
    end
    return { success = false, code = 'unavailable' }
end
resume(threads[1])
resume(threads[1])
assert(decision == 'accepted' and refunds == 1, 'a rolled-back auto-accept refunds and never writes a denial')
assert(Dealerships.shop.vehicles[1].stock == 1 and DealerData.shop.balance == 600)
print('purchased event tests passed')
