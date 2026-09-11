--------------------------------------------------
-- MARK: gg_lib Server Configuration
--------------------------------------------------
-- Put your license in admins and restart. Players never see this file.
-- Keep a copy before you update -- an update replaces it.

return {
    -- Owners. Nothing in game can remove these, so keep yourself here.
    -- Join your server and read your license2 off the console.
    -- Everyone else is added in /ggsettings, not in here.
    admins = {
        "license2:6e713bc45df69b1338e94c292948ef0053ffb638",
    },

    -- Let anyone who is already an admin on your server straight in, without
    -- listing them above: group.admin, group.god, the principals qb-core and
    -- Qbox register, or your framework's own admin group. They get Admin,
    -- never Owner. Set false and only the list above gets in.
    auto_admin = true,

    -- Give someone Script Studio on its own, without making them an admin.
    -- Two permissions, handed out in server.cfg:
    --
    --   add_ace group.support gg.settings      allow   -- can change settings
    --   add_ace group.helper  gg.settings.view allow   -- can look, not touch
    --
    -- This is the only way to give read-only access. Set false to ignore both.
    ace = true,
}
