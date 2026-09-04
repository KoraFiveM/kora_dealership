-- Only the dealership id and vehicle model cross the client/server boundary.
-- Both are opaque intent; server/dealership.lua re-resolves every fact that
-- matters before either charging money or creating an owned vehicle.

QB.callback.register('qbdealership:list', function(src, dealerId)
    local catalogue, err = Dealership.api.list(src, dealerId)
    if not catalogue then return false, err end
    return catalogue
end, { rateLimit = { max = 12, window = 5000 } })

QB.callback.register('qbdealership:buy', function(src, dealerId, model)
    return Dealership.api.buy(src, dealerId, model)
end, { rateLimit = { max = 4, window = 10000 } })
