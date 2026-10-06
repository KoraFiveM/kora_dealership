fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbdealership'
author 'qbcore2'
version '2.0.0'
description 'Dealership creator: build dealership zones, vehicle lists, placements, and spawn points via the AppShell'

dependency 'qblib'
dependency 'qbsql'
dependency 'qbcore'

shared_scripts {
    '@qblib/init.lua',
    '@qbcore/init.lua',
    'config.lua',
    'shared/functions.lua'
}

server_scripts {
    '@qbsql/init.lua',
    'server/functions.lua',
    'server/creator.lua',
    'server/customer.lua',
    'server/sales.lua',
    'server/management.lua',
}

client_scripts {
    'client/functions.lua',
    'client/views.lua',
    'client/creator.lua',
    'client/customer.lua',
    'client/sales.lua',
    'client/management.lua',
}

files { 'locales/en.lua' }
