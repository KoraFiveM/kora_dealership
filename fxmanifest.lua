fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_dealership'
provide 'qb-vehicleshop'
author 'kora'
version '0.2.1'
description 'Dealership creator: build dealership zones, vehicle lists, placements, and spawn points via the AppShell'

dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_core/init.lua',
    'shared/config.lua',
    'shared/functions.lua'
}

server_scripts {
    '@kora_sql/init.lua',
    'server/schema.lua',
    'server/functions.lua',
    'server/creator.lua',
    'server/customer.lua',
    'server/sales.lua',
    'server/Management.lua',
}

client_scripts {
    'client/functions.lua',
    'client/views.lua',
    'client/creator.lua',
    'client/customer.lua',
    'client/sales.lua',
    'client/Management.lua',
}

files {
    'locales/en.lua',
    'locales/pt.lua',
}

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
