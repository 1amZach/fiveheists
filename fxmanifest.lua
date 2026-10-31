fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'fiveheists'
description 'Store, ATM, Fleeca and jewelry store robberies, checked on the server'
version '1.0.0'
author 'IamZach'
discord 'https://discord.gg/agn'
repository 'https://github.com/1amZach/fiveheists'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    'server/framework.lua',
    'server/dispatch.lua',
    'server/main.lua',
    'server/commands.lua',
}

client_scripts {
    'client/interact.lua',
    'client/main.lua',
}

dependency 'ox_lib'
