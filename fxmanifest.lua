fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbdealership'
author 'qbcore2'
version '0.1.0'
description 'Server-authoritative vehicle dealership backed by qbcore shared vehicle definitions'

dependency 'qblib'
dependency 'qbcore'

shared_script '@qblib/init.lua'

shared_scripts {
    'config.lua',
}

-- Explicit order: the authority API is complete before its callback surface is
-- registered. Client code only renders the server-provided catalogue and sends
-- the dealership id plus selected model back as intent.
server_scripts {
    'server/dealership.lua',
    'server/callbacks.lua',
}

client_script 'client/main.lua'
