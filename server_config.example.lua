--------------------------------------------------
-- MARK: gg_lib Server Configuration
--------------------------------------------------
-- Copy this file to server_config.lua and put your own license in the list.
-- This file never reaches players.

return {
    -- Owners. These can never be removed in game, so keep yourself here: it is
    -- the way back in if the database ever says otherwise.
    admins = {
        -- "license2:0000000000000000000000000000000000000000",
    },

    -- Honour the gg.settings and gg.settings.view ACE permissions.
    ace = true,

    -- Anyone your server already trusts is an admin here too, without being
    -- added above: group.admin, group.god and the principals qb-core, Qbox and
    -- ESX register, or your framework's own admin group. They get the Admin
    -- role, never Owner -- deciding who else gets in stays with this file.
    --
    -- Set false to require the list above and the ACE permissions instead.
    auto_admin = true,
}
