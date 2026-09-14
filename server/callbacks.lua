local Api = Dealership.api
local State = Dealership.state

local function register(name, fn, max, window)
    QB.callback.register('qbdealership:server:' .. name, fn, { rateLimit = { max = max, window = window } })
end

register('hydrate', function(src) return { dealerships = State.snapshot(), admin = State.isAdmin(src), ready = State.ready } end, 6, 10000)
register('catalogue', function(src, id) return Api.catalogue(src, id) end, 12, 5000)
register('purchase', function(src, id, model) return Api.purchase(src, id, model) end, 4, 10000)
register('testDrive', function(src, id, model) return Api.testDrive(src, id, model) end, 3, 10000)
register('submitOffer', function(src, id, payload) return Api.submitOffer(src, id, payload) end, 6, 30000)
register('ownedVehicles', function(src) return Api.ownedVehicles(src) end, 6, 10000)
register('offers', function(src, id, management) return Api.offersFor(src, id, management) end, 10, 10000)
register('manageOffer', function(src, id, action, payload) return Api.manageOffer(src, id, action, payload) end, 12, 30000)
register('acceptCounter', function(src, id) return Api.acceptCounter(src, id) end, 4, 10000)
register('wholesale', function(src, id, model, quantity) return Api.wholesale(src, id, model, quantity) end, 6, 30000)
register('setPrice', function(src, id, model, price) return Api.setPrice(src, id, model, price) end, 12, 30000)
register('setDisplay', function(src, id, placement, model) return Api.setDisplay(src, id, placement, model) end, 12, 30000)
register('setAutoAccept', function(src, id, enabled) return Api.setAutoAccept(src, id, enabled) end, 8, 30000)
register('saveDealership', function(src, payload) return Api.saveDealership(src, payload) end, 12, 30000)
register('deleteDealership', function(src, id) return Api.deleteDealership(src, id) end, 4, 30000)
register('vehicleRegistry', function(src) return Api.vehicleRegistry(src) end, 4, 10000)

QB.callback.register('qbdealership:list', function(src, id) return Api.catalogue(src, id) end,
    { rateLimit = { max = 12, window = 5000 } })
QB.callback.register('qbdealership:buy', function(src, id, model) return Api.purchase(src, id, model) end,
    { rateLimit = { max = 4, window = 10000 } })
