fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbdealership'
author 'qbcore2'
version '1.0.0'
description 'Live dealership creator, showroom, management, stock and offer system'

dependency 'qblib'
dependency 'qbsql'
dependency 'qbcore'
dependency 'qbtarget'

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
    '@qbcore/init.lua',
    'config.lua',
    'shared/schema.lua',
}

server_scripts {
    'server/state.lua',
    'server/dealership.lua',
    'server/callbacks.lua',
    'server/main.lua',
}

client_scripts {
    'client/state.lua',
    'client/world.lua',
    'client/app.lua',
    'client/main.lua',
}

files { 'sql/001_dealerships.sql', 'sql/002_stock_model.sql', 'sql/003_offer_settling.sql' }
