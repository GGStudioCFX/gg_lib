
-- Pictures kept as base64 text in the database, one row per owner (the
-- resource they belong to) and name. A script saves a picture once and every
-- player fetches it when it is needed, with no file in any web folder and no
-- resource restart.
Images = {}

local READY_TIMEOUT = 30000

local MAX_DATA     = 4 * 1024 * 1024  -- base64 characters in one picture
local CACHE_BUDGET = 32 * 1024 * 1024 -- base64 characters kept in memory

local MAX_NAMES     = 60       -- names in one fetch request
local BATCH_IMAGES  = 4        -- pictures in one event
local BATCH_BYTES   = 192 * 1024
local SEND_RATE     = 1000000  -- bytes a second for each latent event
local WINDOW        = 2        -- batches on the wire before an ack is needed
local ACK_WAIT      = 20000
local MAX_QUEUED    = 4        -- requests a player may have waiting or running
local RATE_WINDOW   = 10000
local RATE_LIMIT    = 20       -- requests a player may make in RATE_WINDOW
local SERVING_SLOTS = 16       -- players answered at the same time

local function validOwner(owner)
    if type(owner) ~= "string" or #owner == 0 or #owner > 64 or owner:find("[^%w%-_%.]") then return nil end

    return owner
end

-- Any text a script uses as an id, short of control characters and spaces
-- at either end (the database ignores trailing spaces when it compares).
local function validName(name)
    if math.type(name) == "integer" then name = tostring(name) end

    if type(name) ~= "string" or #name == 0 or #name > 128 then return nil end
    if name:find("%c") or name:find("^%s") or name:find("%s$") then return nil end

    return name
end

local function validMime(mime)
    if mime == nil then return "image/webp" end
    if type(mime) ~= "string" or #mime > 32 or not mime:find("^image/[%w%.%+%-]+$") then return nil end

    return mime
end

local function decodedBytes(base64)
    local padding = #base64:match("=*$")

    return ((#base64 - padding) * 3) // 4
end

local function ready()
    local waited = 0

    while not Database.isReady() and waited < READY_TIMEOUT do
        Wait(100)
        waited = waited + 100
    end

    return Database.isReady()
end

local function query(kind, statement, parameters)
    local ok, result = pcall(MySQL[kind].await, statement, parameters)

    if not ok then
        print(("^1[gg_lib] images: %s^0"):format(tostring(result)))
        return nil, false
    end

    return result, true
end

-- MARK: Caches

-- owner -> { [name] = version }, once read. `generation` counts saves and
-- deletes, so a read that a write overtook is not kept.
local versionsOf = {}
local generation = {}

local function bump(owner)
    generation[owner] = (generation[owner] or 0) + 1
end

-- The picture data itself, least recently used out first.
local cache = {}
local cacheSize = 0
local cacheTick = 0

local function cacheKey(owner, name)
    return owner .. "\n" .. name
end

local function cacheDrop(owner, name)
    local key = cacheKey(owner, name)
    local entry = cache[key]

    if not entry then return end

    cacheSize = cacheSize - entry.size
    cache[key] = nil
end

local function cacheGet(owner, name)
    local entry = cache[cacheKey(owner, name)]

    if entry then
        cacheTick = cacheTick + 1
        entry.used = cacheTick
    end

    return entry
end

local function cachePut(owner, name, mime, data, version)
    cacheDrop(owner, name)

    local entry = { mime = mime, data = data, version = version, size = #data }

    if entry.size > CACHE_BUDGET then return entry end

    while cacheSize + entry.size > CACHE_BUDGET do
        local oldest, oldestUsed = nil, nil

        for key, item in pairs(cache) do
            if not oldestUsed or item.used < oldestUsed then oldest, oldestUsed = key, item.used end
        end

        if not oldest then break end

        cacheSize = cacheSize - cache[oldest].size
        cache[oldest] = nil
    end

    cacheTick = cacheTick + 1
    entry.used = cacheTick

    cache[cacheKey(owner, name)] = entry
    cacheSize = cacheSize + entry.size

    return entry
end

local function loadVersions(owner)
    local known = versionsOf[owner]
    if known then return known end

    if not ready() then return nil end

    for _ = 1, 3 do
        local seen = generation[owner] or 0
        local rows, ok = query("query", "SELECT `name`, `version` FROM `gg_lib_images` WHERE `owner` = ?", { owner })

        if not ok then return nil end

        known = {}

        for _, row in ipairs(rows or {}) do
            known[row.name] = tonumber(row.version)
        end

        if (generation[owner] or 0) == seen then
            versionsOf[owner] = known
            return known
        end
    end

    return known
end

-- MARK: Store

function Images.save(owner, name, base64, mime)
    owner, name = validOwner(owner), validName(name)

    if not owner then return nil, "invalid owner" end
    if not name then return nil, "invalid name" end
    if type(base64) ~= "string" then return nil, "image was empty" end

    local fromUrl, body = base64:match("^data:([^;,]+);base64,(.*)$")

    if body then
        base64 = body
        if mime == nil then mime = fromUrl end
    end

    mime = validMime(mime)
    if not mime then return nil, "invalid image type" end

    base64 = (base64:gsub("%s", ""))

    if base64 == "" then return nil, "image was empty" end
    if #base64 > MAX_DATA then return nil, "image exceeded the size limit" end
    if not base64:find("^[%w%+/]+=?=?$") then return nil, "image is not base64" end

    if not ready() then return nil, "the database is not ready" end

    local _, saved = query("update", [[
        INSERT INTO `gg_lib_images` (`owner`, `name`, `mime`, `data`, `bytes`, `version`)
        VALUES (?, ?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE
            `mime` = VALUES(`mime`),
            `data` = VALUES(`data`),
            `bytes` = VALUES(`bytes`),
            `version` = `version` + 1
    ]], { owner, name, mime, base64, decodedBytes(base64) })

    if not saved then return nil, "the database refused the image" end

    local version = tonumber((query("scalar", "SELECT `version` FROM `gg_lib_images` WHERE `owner` = ? AND `name` = ?", { owner, name })))

    if not version then return nil, "the database lost the image" end

    bump(owner)

    local known = versionsOf[owner]
    if known then known[name] = version end

    cachePut(owner, name, mime, base64, version)

    TriggerEvent("gg_lib:image:stored", owner, name, version)

    return version
end

function Images.delete(owner, name)
    owner, name = validOwner(owner), validName(name)

    if not owner or not name or not ready() then return false end

    local affected, ok = query("update", "DELETE FROM `gg_lib_images` WHERE `owner` = ? AND `name` = ?", { owner, name })

    if not ok then return false end

    bump(owner)

    local known = versionsOf[owner]
    if known then known[name] = nil end

    cacheDrop(owner, name)

    if (tonumber(affected) or 0) < 1 then return false end

    TriggerEvent("gg_lib:image:stored", owner, name, nil)

    return true
end

function Images.versions(owner)
    owner = validOwner(owner)
    if not owner then return {} end

    local copy = {}

    for name, version in pairs(loadVersions(owner) or {}) do
        copy[name] = version
    end

    return copy
end

-- Pictures for `names` that exist, cache first, one query for the rest.
local function collect(owner, names)
    local known = loadVersions(owner) or {}
    local found, missing = {}, {}

    for _, name in ipairs(names) do
        local version = known[name]

        if version then
            local entry = cacheGet(owner, name)

            if entry and entry.version == version then
                found[name] = entry
            else
                missing[#missing + 1] = name
            end
        end
    end

    if #missing == 0 then return found end

    local seen = generation[owner] or 0
    local parameters = { owner }

    for index, name in ipairs(missing) do parameters[index + 1] = name end

    local rows = query("query", ("SELECT `name`, `mime`, `data`, `version` FROM `gg_lib_images` WHERE `owner` = ? AND `name` IN (%s)")
        :format(("?, "):rep(#missing):sub(1, -3)), parameters)

    local fresh = (generation[owner] or 0) == seen

    for _, row in ipairs(rows or {}) do
        local version = tonumber(row.version)

        if type(row.data) == "string" and version then
            found[row.name] = fresh and cachePut(owner, row.name, row.mime, row.data, version)
                or { mime = row.mime, data = row.data, version = version }
        end
    end

    return found
end

function Images.get(owner, name)
    owner, name = validOwner(owner), validName(name)
    if not owner or not name then return nil end

    local entry = collect(owner, { name })[name]
    if not entry then return nil end

    return ("data:%s;base64,%s"):format(entry.mime or "image/webp", entry.data), entry.version
end

exports("ggImageSave", Images.save)
exports("ggImageDelete", Images.delete)
exports("ggImageVersions", Images.versions)
exports("ggImageGet", Images.get)

-- MARK: Fetch

-- Any player may read: these are display pictures. Each player's requests
-- are answered one at a time, in batches of a few pictures per latent event,
-- at most WINDOW batches on the wire, each acknowledged by the client. A big
-- answer is paced out and never stalls or drops the connection.
local players = {}
local serving = 0

local function playerState(src)
    local state = players[src]

    if not state then
        state = { queue = {}, times = {}, active = nil, running = false }
        players[src] = state
    end

    return state
end

local function finish(src, request, reason)
    TriggerClientEvent("gg_lib:images:batch", src, request, 0, nil, 0, reason)
end

local function batchesOf(names, found)
    local batches, current, size = {}, {}, 0

    for _, name in ipairs(names) do
        local entry = found[name]

        if entry then
            if #current > 0 and (#current >= BATCH_IMAGES or size + #entry.data > BATCH_BYTES) then
                batches[#batches + 1] = current
                current, size = {}, 0
            end

            current[#current + 1] = { n = name, m = entry.mime or "image/webp", d = entry.data, v = entry.version }
            size = size + #entry.data
        end
    end

    if #current > 0 then batches[#batches + 1] = current end

    return batches
end

local function bytesOf(batch)
    local size = 0

    for _, item in ipairs(batch) do size = size + #item.d end

    return size
end

-- Waits until fewer than `limit` batches are unacknowledged. False when the
-- client went quiet, left, or called the request off.
local function waitForAcks(src, job, sent, limit, onWire)
    local deadline = GetGameTimer() + ACK_WAIT + math.ceil(onWire * 1000 / SEND_RATE)

    while sent - job.acked >= limit do
        if job.cancelled or not players[src] then return false end

        if GetGameTimer() > deadline then
            print(("^3[gg_lib] images: player %s stopped acknowledging pictures^0"):format(tostring(src)))
            return false
        end

        Wait(10)
    end

    return not job.cancelled and players[src] ~= nil
end

local function answer(src, job)
    local found = collect(job.owner, job.names)
    local batches = batchesOf(job.names, found)

    if #batches == 0 then return finish(src, job.request, nil) end

    local sizes = {}

    for seq, batch in ipairs(batches) do
        sizes[seq] = bytesOf(batch)

        local onWire = sizes[seq]
        for earlier = math.max(1, seq - WINDOW), seq - 1 do onWire = onWire + sizes[earlier] end

        if not waitForAcks(src, job, seq - 1, WINDOW, onWire) then return end

        TriggerLatentClientEvent("gg_lib:images:batch", src, SEND_RATE, job.request, seq, batch, #batches, nil)
    end

    local onWire = 0
    for seq = math.max(1, #batches - WINDOW + 1), #batches do onWire = onWire + sizes[seq] end

    waitForAcks(src, job, #batches, 1, onWire)
end

local function work(src, state)
    if state.running then return end

    state.running = true

    CreateThread(function()
        while players[src] == state and #state.queue > 0 do
            local job = table.remove(state.queue, 1)

            state.active = job

            while serving >= SERVING_SLOTS and players[src] == state and not job.cancelled do Wait(100) end

            if players[src] == state and not job.cancelled then
                serving = serving + 1

                local ok, err = pcall(answer, src, job)

                serving = serving - 1

                if not ok then
                    print(("^1[gg_lib] images: %s^0"):format(tostring(err)))
                    finish(src, job.request, "the server could not answer")
                end
            end

            state.active = nil
        end

        state.running = false
    end)
end

RegisterNetEvent("gg_lib:images:fetch", function(request, owner, names)
    local src = source

    request = math.tointeger(request)
    if not request then return end

    owner = validOwner(owner)
    if not owner or type(names) ~= "table" then return finish(src, request, "invalid request") end
    if #names > MAX_NAMES then return finish(src, request, "too many names") end

    local list, seen = {}, {}

    for _, name in ipairs(names) do
        name = validName(name)

        if name and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end

    local state = playerState(src)
    local now = GetGameTimer()
    local times = state.times

    while times[1] and now - times[1] > RATE_WINDOW do table.remove(times, 1) end

    if #times >= RATE_LIMIT then return finish(src, request, "rate") end
    if #state.queue + (state.active and 1 or 0) >= MAX_QUEUED then return finish(src, request, "busy") end

    times[#times + 1] = now

    if #list == 0 then return finish(src, request, nil) end

    state.queue[#state.queue + 1] = { request = request, owner = owner, names = list, acked = 0, got = {} }

    work(src, state)
end)

RegisterNetEvent("gg_lib:images:ack", function(request, seq)
    local state = players[source]
    local job = state and state.active

    request, seq = math.tointeger(request), math.tointeger(seq)

    if not job or job.request ~= request or not seq or job.got[seq] then return end

    job.got[seq] = true
    job.acked = job.acked + 1
end)

RegisterNetEvent("gg_lib:images:cancel", function(request)
    local state = players[source]
    if not state then return end

    request = math.tointeger(request)

    if state.active and state.active.request == request then state.active.cancelled = true end

    for _, job in ipairs(state.queue) do
        if job.request == request then job.cancelled = true end
    end
end)

AddEventHandler("playerDropped", function()
    players[source] = nil
end)
