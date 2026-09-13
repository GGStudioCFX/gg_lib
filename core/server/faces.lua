
GG_FACES = GG_FACES or { cache = {}, pending = {}, told = {} }

local DISCORD_API = "https://discord.com/api/v10/users/%s"
local CFX_API     = "https://policy-live.fivem.net/api/getUserInfo/%s"
local CFX_FORUM   = "https://forum.cfx.re"
local STEAM_XML   = "https://steamcommunity.com/profiles/%s/?xml=1"

function GG_FACES.steam64(identifier)
    if type(identifier) ~= "string" then return nil end

    local hex = identifier:match("^steam:(%x+)$")

    if not hex then return nil end

    local id = tonumber(hex, 16)

    if not id then return nil end

    return ("%d"):format(math.tointeger and math.tointeger(id) or id)
end

function GG_FACES.cfxId(identifier)
    if type(identifier) ~= "string" then return nil end

    return identifier:match("^fivem:(%d+)$")
end

function GG_FACES.discordId(identifier)
    if type(identifier) ~= "string" then return nil end

    return identifier:match("^discord:(%d+)$")
end

function GG_FACES.accountsOf(source)
    local held = { discord = nil, cfx = nil, steam = nil }

    for index = 0, GetNumPlayerIdentifiers(source) - 1 do
        local raw = GetPlayerIdentifier(source, index)

        held.discord = held.discord or GG_FACES.discordId(raw)
        held.cfx     = held.cfx or GG_FACES.cfxId(raw)
        held.steam   = held.steam or GG_FACES.steam64(raw)
    end

    return held
end

function GG_FACES.known(key)
    return key and GG_FACES.cache[key] or nil
end

local function sayOnce(kind, message)
    if GG_FACES.told[kind] then return end

    GG_FACES.told[kind] = true

    print(("^3[gg_lib] %s^0"):format(message))
end

local function record(name, avatar, from)
    if not avatar or avatar == "" then return nil end

    return { name = name, avatar = avatar, from = from }
end

local function once(key, work, done)
    local held = GG_FACES.cache[key]

    if held then
        if done then done(held) end

        return held
    end

    if GG_FACES.pending[key] then
        if done then done(nil) end

        return nil
    end

    GG_FACES.pending[key] = true

    work(function(found)
        GG_FACES.pending[key] = nil

        if not found then return end

        GG_FACES.cache[key] = found

        if done then done(found) end
    end)

    return nil
end

function GG_FACES.canAskDiscord()
    local token = Admins and Admins.setting and Admins.setting("discord_bot_token")

    return type(token) == "string" and token ~= ""
end

function GG_FACES.fetchDiscord(discordId, done)
    if not discordId then
        if done then done(nil) end

        return nil
    end

    local token = Admins and Admins.setting and Admins.setting("discord_bot_token")

    if not GG_FACES.canAskDiscord() then
        if done then done(nil) end

        return nil
    end

    return once(("discord:%s"):format(discordId), function(finish)
        PerformHttpRequest(DISCORD_API:format(discordId), function(status, body)
            if status ~= 200 or type(body) ~= "string" then
                sayOnce("discord_call", ("Discord answered %s for an admin lookup -- check the bot token"):format(tostring(status)))

                return finish(nil)
            end

            local hash = body:match('"avatar"%s*:%s*"([^"]+)"')
            local name = body:match('"global_name"%s*:%s*"([^"]+)"') or body:match('"username"%s*:%s*"([^"]+)"')

            if not hash then return finish(nil) end

            local extension = hash:sub(1, 2) == "a_" and "gif" or "png"

            finish(record(name, ("https://cdn.discordapp.com/avatars/%s/%s.%s?size=128"):format(discordId, hash, extension), "discord"))
        end, "GET", "", { Authorization = ("Bot %s"):format(token) })
    end, done)
end

function GG_FACES.fetchCfx(cfxId, done)
    if not cfxId then
        if done then done(nil) end

        return nil
    end

    return once(("cfx:%s"):format(cfxId), function(finish)
        PerformHttpRequest(CFX_API:format(cfxId), function(status, body)
            if status ~= 200 or type(body) ~= "string" then return finish(nil) end

            local template = body:match('"avatar_template"%s*:%s*"([^"]+)"')
                or body:match('"avatar"%s*:%s*"([^"]+)"')

            local name = body:match('"name"%s*:%s*"([^"]+)"')
                or body:match('"username"%s*:%s*"([^"]+)"')

            if not template or template == "" then return finish(nil) end

            local url = template:gsub("{size}", "128"):gsub("\\/", "/")

            if not url:match("^https?://") then
                url = ("%s%s"):format(CFX_FORUM, url:sub(1, 1) == "/" and url or ("/" .. url))
            end

            finish(record(name, url, "cfx"))
        end, "GET", "", {})
    end, done)
end

function GG_FACES.fetchSteam(steamId, done)
    if not steamId then
        if done then done(nil) end

        return nil
    end

    return once(("steam:%s"):format(steamId), function(finish)
        PerformHttpRequest(STEAM_XML:format(steamId), function(status, body)
            if status ~= 200 or type(body) ~= "string" then return finish(nil) end

            local url = body:match("<avatarFull>%s*<!%[CDATA%[(.-)%]%]>%s*</avatarFull>")
                or body:match("<avatarFull>(.-)</avatarFull>")

            local name = body:match("<steamID>%s*<!%[CDATA%[(.-)%]%]>%s*</steamID>")
                or body:match("<steamID>(.-)</steamID>")

            finish(record(name, url, "steam"))
        end, "GET", "", {})
    end, done)
end

function GG_FACES.fetchFor(source, done)
    local held = GG_FACES.accountsOf(source)

    local ready = GG_FACES.known(held.discord and ("discord:%s"):format(held.discord))
        or GG_FACES.known(held.cfx and ("cfx:%s"):format(held.cfx))
        or GG_FACES.known(held.steam and ("steam:%s"):format(held.steam))

    if ready then
        if done then done(ready) end

        return ready
    end

    local function giveUp()
        local who = GetPlayerName(source) or source

        if held.cfx or held.steam then
            sayOnce("none_private", ("nothing would give a picture for %s -- a private profile answers the same as no profile"):format(who))
        elseif not held.discord then
            sayOnce("none_account", ("no Discord, Cfx.re or Steam account on %s, so the studio shows initials"):format(who))
        end
    end

    local function trySteam()
        if not held.steam then return giveUp() end

        GG_FACES.fetchSteam(held.steam, function(found)
            if found then return done and done(found) end

            giveUp()
        end)
    end

    local function tryCfx()
        if not held.cfx then return trySteam() end

        GG_FACES.fetchCfx(held.cfx, function(found)
            if found then return done and done(found) end

            trySteam()
        end)
    end

    if not held.discord or not GG_FACES.canAskDiscord() then
        return tryCfx()
    end

    GG_FACES.fetchDiscord(held.discord, function(found)
        if found then return done and done(found) end

        tryCfx()
    end)
end
