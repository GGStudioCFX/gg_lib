--------------------------------------------------
-- MARK: gg_lib Server Configuration
--------------------------------------------------
-- Put your own license in admins and restart. Players never see this file.
--
-- Updating gg_lib replaces every other file. This one is yours -- keep a copy
-- before you update, the same as hooks/server.lua.

return {
    -- Owners. Nothing in game can remove these, so keep yourself here.
    -- Join your server and check the console for your license2 identifier.
    -- Everyone else is added in /ggsettings, not here.
    admins = {
        "license2:6e713bc45df69b1338e94c292948ef0053ffb638",
    },

    -- Honour the gg.settings and gg.settings.view ACE permissions.
    ace = true,

    -- Anyone your framework already trusts is an admin here too, without
    -- being listed above. They get Admin, never Owner.
    auto_admin = true,
}
