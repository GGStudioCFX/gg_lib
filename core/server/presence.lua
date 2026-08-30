gg = gg or {}
gg.print = gg.print or { error = print, warn = print, log = print }

local watching = {}

local GRACE = 60

GG_PRESENCE = GG_PRESENCE or {}

local keys = {}

local closed = {}

local function keysOf(player)
    local out = {}

    for index = 0, GetNumPlayerIdentifiers(player) - 1 do
        local key = Admins and Admins.normalize and Admins.normalize(GetPlayerIdentifier(player, index) or "")

        if key then out[#out + 1] = key end
    end

    return out
end

function GG_PRESENCE.state(identifier)
    if not identifier then return nil end

    for player in pairs(watching) do
        for _, key in ipairs(keys[player] or {}) do
            if key == identifier then return "open" end
        end
    end

    local went = closed[identifier]

    if went and (os.time() - went) <= GRACE then return "recent" end

    return nil
end

local function roster()
    local out = {}

    for source, entry in pairs(watching) do
        out[#out + 1] = {
            source = source,
            name   = entry.name,
            handle = entry.handle,
            avatar = entry.avatar,
            since  = entry.since,
        }
    end

    table.sort(out, function(a, b)
        if a.since == b.since then return a.source < b.source end

        return a.since < b.since
    end)

    return out
end

local function announce()
    local list = roster()

    for source in pairs(watching) do
        TriggerClientEvent("gg_lib:presence:sync", source, list)
    end
end

local function remember(player, name)
    local seen = {}

    for index = 0, GetNumPlayerIdentifiers(player) - 1 do
        local raw = GetPlayerIdentifier(player, index)

        local key = raw and Admins and Admins.normalize and Admins.normalize(raw) or nil

        if key and not seen[key] and not key:match("^ip:") then
            seen[key] = true

            local ok, err = pcall(function()
                MySQL.query.await([[
                    INSERT INTO `gg_studio_admin_seen` (`identifier`, `name`, `last_open`, `opens`)
                    VALUES (?, ?, CURRENT_TIMESTAMP, 1)
                    ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `last_open` = CURRENT_TIMESTAMP, `opens` = `opens` + 1
                ]], { key, name })
            end)

            if not ok then
                gg.print.warn(("could not record a studio open: %s"):format(tostring(err)))

                return
            end
        end
    end
end

local function stopped(player)
    for _, key in ipairs(keys[player] or {}) do closed[key] = os.time() end

    keys[player] = nil
end

RegisterNetEvent("gg_lib:presence:enter", function()
    local player = source

    if not GetPlayerName(player) then return end

    keys[player] = keysOf(player)

    for _, key in ipairs(keys[player]) do closed[key] = nil end

    watching[player] = {
        name   = GetPlayerName(player),
        since  = os.time(),
    }

    announce()

    CreateThread(function()
        remember(player, GetPlayerName(player))
    end)

    local function wear(face)
        if not face or not watching[player] then return end

        watching[player].avatar = face.avatar
        watching[player].handle = face.name

        announce()
    end

    wear(GG_FACES.fetchFor(player, wear))
end)

RegisterNetEvent("gg_lib:presence:leave", function()
    local player = source

    if not watching[player] then return end

    watching[player] = nil

    stopped(player)

    TriggerClientEvent("gg_lib:presence:sync", player, {})

    announce()
end)

AddEventHandler("playerDropped", function()
    if not watching[source] then return end

    watching[source] = nil

    stopped(source)

    announce()
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end

    watching = {}
    keys = {}
    closed = {}
end)
