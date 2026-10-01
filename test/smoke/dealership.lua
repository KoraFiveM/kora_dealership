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
local updateHook, claimError, completionError, releaseError, paymentHook, creationHook
local acceptedUpdates = 0

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
        citizenid = params[5], amount = params[7], terms = params[8], status = 'pending', settling = 0, auto_at = params[9] == 1 or nil }
    for _, key in ipairs({ 'plate', 'amount', 'terms' }) do
        if offers[id][key] == QB.sql.NULL then offers[id][key] = nil end
    end
    return id
end
QB.sql.update = function(sql, params)
    if updateHook then updateHook(sql, params) end
    if sql:find("SET `status` = 'expired'", 1, true) then
        local affected = 0
        for _, row in pairs(offers) do
            if row.expired and (row.status == 'pending' or row.status == 'countered')
                and (not sql:find('`settling` = 0', 1, true) or (row.settling or 0) == 0) then
                row.status = 'expired'
                affected = affected + 1
            end
        end
        return affected
    end
    if sql:find('SET `settling` = 1', 1, true) then
        if claimError then return nil, claimError end
        local row = offers[params[1]]
        if not row or row.status ~= params[2] or (row.settling or 0) ~= 0 then return 0 end
        row.settling = 1
        return 1
    end
    if sql:find('SET `settling` = 0', 1, true) then
        if releaseError then return nil, releaseError end
        local row = offers[params[1]]
        if not row or row.status ~= params[2] or row.settling ~= 1 then return 0 end
        row.settling = 0
        return 1
    end
    if sql:find("SET `status` = 'accepted'", 1, true) then
        if completionError then return nil, completionError end
        local row = offers[params[1]]
        if not row or row.status ~= params[2] then return 0 end
        if sql:find('AND `settling` = 1', 1, true) and row.settling ~= 1 then return 0 end
        row.status, row.settling = 'accepted', 0
        return 1
    end
    if sql:find("SET `status` = 'declined'", 1, true) then
        local row = offers[params[1]]
        if not row or row.status ~= 'pending' then return 0 end
        if sql:find('AND `settling` = 0', 1, true) and (row.settling or 0) ~= 0 then return 0 end
        row.status = 'declined'
        return 1
    end
    if sql:find("SET `status` = 'countered'", 1, true) then
        local row = offers[params[3]]
        if not row or row.status ~= 'pending' then return 0 end
        if sql:find('AND `settling` = 0', 1, true) and (row.settling or 0) ~= 0 then return 0 end
        row.status, row.counter_amount, row.counter_terms, row.auto_at = 'countered', params[1], params[2], nil
        return 1
    end
    return 0
end
QB.sql.execute = function(sql, params)
    local id = sql:find('DATE_ADD', 1, true) and params[2] or params[1]
    local row = offers[id]
    if not row then return true end
    if sql:find("AND `status` = 'pending'", 1, true) and row.status ~= 'pending' then return true end
    if sql:find('AND `settling` = 0', 1, true) and (row.settling or 0) ~= 0 then return true end
    if sql:find('SET `auto_at` = NULL', 1, true) then row.auto_at = nil
    elseif sql:find('DATE_ADD', 1, true) then row.auto_at, row.retries = true, (row.retries or 0) + 1 end
    return true
end
QB.sql.query = function(sql)
    local rows = {}
    for _, row in pairs(offers) do
        if row.status == 'pending' and row.auto_at and not row.terms
            and (not sql:find('`settling` = 0', 1, true) or (row.settling or 0) == 0) then
            rows[#rows + 1] = copyRow(row)
        end
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
            if creationHook then creationHook() end
            return true
        end,
        removeMoney = function(_, src, account, amount)
            if paymentHook then
                local paid, err = paymentHook()
                if paid == false then return false, err end
            end
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
TriggerClientEvent = function(event, _, _, status)
    if event == 'qbdealership:client:offerUpdated' and status == 'accepted' then acceptedUpdates = acceptedUpdates + 1 end
end
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

local function buyOffer(countered)
    offers = {}
    local submitted = assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'buy', model = 'sultan', amount = 15000 }))
    if countered then assert(Dealership.api.manageOffer(99, submitted.id, 'counter', { amount = 9000 })) end
    return submitted.id
end

local function acceptOffer(id, countered)
    if countered then return Dealership.api.acceptCounter(1, id) end
    return Dealership.api.manageOffer(99, id, 'accept')
end

offers = {}
local unapproved = assert(Dealership.api.submitOffer(1, 'pdm', { direction = 'buy', model = 'sultan', amount = 1 }))
workerCharges, workerCreated = #charges, #created
H.equal(Dealership.api.acceptCounter(1, unapproved.id), false, 'a customer cannot accept their own pending low-price offer as a counteroffer')
H.equal(#charges, workerCharges, 'pending counter acceptance cannot charge the customer')
H.equal(#created, workerCreated, 'pending counter acceptance cannot deliver a vehicle')
H.equal(offers[unapproved.id].status, 'pending', 'unapproved pending offers remain available for a manager')
H.ok(type(Dealership.api.manageOffer(99, unapproved.id, 'accept')) == 'table', 'an authorized manager still accepts pending offers')

for _, countered in ipairs({ false, true }) do
    local id = buyOffer(countered)
    workerCharges, workerCreated = #charges, #created
    claimError = 'database claim unavailable'
    H.equal(acceptOffer(id, countered), false, 'a failed durable claim refuses settlement')
    H.equal(#charges, workerCharges, 'a failed claim moves no money')
    H.equal(#created, workerCreated, 'a failed claim delivers no vehicle')
    H.equal(offers[id].settling, 0, 'failed claims retain an unclaimed offer')
    claimError = nil
    paymentHook = function()
        H.equal(offers[id].settling, 1, 'the persisted claim exists before the payment export runs')
        return false, 'Insufficient funds.'
    end
    H.equal(acceptOffer(id, countered), false, 'a normal payment refusal is returned to the caller')
    H.equal(offers[id].status, countered and 'countered' or 'pending', 'a known failure preserves the original offer status')
    H.equal(offers[id].settling, 0, 'a known failure releases its durable claim')
    H.equal(#charges, workerCharges, 'a refused payment moves no money')
    paymentHook = nil
    H.ok(type(acceptOffer(id, countered)) == 'table', 'a normally failed offer can be retried')
    H.equal(offers[id].status, 'accepted', 'successful settlement finalizes the claimed offer')
    H.equal(offers[id].settling, 0, 'accepted offers release the flag with their final status')
    H.equal(charges[#charges].amount, countered and 9000 or 15000, 'settlement preserves the selected negotiated amount')
    H.equal(#charges, workerCharges + 1, 'a successful retry charges once')
    H.equal(#created, workerCreated + 1, 'a successful retry delivers once')
    H.equal(acceptOffer(id, countered), false, 'an accepted offer cannot settle twice')
end

local changed = buyOffer(false)
workerCharges, workerCreated = #charges, #created
updateHook = function(sql)
    if not sql:find('SET `settling` = 1', 1, true) then return end
    updateHook = nil
    assert(Dealership.api.manageOffer(99, changed, 'counter', { amount = 10000 }))
end
Dealership.api.processOffers()
updateHook = nil
H.equal(offers[changed].status, 'countered', 'a manager counter that wins before the claim is preserved')
H.equal(#charges, workerCharges, 'a stale worker snapshot losing the claim does not charge')
H.equal(#created, workerCreated, 'a stale worker snapshot losing the claim does not deliver')
H.equal(offers[changed].auto_at, nil, 'a lost claim does not reschedule a counteroffer')

for _, countered in ipairs({ false, true }) do
    local id = buyOffer(countered)
    workerCharges, workerCreated = #charges, #created
    local previousUpdates = acceptedUpdates
    completionError = 'database completion unavailable'
    if countered then acceptOffer(id, true) else Dealership.api.processOffers() end
    H.equal(#charges, workerCharges + 1, 'completion failure follows exactly one payment')
    H.equal(#created, workerCreated + 1, 'completion failure follows exactly one delivery')
    H.equal(offers[id].status, countered and 'countered' or 'pending', 'completion failure preserves the existing public status')
    H.equal(offers[id].settling, 1, 'completion failure retains the durable claim')
    H.equal(acceptedUpdates, previousUpdates, 'completion failure never broadcasts a confirmed accepted status')
    completionError = nil
    Dealership.api.processOffers()
    H.equal(offers[id].retries, nil, 'claimed offers are never automatically requeued')
    H.equal(acceptOffer(id, countered), false, 'manual acceptance cannot replay a protected offer')
    H.equal(Dealership.api.manageOffer(99, id, 'counter', { amount = 1 }), false, 'claimed offers cannot be countered')
    H.equal(Dealership.api.manageOffer(99, id, 'decline'), false, 'claimed offers cannot be declined')
    dofile('server/dealership.lua')
    dofile('server/callbacks.lua')
    Dealership.api.processOffers()
    H.equal(acceptOffer(id, countered), false, 'module reload cannot replay a persisted claim')
    H.equal(#charges, workerCharges + 1, 'worker and manual retries never repeat a completed payment')
    H.equal(#created, workerCreated + 1, 'worker and manual retries never repeat a completed delivery')
    offers[id].expired = true
    Dealership.api.processOffers()
    H.equal(offers[id].status, countered and 'countered' or 'pending', 'claimed offers never autoexpire')
end

local uncertain = buyOffer(false)
workerCharges, workerCreated = #charges, #created
creationHook = function() error('vehicle export failed after its write') end
local handled, result = pcall(acceptOffer, uncertain, false)
creationHook = nil
H.equal(handled, true, 'an unexpected effect exception is handled at the settlement boundary')
H.equal(result, false, 'an unexpected effect exception reports failed settlement')
H.equal(offers[uncertain].settling, 1, 'an ambiguous export error retains its durable claim')
Dealership.api.processOffers()
H.equal(acceptOffer(uncertain, false), false, 'an ambiguous effect error cannot be replayed manually')
H.equal(#charges, workerCharges + 1, 'an ambiguous export error does not repeat payment')
H.equal(#created, workerCreated + 1, 'an ambiguous export error does not repeat delivery')

local releaseFailed = buyOffer(false)
paymentHook = function() return false, 'Insufficient funds.' end
releaseError = 'database release unavailable'
Dealership.api.processOffers()
paymentHook, releaseError = nil, nil
H.equal(offers[releaseFailed].settling, 1, 'failed release writes leave a failed offer protected')
H.equal(offers[releaseFailed].retries, nil, 'a failed release write cannot be automatically requeued')

local beforePayment = buyOffer(false)
workerCharges = #charges
paymentHook = function() error('payment export unavailable before payment') end
handled, result = pcall(acceptOffer, beforePayment, false)
H.equal(handled, true, 'a thrown payment export is handled')
H.equal(result, false, 'a thrown payment export reports failure')
paymentHook = nil
H.equal(#charges, workerCharges, 'the test payment exception happened before any debit')
-- Simulate an operator clearing a claim after confirming that no effects occurred.
offers[beforePayment].settling = 0
H.ok(type(acceptOffer(beforePayment, false)) == 'table', 'an effect exception clears the in-memory guard')

local function pausedCounter(id, amount)
    local original = Dealership.state.canManage
    local thread
    Dealership.state.canManage = function(src, dealership)
        if coroutine.running() == thread then coroutine.yield('manager snapshot ready') end
        return original(src, dealership)
    end
    thread = coroutine.create(function() return Dealership.api.manageOffer(99, id, 'counter', { amount = amount }) end)
    local ok, marker = coroutine.resume(thread)
    assert(ok and marker == 'manager snapshot ready')
    Dealership.state.canManage = original
    return thread
end

local racing = buyOffer(false)
local manager = pausedCounter(racing, 1)
workerCharges, workerCreated = #charges, #created
creationHook = function()
    local ok, countered = coroutine.resume(manager)
    H.equal(ok, true, 'the stale manager counter reaches its conditional update')
    H.equal(countered, false, 'the stale manager counter cannot change a claimed pending row')
    H.equal(Dealership.api.manageOffer(99, racing, 'decline'), false, 'a manager cannot decline during delivery')
end
Dealership.api.processOffers()
creationHook = nil
H.equal(offers[racing].status, 'accepted', 'settlement wins the manager counter interleaving')
H.equal(Dealership.api.acceptCounter(1, racing), false, 'the losing counter cannot permit another purchase')
H.equal(#charges, workerCharges + 1, 'the manager race charges exactly once')
H.equal(#created, workerCreated + 1, 'the manager race delivers exactly once')

local retryCounter = buyOffer(false)
manager = pausedCounter(retryCounter, 1)
workerCharges, workerCreated = #charges, #created
paymentHook = function() return false, 'Insufficient funds.' end
Dealership.api.processOffers()
paymentHook = nil
H.equal(offers[retryCounter].settling, 0, 'a normal worker failure releases the persisted claim')
H.equal(offers[retryCounter].retries, 1, 'a normal worker failure retains the configured retry behavior')
local resumed, countered = coroutine.resume(manager)
H.equal(resumed, true, 'a stale manager snapshot resumes after a known failure')
H.equal(countered, true, 'the restored pending offer may still receive a manager counter')
H.equal(offers[retryCounter].auto_at, nil, 'the later manager counter removes the restored retry schedule')
Dealership.api.processOffers()
H.equal(#charges, workerCharges, 'restoration and a later counter do not charge the old offer')
H.ok(type(Dealership.api.acceptCounter(1, retryCounter)) == 'table', 'the customer can accept the later authorized counter')
H.equal(charges[#charges].amount, 1, 'the later counter preserves its authorized price')
H.equal(#created, workerCreated + 1, 'the later counter delivers exactly once')

for name, callback in pairs(callbacks) do
    H.ok(callback.options.rateLimit ~= nil, name .. ' is rate-limited')
end
H.ok(callbacks['qbdealership:server:manageOffer'] ~= nil, 'management offer callback is registered')
H.ok(callbacks['qbdealership:server:saveDealership'] ~= nil, 'creator save callback is registered')

local previousAdmin = Dealership.state.isAdmin
Dealership.state.isAdmin = function() return true end
local savedDealer
Dealership.state.persist = function(value) savedDealer = value; return true end
GetPlayerRoutingBucket = function(src) assert(src == 99); return 27 end
local payload = { id = 'new', label = 'New', vehicles = { 'sultan' },
    zone = { coords = { x = 1, y = 2, z = 3 }, size = { x = 10, y = 10, z = 4 } } }
H.ok(Dealership.api.saveDealership(99, payload), 'fresh creator zone saves without a client bucket native')
H.equal(savedDealer.zone.bucket, 27, 'server resolves the creator routing bucket')
H.equal(payload.zone.bucket, nil, 'the submitted zone remains unchanged')
payload.zone.bucket = 12
H.ok(Dealership.api.saveDealership(99, payload), 'editing an existing zone succeeds')
H.equal(savedDealer.zone.bucket, 12, 'explicit existing buckets are preserved')
Dealership.state.isAdmin = previousAdmin

local clientSource = assert(io.open('client/world.lua', 'r')):read('*a')
H.ok(clientSource:find("QB.placement.start('asbo')", 1, true) ~= nil, 'coordinate picking uses the shared vehicle placer')
H.ok(clientSource:find('SetVehicleOnGroundProperly', 1, true) ~= nil, 'display and picker vehicles use the FiveM ground native')

dofile('server/state.lua')
Dealership.state.dealerships.pdm = dealer
QB.sql.scalar = function(sql)
    if sql:find('FROM `qbdealership_stock`', 1, true) then return 0 end
    local count = 0
    for _, row in pairs(offers) do
        if sql:find("'" .. row.status .. "'", 1, true) then count = count + 1 end
    end
    return count
end
for _, status in ipairs({ 'pending', 'countered' }) do
    offers = { { status = status, settling = 1 } }
    H.equal(Dealership.state.remove('pdm'), false, 'a durable claim prevents dealership deletion')
    H.ok(Dealership.state.dealerships.pdm ~= nil, 'the dealership containing a claimed offer remains available')
end

local threads, packagedFiles = {}, {}
CreateThread = function(fn) threads[#threads + 1] = fn end
RegisterNetEvent = function() end
GetCurrentResourceName = function() return 'qbdealership' end
QB.sql.ready = function() return true end
QB.sql.migrateFiles = function(resource, migrations)
    H.equal(resource, 'qbdealership', 'startup registers migrations for the current resource')
    H.equal(#migrations, 3, 'startup retains the old migrations and appends the claim migration')
    H.equal(migrations[3].version, 3, 'the claim migration uses the next additive version')
    H.equal(migrations[3].file, 'sql/003_offer_settling.sql', 'startup loads the packaged claim migration')
    return { ran = 0, total = 3 }
end
Dealership.state.load = function() return true end
Dealership.state.broadcast = function() end
Dealership.state.ready = false
dofile('server/main.lua')
threads[1]()
H.equal(Dealership.state.ready, true, 'startup still initializes the resource after migrations')
for _, name in ipairs({ 'fx_version', 'game', 'lua54', 'name', 'author', 'version', 'description',
    'dependency', 'shared_scripts', 'server_scripts', 'client_scripts' }) do
    _G[name] = function() end
end
files = function(paths) packagedFiles = paths end
dofile('fxmanifest.lua')
H.equal(packagedFiles[3], 'sql/003_offer_settling.sql', 'the resource package includes migration 003')
for _, path in ipairs(packagedFiles) do
    local file = assert(io.open(path, 'r'))
    file:close()
    H.ok(true, path .. ' exists in the resource package')
end

H.finish()
