
Logs = {}

local KEEP_ROWS = 5000
local DEFAULT_DAYS = 14

local trim_pending = false

local function retentionDays()
    local stored = GenericSettings and GenericSettings.get and GenericSettings.get("logs.retention_days")

    return math.max(math.floor(tonumber(stored) or DEFAULT_DAYS), 1)
end

local function trim()
    if trim_pending then return end
    trim_pending = true

    SetTimeout(5000, function()
        trim_pending = false

        pcall(MySQL.query.await,
            "DELETE FROM gg_studio_log WHERE changed_at < (NOW() - INTERVAL ? DAY)",
            { retentionDays() })

        pcall(MySQL.query.await, [[
            DELETE FROM gg_studio_log
            WHERE id <= (
                SELECT id FROM (
                    SELECT id FROM gg_studio_log ORDER BY id DESC LIMIT 1 OFFSET ?
                ) AS cutoff
            )
        ]], { KEEP_ROWS })
    end)
end

CreateThread(function()
    while true do
        Wait(6 * 60 * 60 * 1000)
        trim()
    end
end)

local MAX_VALUE = 4000

local function encode(value)
    if value == nil then return nil end

    local ok, encoded = pcall(json.encode, { v = value })
    if not ok then return nil end

    if #encoded > MAX_VALUE then
        local size = type(value) == "table" and #value or 0
        local summary = size > 0 and ("%d entries"):format(size) or "too large to record"

        encoded = json.encode({ v = ("<%s>"):format(summary) })
    end

    return encoded
end

function Logs.write(rows, actor)
    if type(rows) ~= "table" or #rows == 0 then return false end

    local queries = {}

    for index = 1, #rows do
        local row = rows[index]

        if type(row) == "table" and type(row.resource) == "string" and type(row.path) == "string" then
            queries[#queries + 1] = {
                query = [[
                    INSERT INTO gg_studio_log (resource, path, action, old_value, new_value, actor)
                    VALUES (?, ?, ?, ?, ?, ?)
                ]],
                values = {
                    row.resource,
                    row.path,
                    row.action or "change",
                    encode(row.old),
                    encode(row.new),
                    actor or row.actor or "unknown",
                },
            }
        end
    end

    if #queries == 0 then return false end

    local ok, err = pcall(function()
        return MySQL.transaction.await(queries)
    end)

    if not ok then
        print(("^3[gg_lib] could not write %d log row(s): %s^0"):format(#queries, err))
        return false
    end

    trim()

    return true
end

exports("ggLogChange", function(rows, actor)
    local invoker = GetInvokingResource()

    if invoker then
        for index = 1, #(rows or {}) do
            if type(rows[index]) == "table" then rows[index].resource = invoker end
        end
    end

    return Logs.write(rows, actor)
end)

local function decode(raw)
    if raw == nil then return nil end

    local ok, wrapper = pcall(json.decode, raw)
    if not ok or type(wrapper) ~= "table" then return nil end

    return wrapper.v
end

local PREVIEW_MAX = 120

local function preview(value)
    if value == nil then return nil end

    local kind = type(value)
    local text

    if kind == "boolean" then
        text = value and "On" or "Off"
    elseif kind == "number" or kind == "string" then
        text = tostring(value)
    else
        local ok, encoded = pcall(json.encode, value)
        text = ok and encoded or "?"
    end

    if #text > PREVIEW_MAX then return text:sub(1, PREVIEW_MAX - 3) .. "..." end

    return text
end

local function expand(value)
    if value == nil then return nil end

    local kind = type(value)

    if kind == "boolean" then return value and "On" or "Off" end
    if kind == "number" or kind == "string" then return tostring(value) end

    local ok, encoded = pcall(json.encode, value, { indent = true })
    if not ok then return "?" end

    return encoded
end

local PAGE_SIZE = 25
local MAX_PAGE_SIZE = 100

local SETTING_SELECT = [[
    SELECT 'setting' AS kind, id, resource, path AS subject, action AS event,
           actor AS who, NULL AS character_name, NULL AS identifier, old_value, new_value, NULL AS data,
           changed_at AS at
    FROM gg_studio_log
]]

local ACTION_SELECT = [[
    SELECT 'action' AS kind, id, resource, action AS subject, 'fired' AS event,
           player AS who, character_name, identifier, NULL AS old_value, NULL AS new_value, data,
           fired_at AS at
    FROM gg_studio_action_log
]]

local function filters(opts)
    local search   = type(opts.search) == "string" and opts.search:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local resource = type(opts.resource) == "string" and opts.resource ~= "" and opts.resource or nil
    local kind     = type(opts.kind) == "string" and opts.kind ~= "" and opts.kind or nil

    if search == "" then search = nil end

    local settingWhere, settingArgs = {}, {}
    local actionWhere,  actionArgs  = {}, {}

    if resource then
        settingWhere[#settingWhere + 1] = "resource = ?"
        settingArgs[#settingArgs + 1] = resource

        actionWhere[#actionWhere + 1] = "resource = ?"
        actionArgs[#actionArgs + 1] = resource
    end

    if search then
        local like = "%" .. search .. "%"

        settingWhere[#settingWhere + 1] = "(actor LIKE ? OR resource LIKE ? OR path LIKE ?)"

        for _ = 1, 3 do settingArgs[#settingArgs + 1] = like end

        actionWhere[#actionWhere + 1] = "(player LIKE ? OR identifier LIKE ? OR resource LIKE ? OR action LIKE ?)"

        for _ = 1, 4 do actionArgs[#actionArgs + 1] = like end
    end

    local function clause(where)
        return #where > 0 and (" WHERE " .. table.concat(where, " AND ")) or ""
    end

    local parts, args = {}, {}

    if kind ~= "action" then
        parts[#parts + 1] = SETTING_SELECT .. clause(settingWhere)
        for index = 1, #settingArgs do args[#args + 1] = settingArgs[index] end
    end

    if kind ~= "setting" then
        parts[#parts + 1] = ACTION_SELECT .. clause(actionWhere)
        for index = 1, #actionArgs do args[#args + 1] = actionArgs[index] end
    end

    return table.concat(parts, " UNION ALL "), args
end

function Logs.page(opts)
    opts = type(opts) == "table" and opts or {}

    local size   = math.min(math.max(tonumber(opts.size) or PAGE_SIZE, 1), MAX_PAGE_SIZE)
    local page   = math.max(math.floor(tonumber(opts.page) or 1), 1)
    local offset = (page - 1) * size

    local merged, args = filters(opts)

    local rowArgs = {}
    for index = 1, #args do rowArgs[index] = args[index] end
    rowArgs[#rowArgs + 1] = size
    rowArgs[#rowArgs + 1] = offset

    local ok, rows = pcall(MySQL.query.await, ([[
        SELECT kind, id, resource, subject, event, who, character_name, identifier, old_value, new_value, data,
               DATE_FORMAT(at, '%%Y-%%m-%%d %%H:%%i') AS at
        FROM (%s) AS merged
        ORDER BY at DESC, id DESC
        LIMIT ? OFFSET ?
    ]]):format(merged), rowArgs)

    if not ok then return {}, 0, {}, {}, {} end

    local counted, total = pcall(MySQL.scalar.await,
        ("SELECT COUNT(*) FROM (%s) AS merged"):format(merged), args)

    -- The rail has to keep showing every script while one of them is selected,
    -- so its tallies are built without the script filter -- but still inside the
    -- section and the search, or the numbers would not match what a click gives.
    local wide, wideArgs = filters({ search = opts.search, kind = opts.kind })

    local tallied, tallies = pcall(MySQL.query.await,
        ("SELECT resource, COUNT(*) AS n FROM (%s) AS merged GROUP BY resource ORDER BY n DESC"):format(wide), wideArgs)

    local listedActors, actors = pcall(MySQL.query.await, [[
        SELECT DISTINCT actor AS who FROM gg_studio_log
        WHERE actor IS NOT NULL AND actor <> '' ORDER BY who
    ]])

    local listedPlayers, players = pcall(MySQL.query.await, [[
        SELECT DISTINCT player AS who FROM gg_studio_action_log
        WHERE player IS NOT NULL AND player <> '' ORDER BY who
    ]])

    local listedScripts, scripts = pcall(MySQL.query.await, [[
        SELECT resource FROM (
            SELECT DISTINCT resource FROM gg_studio_log
            UNION
            SELECT DISTINCT resource FROM gg_studio_action_log
        ) AS everything ORDER BY resource
    ]])

    local actorNames, playerNames = {}, {}

    if listedActors then
        for _, row in ipairs(actors or {}) do actorNames[#actorNames + 1] = row.who end
    end

    if listedPlayers then
        for _, row in ipairs(players or {}) do playerNames[#playerNames + 1] = row.who end
    end

    local counts = {}

    if tallied then
        for _, row in ipairs(tallies or {}) do counts[row.resource] = row.n end
    end

    local resources = {}

    if listedScripts then
        for _, row in ipairs(scripts or {}) do
            resources[#resources + 1] = { name = row.resource, n = counts[row.resource] or 0 }
        end
    end

    local out = {}

    for _, row in ipairs(rows or {}) do
        local old, new = decode(row.old_value), decode(row.new_value)

        out[#out + 1] = {
            key        = row.kind .. ":" .. tostring(row.id),
            kind       = row.kind,
            id         = row.id,
            resource   = row.resource,
            subject    = row.subject,
            event      = row.event,
            who        = row.who,
            character  = row.character_name,
            identifier = row.identifier,
            data       = row.data,
            at         = row.at,
            old        = preview(old),
            new        = preview(new),
            old_full   = expand(old),
            new_full   = expand(new),
        }
    end

    return out, counted and total or 0, actorNames, playerNames, resources
end

GGCallback.register("gg_lib:logs:fetch", function(source, data)
    if not Admins.can(source, "logs") then
        print(("^3[gg_lib] blocked log fetch from %s^0"):format(Admins.actor(source)))
        return false
    end

    local rows, total, actorNames, playerNames, resources = Logs.page(data)

    local declared, routes = {}, {}

    if Actions and Actions.describe then
        local ok, a, r = pcall(Actions.describe)

        if ok then
            declared = a or {}
            routes   = r or {}
        end
    end

    return true, {
        rows      = rows,
        total     = total,
        actors    = actorNames,
        players   = playerNames,
        scripts   = resources,
        actions   = declared,
        routes    = routes,
        retention = retentionDays(),
    }
end)

GGCallback.register("gg_lib:logs:setRetention", function(source, days)
    if not Admins.can(source, "logs") then return false end

    local ok = GenericSettings.apply({ ["logs.retention_days"] = math.floor(tonumber(days) or DEFAULT_DAYS) }, Admins.actor(source))

    if ok then trim() end

    return ok == true
end)
