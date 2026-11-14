-- Run from kora_dealership: lua5.4 test/schema.lua
Kora = { sql = { NULL = '\0kora_sql:null\0' } }
dofile('server/schema.lua')

local declared = {}
for _, spec in ipairs(KoraDealershipSchema) do declared[spec.name] = spec end
assert(#KoraDealershipSchema == 3, 'three tables declared')
assert(KoraDealershipSchema[1].name == 'kora_dealerships', 'the parent table comes first for the foreign keys')
for _, name in ipairs({ 'kora_dealerships', 'kora_dealership_management', 'kora_dealership_offers' }) do
    assert(declared[name] and #declared[name].columns > 0, name .. ' is declared')
end
assert(declared.kora_dealership_offers.foreign[1].ref_table == 'kora_dealerships', 'offers cascade from dealerships')

local pdm = declared.kora_dealerships.seed.rows[1]
assert(pdm.id == 'pdm' and pdm.type == 'public' and pdm.price == nil, 'pdm seed row is a public dealership')
assert(pdm.vehicles:find('"model":"asbo"', 1, true) and pdm.zone:find('"thickness":28.375', 1, true), 'pdm seed keeps its JSON payloads')

local manifest = assert(io.open('fxmanifest.lua')):read('a')
assert(manifest:find("'server/schema.lua'", 1, true) and not manifest:find('dealers.sql', 1, true), 'manifest loads the schema, not the sql file')

local boot
function CreateThread(action) boot = action end
function AddEventHandler() end
Config = { UsePDM = true }
GlobalState = {}
Kora.print = { debug = function() end }
Kora.sql.ready = function() return true end
Kora.sql.ensureTables = function() return {} end
local tablesReady = false
Kora.sql.awaitTables = function(names)
    assert(#names == 2 and names[1] == 'players' and names[2] == 'player_vehicles')
    assert(GlobalState.Dealerships == nil, 'dealerships must not be published while Core tables are unavailable')
    return tablesReady, 'tables unavailable'
end
Kora.sql.query = function()
    assert(tablesReady, 'startup must wait before loading dealerships')
    return {}
end
dofile('server/functions.lua')
boot()
assert(GlobalState.Dealerships == nil)
tablesReady = true
boot()
assert(type(GlobalState.Dealerships) == 'table', 'startup publishes once Core tables are ready')
print('kora_dealership: schema declares its tables and the pdm seed')
