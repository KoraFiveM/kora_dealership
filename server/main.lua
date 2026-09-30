local State = Dealership.state
local Api = Dealership.api
local RESOURCE = GetCurrentResourceName()

CreateThread(function()
    if not QB.sql.ready(60000) then return print('^1[qbdealership]^7 qbsql was not ready; resource disabled.') end
    local _, migrationErr = QB.sql.migrateFiles(RESOURCE, {
        { version = 1, name = 'dealerships', file = 'sql/001_dealerships.sql' },
        { version = 2, name = 'stock_model', file = 'sql/002_stock_model.sql' },
        { version = 3, name = 'offer_settling', file = 'sql/003_offer_settling.sql' },
    })
    if migrationErr then return print(('^1[qbdealership]^7 migration failed: %s'):format(migrationErr)) end
    local loaded, loadErr = State.load()
    if not loaded then return print(('^1[qbdealership]^7 load failed: %s'):format(tostring(loadErr))) end
    State.ready = true
    State.broadcast()
end)

CreateThread(function()
    while true do
        Wait(30000)
        if State.ready then Api.processOffers() end
    end
end)

RegisterNetEvent('QBCore:Server:PlayerLoaded', function()
    if State.ready then State.broadcast(source) end
end)

exports('GetDealerships', function() return State.snapshot() end)
exports('GetDealership', function(id)
    local dealer = State.get(id)
    return dealer and json.decode(json.encode(dealer)) or nil
end)
