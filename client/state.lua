Dealership = Dealership or {}

local Client = {
    dealerships = {},
    admin = false,
    ready = false,
}
Dealership.client = Client

function Client.notify(message, kind)
    QB.notify.send({ title = 'Dealership', message = message, type = kind or 'info' })
end

function Client.job()
    local job = exports.qbcore:getPlayerData({ 'job' })
    return type(job) == 'table' and job or {}
end

function Client.isBoss(dealer)
    if not dealer or not dealer.job then return false end
    local job = Client.job()
    if job.name ~= dealer.job then return false end
    local definition = QB.shared.get('jobs', dealer.job)
    local grade = definition and definition.grades and definition.grades[job.grade and job.grade.level]
    return grade ~= nil and grade.isboss == true
end

function Client.canManage(dealer)
    return Client.admin or Client.isBoss(dealer)
end

function Client.category(model)
    local labels = {
        [0] = 'Compacts', [1] = 'Sedans', [2] = 'SUVs', [3] = 'Coupes', [4] = 'Muscle',
        [5] = 'Sports Classics', [6] = 'Sports', [7] = 'Super', [8] = 'Motorcycles',
        [9] = 'Off-Road', [10] = 'Industrial', [11] = 'Utility', [12] = 'Vans',
        [13] = 'Cycles', [14] = 'Boats', [15] = 'Helicopters', [16] = 'Planes',
        [17] = 'Service', [18] = 'Emergency', [19] = 'Military', [20] = 'Commercial', [21] = 'Trains',
    }
    return labels[GetVehicleClassFromName(joaat(model))] or 'Other'
end

function Client.money(value)
    local amount = math.floor(tonumber(value) or 0)
    local formatted = tostring(amount)
    while true do
        local replaced, count = formatted:gsub('^(%-?%d+)(%d%d%d)', '%1,%2')
        formatted = replaced
        if count == 0 then break end
    end
    return '$' .. formatted
end

RegisterNetEvent('qbdealership:client:synced', function(dealerships)
    Client.dealerships = type(dealerships) == 'table' and dealerships or {}
    if Dealership.world then Dealership.world.rebuild() end
    if Dealership.app then Dealership.app.refresh() end
end)

RegisterNetEvent('qbdealership:client:offerUpdated', function()
    if Dealership.app then Dealership.app.refreshOffers() end
end)
