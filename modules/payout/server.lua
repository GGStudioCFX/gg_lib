local payout = gg.payout

-- MARK: Server: the ledger
--
-- A job calls gg.payout.setup once, then gg.payout.add when a job is done. The worker's
-- game asks for its pay through "<resource>:payout:collect" at a table or the depot ped;
-- the server checks they stand at one of the job's pay points, clears the ledger first
-- and pays through the job's own `pay` function. Calls answer { ok = true, ... } or
-- { ok = false, error = code }. Codes: not_ready, nothing_owed, too_far, busy, failed.

local RESOURCE = GetCurrentResourceName()

local options = nil
local ready = false
local cache = {}  -- [identifier] = { money, experience, count, data }
local busy = {}   -- [identifier] = true while a collection is paying

local function empty()
    return { money = 0, experience = 0, count = 0, data = {} }
end

local function prepare()
    if ready then return true end

    local ok, err = pcall(function()
        MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS `gg_studio_job_payouts` (
            `identifier` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `job` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `money` BIGINT NOT NULL DEFAULT 0,
            `experience` BIGINT NOT NULL DEFAULT 0,
            `count` INT NOT NULL DEFAULT 0,
            `data` LONGTEXT NULL COLLATE 'utf8mb4_general_ci',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `job`) USING BTREE
        )
        COLLATE='utf8mb4_general_ci'
        ENGINE=InnoDB;
        ]=])
    end)

    if not ok then
        gg.print.error(("Pay table ledger unavailable: %s"):format(err))

        return false
    end

    ready = true

    return true
end

local function jobKey()
    return options and options.job or RESOURCE
end

local function identifierOf(target)
    if type(target) == "string" then return target end

    local ok, identifier = pcall(gg.framework.GetIdentifier, target)

    return ok and identifier or nil
end

local function load(identifier)
    local entry = cache[identifier]
    if entry then return entry end

    entry = empty()

    if prepare() then
        local row = MySQL.single.await(
            "SELECT money, experience, count, data FROM gg_studio_job_payouts WHERE identifier = ? AND job = ?",
            { identifier, jobKey() }
        )

        if row then
            local data = type(row.data) == "string" and json.decode(row.data) or nil

            entry = {
                money      = math.max(0, math.floor(tonumber(row.money) or 0)),
                experience = math.max(0, math.floor(tonumber(row.experience) or 0)),
                count      = math.max(0, math.floor(tonumber(row.count) or 0)),
                data       = type(data) == "table" and data or {},
            }
        end
    end

    -- Another call may have loaded it while this one waited on the database.
    cache[identifier] = cache[identifier] or entry

    return cache[identifier]
end

local function save(identifier, entry)
    if not prepare() then return false end

    local ok, err = pcall(MySQL.query.await, [=[
        INSERT INTO gg_studio_job_payouts (identifier, job, money, experience, count, data)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE money = VALUES(money), experience = VALUES(experience),
            count = VALUES(count), data = VALUES(data)
    ]=], {
        identifier, jobKey(), entry.money, entry.experience, entry.count, json.encode(entry.data or {}),
    })

    if not ok then gg.print.error(("Could not save the pay owed to %s: %s"):format(identifier, tostring(err))) end

    return ok
end

local function view(entry)
    return { money = entry.money, experience = entry.experience, count = entry.count }
end

local function push(source, entry)
    if type(source) ~= "number" or source <= 0 then return end

    TriggerClientEvent(("%s:payout:owed"):format(RESOURCE), source, view(entry))
end

local function sourceOf(identifier)
    for _, player in ipairs(GetPlayers()) do
        local id = tonumber(player)

        if id and identifierOf(id) == identifier then return id end
    end
end

--------------------------------------------------
-- MARK: Setup
--------------------------------------------------

--- Sets the job's pay table up. Call once at boot.
---@param opts table
---   job      string    the ledger key (default: the resource name)
---   pay      function(source, owed) -> paid table | false, error   pays money, experience and the rest
---   points   function(source) -> { { id, x, y, z, mode } }           where pay can be collected
---   reach    number    metres from a point that count as there (default 4.0)
---   collected function(source, result)                              after a collection, for counters
function payout.setup(opts)
    if type(opts) ~= "table" or type(opts.pay) ~= "function" then
        error("gg.payout.setup wants a table with a pay function", 2)
    end

    options = opts

    CreateThread(prepare)
end

--- What a worker is owed. `target` is a source or an identifier.
---@return table { money, experience, count }
function payout.owed(target)
    local identifier = identifierOf(target)
    if not identifier then return view(empty()) end

    return view(load(identifier))
end

--- Adds a finished job to the ledger, or pays it at once.
---@param target number|string source or identifier
---@param entry table { money, experience, count = 1, data = { key = number } }
---@param how table|nil { instant = true } pays now through the job's pay function
---@return table { owed = {...} } or { paid = result } or { ok = false, error }
function payout.add(target, entry, how)
    if not options then return { ok = false, error = "not_ready" } end

    entry = type(entry) == "table" and entry or {}

    local money = math.max(0, math.floor(tonumber(entry.money) or 0))
    local experience = math.max(0, math.floor(tonumber(entry.experience) or 0))
    local count = math.max(0, math.floor(tonumber(entry.count) or 1))

    if how and how.instant then
        local source = type(target) == "number" and target or sourceOf(target)

        if not source then return { ok = false, error = "failed" } end

        local paid, err = options.pay(source, { money = money, experience = experience, count = count, data = entry.data or {} })

        if not paid then return { ok = false, error = err or "failed" } end

        return { ok = true, paid = paid }
    end

    local identifier = identifierOf(target)
    if not identifier then return { ok = false, error = "failed" } end

    local owed = load(identifier)

    owed.money = owed.money + money
    owed.experience = owed.experience + experience
    owed.count = owed.count + count

    for key, value in pairs(type(entry.data) == "table" and entry.data or {}) do
        if type(value) == "number" then owed.data[key] = (tonumber(owed.data[key]) or 0) + value end
    end

    save(identifier, owed)
    push(type(target) == "number" and target or sourceOf(identifier), owed)

    return { ok = true, owed = view(owed) }
end

local function atPoint(source, pointId)
    if type(options.points) ~= "function" then return true end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local here = GetEntityCoords(ped)
    local reach = tonumber(options.reach) or 4.0

    for _, point in ipairs(options.points(source) or {}) do
        if (pointId == nil or point.id == pointId) and point.mode ~= "instant" then
            if #(here - vector3(point.x + 0.0, point.y + 0.0, point.z + 0.0)) <= reach then return true end
        end
    end

    return false
end

--- Pays out everything owed, if the worker stands at a pay point (or `anywhere` is set,
--- for a job that pays the crew as it hands the vehicle back).
function payout.collect(source, pointId, anywhere)
    if not options then return { ok = false, error = "not_ready" } end

    local identifier = identifierOf(source)
    if not identifier then return { ok = false, error = "failed" } end
    if busy[identifier] then return { ok = false, error = "busy" } end

    local owed = load(identifier)

    if owed.count <= 0 and owed.money <= 0 and owed.experience <= 0 then return { ok = false, error = "nothing_owed" } end
    if not anywhere and not atPoint(source, pointId) then return { ok = false, error = "too_far" } end

    busy[identifier] = true

    -- Cleared before anything is paid, so a second ask finds nothing.
    local taken = { money = owed.money, experience = owed.experience, count = owed.count, data = owed.data }

    cache[identifier] = empty()
    save(identifier, cache[identifier])

    local ok, paid, err = pcall(options.pay, source, taken)

    if not ok or not paid then
        -- Put it back so nothing is lost.
        local now = load(identifier)

        now.money = now.money + taken.money
        now.experience = now.experience + taken.experience
        now.count = now.count + taken.count

        for key, value in pairs(taken.data or {}) do
            if type(value) == "number" then now.data[key] = (tonumber(now.data[key]) or 0) + value end
        end

        save(identifier, now)
        busy[identifier] = nil

        if not ok then gg.print.error(("Paying %s failed: %s"):format(identifier, tostring(paid))) end

        return { ok = false, error = (ok and err) or "failed" }
    end

    busy[identifier] = nil

    push(source, cache[identifier])

    local result = type(paid) == "table" and paid or {}

    result.ok = true
    result.count = result.count or taken.count
    result.money = result.money or taken.money
    result.experience = result.experience or taken.experience

    if type(options.collected) == "function" then
        local fine, failure = pcall(options.collected, source, result, taken)

        if not fine then gg.print.error(("gg.payout collected hook failed: %s"):format(tostring(failure))) end
    end

    return result
end

--------------------------------------------------
-- MARK: Callbacks
--------------------------------------------------

gg.callback.register(("%s:payout:owed"):format(RESOURCE), function(source)
    return payout.owed(source)
end)

gg.callback.register(("%s:payout:collect"):format(RESOURCE), function(source, pointId)
    return payout.collect(source, type(pointId) == "number" and pointId or nil)
end)

AddEventHandler("playerDropped", function()
    local identifier = identifierOf(source)

    if identifier and not busy[identifier] then cache[identifier] = nil end
end)
