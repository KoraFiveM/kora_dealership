local H = dofile('test/harness.lua')

Config = nil
QB = { sql = { NULL = {} } }
dofile('config.lua')
dofile('shared/schema.lua')

local dealer = assert(Dealership.schema.normaliseDealership({
    id = 'pdm', label = 'Premium Deluxe Motorsport', autoAccept = true,
    zone = { coords = { x = 1, y = 2, z = 3 }, size = { x = 10, y = 10, z = 4 } },
    vehicles = { 'sultan', 'sultan', 'blista' }, prices = { sultan = 15000 }, placements = {},
    purchaseSpawnCoords = { x = 5, y = 6, z = 7, w = 90 },
}))
H.equal(#dealer.vehicles, 2, 'schema removes duplicate vehicle models')
H.equal(dealer.prices.sultan, 15000, 'schema preserves dealership price overrides')
H.equal(dealer.prices.blista, nil, 'missing overrides continue to use QB Core prices')

local custom = assert(Dealership.schema.offer({ direction = 'buy', model = 'sultan', terms = '10 meals' }))
H.equal(custom.amount, nil, 'non-cash offers do not require a cash amount')
H.equal(custom.terms, '10 meals', 'non-cash terms are retained for manual review')

local callbacks, charges, created, inserted = {}, {}, {}, {}
local vehicles = {
    sultan = { model = 'sultan', name = 'Sultan', brand = 'Karin', price = 12000 },
    blista = { model = 'blista', name = 'Blista', brand = 'Dinka', price = 8000 },
}
Dealership.state = {
    get = function(id) return id == 'pdm' and dealer or nil end,
    near = function() return true end,
    canManage = function() return false end,
    stock = function() return {} end,
    player = function(src)
        return { source = src, citizenid = 'CID-1', charinfo = { firstname = 'John', lastname = 'Doe' } }
    end,
    snapshot = function() return { pdm = dealer } end,
    isAdmin = function() return false end,
    ready = true,
}

QB.callback = { register = function(name, fn, options) callbacks[name] = { fn = fn, options = options } end }
QB.sql.insert = function(_, params) inserted[#inserted + 1] = params; return 7 end
QB.sql.update = function() return 1 end
QB.sql.execute = function() return {} end
QB.sql.query = function() return {} end
QB.sql.transaction = function() return true end
QB.sql.single = function() return nil end
exports = {
    qbcore = {
        getShared = function(_, namespace, model)
            H.equal(namespace, 'vehicles', 'catalogue uses QB Core shared vehicles')
            return vehicles[model]
        end,
        getByPlate = function() return nil end,
        createVehicle = function(_, citizenid, model, plate)
            created[#created + 1] = { citizenid = citizenid, model = model, plate = plate }
            return true
        end,
        removeMoney = function(_, src, account, amount)
            charges[#charges + 1] = { src = src, account = account, amount = amount }
            return true
        end,
        addMoney = function() return true end,
        spawnVehicle = function() return 42 end,
        getPlayerByCitizenId = function() return nil end,
        getByOwner = function() return {} end,
        allShared = function() return {} end,
    },
}
setmetatable(exports, { __call = function() end })
GetResourceState = function() return 'missing' end
TriggerClientEvent = function() end
AddEventHandler = function() end

dofile('server/dealership.lua')
dofile('server/callbacks.lua')

local catalogue = assert(Dealership.api.catalogue(1, 'pdm'))
H.equal(#catalogue.vehicles, 2, 'catalogue contains the configured vehicles')
H.equal(catalogue.vehicles[1].price, 15000, 'dealership override is the customer price')
H.equal(catalogue.vehicles[2].price, 8000, 'QB Core shared price is the default')

local purchased = assert(Dealership.api.purchase(1, 'pdm', 'blista'))
H.equal(charges[1].amount, 8000, 'purchase charges the server-resolved shared price')
H.equal(created[1].citizenid, 'CID-1', 'purchased ownership uses the server-resolved character')
H.equal(purchased.networkId, 42, 'direct purchase spawns at the configured purchase point')

local beforeCharges = #charges
local forged = Dealership.api.purchase(1, 'pdm', 'police')
H.equal(forged, false, 'a model outside the dealership catalogue is refused')
H.equal(#charges, beforeCharges, 'forged models are refused before money moves')

local managed = Dealership.api.setPrice(1, 'pdm', 'sultan', 1)
H.equal(managed, false, 'pricing changes require dealership management access')

local offer = assert(Dealership.api.submitOffer(1, 'pdm', {
    direction = 'buy', model = 'sultan', amount = 10000, terms = '10 meals',
}))
H.equal(offer.manual, true, 'offers with non-cash terms are always manual')
H.equal(inserted[1][9], 0, 'manual terms never receive an automatic acceptance time')

for name, callback in pairs(callbacks) do
    H.ok(callback.options.rateLimit ~= nil, name .. ' is rate-limited')
end
H.ok(callbacks['qbdealership:server:manageOffer'] ~= nil, 'management offer callback is registered')
H.ok(callbacks['qbdealership:server:saveDealership'] ~= nil, 'creator save callback is registered')

local serverSource = assert(io.open('server/dealership.lua', 'r')):read('*a')
local clientSource = assert(io.open('client/world.lua', 'r')):read('*a')
H.ok(serverSource:find('Config.AutoSellTime', 1, true) ~= nil, 'automatic offers use the configured delay')
H.ok(serverSource:find('not offer.terms', 1, true) ~= nil, 'non-cash terms are excluded from automatic settlement')
H.ok(clientSource:find("QB.placement.start('asbo')", 1, true) ~= nil, 'coordinate picking uses the shared vehicle placer')
H.ok(clientSource:find('SetVehicleOnGroundProperly', 1, true) ~= nil, 'display and picker vehicles use the FiveM ground native')

H.finish()
