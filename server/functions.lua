Dealerships, Swaps, DealerData, fn = {}, {}, {}, {}
QB.print.debug('qbdealership server/functions.lua loaded.')

local publicStock = 9999
local maxSalesLog = 500
local clearance = Config.spawnClearance
local defaultSettings = { maxPriceOverride = 10, commission = 5, employeeDiscount = 5 }

fn.defaultSettings = defaultSettings

CreateThread(function()
    local dealership = QB.sql.query([[
        CREATE TABLE IF NOT EXISTS `qbdealerships` (
          `id` varchar(64) NOT NULL,
          `label` varchar(128) NOT NULL DEFAULT '',
          `type` enum('public','for_sale','owned') NOT NULL DEFAULT 'public',
          `price` int(10) unsigned DEFAULT NULL,
          `owner` varchar(50) DEFAULT NULL,
          `zone` longtext DEFAULT NULL,
          `vehicles` longtext DEFAULT NULL,
          `placements` longtext DEFAULT NULL,
          `spawns` longtext DEFAULT NULL,
          `management_zones` longtext DEFAULT NULL,
          `sale_zones` longtext DEFAULT NULL,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
          PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    local dealerData = QB.sql.query([[
        CREATE TABLE IF NOT EXISTS `qbdealership_management` (
        `dealership_id` varchar(64) NOT NULL,
        `current_balance` int(11) NOT NULL DEFAULT 0,
        `income` int(10) unsigned NOT NULL DEFAULT 0,
        `spent` int(10) unsigned NOT NULL DEFAULT 0,
        `sales` longtext DEFAULT NULL,
        `employees` longtext DEFAULT NULL,
        `employee_permissions` longtext DEFAULT NULL,
        `settings` longtext NOT NULL,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`dealership_id`),
        CONSTRAINT `fk_management_dealership` FOREIGN KEY (`dealership_id`) REFERENCES `qbdealerships` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
        )ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    local offers = QB.sql.query([[
    CREATE TABLE IF NOT EXISTS `qbdealership_offers` (
          `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
          `dealership_id` varchar(64) NOT NULL,
          `model` varchar(64) NOT NULL,
          `offer_price` int(10) unsigned NOT NULL,
          `offer_text` varchar(500) NOT NULL DEFAULT '',
          `auto_accept_at` datetime DEFAULT NULL,
          `status` enum('pending','accepted','denied') NOT NULL DEFAULT 'pending',
          `offeror` varchar(50) NOT NULL,
          `acceptor` varchar(50) DEFAULT NULL,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
          PRIMARY KEY (`id`),
          KEY `idx_offers_dealership` (`dealership_id`),
          KEY `idx_offers_offeror` (`offeror`),
          KEY `idx_offers_pending_auto_accept` (`status`,`auto_accept_at`),
          CONSTRAINT `fk_offers_dealership` FOREIGN KEY (`dealership_id`) REFERENCES `qbdealerships` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
    if Config.UsePDM then
        local pdmExists = QB.sql.query('SELECT id FROM qbdealerships WHERE id = "pdm"')
        if not pdmExists or #pdmExists == 0 then
            QB.sql.query([[INSERT IGNORE INTO `qbdealerships` (`id`, `label`, `type`, `price`, `owner`, `zone`, `vehicles`, `placements`, `spawns`, `management_zones`, `sale_zones`, `created_at`, `updated_at`) VALUES
	            ('pdm', 'PDM', 'public', NULL, NULL, '{"thickness":28.375,"points":[{"x":-61.33901214599609,"z":26.3088264465332,"y":-1066.62255859375},{"x":-84.96515655517578,"z":24.74927711486816,"y":-1128.9659423828126},{"x":-17.24543952941894,"z":26.06214332580566,"y":-1127.2347412109376},{"x":-1.36206722259521,"z":25.90620803833007,"y":-1081.4486083984376}]}', '[{"model":"asbo","price":4000},{"model":"blista","price":13000},{"model":"brioso","price":20000},{"model":"club","price":8000},{"model":"dilettante","price":9000},{"model":"dilettante2","price":12000},{"model":"kanjo","price":12000},{"model":"issi2","price":7000},{"model":"issi3","price":5000},{"model":"issi4","price":80000},{"model":"issi5","price":80000},{"model":"issi6","price":80000},{"model":"panto","price":3200},{"model":"prairie","price":30000},{"model":"rhapsody","price":10000},{"model":"brioso2","price":12000},{"model":"weevil","price":9000},{"model":"issi7","price":100000},{"model":"blista2","price":18950},{"model":"blista3","price":15000},{"model":"brioso3","price":125000},{"model":"boor","price":23000},{"model":"asea","price":2500},{"model":"asterope","price":11000},{"model":"cog55","price":22000},{"model":"cognoscenti","price":22500},{"model":"emperor","price":4250},{"model":"fugitive","price":20000},{"model":"glendale","price":3400},{"model":"glendale2","price":12000},{"model":"ingot","price":4999},{"model":"intruder","price":11250},{"model":"premier","price":12000},{"model":"primo","price":5000},{"model":"primo2","price":14500},{"model":"regina","price":7000},{"model":"stafford","price":30000},{"model":"stanier","price":19000},{"model":"stratum","price":15000},{"model":"stretch","price":19000},{"model":"superd","price":17000},{"model":"surge","price":20000},{"model":"tailgater","price":22000},{"model":"warrener","price":4000},{"model":"washington","price":7000},{"model":"tailgater2","price":51000},{"model":"cinquemila","price":125000},{"model":"iwagen","price":225000},{"model":"astron","price":150000},{"model":"baller7","price":145000},{"model":"comet7","price":25000},{"model":"deity","price":505000},{"model":"jubilee","price":485000},{"model":"oracle","price":22000},{"model":"schafter2","price":16000},{"model":"warrener2","price":30000},{"model":"rhinehart","price":105000},{"model":"eudora","price":17000},{"model":"asterope2","price":459000},{"model":"impaler5","price":768000},{"model":"baller","price":22000},{"model":"baller2","price":15000},{"model":"baller3","price":15000},{"model":"baller4","price":29000},{"model":"baller5","price":78000},{"model":"baller6","price":82000},{"model":"bjxl","price":19000},{"model":"cavalcade","price":14000},{"model":"cavalcade2","price":16500},{"model":"contender","price":35000},{"model":"dubsta","price":19000},{"model":"dubsta2","price":19500},{"model":"fq2","price":18500},{"model":"granger","price":22000},{"model":"gresley","price":25000},{"model":"habanero","price":20000},{"model":"huntley","price":24500},{"model":"landstalker","price":12000},{"model":"landstalker2","price":26000},{"model":"novak","price":70000},{"model":"patriot","price":21000},{"model":"patriot2","price":21000},{"model":"radi","price":18000},{"model":"rebla","price":21000},{"model":"rocoto","price":13000},{"model":"seminole","price":20000},{"model":"seminole2","price":13000},{"model":"serrano","price":48000},{"model":"toros","price":65000},{"model":"xls","price":17000},{"model":"granger2","price":221000},{"model":"patriot3","price":270000},{"model":"aleutian","price":183500},{"model":"baller8","price":171500},{"model":"cavalcade3","price":166500},{"model":"dorado","price":137500},{"model":"vivanite","price":160500},{"model":"cogcabrio","price":30000},{"model":"exemplar","price":40000},{"model":"f620","price":32500},{"model":"felon","price":31000},{"model":"felon2","price":37000},{"model":"jackal","price":19000},{"model":"oracle2","price":28000},{"model":"sentinel","price":30000},{"model":"sentinel2","price":33000},{"model":"windsor","price":27000},{"model":"windsor2","price":34000},{"model":"zion","price":22000},{"model":"zion2","price":28000},{"model":"previon","price":149000},{"model":"champion","price":205000},{"model":"futo","price":17500},{"model":"sentinel3","price":70000},{"model":"kanjosj","price":143000},{"model":"postlude","price":90000},{"model":"tahoma","price":12000},{"model":"broadway","price":20000},{"model":"fr36","price":161000},{"model":"blade","price":23500},{"model":"buccaneer","price":22500},{"model":"buccaneer2","price":24500},{"model":"chino","price":5000},{"model":"chino2","price":8000},{"model":"clique","price":20000},{"model":"coquette3","price":180000},{"model":"deviant","price":70000},{"model":"dominator","price":62500},{"model":"dominator2","price":50000},{"model":"dominator3","price":70000},{"model":"dominator4","price":200000},{"model":"dominator7","price":110000},{"model":"dominator8","price":80000},{"model":"dukes","price":23500},{"model":"dukes2","price":60000},{"model":"dukes3","price":45000},{"model":"faction","price":17000},{"model":"faction2","price":19000},{"model":"faction3","price":35000},{"model":"ellie","price":42250},{"model":"gauntlet","price":28500},{"model":"gauntlet2","price":70000},{"model":"gauntlet3","price":75000},{"model":"gauntlet4","price":80000},{"model":"gauntlet5","price":120000},{"model":"hermes","price":535000},{"model":"hotknife","price":90000},{"model":"hustler","price":95000},{"model":"impaler","price":95000},{"model":"impaler2","price":95000},{"model":"impaler3","price":95000},{"model":"impaler4","price":95000},{"model":"imperator","price":95000},{"model":"imperator2","price":95000},{"model":"imperator3","price":95000},{"model":"lurcher","price":21000},{"model":"nightshade","price":70000},{"model":"phoenix","price":65000},{"model":"picador","price":20000},{"model":"ratloader2","price":20000},{"model":"ruiner","price":29000},{"model":"ruiner2","price":50000},{"model":"sabregt","price":23000},{"model":"sabregt2","price":26500},{"model":"slamvan","price":30000},{"model":"slamvan2","price":90000},{"model":"slamvan3","price":17000},{"model":"stalion","price":33000},{"model":"stalion2","price":40000},{"model":"tampa","price":24500},{"model":"tulip","price":80000},{"model":"vamos","price":30000},{"model":"vigero","price":39500},{"model":"virgo","price":22000},{"model":"virgo2","price":21000},{"model":"virgo3","price":21000},{"model":"voodoo","price":13000},{"model":"yosemite","price":19500},{"model":"yosemite2","price":55000},{"model":"buffalo4","price":345000},{"model":"manana","price":12800},{"model":"manana2","price":24000},{"model":"tampa2","price":80000},{"model":"ruiner4","price":85000},{"model":"vigero2","price":105000},{"model":"weevil2","price":95000},{"model":"buffalo5","price":214000},{"model":"tulip2","price":80000},{"model":"clique2","price":102500},{"model":"brigham","price":149900},{"model":"greenwood","price":105000},{"model":"dominator9","price":219500},{"model":"impaler6","price":146500},{"model":"vigero3","price":229500},{"model":"ardent","price":30000},{"model":"btype","price":75000},{"model":"btype2","price":87000},{"model":"btype3","price":63000},{"model":"casco","price":100000},{"model":"deluxo","price":55000},{"model":"dynasty","price":25000},{"model":"fagaloa","price":13000},{"model":"feltzer3","price":115000},{"model":"gt500","price":130000},{"model":"infernus2","price":245000},{"model":"jb700","price":240000},{"model":"jb7002","price":40000},{"model":"mamba","price":140000},{"model":"michelli","price":30000},{"model":"monroe","price":115000},{"model":"nebula","price":22000},{"model":"peyote","price":23500},{"model":"peyote3","price":48000},{"model":"pigalle","price":92000},{"model":"rapidgt3","price":90000},{"model":"retinue","price":32000},{"model":"retinue2","price":38000},{"model":"savestra","price":67000},{"model":"stinger","price":39500},{"model":"stingergt","price":70000},{"model":"stromberg","price":80000},{"model":"swinger","price":221000},{"model":"torero","price":84000},{"model":"tornado","price":21000},{"model":"tornado2","price":22000},{"model":"tornado5","price":22000},{"model":"turismo2","price":170000},{"model":"viseris","price":210000},{"model":"z190","price":78000},{"model":"ztype","price":270000},{"model":"zion3","price":45000},{"model":"cheburek","price":7000},{"model":"toreador","price":50000},{"model":"peyote2","price":40000},{"model":"coquette2","price":165000},{"model":"stingertt","price":238000},{"model":"everon2","price":80000},{"model":"issi8","price":10000},{"model":"gauntlet6","price":181000},{"model":"coureur","price":199000},{"model":"r300","price":56000},{"model":"panthere","price":55000},{"model":"ignus","price":1120000},{"model":"zeno","price":1350000},{"model":"akuma","price":55000},{"model":"avarus","price":20000},{"model":"bagger","price":13500},{"model":"bati","price":24000},{"model":"bati2","price":19000},{"model":"bf400","price":22000},{"model":"carbonrs","price":22000},{"model":"chimera","price":21000},{"model":"cliffhanger","price":28500},{"model":"daemon","price":14000},{"model":"daemon2","price":23000},{"model":"defiler","price":30000},{"model":"deathbike","price":30000},{"model":"deathbike2","price":30000},{"model":"deathbike3","price":30000},{"model":"diablous","price":30000},{"model":"diablous2","price":38000},{"model":"double","price":28000},{"model":"enduro","price":5500},{"model":"esskey","price":12000},{"model":"faggio","price":2000},{"model":"faggio2","price":1900},{"model":"faggio3","price":2500},{"model":"fcr","price":5000},{"model":"fcr2","price":19000},{"model":"gargoyle","price":32000},{"model":"hakuchou","price":17000},{"model":"hakuchou2","price":45000},{"model":"hexer","price":16000},{"model":"innovation","price":33500},{"model":"lectro","price":28000},{"model":"manchez","price":8300},{"model":"nemesis","price":20000},{"model":"nightblade","price":23000},{"model":"pcj","price":15000},{"model":"ratbike","price":3000},{"model":"ruffian","price":25000},{"model":"sanchez","price":5300},{"model":"sanchez2","price":5300},{"model":"sanctus","price":35000},{"model":"shotaro","price":320000},{"model":"sovereign","price":8000},{"model":"stryder","price":50000},{"model":"thrust","price":22000},{"model":"vader","price":7200},{"model":"vindicator","price":19000},{"model":"vortex","price":31000},{"model":"wolfsbane","price":14000},{"model":"zombiea","price":28000},{"model":"zombieb","price":27000},{"model":"manchez2","price":14000},{"model":"shinobi","price":25000},{"model":"reever","price":25000},{"model":"manchez3","price":15000},{"model":"powersurge","price":7000},{"model":"bfinjection","price":9000},{"model":"bifta","price":15500},{"model":"blazer","price":7500},{"model":"blazer2","price":7000},{"model":"blazer3","price":7000},{"model":"blazer4","price":9250},{"model":"blazer5","price":40000},{"model":"brawler","price":40000},{"model":"caracara","price":60000},{"model":"caracara2","price":80000},{"model":"dubsta3","price":34000},{"model":"dune","price":14000},{"model":"everon","price":60000},{"model":"freecrawler","price":24000},{"model":"hellion","price":38000},{"model":"kalahari","price":14000},{"model":"kamacho","price":50000},{"model":"mesa3","price":400000},{"model":"outlaw","price":15000},{"model":"rancherxl","price":24000},{"model":"rebel2","price":20000},{"model":"riata","price":380000},{"model":"sandking","price":25000},{"model":"sandking2","price":38000},{"model":"trophytruck","price":60000},{"model":"trophytruck2","price":80000},{"model":"vagrant","price":50000},{"model":"verus","price":20000},{"model":"winky","price":10000},{"model":"yosemite3","price":425000},{"model":"mesa","price":12000},{"model":"ratel","price":199000},{"model":"l35","price":167000},{"model":"monstrociti","price":48000},{"model":"draugur","price":99000},{"model":"terminus","price":187750},{"model":"sadler","price":20000},{"model":"bison","price":18000},{"model":"bobcatxl","price":13500},{"model":"burrito3","price":4000},{"model":"gburrito2","price":11500},{"model":"rumpo","price":9000},{"model":"journey","price":6500},{"model":"minivan","price":7000},{"model":"minivan2","price":10000},{"model":"paradise","price":9000},{"model":"rumpo3","price":19500},{"model":"speedo","price":10000},{"model":"speedo4","price":15000},{"model":"surfer","price":9000},{"model":"youga3","price":15000},{"model":"youga","price":8000},{"model":"youga2","price":14500},{"model":"youga4","price":85000},{"model":"moonbeam","price":13000},{"model":"moonbeam2","price":15000},{"model":"journey2","price":7000},{"model":"surfer3","price":15000},{"model":"speedo5","price":238000},{"model":"mule2","price":40000},{"model":"mule3","price":40000},{"model":"taco","price":45000},{"model":"boxville6","price":47500},{"model":"bmx","price":160},{"model":"cruiser","price":510},{"model":"fixter","price":225},{"model":"scorcher","price":280},{"model":"tribike","price":500},{"model":"tribike2","price":700},{"model":"tribike3","price":520},{"model":"inductor","price":5000},{"model":"inductor2","price":5000}]', '[{"model":"club","coords":{"x":-42.77,"w":68.88,"z":25.42,"y":-1093.03}},{"model":"regina","coords":{"x":-38.57,"w":69.97,"z":25.42,"y":-1097.03}},{"model":"hotknife","coords":{"x":-40.43,"w":69.58,"z":25.42,"y":-1099.87}},{"model":"hellion","coords":{"x":-40.66,"w":71.47,"z":25.42,"y":-1103.07}},{"model":"brioso3","coords":{"x":-46.19,"w":71.22,"z":25.42,"y":-1101.11}},{"model":"baller","coords":{"x":-45.66,"w":73.51,"z":25.42,"y":-1097.63}},{"model":"issi3","coords":{"x":-43.79,"w":70.23,"z":25.42,"y":-1095.27}}]', '[{"coords":{"x":-49.7,"w":70.15,"z":25.81,"y":-1073.9}},{"coords":{"x":-42.06,"w":70.49,"z":25.69,"y":-1076.45}},{"coords":{"x":-28.51,"w":71.52,"z":25.64,"y":-1081.5}}]', '[]', '[]', '2026-10-04 07:58:46', '2026-10-04 08:30:53');
        ]])
        end
    end
end)

function fn.notify(src, message, class)
    QB.notify.send(src, { title = 'QB Dealerships', message = message, type = class })
end

function fn.fail(message)
    return false, message
end

function fn.decode(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    return (ok and type(decoded) == 'table' and decoded) or fallback
end

function fn.copy(value)
    return json.decode(json.encode(value))
end

function fn.trim(value, max)
    if type(value) ~= 'string' or not value:match('%S') then return nil end
    return value:match('^%s*(.-)%s*$'):sub(1, max)
end

-- Whole-number amount in [1, max], or nil. Rejects floats, NaN, inf and non-numbers.
function fn.toAmount(value, max)
    local number = tonumber(value)
    if not number or number ~= number or number < 1 or number > max then return nil end
    return math.tointeger(math.floor(number))
end

function fn.isAdmin(src)
    return IsPlayerAceAllowed(src, 'command')
end

-- Validates a client-supplied list index and the player's distance to that point.
-- Returns true, or false and a message. Never raises on bad client input.
function fn.nearPoint(src, record, field, index, dist)
    local list = type(record) == 'table' and record[field]
    local number = tonumber(index)
    index = number and math.tointeger(number)
    local point = list and index and list[index]
    if not point then return false, 'Invalid location.' end
    if not QB.distance.player(src, point.coords, dist) then return false, 'You are too far away.' end
    return true
end

-- true when `key` is off cooldown for this player (and starts the cooldown).
local cooldowns = {}

function fn.rateLimit(src, key, ms)
    local now = GetGameTimer()
    local byKey = cooldowns[src] or {}
    if byKey[key] and now - byKey[key] < ms then return false end
    byKey[key] = now
    cooldowns[src] = byKey
    return true
end

local function clearCooldowns()
    cooldowns[source] = nil
end

AddEventHandler('playerDropped', clearCooldowns)

AddEventHandler('playerDropped', clearCooldowns)

function fn.citizenId(src)
    local player = exports.qbcore:getPlayerData(src)
    return player and player.citizenid
end

-- Accepts a server id (online) or an 8-character citizenid (online or offline).
function fn.playerName(who)
    if type(who) == 'number' then
        local player = exports.qbcore:getPlayerData(who)
        local info = player and player.charinfo or {}
        local name = ('%s %s'):format(info.firstname or '', info.lastname or ''):match('^%s*(.-)%s*$')
        return name ~= '' and name or ('Player %d'):format(who)
    end
    if type(who) == 'string' and #who == 8 then
        local rows = QB.sql.query(
            'SELECT CONCAT(JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, "$.firstname")), " ", JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, "$.lastname"))) AS `name` FROM `players` WHERE `citizenid` = ?',
            { who }
        )
        return rows and rows[1] and rows[1].name
    end
end

function fn.publish()
    GlobalState.Dealerships = Dealerships
end

function fn.publishSwaps()
    GlobalState.DealershipSwaps = Swaps
end

-- Money for a citizenid that may be offline. Cash only.

function fn.takeCash(cid, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    local player = exports.qbcore:getPlayerByCitizenId(cid)
    if player then return player.removeMoney(amount) end

    local result = QB.sql.query(
        'UPDATE `players` SET `money` = JSON_SET(`money`, "$.cash", JSON_EXTRACT(`money`, "$.cash") - ?) WHERE `citizenid` = ? AND JSON_EXTRACT(`money`, "$.cash") >= ?',
        { amount, cid, amount }
    )
    return result and result.affectedRows == 1
end

function fn.giveCash(cid, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end

    local player = exports.qbcore:getPlayerByCitizenId(cid)
    if player then return player.addMoney(amount) end

    local result = QB.sql.query(
        'UPDATE `players` SET `money` = JSON_SET(`money`, "$.cash", JSON_EXTRACT(`money`, "$.cash") + ?) WHERE `citizenid` = ?',
        { amount, cid }
    )
    return result and result.affectedRows == 1
end

-- Vehicles and stock

local function sharedVehicle(model)
    return exports.qbcore:getShared('vehicles', model)
end

function fn.getVehicleData(model)
    local ok, vehicle = pcall(sharedVehicle, model)
    if not ok or type(vehicle) ~= 'table' then return nil end

    local price = tonumber(vehicle.price)
    if not price or price < 1 then return nil end
    return { model = model, name = vehicle.name or model, price = price }
end

function fn.findVehicle(record, model)
    if type(model) ~= 'string' then return nil end
    model = model:lower()
    for _, entry in ipairs(record.vehicles) do
        if entry.model == model then return entry end
    end
end

local function cleanVehicles(list, current, dealershipType)
    local stock = {}
    for _, entry in ipairs(current) do stock[entry.model] = tonumber(entry.stock) end

    local result, seen = {}, {}
    for _, entry in ipairs(list) do
        local model = type(entry) == 'string' and entry or type(entry) == 'table' and entry.model
        model = type(model) == 'string' and model:lower()

        local shared = model and not seen[model] and fn.getVehicleData(model)
        if shared then
            seen[model] = true
            local price = tonumber(type(entry) == 'table' and entry.price) or shared.price
            result[#result + 1] = {
                model = model,
                name = shared.name,
                price = math.max(1, math.min(math.floor(price), Config.maxPrice)),
                stock = dealershipType == 'public' and publicStock or math.floor(stock[model] or 0),
            }
        end
    end
    return result
end

function fn.inStock(record, entry)
    return record.type == 'public' or (tonumber(entry.stock) or 0) > 0
end

-- Returns false when the vehicle is unknown, there is not enough stock for a decrement,
-- or the save failed (the in-memory stock is restored in both failure cases).
function fn.adjustStock(dealer, model, delta)
    local record = Dealerships[dealer]
    local entry = record and fn.findVehicle(record, model)
    if not entry then return false end
    if record.type == 'public' then return true end

    local previous = math.floor(tonumber(entry.stock) or 0)
    local updated = previous + delta
    if updated < 0 or updated > Config.maxStock then return false end

    entry.stock = updated
    if not fn.saveDealership(record) then
        entry.stock = previous
        return false
    end
    fn.publish()
    return true
end

function fn.createVehicle(model, coords)
    local vehicle = CreateVehicle(joaat(model), coords.x, coords.y, coords.z, coords.w or 0.0, true, true)
    local waited = 0
    while not DoesEntityExist(vehicle) and waited < 3000 do
        Wait(50)
        waited = waited + 50
    end
    return DoesEntityExist(vehicle) and vehicle or nil
end

local plateChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

local function newPlate()
    for _ = 1, 20 do
        local plate = {}
        for i = 1, 8 do
            local n = math.random(#plateChars)
            plate[i] = plateChars:sub(n, n)
        end
        plate = table.concat(plate)
        local rows = QB.sql.query('SELECT 1 FROM `player_vehicles` WHERE `plate` = ? LIMIT 1', { plate })
        if not rows or not rows[1] then return plate end
    end
end

local function insertOwnedVehicle(cid, model, plate, state)
    return QB.sql.transaction({
        {
            sql = 'INSERT INTO player_vehicles (plate, vehicle, citizenid, state, fuel, engine_health, body_health, balance, paymentamount, paymentsleft, financetime) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            params = { plate, model, cid, state, 100.0, 1000.0, 1000.0, 0, 0, 0, 0 },
        },
    })
end

-- `target` is a server id (the car is spawned at `spawn`, keyed and the player warped in; returns the
-- network id) or a citizenid (a garaged row is written, nothing spawns; returns true). nil on failure.
function fn.deliverVehicle(target, model, spawn)
    local plate = newPlate()
    if not plate then return nil end

    if type(target) ~= 'number' then
        if not insertOwnedVehicle(target, model, plate, Config.offerVehicleState) then return nil end
        return true
    end

    local cid = fn.citizenId(target)
    if not cid or not spawn then return nil end

    local vehicle = fn.createVehicle(model, spawn.coords)
    if not vehicle then return nil end

    SetVehicleNumberPlateText(vehicle, plate)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 or not insertOwnedVehicle(cid, model, plate, 'out') then
        DeleteEntity(vehicle)
        return nil
    end

    exports.qbvehiclekeys:giveKeys(target, plate)
    TaskWarpPedIntoVehicle(GetPlayerPed(target), vehicle, -1)
    return netId
end

-- Returns the first spawn with no vehicle within the clearance radius, or nil.
function fn.getFreeSpawn(spawns, radius)
    radius = radius or clearance
    local vehicles = GetAllVehicles()
    for i = 1, #spawns do
        local c = spawns[i].coords
        local point = vec3(c.x, c.y, c.z)
        local blocked = false
        for j = 1, #vehicles do
            if #(GetEntityCoords(vehicles[j]) - point) <= radius then
                blocked = true
                break
            end
        end
        if not blocked then return spawns[i] end
    end
end

-- Management data

local function newManagement(row)
    row = row or {}
    local settings = fn.decode(row.settings, {})
    for key, default in pairs(defaultSettings) do
        settings[key] = tonumber(settings[key]) or default
    end

    return {
        balance = math.floor(tonumber(row.current_balance) or 0),
        income = math.floor(tonumber(row.income) or 0),
        spent = math.floor(tonumber(row.spent) or 0),
        sales = fn.decode(row.sales, {}),
        employees = fn.decode(row.employees, {}),
        permissions = fn.decode(row.employee_permissions, {}),
        settings = settings,
    }
end

local function writeManagement(dealer, data)
    return QB.sql.transaction({
        {
            sql = 'UPDATE `qbdealership_management` SET `current_balance` = ?, `income` = ?, `spent` = ?, `sales` = ?, `employees` = ?, `employee_permissions` = ?, `settings` = ? WHERE `dealership_id` = ?',
            params = {
                data.balance, data.income, data.spent, json.encode(data.sales),
                json.encode(data.employees), json.encode(data.permissions), json.encode(data.settings), dealer,
            },
        },
    })
end

function fn.management(dealer)
    if not DealerData[dealer] then
        DealerData[dealer] = newManagement()
        QB.sql.query(
            'INSERT IGNORE INTO `qbdealership_management` (`dealership_id`, `sales`, `employees`, `employee_permissions`, `settings`) VALUES (?, ?, ?, ?, ?)',
            { dealer, '[]', '[]', '{}', json.encode(defaultSettings) }
        )
    end
    return DealerData[dealer]
end

-- Callers must pass new tables for any field they change (never mutate the cached ones), so a
-- failed write can restore the previous state. Returns the new data or false.
function fn.updateManagement(dealer, changes)
    local previous = fn.management(dealer)
    local updated = {}
    for key, value in pairs(previous) do updated[key] = value end
    for key, value in pairs(changes) do updated[key] = value end

    DealerData[dealer] = updated
    local ok, err = writeManagement(dealer, updated)
    if not ok then
        print(('[qbdealership] management save FAILED for %s: %s'):format(dealer, tostring(err)))
        DealerData[dealer] = previous
        return false
    end
    return updated
end

-- Credits (or, with a negative amount, reverses) a sale for the dealership. true or false.
function fn.creditSale(dealer, amount)
    local record = Dealerships[dealer]
    if not record then return false end
    if record.type ~= 'owned' then return true end

    local data = fn.management(dealer)
    return fn.updateManagement(dealer, { balance = data.balance + amount, income = data.income + amount }) ~= false
end

function fn.recordSale(dealer, seller, sale)
    local record = Dealerships[dealer]
    if not record or record.type ~= 'owned' then return true, 0 end
    if not fn.isEmployee(seller, dealer) then return false end

    local data = fn.management(dealer)
    local sellerCid = fn.citizenId(seller)
    local price = math.floor(tonumber(sale.price) or 0)
    local commission = math.floor(price * data.settings.commission / 100)

    local log = fn.copy(data.sales)
    log[#log + 1] = {
        model = sale.model,
        vehicle = sale.vehicle,
        price = price,
        commission = commission,
        seller = sellerCid,
        sellerName = fn.playerName(seller),
        customer = sale.customer,
        customerName = sale.customerName,
        time = os.time(),
    }
    if #log > maxSalesLog then table.remove(log, 1) end

    local employees = fn.copy(data.employees)
    for i = 1, #employees do
        if employees[i].citizenid == sellerCid then
            employees[i].sales = (tonumber(employees[i].sales) or 0) + 1
            employees[i].income = (tonumber(employees[i].income) or 0) + price
        end
    end

    local dealerShare = price - commission
    local updated = fn.updateManagement(dealer, {
        balance = data.balance + dealerShare,
        income = data.income + dealerShare,
        sales = log,
        employees = employees,
    })
    if not updated then return false end

    if commission > 0 then exports.qbcore:addMoney(seller, 'bank', commission) end
    return true, commission
end

-- Permissions

local function hasPermission(dealer, cid, action)
    local record = Dealerships[dealer]
    if not record or not cid then return false end
    if cid == record.owner then return true end

    for _, permission in ipairs(fn.management(dealer).permissions[cid] or {}) do
        if permission == action then return true end
    end
    return false
end

function fn.isOwner(src, dealer)
    local record = Dealerships[dealer]
    return record ~= nil and record.owner ~= nil and record.owner == fn.citizenId(src)
end

-- The owner counts as an employee.
function fn.isEmployee(src, dealer)
    local cid = fn.citizenId(src)
    if not cid or not Dealerships[dealer] then return false end
    if fn.isOwner(src, dealer) then return true end

    for _, employee in ipairs(fn.management(dealer).employees) do
        if employee.citizenid == cid then return true end
    end
    return false
end

function fn.canEmployeeDo(src, dealer, action)
    return hasPermission(dealer, fn.citizenId(src), action)
end

function fn.publishStaff()
    local staff, offerStaff = {}, {}
    for dealer, record in pairs(Dealerships) do
        if record.type == 'owned' and record.owner then
            staff[dealer] = { [record.owner] = true }
            offerStaff[dealer] = { [record.owner] = true }
            for _, employee in ipairs(fn.management(dealer).employees) do
                if hasPermission(dealer, employee.citizenid, 'sellVehicles') then
                    staff[dealer][employee.citizenid] = true
                end
                if hasPermission(dealer, employee.citizenid, 'handleOffers') then
                    offerStaff[dealer][employee.citizenid] = true
                end
            end
        end
    end
    GlobalState.DealershipStaff = staff
    GlobalState.DealershipOfferStaff = offerStaff -- who may open the management Offers page
end

-- Persistence

function fn.saveDealership(record)
    return QB.sql.transaction({
        {
            sql = [[INSERT INTO `qbdealerships` (`id`,`label`,`type`,`price`,`owner`,`zone`,`vehicles`,`placements`,`spawns`,`management_zones`,`sale_zones`)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `type` = VALUES(`type`), `price` = VALUES(`price`),
                    `owner` = VALUES(`owner`), `zone` = VALUES(`zone`), `vehicles` = VALUES(`vehicles`),
                    `placements` = VALUES(`placements`), `spawns` = VALUES(`spawns`),
                    `management_zones` = VALUES(`management_zones`), `sale_zones` = VALUES(`sale_zones`)]],
            params = {
                record.id, record.label, record.type, record.price or QB.sql.NULL, record.owner or QB.sql.NULL,
                record.zone and json.encode(record.zone) or QB.sql.NULL,
                json.encode(record.vehicles), json.encode(record.placements), json.encode(record.spawns),
                json.encode(record.managementZones), json.encode(record.saleZones),
            },
        },
    })
end

function fn.commitDealership(record)
    local ok, err = fn.saveDealership(record)
    if not ok then return false, err or 'Failed to save.' end

    Dealerships[record.id] = record
    fn.publish()
    fn.publishStaff()
    return record
end

-- Drops every cached trace of a deleted dealership so a re-created one with the same id starts clean.
function fn.forgetDealership(id)
    Dealerships[id] = nil
    DealerData[id] = nil
    Swaps[id] = nil
    fn.publish()
    fn.publishSwaps()
    fn.publishStaff()
end

local function cleanCoords(value, withHeading)
    if type(value) ~= 'table' then return nil end
    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z, w = withHeading and (tonumber(value.w) or 0.0) or nil }
end

local function cleanPoints(list, withHeading, allowedModels, limit)
    local result = {}
    for _, entry in ipairs(list) do
        if #result >= limit then break end
        if type(entry) == 'table' then
            local coords = cleanCoords(entry.coords, withHeading)
            local model = allowedModels and type(entry.model) == 'string' and entry.model:lower()
            if coords and (not allowedModels or allowedModels[model]) then
                result[#result + 1] = { model = model or nil, coords = coords }
            end
        end
    end
    return result
end

local function soldModels(vehicles)
    local set = {}
    for _, vehicle in ipairs(vehicles) do set[vehicle.model] = true end
    return set
end

fn.fieldLimits = {
    placements = Config.maxPlacements,
    spawns = Config.maxSpawns,
    managementZones = Config.maxZones,
    saleZones = Config.maxZones,
}

local function applyPatch(record, patch)
    local previousType = record.type
    record.label = fn.trim(patch.label, 128) or record.label

    if patch.type == 'public' or patch.type == 'for_sale' or patch.type == 'owned' then
        record.type = patch.type
    end

    -- Stock only means something for non-public dealerships: a public one holds 9999 of everything.
    if record.type ~= previousType then
        if previousType == 'public' then
            for _, entry in ipairs(record.vehicles) do entry.stock = 0 end
        end
        record.vehicles = cleanVehicles(record.vehicles, record.vehicles, record.type)
    end

    if record.type == 'for_sale' then
        local price = tonumber(patch.price)
        if price and price >= 1 and price <= Config.maxPrice then record.price = math.floor(price) end
    else
        record.price = nil
    end

    if record.type == 'owned' then
        record.owner = fn.trim(patch.owner, 50) or record.owner
    else
        record.owner = nil
    end

    if patch.clearZone then record.zone = nil end

    if type(patch.zone) == 'table' and type(patch.zone.points) == 'table' then
        local points = {}
        for _, point in ipairs(patch.zone.points) do
            if #points >= Config.maxZonePoints then break end
            points[#points + 1] = cleanCoords(point)
        end
        if #points >= 3 then
            record.zone = { points = points, thickness = tonumber(patch.zone.thickness) or 4.0 }
        end
    end

    if type(patch.vehicles) == 'table' then
        record.vehicles = cleanVehicles(patch.vehicles, record.vehicles, record.type)
        record.placements = cleanPoints(record.placements, true, soldModels(record.vehicles), Config.maxPlacements)
    end

    local limits = fn.fieldLimits
    if type(patch.placements) == 'table' then
        record.placements = cleanPoints(patch.placements, true, soldModels(record.vehicles), limits.placements)
    end
    if type(patch.spawns) == 'table' then record.spawns = cleanPoints(patch.spawns, true, nil, limits.spawns) end
    if type(patch.managementZones) == 'table' then
        record.managementZones = cleanPoints(patch.managementZones, false, nil, limits.managementZones)
    end
    if type(patch.saleZones) == 'table' then
        record.saleZones = cleanPoints(patch.saleZones, false, nil, limits.saleZones)
    end

    return record
end

local function samePlacements(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        local p, q = a[i], b[i]
        if p.model ~= q.model then return false end
        local c, d = p.coords, q.coords
        if c.x ~= d.x or c.y ~= d.y or c.z ~= d.z or c.w ~= d.w then return false end
    end
    return true
end

local function reconcileSwaps(id, record, placementsChanged)
    local swaps = Swaps[id]
    if not swaps then return end
    if placementsChanged then
        Swaps[id] = nil
        return
    end

    local sold = soldModels(record.vehicles)
    for key, model in pairs(swaps) do
        if not sold[model] then swaps[key] = nil end
    end
    if next(swaps) == nil then Swaps[id] = nil end
end

function fn.patchDealership(id, patch)
    local record = Dealerships[id]
    if not record then return fn.fail('Unknown dealership.') end
    if type(patch) ~= 'table' then return fn.fail('Nothing to save.') end

    local working = applyPatch(fn.copy(record), patch)
    local saved, err = fn.commitDealership(working)
    if not saved then return false, err end

    reconcileSwaps(id, working, not samePlacements(record.placements, working.placements))
    fn.publishSwaps()
    return saved
end

local function rowToRecord(row)
    local vehicles = fn.decode(row.vehicles, {})
    return {
        id = row.id,
        label = row.label,
        type = row.type,
        price = row.price,
        owner = row.owner,
        zone = fn.decode(row.zone, nil),
        vehicles = cleanVehicles(vehicles, vehicles, row.type),
        placements = fn.decode(row.placements, {}),
        spawns = fn.decode(row.spawns, {}),
        managementZones = fn.decode(row.management_zones, {}),
        saleZones = fn.decode(row.sale_zones, {}),
    }
end

local function load()
    for _, row in ipairs(QB.sql.query('SELECT * FROM `qbdealerships`', {}) or {}) do
        Dealerships[row.id] = rowToRecord(row)
    end

    for _, row in ipairs(QB.sql.query('SELECT * FROM `qbdealership_management`', {}) or {}) do
        DealerData[row.dealership_id] = newManagement(row)
    end
    fn.publish()
    fn.publishSwaps()
    fn.publishStaff()
end

CreateThread(function() load() end)

