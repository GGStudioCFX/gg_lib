--------------------------------------------------
-- MARK: gg_lib Server Configuration
--------------------------------------------------
-- Put your license below and restart. It is saved as an Owner in the database.
-- Saved access survives updates that replace this file.

return {
    -- You. Join your server and read your license2 off the console.
    -- Each identifier is imported once. Manage or remove saved access in
    -- /ggsettings; removing it there will not be undone by a restart.
    -- The shipped example below stays config-only and is never imported.
    admins = {
        "license2:6e713bc45df69b1338e94c292948ef0053ffb638",
    },

    -- Anyone who is already an admin on your server gets in too, without
    -- being listed above. They get Admin, never Owner.
    -- Set false if you want only explicitly configured or saved admins.
    auto_admin = true,
}
