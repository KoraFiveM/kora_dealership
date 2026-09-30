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
local offers, payouts, owned = {}, {}, {}

local function copyRow(row)
    if not row then return nil end
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    return copy
end
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
QB.sql.insert = function(_, params)
    inserted[#inserted + 1] = params
    local id = #inserted
    offers[id] = { id = id, dealership = params[1], direction = params[2], model = params[3], plate = params[4],
        citizenid = params[5], amount = params[7], terms = params[8], status = 'pending', auto_at = params[9] == 1 or nil }
    for _, key in ipairs({ 'plate', 'amount', 'terms' }) do
        if offers[id][key] == QB.sql.NULL then offers[id][key] = nil end
    end
    return id
end
QB.sql.update = function(sql, params)
    if sql:find("SET `status` = 'accepted'", 1, true) then
        local row = offers[params[1]]
        if not row or row.status ~= params[2] then return 0 end
        row.status = 'accepted'
        return 1
    end
    if sql:find("SET `status` = 'countered'", 1, true) then
        local row = offers[params[3]]
        if not row or row.status ~= 'pending' then return 0 end
        row.status, row.counter_amount, row.counter_terms, row.auto_at = 'countered', params[1], params[2], nil
        return 1
    end
    return 0
end
QB.sql.execute = function(sql, params)
    if sql:find('SET `auto_at` = NULL', 1, true) then offers[params[1]].auto_at = nil end
    return true
end
QB.sql.query = function()
    local rows = {}
    for _, row in pairs(offers) do
        if row.status == 'pending' and row.auto_at and not row.terms then rows[#rows + 1] = copyRow(row) end
    end
    return rows
end
QB.sql.transaction = function(statements)
    for _, statement in ipairs(statements) do
        if statement.sql:find('UPDATE `player_vehicles`', 1, true) then owned[statement.params[1]] = nil end
    end
    return true
end
QB.sql.single = function(_, params) return copyRow(offers[params[1]]) end
exports = {
    qbcore = {
        getShared = function(_, namespace, model)
            H.equal(namespace, 'vehicles', 'catalogue uses QB Core shared vehicles')
            return vehicles[model]
        end,
        getByPlate = function(_, plate) return owned[plate] end,
        createVehicle = function(_, citizenid, model, plate)
            created[#created + 1] = { citizenid = citizenid, model = model, plate = plate }
            return true
        end,
        removeMoney = function(_, src, account, amount)
            charges[#charges + 1] = { src = src, account = account, amount = amount }
            return true
        end,
        addMoney = function(_, _, _, amount) payouts[#payouts + 1] = amount; return true end,
        spawnVehicle = function() return 42 end,
        getPlayerByCitizenId = function(_, citizenid) return { source = 1, citizenid = citizenid } end,
        getByOwner = function() return {} end,
        allShared = function() return {} end,
    },
}
setmetatable(exports, { __call = function() end })
GetResourceState = function() return 'missing' end
TriggerClientEvent = function() end
AddEventHandler = function() end
QB.notify = { send = function() end }

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
H.equal(inserted[1][10], Config.AutoSellTime, 'submission retains the configured automatic delay')

owned.PERSONAL = { plate = 'PERSONAL', model = 'sultan', citizenid = 'CID-1', state = 'garaged' }
for _, case in ipairs({
    { 'buy', 1, false }, { 'buy', 14999, false }, { 'buy', 15000, true }, { 'buy', 15001, true },
    { 'sell', 12001, false }, { 'sell', 12000, true }, { 'sell', 11999, true }, { 'sell', Config.maxPrice, false },
}) do
    local submitted = assert(Dealership.api.submitOffer(1, 'pdm', {
        direction = case[1], model = 'sultan', plate = 'PERSONAL', amount = case[2],
    }))
    H.equal(submitted.automatic, case[3], ('%s amount %d respects automatic pricing bounds'):format(case[1], case[2]))
    H.equal(submitted.manual, not case[3], 'out-of-policy cash offers remain available for manual review')
    H.equal(inserted[submitted.id][9], case[3] and 1 or 0, 'only eligible offers receive a scheduled acceptance time')
end

dealer.prices.sultan = 7000
local lowerOverride = assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'sell', model = 'sultan', plate = 'PERSONAL', amount = 7001 }))
H.equal(lowerOverride.automatic, false, 'a lower local sale override also caps automatic trade-in payments')
H.equal(assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'sell', model = 'sultan', plate = 'PERSONAL', amount = 7000 })).automatic,
    true, 'a trade-in at the lower local ceiling can settle automatically')
dealer.prices.sultan = 15000
Config.AutoAccept.enabled = false
H.equal(assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'buy', model = 'sultan', amount = 15000 })).automatic,
    false, 'the global automatic-acceptance switch still applies')
Config.AutoAccept.enabled = true
dealer.autoAccept = false
H.equal(assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'buy', model = 'sultan', amount = 15000 })).automatic,
    false, 'the dealership automatic-acceptance switch still applies')
dealer.autoAccept = true

-- Persisted rows may predate pricing checks, so exercise the worker directly.
offers = {
    [101] = { id = 101, dealership = 'pdm', direction = 'buy', model = 'sultan', citizenid = 'CID-1', amount = 1, status = 'pending', auto_at = true },
    [102] = { id = 102, dealership = 'pdm', direction = 'sell', model = 'sultan', plate = 'PERSONAL', citizenid = 'CID-1', amount = Config.maxPrice, status = 'pending', auto_at = true },
    [103] = { id = 103, dealership = 'pdm', direction = 'buy', model = 'sultan', citizenid = 'CID-1', amount = 15000, status = 'pending', auto_at = true },
    [104] = { id = 104, dealership = 'pdm', direction = 'sell', model = 'sultan', plate = 'PERSONAL', citizenid = 'CID-1', amount = 12000, status = 'pending', auto_at = true },
}
local workerCharges, workerCreated, workerPayouts = #charges, #created, #payouts
Dealership.api.processOffers()
for _, id in ipairs({ 101, 102 }) do
    H.equal(offers[id].status, 'pending', 'persisted unsafe offers stay pending for manual review')
    H.equal(offers[id].auto_at, nil, 'persisted unsafe offers have their automatic schedule cleared')
end
H.equal(#charges, workerCharges + 1, 'only the fairly priced persisted purchase is charged')
H.equal(#created, workerCreated + 1, 'only the fairly priced persisted purchase creates a vehicle')
H.equal(charges[#charges].amount, 15000, 'automatic purchase uses the permitted offer amount')
H.equal(#payouts, workerPayouts + 1, 'only the fairly priced persisted trade-in is paid')
H.equal(payouts[#payouts], 12000, 'automatic trade-in respects the shared base ceiling')
H.equal(offers[103].status, 'accepted', 'purchase at its floor still settles normally')
H.equal(offers[104].status, 'accepted', 'trade-in at its ceiling still settles normally')

offers = {}
local repricedBuy = assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'buy', model = 'sultan', amount = 15000 }))
dealer.prices.sultan = 16000
workerCharges, workerCreated = #charges, #created
Dealership.api.processOffers()
H.equal(offers[repricedBuy.id].auto_at, nil, 'a later retail price increase makes a scheduled purchase manual')
H.equal(offers[repricedBuy.id].status, 'pending', 'repricing does not decline a customer offer')
H.equal(#charges, workerCharges, 'repriced purchase is not charged')
H.equal(#created, workerCreated, 'repriced purchase is not delivered')

offers = {}
owned.PERSONAL = { plate = 'PERSONAL', model = 'sultan', citizenid = 'CID-1', state = 'garaged' }
dealer.prices.sultan = 7000
local repricedSell = assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'sell', model = 'sultan', plate = 'PERSONAL', amount = 7000 }))
dealer.prices.sultan = 6500
workerPayouts = #payouts
Dealership.api.processOffers()
H.equal(offers[repricedSell.id].auto_at, nil, 'a later local ceiling decrease makes a scheduled trade-in manual')
H.equal(#payouts, workerPayouts, 'repriced trade-in is not paid')
H.ok(owned.PERSONAL ~= nil, 'repriced trade-in does not consume the vehicle')

offers = {}
local sharedRepricedSell = assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'sell', model = 'sultan', plate = 'PERSONAL', amount = 6500 }))
vehicles.sultan.price = 6000
Dealership.api.processOffers()
H.equal(offers[sharedRepricedSell.id].auto_at, nil, 'a later shared base decrease is rechecked before payment')
H.equal(#payouts, workerPayouts, 'a changed shared base price cannot cause an automatic overpayment')
dealer.prices.sultan, vehicles.sultan.price = 15000, 12000

offers = {}
Dealership.state.canManage = function(src) return src == 99 end
local manualBuy = assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'buy', model = 'sultan', amount = 1 }))
workerCharges = #charges
H.equal(Dealership.api.manageOffer(1, manualBuy.id, 'accept'), false, 'manual offers still require manager authorization')
H.equal(#charges, workerCharges, 'unauthorized approval does not move money')
H.ok(type(Dealership.api.manageOffer(99, manualBuy.id, 'accept')) == 'table', 'an authorized manager can accept an out-of-policy offer')
H.equal(charges[#charges].amount, 1, 'explicit manager negotiation is not forced to the automatic floor')
local counterBuy = assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'buy', model = 'sultan', amount = 15000 }))
H.equal(Dealership.api.manageOffer(99, counterBuy.id, 'counter', { amount = 1, terms = '10 meals' }), true, 'a manager may negotiate a custom counteroffer')
H.equal(offers[counterBuy.id].auto_at, nil, 'counteroffers still disable automatic settlement')
H.ok(type(Dealership.api.acceptCounter(1, counterBuy.id)) == 'table', 'the customer may explicitly accept a negotiated counteroffer')
H.equal(charges[#charges].amount, 1, 'counteroffer settlement keeps its explicitly negotiated amount')

for name, callback in pairs(callbacks) do
    H.ok(callback.options.rateLimit ~= nil, name .. ' is rate-limited')
end
H.ok(callbacks['qbdealership:server:manageOffer'] ~= nil, 'management offer callback is registered')
H.ok(callbacks['qbdealership:server:saveDealership'] ~= nil, 'creator save callback is registered')

local clientSource = assert(io.open('client/world.lua', 'r')):read('*a')
H.ok(clientSource:find("QB.placement.start('asbo')", 1, true) ~= nil, 'coordinate picking uses the shared vehicle placer')
H.ok(clientSource:find('SetVehicleOnGroundProperly', 1, true) ~= nil, 'display and picker vehicles use the FiveM ground native')

H.finish()
