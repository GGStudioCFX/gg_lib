--[[
    Your hooks.

    Open /ggsettings, go to Logs -> Activity Types, pick an action and press
    Code. Paste what it copies below -- it already lists everything that action
    hands you.

    Everything here runs on the server, after the thing has already happened.
    A hook cannot cancel anything. If yours errors, gg_lib prints which action
    caused it and carries on, so a broken hook never takes a script down.

    To do something on the player's screen, trigger a client event from in here
    the same way you would anywhere else.

    Updating gg_lib replaces every other file. This one is yours -- keep a copy
    before you update, the same as your server_config.lua.
]]

-- GGHook('gg_taxijob:job.complete', function(data)
--     print(("%s earned %s"):format(data.name, data.earnings))
-- end)
