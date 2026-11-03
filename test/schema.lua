-- Run from qbdealership: lua5.4 test/schema.lua
Kora = { sql = { NULL = '\0qbsql:null\0' } }
dofile('server/schema.lua')

local declared = {}
for _, spec in ipairs(QBDealershipSchema) do declared[spec.name] = spec end
assert(#QBDealershipSchema == 3, 'three tables declared')
assert(QBDealershipSchema[1].name == 'qbdealerships', 'the parent table comes first for the foreign keys')
for _, name in ipairs({ 'qbdealerships', 'qbdealership_management', 'qbdealership_offers' }) do
    assert(declared[name] and #declared[name].columns > 0, name .. ' is declared')
end
assert(declared.qbdealership_offers.foreign[1].ref_table == 'qbdealerships', 'offers cascade from dealerships')

local pdm = declared.qbdealerships.seed.rows[1]
assert(pdm.id == 'pdm' and pdm.type == 'public' and pdm.price == nil, 'pdm seed row is a public dealership')
assert(pdm.vehicles:find('"model":"asbo"', 1, true) and pdm.zone:find('"thickness":28.375', 1, true), 'pdm seed keeps its JSON payloads')

local manifest = assert(io.open('fxmanifest.lua')):read('a')
assert(manifest:find("'server/schema.lua'", 1, true) and not manifest:find('dealers.sql', 1, true), 'manifest loads the schema, not the sql file')
print('qbdealership: schema declares its tables and the pdm seed')
