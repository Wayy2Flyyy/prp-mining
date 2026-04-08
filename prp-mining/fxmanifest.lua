fx_version "cerulean"
game "gta5"


author "Prodigy Studios"
version "1.0.0"

lua54 "yes"
shared_scripts {
    "@ox_lib/init.lua",
    "@prp-bridge/import.lua",
}

client_scripts {
    "config/sh_config.lua",
    "client/*.lua",
}

server_scripts {
    "@oxmysql/lib/MySQL.lua",
    "config/sh_config.lua",
    "config/sv_config.lua",
    "server/*.lua",
}

files {
    "dui/*",
    "locales/*.json"
}

escrow_ignore {
    "server/**/*.lua",
    "config/**/*.lua",
    "client/collection.lua",
}

dependencies {
    '/assetpacks',
    'ox_target',
}