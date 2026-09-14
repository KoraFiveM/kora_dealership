Dealership = Dealership or {}

local Schema = Dealership.schema
local State = { dealerships = {}, ready = false }
Dealership.state = State

local function clone(value) return json.decode(json.encode(value)) end

function State.isAdmin(src)
    return QB.permissions.hasPermission(src, Config.adminPermission, 'qbcore')
end

function State.player(src) return exports.qbcore:getPlayer(src) end

function State.isBoss(src, dealer)
    if not dealer or not dealer.job then return false end
    local player = State.player(src)
    local job = player and player.job
    if not job or job.name ~= dealer.job then return false end
    local definition = exports.qbcore:getShared('jobs', dealer.job)
    local grade = definition and definition.grades and definition.grades[job.grade and job.grade.level]
    return grade ~= nil and grade.isboss == true
end

function State.canManage(src, dealer)
    return State.isAdmin(src) or State.isBoss(src, dealer)
end

function State.get(id) return type(id) == 'string' and State.dealerships[id] or nil end

function State.near(src, dealer)
    if not dealer or not dealer.zone or dealer.zone.deleted then return false, 'This dealership has no active customer zone.' end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetPlayerRoutingBucket(src) ~= dealer.zone.bucket then
        return false, 'You cannot use this dealership.'
    end
    local playerCoords = GetEntityCoords(ped)
    local coords = dealer.zone.coords
    local distance = math.sqrt((playerCoords.x - coords.x) ^ 2 + (playerCoords.y - coords.y) ^ 2 + (playerCoords.z - coords.z) ^ 2)
    local radius = math.max(dealer.zone.size.x, dealer.zone.size.y) * 0.75 + dealer.zone.distance
    if distance > radius then return false, 'You are too far from the dealership.' end
    return true
end

function State.snapshot() return clone(State.dealerships) end

function State.broadcast(target)
    TriggerClientEvent('qbdealership:client:synced', target or -1, State.snapshot())
end

function State.persist(value)
    local dealer, err = Schema.normaliseDealership(value)
    if not dealer then return nil, err end
    local saved, writeErr = QB.sql.transaction({
        { sql = [[INSERT INTO `qbdealerships` (`id`,`definition`) VALUES (?,?)
            ON DUPLICATE KEY UPDATE `definition` = VALUES(`definition`)]], params = { dealer.id, json.encode(dealer) } },
        { sql = 'DELETE FROM `qbdealership_deleted` WHERE `id` = ?', params = { dealer.id } },
    })
    if not saved then return nil, writeErr end
    State.dealerships[dealer.id] = dealer
    State.broadcast()
    return clone(dealer)
end

function State.remove(id)
    if not State.dealerships[id] then return false, 'Dealership no longer exists.' end
    local stock = tonumber(QB.sql.scalar('SELECT COUNT(*) FROM `qbdealership_stock` WHERE `dealership` = ?', { id })) or 0
    if stock > 0 then return false, 'Sell the dealership stock before deleting it.' end
    local activeOffers = tonumber(QB.sql.scalar([[SELECT COUNT(*) FROM `qbdealership_offers` WHERE `dealership` = ?
        AND `status` IN ('pending','countered')]], { id })) or 0
    if activeOffers > 0 then return false, 'Resolve pending and countered offers before deleting this dealership.' end
    local removed, err = QB.sql.transaction({
        { sql = 'DELETE FROM `qbdealership_offers` WHERE `dealership` = ?', params = { id } },
        { sql = 'DELETE FROM `qbdealerships` WHERE `id` = ?', params = { id } },
        { sql = 'INSERT INTO `qbdealership_deleted` (`id`) VALUES (?) ON DUPLICATE KEY UPDATE `deleted_at` = NOW()', params = { id } },
    })
    if not removed then return false, err end
    State.dealerships[id] = nil
    State.broadcast()
    return true
end

function State.load()
    local rows, err = QB.sql.query('SELECT `id`, `definition` FROM `qbdealerships`')
    if not rows then return false, err end
    local deletedRows = QB.sql.query('SELECT `id` FROM `qbdealership_deleted`') or {}
    local deleted, loaded = {}, {}
    for _, row in ipairs(deletedRows) do deleted[row.id] = true end
    for _, row in ipairs(rows) do
        local ok, raw = pcall(json.decode, row.definition or '')
        if ok and raw then raw.id = row.id end
        local dealer, validationErr = Schema.normaliseDealership(ok and raw or nil)
        if dealer then loaded[dealer.id] = dealer
        else print(('^3[qbdealership]^7 skipped invalid dealership %s: %s'):format(tostring(row.id), validationErr)) end
    end
    State.dealerships = loaded
    for id, seed in pairs(Config.dealerships or {}) do
        if not loaded[id] and not deleted[id] then
            local raw = clone(seed)
            raw.id = id
            local saved, saveErr = State.persist(raw)
            if not saved then print(('^3[qbdealership]^7 could not seed %s: %s'):format(id, tostring(saveErr))) end
        end
    end
    return true
end

function State.stock(dealerId)
    local rows = QB.sql.query([[SELECT `model`, COUNT(*) AS `count` FROM `qbdealership_stock`
        WHERE `dealership` = ? GROUP BY `model`]], { dealerId }) or {}
    local stock = {}
    for _, row in ipairs(rows) do stock[row.model] = tonumber(row.count) or 0 end
    return stock
end
