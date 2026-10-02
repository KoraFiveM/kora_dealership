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
    '@qbsql/init.lua',
    '@qbcore/init.lua',
    'config.lua',
}

server_script 'server/**.lua'
client_script 'client/**.lua'

files { 'sql/001_dealerships.sql' }
