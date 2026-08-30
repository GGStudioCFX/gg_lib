
Daily = {}

local DAY = 86400

local every = 0

local MAX_SLEEP = 60

local function say(message)
    print(("[gg_lib] %s"):format(message))
end

local function warn(message)
    print(("^3[gg_lib] %s^0"):format(message))
end

local tasks   = {}   -- resource -> true
local handled = {}   -- resource -> the last boundary it dealt with
local ready   = false

local function resetClock()
    local clock = GenericSettings and GenericSettings.get and GenericSettings.get("reset.daily_time") or "00:00"
    local zone  = GenericSettings and GenericSettings.get and GenericSettings.get("reset.timezone")

    local hour, minute = tostring(clock):match("^(%d%d?):(%d%d)$")

    return tonumber(hour) or 0, tonumber(minute) or 0, (settings.timezones or {})[zone] or 0
end

function Daily.boundaryAt(now)
    if every > 0 then return now - (now % every) end

    local hour, minute, offset = resetClock()

    local zoned  = now + offset
    local intoDay = zoned % DAY
    local target  = (hour * 3600) + (minute * 60)

    local due = zoned - intoDay + target

    if intoDay < target then due = due - DAY end

    return due - offset
end

function Daily.nextAt(now)
    now = now or os.time()

    return Daily.boundaryAt(now) + (every > 0 and every or DAY)
end

function Daily.lastAt(now)
    now = now or os.time()

    return Daily.boundaryAt(now)
end

function Daily.secondsUntil(now)
    now = now or os.time()

    return math.max(0, Daily.nextAt(now) - now)
end

local function ensureTable()
    MySQL.query.await([=[
    CREATE TABLE IF NOT EXISTS `gg_studio_daily` (
        `resource` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
        `last_run` BIGINT NOT NULL DEFAULT 0,
        `ran_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`resource`) USING BTREE
    )
    COLLATE='utf8mb4_general_ci'
    ENGINE=InnoDB
    ROW_FORMAT=DYNAMIC;
    ]=])
end

local function loadHandled()
    local rows = MySQL.query.await("SELECT resource, last_run FROM gg_studio_daily")

    for _, row in ipairs(rows or {}) do
        handled[row.resource] = tonumber(row.last_run) or 0
    end
end

local function remember(resource, boundary)
    handled[resource] = boundary

    MySQL.query.await([[
        INSERT INTO gg_studio_daily (resource, last_run) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE last_run = VALUES(last_run)
    ]], { resource, boundary })
end

local function publish()
    local now = os.time()

    GlobalState.gg_daily = {
        next = Daily.nextAt(now),
        at   = now,
    }
end

local function run(resource, boundary)
    if GetResourceState(resource) ~= "started" then return false end

    local ok, accepted = pcall(function()
        return exports[resource]:ggDailyRun(boundary)
    end)

    if not ok then
        warn(("Daily reset for %s failed: %s"):format(resource, accepted))
        return false
    end

    if accepted == false then
        warn(("Daily reset for %s reported a problem; it will be tried again"):format(resource))
        return false
    end

    remember(resource, boundary)

    return true
end

local function catchUp(boundary)
    local ran = 0

    for resource in pairs(tasks) do
        local last = handled[resource]

        if last and last < boundary then
            if run(resource, boundary) then ran = ran + 1 end
        end
    end

    if ran > 0 then
        say(("Daily reset ran for %d script(s)"):format(ran))
        TriggerEvent("gg_lib:daily:reset", boundary)
    end

    return ran
end

local function register(resource)
    if not resource or tasks[resource] then return end

    tasks[resource] = true

    if not ready then return end

    local boundary = Daily.boundaryAt(os.time())

    if handled[resource] == nil then
        remember(resource, boundary)
        return
    end

    if handled[resource] < boundary then run(resource, boundary) end
end

exports("ggDailyRegister", function()
    register(GetInvokingResource())

    return true
end)

exports("ggDailyNext", function()
    return Daily.nextAt()
end)

exports("ggDailySecondsUntil", function()
    return Daily.secondsUntil()
end)

exports("ggDailyLast", function()
    return Daily.lastAt()
end)

function Daily.force()
    local boundary = Daily.boundaryAt(os.time())
    local ran = 0

    for resource in pairs(tasks) do
        if run(resource, boundary) then ran = ran + 1 end
    end

    if ran > 0 then TriggerEvent("gg_lib:daily:reset", boundary) end

    return ran
end

exports("ggDailyForce", function()
    return Daily.force()
end)

AddEventHandler("gg_lib:database:ready", function()
    ensureTable()
    loadHandled()

    ready = true

    for resource in pairs(tasks) do
        if handled[resource] == nil then
            remember(resource, Daily.boundaryAt(os.time()))
        end
    end

    publish()

    CreateThread(function()
        while true do
            local now      = os.time()
            local boundary = Daily.boundaryAt(now)

            catchUp(boundary)
            publish()

            local remaining = math.max(1, Daily.nextAt(now) - now)

            Wait(math.min(remaining, MAX_SLEEP) * 1000)
        end
    end)
end)

AddEventHandler("gg_lib:generic:changed", function(changed)
    for _, path in ipairs(changed or {}) do
        if path == "reset.daily_time" or path == "reset.timezone" then
            publish()
            return
        end
    end
end)

RegisterCommand("gg_daily_reset", function(source)
    if source ~= 0 and not Admins.can(source, "manage_admins") then return end

    local ran = Daily.force()

    print(("[gg_lib] daily reset ran for %d script(s)"):format(ran))
end, true)

RegisterCommand("gg_daily_status", function(source)
    if source ~= 0 and not Admins.can(source, "manage_admins") then return end

    local now = os.time()
    local last = Daily.lastAt(now)
    local nextAt = Daily.nextAt(now)

    print(("[gg_lib] daily clock: %s | last boundary %d (%ds ago) | next %d (in %ds)"):format(
        every > 0 and ("development, every %d minute(s)"):format(every / 60) or "real day",
        last, now - last, nextAt, nextAt - now
    ))

    for resource in pairs(tasks) do
        local done = handled[resource]

        print(("[gg_lib]   %s: handled boundary %s -- %s"):format(
            resource,
            tostring(done),
            (done and done >= last) and "up to date" or "BEHIND: will reset on the next pass"
        ))
    end
end, true)

RegisterCommand("gg_daily_every", function(source, args)
    if source ~= 0 and not Admins.can(source, "manage_admins") then return end

    local minutes = math.max(0, tonumber(args and args[1]) or 0)

    every = math.floor(minutes * 60)

    for resource in pairs(tasks) do
        handled[resource] = Daily.boundaryAt(os.time())
    end

    publish()

    if every > 0 then
        print(("[gg_lib] daily reset now every %d minute(s) -- development clock, until restart"):format(minutes))
    else
        print("[gg_lib] daily reset back on the real clock")
    end
end, true)
