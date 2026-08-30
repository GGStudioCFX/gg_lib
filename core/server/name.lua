GGName = {}

-- Identifier preference. fivem: is the Cfx account, which is the one that
-- survives someone reinstalling or swapping a Steam login, so it is asked for
-- first and steam: is the last resort.
local ORDER = { "fivem", "license2", "license", "steam", "discord" }

local UNKNOWN = "unknown"

--- The account identifier, most durable first.
function GGName.identifier(source)
    if not source or source == 0 or source == "0" then return nil end

    for index = 1, #ORDER do
        local found = GetPlayerIdentifierByType(source, ORDER[index])

        if found and found ~= "" then return found end
    end

    return nil
end

--- Who they are in the world: first and last name, from the framework bridge.
function GGName.character(source)
    if not source or source <= 0 then return nil end

    if Framework and Framework.ensure then pcall(Framework.ensure) end

    local ok, name = pcall(function()
        return gg and gg.framework and gg.framework.GetName and gg.framework.GetName(source)
    end)

    if ok and type(name) == "string" and name ~= "" then return name end

    return nil
end

--- Who they are on the account. FiveM reports one display name per player --
--- there is no separate native for a Cfx name and a Steam name -- so this is
--- that name, and the fivem-before-steam preference lives in the identifier.
function GGName.account(source)
    if not source or source == 0 or source == "0" then return nil end

    local name = GetPlayerName(source)

    if type(name) == "string" and name ~= "" then return name end

    return nil
end

--- Everything about a player in one call.
---
--- Returns account, character, identifier. The account name is what the admin
--- list and the top bar show, so a log row and an admin row name the same
--- person the same way.
function GGName.of(source)
    return GGName.account(source), GGName.character(source), GGName.identifier(source)
end

--- One string for both names, for anywhere that has a single column to put
--- them in. "BigX Deplug -- Martin Duggan", or just the account name when the
--- player has no character loaded.
function GGName.both(source)
    local account, character = GGName.account(source), GGName.character(source)

    if account and character and account ~= character then
        return ("%s -- %s"):format(account, character)
    end

    return account or character or UNKNOWN
end
