fn = {}

function fn.notify(message, tone)
    QB.notify.send({ title = 'Dealership Management', message = message, type = tone or 'error' })
end

function fn.isOwner(dealer)
    local data = exports.qbcore:getPlayerData()
    local dealership = GlobalState.Dealerships and GlobalState.Dealerships[dealer]
    return data ~= nil and dealership ~= nil
        and dealership.type == 'owned'
        and data.citizenid ~= nil
        and data.citizenid == dealership.owner
end

function fn.isStaff(dealer)
    local data = exports.qbcore:getPlayerData()
    local staff = GlobalState.DealershipStaff
    local set = staff and staff[dealer]
    return data ~= nil and data.citizenid ~= nil and set ~= nil and set[data.citizenid] == true
end
