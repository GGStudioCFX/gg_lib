Actions = {}

local RESOURCE = GetCurrentResourceName()

local DEFAULT_RETENTION_DAYS = 14
local KEEP_ROWS  = 20000
local MAX_DATA   = 4000
local FLUSH_MS   = 2000
local MAX_QUEUE  = 1000
local MAX_EMBEDS = 10

local KINDS = { webhook = true }

local registry    = {}
local order       = {}
local routes      = {}
local subscribers = {}

local logQueue     = {}
local webhookQueue = {}
local backoffUntil = 0
local function trim(text)
    if type(text) ~= "string" then return nil end

    local out = text:gsub("^%s+", ""):gsub("%s+$", "")

    return out ~= "" and out or nil
end

GGHooks = GGHooks or {}

-- What hooks/server.lua calls. Everything runs on the server: if a hook needs
-- the player to see something, it triggers a client event of its own.
function GGHook(action, fn)
    if type(action) ~= "string" or action == "" then
        print("^1[gg_lib] GGHook needs an action id, like GGHook('gg_taxijob:job.complete', ...)^0")
        return false
    end

    if type(fn) ~= "function" then
        print(("^1[gg_lib] GGHook('%s') was given a %s instead of a function^0"):format(action, type(fn)))
        return false
    end

    if GGHooks[action] then
        print(("^3[gg_lib] hooks/server.lua sets up '%s' twice -- only the last one runs^0"):format(action))
    end

    GGHooks[action] = fn

    return true
end

local function toMatcher(pattern)
    local escaped = pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*")

    return "^" .. escaped .. "$"
end

local function matches(pattern, script, action)
    local matcher = toMatcher(pattern)

    if pattern:find(":", 1, true) then
        return (script .. ":" .. action):match(matcher) ~= nil
    end

    return action:match(matcher) ~= nil
end

-- "earnings:number, type:string" -- what a hook is handed, so the Studio can
-- write the comment block above the function instead of the author guessing.
local function parseFields(raw)
    local out = {}

    for piece in (raw or ""):gmatch("[^,]+") do
        local field, kind = piece:match("^%s*([%w_]+)%s*:?%s*([%w]*)%s*$")

        if field then
            out[#out + 1] = { name = field, kind = kind ~= "" and kind or "any" }
        end
    end

    return out
end

local function declare(script, raw)
    local name, label, help, fields = raw:match("^([^|]*)|?([^|]*)|?([^|]*)|?(.*)$")

    name = trim(name)

    if not name or not name:match("^[%w_%.%-]+$") then
        print(("^3[gg_lib] %s declared an unusable action name '%s'^0"):format(script, tostring(raw)))
        return
    end

    local full = script .. ":" .. name

    if registry[full] then return end

    registry[full] = {
        full   = full,
        script = script,
        action = name,
        label  = trim(label) or name,
        help   = trim(help),
        fields = parseFields(fields),
    }

    order[#order + 1] = full
end

local function scan(script)
    local count = GetNumResourceMetadata(script, "gg_action") or 0

    for index = 0, count - 1 do
        local raw = GetResourceMetadata(script, "gg_action", index)

        if type(raw) == "string" and raw ~= "" then declare(script, raw) end
    end
end

CreateThread(function()
    for index = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(index)

        if name and GetResourceState(name) == "started" then scan(name) end
    end
end)

AddEventHandler("onResourceStart", function(script)
    if type(script) == "string" then scan(script) end
end)

local function retentionDays()
    local stored = GenericSettings and GenericSettings.get and GenericSettings.get("actions.retention_days")

    return math.max(math.floor(tonumber(stored) or DEFAULT_RETENTION_DAYS), 1)
end

function Actions.loadRoutes()
    local ok, rows = pcall(MySQL.query.await, "SELECT id, action, kind, label, target, message, enabled FROM gg_studio_action_routes")

    if not ok then return false end

    local out = {}

    for _, row in ipairs(rows or {}) do
        out[#out + 1] = {
            id      = row.id,
            action  = row.action,
            kind    = row.kind,
            label   = row.label,
            target  = row.target,
            message = row.message,
            enabled = row.enabled == 1 or row.enabled == true,
        }
    end

    routes = out

    return true
end

AddEventHandler("gg_lib:database:ready", function()
    Actions.loadRoutes()
end)

local function encodeData(value)
    if value == nil then return nil end

    local ok, encoded = pcall(json.encode, value)

    if not ok then return nil end

    if #encoded > MAX_DATA then return json.encode({ note = "payload too large to record" }) end

    return encoded
end

local HOISTED = { source = true, src = true, identifier = true }

-- One flat table, so a hook author writes data.earnings rather than reaching
-- through an envelope. The lib's own fields win over anything the payload
-- happens to be carrying under the same name.
function Actions.payload(envelope)
    local out = {
        action     = envelope.full,
        script     = envelope.script,
        name       = envelope.character or envelope.player,
        account    = envelope.player,
        identifier = envelope.identifier,
        source     = envelope.source,
        at         = envelope.at,
    }

    for key, value in pairs(envelope.data or {}) do
        if out[key] == nil then out[key] = value end
    end

    return out
end

local function databaseSink(envelope)
    if #logQueue >= MAX_QUEUE then return end

    logQueue[#logQueue + 1] = {
        envelope.script,
        envelope.action,
        envelope.source,
        envelope.identifier,
        envelope.player,
        envelope.character,
        encodeData(envelope.data),
    }
end

-- {player}, {earnings}, anything the payload carries. An unknown name is left
-- standing rather than blanked, so a typo shows itself in Discord instead of
-- quietly producing a sentence with a hole in it.
local function render(template, envelope)
    return (template:gsub("{([%w_]+)}", function(key)
        if key == "name" or key == "player" then return envelope.character or envelope.player or "someone" end
        if key == "account" then return envelope.player or "someone" end
        if key == "identifier" then return envelope.identifier or "?" end
        if key == "script" then return envelope.script end
        if key == "action" then return envelope.action end
        if key == "source" then return tostring(envelope.source or "?") end

        local value = envelope.data and envelope.data[key]

        if value ~= nil and type(value) ~= "table" then return tostring(value) end

        return "{" .. key .. "}"
    end))
end

local function embedOf(envelope, route)
    local fields = {}
    local keys = {}

    for key in pairs(envelope.data or {}) do
        if not HOISTED[key] then keys[#keys + 1] = key end
    end

    table.sort(keys)

    for _, key in ipairs(keys) do
        local value = envelope.data[key]

        if type(value) ~= "table" then
            fields[#fields + 1] = {
                name   = tostring(key),
                value  = "`" .. tostring(value) .. "`",
                inline = true,
            }
        end
    end

    if envelope.player or envelope.character then
        local who = envelope.player or envelope.character

        if envelope.character and envelope.player and envelope.character ~= envelope.player then
            who = ("%s (%s)"):format(envelope.player, envelope.character)
        end

        table.insert(fields, 1, { name = "Player", value = who, inline = true })
    end

    if envelope.identifier then
        fields[#fields + 1] = { name = "Identifier", value = "`" .. envelope.identifier .. "`", inline = false }
    end

    local known = registry[envelope.full]
    local written = trim(route.message)

    return {
        title       = known and known.label or envelope.action,
        description = written and render(written, envelope) or (known and known.help) or nil,
        color       = 13011455,
        fields      = fields,
        footer      = { text = envelope.script },
        timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ", envelope.at),
    }
end

-- Discord hands people the whole address, but plenty of panels and tickets pass
-- only the id/token half of it. Both are accepted and stored the same way, so
-- nothing downstream has to care which one was pasted.
function Actions.webhookUrl(raw)
    local text = trim(raw)

    if not text then return nil end

    if text:match("^https://") then return text end

    local id, token = text:match("^(%d+)/([%w_%-]+)$")

    if id and token then return ("https://discord.com/api/webhooks/%s/%s"):format(id, token) end

    return nil
end

local function webhookSink(envelope, route)
    local url = trim(route.target)

    if not url or not url:match("^https://") then return end

    local queue = webhookQueue[url]

    if not queue then
        queue = {}
        webhookQueue[url] = queue
    end

    if #queue >= MAX_QUEUE then return end

    queue[#queue + 1] = embedOf(envelope, route)
end

local SINKS = {
    webhook = webhookSink,
}

function Actions.emit(script, name, data)
    if type(script) ~= "string" or script == "" then return false end

    name = trim(name)

    if not name then return false end

    if type(data) ~= "table" then data = data ~= nil and { value = data } or {} end

    local source = tonumber(data.source) or tonumber(data.src)
    local account, character = GGName.of(source)

    local envelope = {
        full       = script .. ":" .. name,
        script     = script,
        action     = name,
        source     = source,
        -- Resolved wins. A caller may still supply one for a player who has
        -- already left, which is the only case the bridge cannot answer.
        identifier = GGName.identifier(source) or data.identifier,
        player     = account,
        character  = character,
        at         = os.time(),
        data       = data,
    }

    for index = 1, #subscribers do
        local sub = subscribers[index]

        if matches(sub.pattern, script, name) then
            local ok, err = pcall(sub.fn, envelope)

            if not ok then
                print(("^3[gg_lib] action listener from %s errored on %s: %s^0"):format(sub.resource, envelope.full, err))
            end
        end
    end

    if type(GGHooks) == "table" then
        local hook = GGHooks[envelope.full]

        if type(hook) == "function" then
            local ok, err = pcall(hook, Actions.payload(envelope))

            if not ok then
                print(("^1[gg_lib] hooks/server.lua errored on %s: %s^0"):format(envelope.full, err))
            end
        end
    end

    pcall(databaseSink, envelope)

    for index = 1, #routes do
        local route = routes[index]

        if route.enabled and matches(route.action, script, name) then
            local sink = SINKS[route.kind]

            if sink then pcall(sink, envelope, route) end
        end
    end

    return true
end

exports("ggAction", function(name, data)
    local script = GetInvokingResource() or RESOURCE

    return Actions.emit(script, name, data)
end)

exports("ggOnAction", function(pattern, fn)
    if type(pattern) ~= "string" or type(fn) ~= "function" then return false end

    subscribers[#subscribers + 1] = {
        pattern  = pattern,
        fn       = fn,
        resource = GetInvokingResource() or RESOURCE,
    }

    return true
end)

exports("ggActionList", function()
    local out = {}

    for _, full in ipairs(order) do out[#out + 1] = registry[full] end

    return out
end)

AddEventHandler("onResourceStop", function(script)
    for index = #subscribers, 1, -1 do
        if subscribers[index].resource == script then table.remove(subscribers, index) end
    end
end)

local function flushLog()
    if #logQueue == 0 then return end

    local batch = logQueue
    logQueue = {}

    local queries = {}

    for index = 1, #batch do
        queries[#queries + 1] = {
            query = [[
                INSERT INTO gg_studio_action_log (resource, action, source, identifier, player, character_name, data)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ]],
            values = batch[index],
        }
    end

    local ok, err = pcall(function() return MySQL.transaction.await(queries) end)

    if not ok then
        print(("^3[gg_lib] could not record %d action(s): %s^0"):format(#queries, err))
    end
end

local function post(url, embeds, attempt)
    local body = json.encode({
        username   = GenericSettings and GenericSettings.get and GenericSettings.get("actions.webhook_name") or "GG Studio",
        avatar_url = GenericSettings and GenericSettings.get and GenericSettings.get("actions.webhook_avatar") or nil,
        embeds     = embeds,
    })

    PerformHttpRequest(url, function(status, _, headers)
        if status == 429 then
            local wait = tonumber(headers and (headers["retry-after"] or headers["Retry-After"])) or 5

            backoffUntil = GetGameTimer() + math.floor(wait * 1000) + 250

            if (attempt or 1) < 3 then
                SetTimeout(math.floor(wait * 1000) + 250, function() post(url, embeds, (attempt or 1) + 1) end)
            end

            return
        end

        if status ~= 200 and status ~= 204 then
            print(("^3[gg_lib] action webhook returned %s^0"):format(tostring(status)))
        end
    end, "POST", body, { ["Content-Type"] = "application/json" })
end

local function flushWebhooks()
    if GetGameTimer() < backoffUntil then return end

    for url, embeds in pairs(webhookQueue) do
        if #embeds > 0 then
            local batch = {}

            for index = 1, math.min(#embeds, MAX_EMBEDS) do batch[index] = embeds[index] end

            for _ = 1, #batch do table.remove(embeds, 1) end

            post(url, batch, 1)
        end

        if #embeds == 0 then webhookQueue[url] = nil end
    end
end

CreateThread(function()
    while true do
        Wait(FLUSH_MS)

        pcall(flushLog)
        pcall(flushWebhooks)
    end
end)

local trimPending = false

local function trimLog()
    if trimPending then return end

    trimPending = true

    SetTimeout(5000, function()
        trimPending = false

        pcall(MySQL.query.await,
            "DELETE FROM gg_studio_action_log WHERE fired_at < (NOW() - INTERVAL ? DAY)",
            { retentionDays() })

        pcall(MySQL.query.await, [[
            DELETE FROM gg_studio_action_log
            WHERE id <= (
                SELECT id FROM (
                    SELECT id FROM gg_studio_action_log ORDER BY id DESC LIMIT 1 OFFSET ?
                ) AS cutoff
            )
        ]], { KEEP_ROWS })
    end)
end

CreateThread(function()
    while true do
        Wait(6 * 60 * 60 * 1000)
        trimLog()
    end
end)

function Actions.describe()
    local declared = {}

    for _, full in ipairs(order) do
        local entry = registry[full]

        declared[#declared + 1] = {
            full   = entry.full,
            script = entry.script,
            action = entry.action,
            label  = entry.label,
            help   = entry.help,
            fields = entry.fields,
            hooked = type(GGHooks) == "table" and type(GGHooks[entry.full]) == "function" or false,
        }
    end

    local listeners = {}

    for index = 1, #subscribers do
        listeners[#listeners + 1] = { pattern = subscribers[index].pattern, resource = subscribers[index].resource }
    end

    return declared, routes, listeners
end

GGCallback.register("gg_lib:actions:saveRoute", function(source, route)
    if not Admins.can(source, "logs") then return false end
    if type(route) ~= "table" then return false end

    local action = trim(route.action)
    local kind   = trim(route.kind)

    if not action or not kind or not KINDS[kind] then return false end

    local target = Actions.webhookUrl(route.target)

    if kind == "webhook" and not target then
        return false, { err = "That is not a webhook address or key" }
    end

    local label   = trim(route.label)
    local message = trim(route.message)
    local enabled = route.enabled ~= false and 1 or 0
    local actor   = Admins.actor(source)

    local ok, err = pcall(function()
        if route.id then
            MySQL.update.await(
                "UPDATE gg_studio_action_routes SET action = ?, kind = ?, label = ?, target = ?, message = ?, enabled = ? WHERE id = ?",
                { action, kind, label, target, message, enabled, route.id })
        else
            MySQL.insert.await(
                "INSERT INTO gg_studio_action_routes (action, kind, label, target, message, enabled, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)",
                { action, kind, label, target, message, enabled, actor })
        end
    end)

    if not ok then return false, { err = tostring(err) } end

    Actions.loadRoutes()

    return true, { routes = routes }
end)

GGCallback.register("gg_lib:actions:deleteRoute", function(source, id)
    if not Admins.can(source, "logs") then return false end
    if not tonumber(id) then return false end

    local ok = pcall(MySQL.query.await, "DELETE FROM gg_studio_action_routes WHERE id = ?", { tonumber(id) })

    if not ok then return false end

    Actions.loadRoutes()

    return true, { routes = routes }
end)

GGCallback.register("gg_lib:actions:test", function(source, id)
    if not Admins.can(source, "logs") then return false end

    local target

    for index = 1, #routes do
        if routes[index].id == tonumber(id) then target = routes[index] end
    end

    if not target then return false end

    local envelope = {
        full       = "gg_lib:studio.test",
        script     = "gg_lib",
        action     = "studio.test",
        source     = source,
        identifier = GGName.identifier(source),
        player     = GetPlayerName(source),
        at         = os.time(),
        data       = { sent_by = Admins.actor(source), route = target.label or target.kind },
    }

    local sink = SINKS[target.kind]

    if not sink then return false end

    pcall(sink, envelope, target)

    pcall(flushLog)
    pcall(flushWebhooks)

    return true
end)

GGCallback.register("gg_lib:actions:setRetention", function(source, days)
    if not Admins.can(source, "logs") then return false end

    local ok = GenericSettings.apply(
        { ["actions.retention_days"] = math.floor(tonumber(days) or DEFAULT_RETENTION_DAYS) },
        Admins.actor(source))

    if ok then trimLog() end

    return ok == true
end)
