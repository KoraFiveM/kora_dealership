fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kora_dealership'
-- Keep the legacy resource name resolvable for exports['qbdealership'] callers.
provide 'qbdealership'
author 'qbcore2'
version '2.0.0'
description 'Dealership creator: build dealership zones, vehicle lists, placements, and spawn points via the AppShell'

dependency 'kora_lib'
dependency 'kora_sql'
dependency 'kora_core'

shared_scripts {
    '@kora_lib/init.lua',
    '@kora_core/init.lua',
    'config.lua',
    'shared/functions.lua'
}

server_scripts {
    '@kora_sql/init.lua',
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

files { 'locales/en.lua', 'sql/dealers.sql' }
