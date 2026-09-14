fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gg_lib'
author 'GG Studio'
license 'LGPL-3.0-or-later'
version '1.0.4'
description 'GG Studio | Import-based library: bridge, gg.* modules, /ggsettings | Discord: https://discord.gg/DqMXJzATph'

ui_page "web/dist/index.html"
-- ui_page "http://localhost:5180/"

files {
    'init.lua',
    'core/shared/callback.lua',
    'core/client/console.lua',
    'locales/*.json',
    'feed/home.json',
    'feed/products.json',
    'feed/updates/*.json',
    'hooks/*.lua',
    'bridge/manifest.lua',
    'bridge/fallback.lua',
    'bridge/**/client.lua',
    'bridge/**/server.lua',
    'modules/**/client.lua',
    'modules/**/server.lua',
    'modules/**/shared.lua',
    'web/dist/index.html',
    'web/dist/**/*',
}

shared_scripts {
    'core/shared/callback.lua',
    'core/shared/locale_names.lua',
}

client_scripts {
    'core/client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'modules/settings/shared.lua',
    'core/server/*.lua',
    'hooks/server.lua',
}

dependencies {
    'oxmysql',
}
