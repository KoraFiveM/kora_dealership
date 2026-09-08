local H = dofile('test/harness.lua')

local callbacks, charges, refunds, created, notifications = {}, {}, {}, {}, {}
local player = { coords = { x = -56.6, y = -1096.7, z = 26.4 }, bucket = 0 }
local vehicles = {
    sultan = { model = 'sultan', name = 'Sultan', brand = 'Karin', price = 12000 },
    blista = { model = 'blista', name = 'Blista', brand = 'Dinka', price = 8000 },
    kuruma = { model = 'kuruma', name = 'Kuruma', brand = 'Karin', price = 95000 },
    police = { model = 'police', name = 'Cruiser', brand = 'Vapid', price = 0 },
}
local persist = true

Config = nil
dofile('config.lua')
QB = {
    callback = { register = function(name, fn, opts) callbacks[name] = { fn = fn, opts = opts } end },
    notify = { send = function(_, payload) notifications[#notifications + 1] = payload end },
}
exports = {
    qbcore = {
        getShared = function(_, namespace, model)
            H.equal(namespace, 'vehicles', 'catalogue uses the shared vehicle registry')
            return vehicles[model]
        end,
        getPlayerData = function(_, _, path)
            H.equal(path[1], 'citizenid', 'buyer identity comes from qbcore')
            return 'CID-1'
        end,
        removeMoney = function(_, _, account, amount)
            charges[#charges + 1] = { account = account, amount = amount }
            return true
        end,
        addMoney = function(_, _, account, amount, reason, ignoreTax)
            refunds[#refunds + 1] = { account = account, amount = amount, reason = reason, ignoreTax = ignoreTax }
            return true
        end,
        getByPlate = function() return nil end,
        createVehicle = function(_, citizenid, model, plate, job, extra)
            created[#created + 1] = { citizenid = citizenid, model = model, plate = plate, job = job, extra = extra }
            return persist
        end,
    },
}
setmetatable(exports, { __call = function() end })
GetPlayerPed = function() return 12 end
GetEntityCoords = function() return player.coords end
GetPlayerRoutingBucket = function() return player.bucket end

dofile('server/dealership.lua')
dofile('server/callbacks.lua')

H.equal(Config.dealerships.pdm.vehicles[1].vehicle, 'sultan', 'config stores only a vehicle model reference')
H.equal(Config.dealerships.pdm.vehicles[1].price, nil, 'config uses the shared price when no override is configured')
H.ok(callbacks['qbdealership:list'].opts.rateLimit ~= nil and callbacks['qbdealership:buy'].opts.rateLimit ~= nil, 'every client callback is rate-limited')

local catalogue = Dealership.api.list(1, 'pdm')
H.equal(#catalogue.vehicles, 3, 'configured shared vehicles are listed in configuration order')
H.equal(catalogue.vehicles[1].price, 12000, 'price is read from qbcore shared vehicles')
H.equal(catalogue.vehicles[3].price, 90000, 'configured price override replaces the shared vehicle price')

local bought = Dealership.api.buy(1, 'pdm', 'sultan')
H.equal(bought.model, 'sultan', 'purchase returns the resolved shared model')
H.equal(charges[1].amount, 12000, 'purchase charges the shared vehicle price')
H.equal(created[1].citizenid, 'CID-1', 'persistence uses the server-resolved character')
H.equal(created[1].job, nil, 'dealership creates a civilian-owned vehicle')
H.ok(notifications[1].type == 'success', 'successful purchase notifies the buyer')

local overrideBought = Dealership.api.buy(1, 'pdm', 'kuruma')
H.equal(overrideBought.price, 90000, 'purchase returns the configured price override')
H.equal(charges[2].amount, 90000, 'purchase charges the configured price override')

local before = #charges
local rejected = Dealership.api.buy(1, 'pdm', 'police')
H.equal(rejected, false, 'a vehicle not in the dealership vehicle list is refused')
H.equal(#charges, before, 'forged model is refused before charging')

player.coords = { x = 0, y = 0, z = 0 }
rejected = Dealership.api.buy(1, 'pdm', 'sultan')
H.equal(rejected, false, 'purchase is refused away from the configured dealership')
H.equal(#charges, before, 'distance refusal happens before charging')

player.coords = { x = -56.6, y = -1096.7, z = 26.4 }
persist = false
rejected = Dealership.api.buy(1, 'pdm', 'sultan')
H.equal(rejected, false, 'failed vehicle persistence refuses the purchase')
H.equal(refunds[1].amount, 12000, 'failed persistence refunds the exact charged shared price')
H.ok(refunds[1].ignoreTax == true, 'refund is not taxed again')

H.finish()
