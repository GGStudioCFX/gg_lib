gg.jobs = gg.jobs or {}

-- MARK: One progress engine for every GG job
--
-- The other half of the jobs kit's shared layer (gg.jobprofile keeps the profile). Every
-- GG job counts what its workers do here and gets the same four things from it: daily
-- challenges (with rerolls, a bonus for finishing them all and a streak), weekly
-- challenges in three milestones, a competition (a month or a week long) whose places
-- earn a title and, if the owner wants, a small prize, and achievements in tiers. The
-- tablets draw them the same way, so a worker who knows one job knows them all.
--
-- Bonus days (def.boost, gg.jobs.boost) multiply what a job pays for its work on the
-- weekdays the owner picks, weekends by default, so every job runs them on one rule.
--
-- It also keeps each player's face (gg.jobs.saveFace): a small picture the tablet takes
-- when it opens, shared by every job, so boards show faces of players far away or off.
--
-- A job describes itself with gg.jobs.register (again whenever the owner saves its
-- settings) and counts with gg.jobs.track. The engine answers the rest: the pages
-- (gg.jobs.payload), claims, rerolls and each week's results. Rewards are paid by the job
-- (def.pay), in its own money, experience and currency.
--
-- The module runs inside the job's own resource (gg_lib modules load into the caller),
-- so a job only writes its own rows. The tables are shared, so one place can read every
-- job: gg.jobs.directory, gg.jobs.summary and gg.jobs.standings (a city hall, a phone app).
--
-- Days follow gg_lib's daily reset; a week is seven of those days from compete.starts
-- (0 = Monday), a month runs from its first day's reset. Nothing is wiped: a new day,
-- week or competition rolls over the next time a row is read, and lifetime counts only
-- grow. The competition tables keep their `week` column for any period: a week is its
-- number since 1970 (about 2,960 in 2026), a month is year * 100 + month (202611).

local DAY = 86400
local FLUSH_EVERY = 15000
local SETTLE_EVERY = 60000
local BOARD_SIZE = 50
local FACE_MAX = 48000      -- characters of a face's data URL (a 112 px WebP is about 6,000)
local FACE_EVERY = 30       -- seconds between one player's face saves
local FACE_KEEP_DAYS = 90   -- a face nobody refreshed in this long is deleted

-- A weekly challenge pays a part of its reward at a third, two thirds and the goal.
gg.jobs.MILESTONES = {
    { at = 1 / 3, share = 0.2 },
    { at = 2 / 3, share = 0.3 },
    { at = 1,     share = 0.5 },
}

-- Counters the engine keeps itself; achievements can count them like any other.
--   dailies   daily challenges claimed       sweeps    days every daily was claimed
--   weeklies  weekly challenges finished     streak    the best run of swept days
--   podiums   top three finishes             prizes    any titled place in a competition
--   champions competitions won
gg.jobs.ENGINE = { "dailies", "sweeps", "weeklies", "streak", "podiums", "prizes", "champions" }

local MILESTONES = gg.jobs.MILESTONES

-- MARK: Tables

local ready = false

local function prepare()
    if ready then return true end

    local ok, err = pcall(function()
        MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS `gg_studio_jobs` (
            `job` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `data` LONGTEXT NULL COLLATE 'utf8mb4_general_ci',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`job`) USING BTREE
        ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]=])

        MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS `gg_studio_job_stats` (
            `identifier` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `job` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `name` VARCHAR(100) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
            `lifetime` LONGTEXT NULL COLLATE 'utf8mb4_general_ci',
            `day` BIGINT NOT NULL DEFAULT 0,
            `daily` LONGTEXT NULL COLLATE 'utf8mb4_general_ci',
            `week` INT NOT NULL DEFAULT 0,
            `weekly` LONGTEXT NULL COLLATE 'utf8mb4_general_ci',
            `streak` INT NOT NULL DEFAULT 0,
            `best_streak` INT NOT NULL DEFAULT 0,
            `streak_day` BIGINT NOT NULL DEFAULT 0,
            `claims` LONGTEXT NULL COLLATE 'utf8mb4_general_ci',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `job`) USING BTREE,
            KEY `idx_job` (`job`)
        ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]=])

        MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS `gg_studio_job_compete` (
            `job` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `week` INT NOT NULL,
            `identifier` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `name` VARCHAR(100) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
            `value` BIGINT NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`job`, `week`, `identifier`) USING BTREE,
            KEY `idx_board` (`job`, `week`, `value`)
        ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]=])

        MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS `gg_studio_job_weeks` (
            `job` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `week` INT NOT NULL,
            `counter` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `settled` TINYINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`job`, `week`) USING BTREE
        ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]=])

        MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS `gg_studio_job_results` (
            `job` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `week` INT NOT NULL,
            `place` INT NOT NULL,
            `identifier` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `name` VARCHAR(100) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
            `value` BIGINT NOT NULL DEFAULT 0,
            `reward` LONGTEXT NULL COLLATE 'utf8mb4_general_ci',
            `claimed` TINYINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`job`, `week`, `place`) USING BTREE,
            KEY `idx_winner` (`identifier`, `job`)
        ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]=])

        -- One face per player for every job (not per job): boards fetch them by token.
        MySQL.query.await([=[
        CREATE TABLE IF NOT EXISTS `gg_studio_job_faces` (
            `identifier` VARCHAR(64) NOT NULL COLLATE 'utf8mb4_general_ci',
            `image` MEDIUMTEXT NULL COLLATE 'utf8mb4_general_ci',
            `version` INT NOT NULL DEFAULT 1,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`) USING BTREE,
            KEY `idx_updated` (`updated_at`)
        ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]=])

        -- The competition's own counts (a month outlasts the weekly ones), added to tables
        -- made before it.
        local has = MySQL.scalar.await(
            "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gg_studio_job_stats' AND COLUMN_NAME = 'compete'"
        )

        if (tonumber(has) or 0) == 0 then
            MySQL.query.await("ALTER TABLE gg_studio_job_stats ADD COLUMN compete LONGTEXT NULL COLLATE 'utf8mb4_general_ci' AFTER claims")
        end
    end)

    if not ok then
        gg.print.error(("Job challenges unavailable: %s"):format(err))

        return false
    end

    ready = true

    return true
end

gg.jobs.ready = prepare

-- MARK: Helpers

local function int(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function decode(text, fallback)
    if type(text) ~= "string" or text == "" then return fallback end

    local ok, value = pcall(json.decode, text)

    return ok and type(value) == "table" and value or fallback
end

local function copy(value)
    if type(value) ~= "table" then return value end

    local out = {}

    for key, inner in pairs(value) do out[key] = copy(inner) end

    return out
end

local function reward(raw)
    raw = type(raw) == "table" and raw or {}

    return { money = int(raw.money), experience = int(raw.experience), currency = int(raw.currency) }
end

local function addReward(total, part)
    total.money = total.money + part.money
    total.experience = total.experience + part.experience
    total.currency = total.currency + part.currency

    return total
end

local function share(base, part)
    local function round(value)
        value = value * part

        return value >= 100 and math.floor(value / 5 + 0.5) * 5 or math.floor(value + 0.5)
    end

    return { money = round(base.money), experience = round(base.experience), currency = round(base.currency) }
end

local function empty(value)
    return value.money <= 0 and value.experience <= 0 and value.currency <= 0
end

-- Float arithmetic that stays exact (under 2^53), so a day draws the same on any Lua.
local function hash(text)
    local h = 5381.0

    for index = 1, #text do h = (h * 33 + text:byte(index)) % 2147483647 end

    return math.floor(h)
end

-- Seeded draws, so a worker's day is the same however often it is rebuilt, without
-- touching math.random, which the job's own loot rolls use.
local function random(seed)
    local state = (seed % 2147483646) + 1.0

    return function(count)
        state = (state * 48271) % 2147483647

        return math.floor(state % count) + 1
    end
end

-- Goals land on round numbers: 37 bags reads as a typo, 35 as a goal.
local function nice(value, least, most)
    local span = most - least
    local step = 1

    if span >= 2000 then step = 100 elseif span >= 400 then step = 50 elseif span >= 100 then step = 10 elseif span >= 30 then step = 5 end

    local rounded = math.floor(value / step + 0.5) * step

    return math.max(least, math.min(most, rounded))
end

local function warn(message)
    if gg.print and gg.print.warn then gg.print.warn(message) else print(message) end
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end

    local ok, result = pcall(fn, ...)

    if not ok then
        warn(("A job hook failed: %s"):format(tostring(result)))

        return nil
    end

    return result
end

-- MARK: The day and the week

local clock = { day = 0, next = 0 }

--- The current day's start (gg_lib's daily reset) and when it ends.
local function today()
    local now = os.time()

    if clock.day > 0 and now < clock.next then return clock.day, clock.next end

    local last = tonumber(safe(gg.daily.lastAt)) or 0
    local nextAt = tonumber(safe(gg.daily.nextAt)) or 0

    if last <= 0 or last > now then last = now - now % DAY end
    if nextAt <= last then nextAt = last + DAY end

    clock.day, clock.next = math.floor(last), math.floor(nextAt)

    return clock.day, clock.next
end

local function dayIndex(day)
    return (math.floor(day) + 43200) // DAY
end

--- The week a day falls in: its number, the day of the week (0-6) and when it ends.
local function weekOf(day, starts)
    local index = dayIndex(day)
    local weekday = (index + 3) % 7 -- 0 = Monday: 1 January 1970 was a Thursday
    local into = (weekday - (starts or 0)) % 7

    return (index - into) // 7, into, day + (7 - into) * DAY
end

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function monthDays(year, month)
    if month == 2 and year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then return 29 end

    return MONTH_DAYS[month]
end

--- The month a day falls in: its id (year * 100 + month), when it ends, its year and month.
local function monthOf(day)
    local date = os.date("!*t", dayIndex(day) * DAY)
    local left = monthDays(date.year, date.month) - date.day + 1

    return date.year * 100 + date.month, day + left * DAY, date.year, date.month
end

local MONTH_ID = 100000

--- What a competition period id names: { kind = "month", year, month } or { kind = "week" }.
local function periodInfo(id)
    if id >= MONTH_ID then return { kind = "month", year = id // 100, month = id % 100 } end

    return { kind = "week" }
end

local function previousPeriod(id)
    if id >= MONTH_ID and id % 100 <= 1 then return (id // 100 - 1) * 100 + 12 end

    return id - 1
end

-- Months and weeks each count up by one, so the competitions take the pool in turn.
local function sequence(id)
    if id >= MONTH_ID then return (id // 100) * 12 + id % 100 - 1 end

    return id
end

--- The competition period a day falls in for a job: its id and when it ends.
local function periodOf(def, day)
    if def.compete.period == "month" then
        local id, ends = monthOf(day)

        return id, ends
    end

    local week, _, ends = weekOf(day, def.compete.starts)

    return week, ends
end

gg.jobs.today = today
gg.jobs.weekOf = weekOf
gg.jobs.monthOf = monthOf
gg.jobs.periodInfo = periodInfo
gg.jobs.previousPeriod = previousPeriod

-- MARK: Definitions

local defs = {}
local primary = nil

local function pool(rows, kind)
    local out = {}

    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and row.enabled ~= false and type(row.counter) == "string" and row.counter ~= "" then
            local least = math.max(1, int(row.least or row.goal))
            local most = math.max(least, int(row.most or least))

            out[#out + 1] = { counter = row.counter, least = least, most = most, reward = reward(row.reward), level = int(row.level), kind = kind }
        end
    end

    return out
end

local function normalize(job, def)
    local daily = type(def.daily) == "table" and def.daily or {}
    local weekly = type(def.weekly) == "table" and def.weekly or {}
    local compete = type(def.compete) == "table" and def.compete or {}
    local sweep = type(daily.sweep) == "table" and daily.sweep or {}

    local prizes = {}

    for _, row in ipairs(type(compete.prizes) == "table" and compete.prizes or {}) do
        local from = math.max(1, int(row.from))
        local to = math.max(from, int(row.to or from))

        prizes[#prizes + 1] = { from = from, to = to, reward = reward(row.reward) }
    end

    table.sort(prizes, function(a, b) return a.from < b.from end)

    local events = {}

    for _, row in ipairs(type(compete.pool) == "table" and compete.pool or {}) do
        if type(row) == "table" and row.enabled ~= false and type(row.counter) == "string" and row.counter ~= "" then
            events[#events + 1] = { counter = row.counter, least = math.max(1, int(row.least)) }
        end
    end

    -- Bonus days: the weekdays (0 = Monday) and what each part of the pay is multiplied by.
    local boost = type(def.boost) == "table" and def.boost or {}
    local boostDays, anyDay = {}, false

    for weekday = 1, 7 do boostDays[weekday] = false end

    for _, weekday in ipairs(type(boost.days) == "table" and boost.days or {}) do
        weekday = tonumber(weekday)

        if weekday and weekday >= 0 and weekday <= 6 then
            boostDays[math.floor(weekday) + 1] = true
            anyDay = true
        end
    end

    local function factor(value)
        value = tonumber(value) or 1

        return math.max(1, math.min(5, math.floor(value * 20 + 0.5) / 20))
    end

    local boostMoney, boostExperience, boostCurrency = factor(boost.money), factor(boost.experience), factor(boost.currency)

    local achievements, byId = {}, {}

    for _, row in ipairs(type(def.achievements) == "table" and def.achievements or {}) do
        if type(row) == "table" and row.enabled ~= false and type(row.id) == "string" and type(row.counter) == "string" then
            local tiers, last = {}, 0

            for _, tier in ipairs(type(row.tiers) == "table" and row.tiers or {}) do
                local goal = int(tier.goal)

                if goal > last then
                    tiers[#tiers + 1] = { goal = goal, reward = reward(tier.reward) }
                    last = goal
                end
            end

            if #tiers > 0 then
                local entry = { id = row.id, counter = row.counter, icon = row.icon, category = row.category, tiers = tiers }

                achievements[#achievements + 1] = entry
                byId[row.id] = entry
            end
        end
    end

    return {
        job          = job,
        label        = tostring(def.label or job),
        company      = def.company,
        icon         = def.icon,
        description  = def.description,
        accent       = def.accent,
        banner       = def.banner,
        places       = type(def.places) == "table" and def.places or {},
        counters     = type(def.counters) == "table" and def.counters or {},
        values       = def.values,
        level        = def.level,
        pay          = def.pay,
        notify       = def.notify,
        name         = def.name,
        daily        = {
            count   = math.max(0, math.min(8, int(daily.count or 3))),
            rerolls = math.max(0, math.min(10, int(daily.rerolls or 1))),
            pool    = pool(daily.pool, "daily"),
            sweep   = { reward = reward(sweep.reward), bonus = math.max(0, tonumber(sweep.bonus) or 0), cap = int(sweep.cap or 7) },
        },
        weekly       = {
            count = math.max(0, math.min(4, int(weekly.count or 1))),
            pool  = pool(weekly.pool, "weekly"),
        },
        compete      = {
            enabled = compete.enabled ~= false and #events > 0,
            pool    = events,
            -- A competition is a side bonus (owner 2026-11-07): its places earn a title,
            -- and pay a small prize only while pay is on.
            prizes  = compete.pay ~= false and prizes or {},
            pay     = compete.pay ~= false,
            period  = compete.period == "week" and "week" or "month",
            places  = math.max(1, math.min(50, int(compete.places or 10))),
            starts  = math.max(0, math.min(6, int(compete.starts))),
        },
        achievements = achievements,
        byId         = byId,
        boost        = {
            enabled    = boost.enabled == true and anyDay and (boostMoney > 1 or boostExperience > 1 or boostCurrency > 1),
            days       = boostDays,
            money      = boostMoney,
            experience = boostExperience,
            currency   = boostCurrency,
        },
    }
end

-- What the city hall reads: the job as players see it, in the server's language.
local function listing(def)
    local counters = {}

    for name, counter in pairs(def.counters) do
        if type(counter) == "table" then counters[name] = { label = counter.label, icon = counter.icon, money = counter.money == true } end
    end

    local places = {}

    for index, place in ipairs(def.places) do
        local coords = place.coords

        if coords then
            places[index] = { label = place.label, x = coords.x, y = coords.y, z = coords.z }
        end
    end

    return {
        resource     = GetCurrentResourceName(),
        label        = def.label,
        company      = def.company,
        icon         = def.icon,
        description  = def.description,
        accent       = def.accent,
        banner       = def.banner,
        places       = places,
        counters     = counters,
        achievements = #def.achievements,
        challenges   = { daily = def.daily.count, weekly = def.weekly.count },
        compete      = def.compete.enabled,
        compete_period = def.compete.period,
    }
end

local listed = {}

local function list(def)
    local encoded = json.encode(listing(def))

    if listed[def.job] == encoded then return end

    listed[def.job] = encoded

    MySQL.insert.await("INSERT INTO gg_studio_jobs (job, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)", { def.job, encoded })
end

-- MARK: Rows

local rows = {}     -- identifier \0 job -> row
local dirty = {}    -- the rows to write
local sources = {}  -- server id -> identifier, for names and the winners' notices

local function keyOf(identifier, job)
    return identifier .. "\0" .. job
end

local function freshDaily()
    return { counters = {}, set = {}, rerolls = 0, sweep = false }
end

local function freshWeekly()
    return { counters = {}, set = {}, days = { false, false, false, false, false, false, false } }
end

local function rowOf(identifier, job)
    local key = keyOf(identifier, job)
    local row = rows[key]

    if row then return row end

    local stored = MySQL.single.await("SELECT * FROM gg_studio_job_stats WHERE identifier = ? AND job = ?", { identifier, job })

    row = {
        identifier = identifier,
        job        = job,
        name       = stored and stored.name or nil,
        lifetime   = decode(stored and stored.lifetime, {}),
        day        = stored and math.floor(tonumber(stored.day) or 0) or 0,
        daily      = decode(stored and stored.daily, freshDaily()),
        week       = stored and math.floor(tonumber(stored.week) or 0) or 0,
        weekly     = decode(stored and stored.weekly, freshWeekly()),
        streak     = stored and int(stored.streak) or 0,
        best       = stored and int(stored.best_streak) or 0,
        streakDay  = stored and math.floor(tonumber(stored.streak_day) or 0) or 0,
        claims     = decode(stored and stored.claims, {}),
        compete    = decode(stored and stored.compete, nil),
    }

    row.daily.counters = row.daily.counters or {}
    row.daily.set = row.daily.set or {}
    row.weekly.counters = row.weekly.counters or {}
    row.weekly.set = row.weekly.set or {}
    row.weekly.days = row.weekly.days or freshWeekly().days

    -- Two requests can load the same row at once; the first one kept wins.
    if rows[key] then return rows[key] end

    rows[key] = row

    return row
end

local SAVE_SQL = [[
    INSERT INTO gg_studio_job_stats (identifier, job, name, lifetime, day, daily, week, weekly, streak, best_streak, streak_day, claims, compete)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE name = VALUES(name), lifetime = VALUES(lifetime), day = VALUES(day), daily = VALUES(daily),
        week = VALUES(week), weekly = VALUES(weekly), streak = VALUES(streak), best_streak = VALUES(best_streak),
        streak_day = VALUES(streak_day), claims = VALUES(claims), compete = VALUES(compete)
]]

local function saveArgs(row)
    return {
        row.identifier, row.job, row.name,
        json.encode(row.lifetime), row.day, json.encode(row.daily),
        row.week, json.encode(row.weekly),
        row.streak, row.best, row.streakDay, json.encode(row.claims),
        json.encode(row.compete or {}),
    }
end

local function save(row)
    MySQL.insert.await(SAVE_SQL, saveArgs(row))
end

local function identify(who)
    if type(who) == "string" then return who ~= "" and #who <= 64 and who or nil, nil end

    local source = math.floor(tonumber(who) or 0)

    if source <= 0 or not GetPlayerName(source) then return nil, nil end

    local known = sources[source]

    if known then return known, source end

    local identifier = safe(gg.framework.GetIdentifier, source)

    if type(identifier) ~= "string" or identifier == "" then return nil, source end

    sources[source] = identifier

    return identifier, source
end

local function sourceOf(identifier)
    for source, known in pairs(sources) do
        if known == identifier and GetPlayerName(source) then return source end
    end

    return nil
end

local function resolveJob(job)
    return defs[job or primary]
end

-- MARK: Drawing challenges

local function scaled(entry, goal)
    if entry.most <= entry.least then return copy(entry.reward) end

    -- The reward is the hardest goal's; an easier roll pays less, down to half.
    return share(entry.reward, 0.5 + 0.5 * (goal - entry.least) / (entry.most - entry.least))
end

local function draw(def, kind, identifier, period, count, level, avoid, salt)
    local rand = random(hash(table.concat({ identifier, def.job, kind, tostring(period), tostring(salt or 0) }, ":")))
    local eligible, picked, used, spare = {}, {}, {}, {}

    for _, entry in ipairs(def[kind].pool) do
        if entry.level <= level and not (avoid and avoid[entry.counter]) then eligible[#eligible + 1] = entry end
    end

    local function take(entry)
        local goal = nice(entry.least + rand(entry.most - entry.least + 1) - 1, entry.least, entry.most)
        local item = { counter = entry.counter, goal = goal, reward = scaled(entry, goal), base = 0 }

        if kind == "weekly" then item.claimed = { false, false, false } else item.claimed = false end

        picked[#picked + 1] = item
    end

    -- Different counters first, so a day is not three ways of saying the same thing.
    while #picked < count and #eligible > 0 do
        local entry = table.remove(eligible, rand(#eligible))

        if used[entry.counter] then
            spare[#spare + 1] = entry
        else
            used[entry.counter] = true
            take(entry)
        end
    end

    while #picked < count and #spare > 0 do take(table.remove(spare, rand(#spare))) end

    return picked
end

local function levelOf(def, identifier)
    return math.max(1, int(safe(def.level, identifier) or 1))
end

--- Brings a row up to the current day, week and competition. Returns true when it changed.
local function roll(def, row)
    local day = today()
    local week = weekOf(day, def.compete.starts)
    local period = periodOf(def, day)
    local changed = false
    local level = nil

    -- A row from before the competition kept its own counts starts from this week's,
    -- so nobody loses what they did this week.
    if type(row.compete) ~= "table" or row.compete.period ~= period then
        local seed = type(row.compete) ~= "table" and row.week == week and copy(row.weekly.counters) or {}

        row.compete = { period = period, counters = seed }
        changed = true
    end

    row.compete.counters = row.compete.counters or {}

    -- A day with nothing drawn (an empty pool, or nothing at the worker's level yet) draws
    -- again once there is something to draw.
    if row.day ~= day or (#row.daily.set == 0 and #def.daily.pool > 0 and def.daily.count > 0) then
        level = level or levelOf(def, row.identifier)

        local set = draw(def, "daily", row.identifier, day, def.daily.count, level)

        if row.day ~= day then
            row.day = day
            row.daily = freshDaily()
            changed = true
        end

        if #set > 0 then
            row.daily.set = set
            changed = true
        end
    end

    if row.week ~= week or (#row.weekly.set == 0 and #def.weekly.pool > 0 and def.weekly.count > 0) then
        level = level or levelOf(def, row.identifier)

        local set = draw(def, "weekly", row.identifier, week, def.weekly.count, level)

        if row.week ~= week then
            row.week = week
            row.weekly = freshWeekly()
            changed = true
        end

        if #set > 0 then
            row.weekly.set = set
            changed = true
        end
    end

    if changed then dirty[keyOf(row.identifier, row.job)] = true end

    return changed
end

local function progressOf(counters, entry)
    return math.max(0, int(counters[entry.counter]) - int(entry.base))
end

local function milestoneGoal(entry, index)
    return math.max(1, math.ceil(entry.goal * MILESTONES[index].at))
end

-- MARK: Competition

local events = {}   -- job:week -> counter
local boardDirty = {}

local function eventOf(def, week)
    if not def.compete.enabled then return nil end

    local key = def.job .. ":" .. week
    local known = events[key]

    if known then return known end

    local counter = MySQL.scalar.await("SELECT counter FROM gg_studio_job_weeks WHERE job = ? AND week = ?", { def.job, week })

    if not counter then
        local entry = def.compete.pool[(sequence(week) % #def.compete.pool) + 1]

        counter = entry.counter

        MySQL.insert.await("INSERT IGNORE INTO gg_studio_job_weeks (job, week, counter) VALUES (?, ?, ?)", { def.job, week, counter })

        counter = MySQL.scalar.await("SELECT counter FROM gg_studio_job_weeks WHERE job = ? AND week = ?", { def.job, week }) or counter
    end

    events[key] = counter

    return counter
end

local function leastFor(def, counter)
    for _, entry in ipairs(def.compete.pool) do
        if entry.counter == counter then return entry.least end
    end

    return 1
end

local function prizeFor(def, place)
    for _, prize in ipairs(def.compete.prizes) do
        if place >= prize.from and place <= prize.to then return prize end
    end

    return nil
end

local function saveBoard(def, row)
    if type(row.compete) ~= "table" then return end

    local counter = eventOf(def, row.compete.period)

    if not counter then return end

    local value = int(row.compete.counters[counter])

    if value <= 0 then return end

    MySQL.insert.await(
        "INSERT INTO gg_studio_job_compete (job, week, identifier, name, value) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), value = VALUES(value)",
        { def.job, row.compete.period, row.identifier, row.name, value }
    )
end

local function flush(only)
    for key in pairs(dirty) do
        local row = rows[key]

        if row and (not only or row.identifier == only) then
            dirty[key] = nil

            local ok, err = pcall(save, row)

            if not ok then
                dirty[key] = true
                warn(("Could not save job progress for %s: %s"):format(row.identifier, tostring(err)))
            end
        end
    end

    for key in pairs(boardDirty) do
        local row = rows[key]
        local def = row and defs[row.job]

        if row and def and (not only or row.identifier == only) then
            boardDirty[key] = nil
            pcall(saveBoard, def, row)
        end
    end
end

gg.jobs.flush = flush

local winners = {} -- job:identifier -> { at, podiums, champions, prizes }
local titles = {}  -- job -> { at, period, places = { [identifier] = place } }

local function wins(def, identifier)
    local key = def.job .. ":" .. identifier
    local known = winners[key]

    if known and os.time() - known.at < 60 then return known end

    local row = MySQL.single.await(
        "SELECT SUM(place <= 3) AS podiums, SUM(place = 1) AS champions, COUNT(*) AS prizes FROM gg_studio_job_results WHERE identifier = ? AND job = ?",
        { identifier, def.job }
    ) or {}

    known = { at = os.time(), podiums = int(row.podiums), champions = int(row.champions), prizes = int(row.prizes) }
    winners[key] = known

    return known
end

local function settle(def, week)
    local counter = MySQL.scalar.await("SELECT counter FROM gg_studio_job_weeks WHERE job = ? AND week = ?", { def.job, week })

    if not counter then return end

    -- Every titled place is recorded (its title lasts the next period); a place with a
    -- prize keeps it to claim, one without is closed at once.
    local top = def.compete.places

    for _, prize in ipairs(def.compete.prizes) do top = math.max(top, prize.to) end

    local placed = {}

    if top > 0 then
        local board = MySQL.query.await(
            "SELECT identifier, name, value FROM gg_studio_job_compete WHERE job = ? AND week = ? AND value >= ? ORDER BY value DESC, updated_at ASC LIMIT ?",
            { def.job, week, leastFor(def, counter), top }
        ) or {}

        for place, entry in ipairs(board) do
            local prize = prizeFor(def, place)
            local paid = prize and not empty(prize.reward) and prize.reward or nil

            MySQL.insert.await(
                "INSERT IGNORE INTO gg_studio_job_results (job, week, place, identifier, name, value, reward, claimed) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                { def.job, week, place, entry.identifier, entry.name, int(entry.value), json.encode(paid or reward()), paid and 0 or 1 }
            )

            placed[#placed + 1] = { place = place, identifier = entry.identifier, reward = paid or reward() }
            winners[def.job .. ":" .. entry.identifier] = nil
        end
    end

    titles[def.job] = nil

    MySQL.update.await("UPDATE gg_studio_job_weeks SET settled = 1 WHERE job = ? AND week = ?", { def.job, week })

    for _, entry in ipairs(placed) do
        local source = sourceOf(entry.identifier)

        if source then safe(def.notify, source, "compete_result", { place = entry.place, counter = counter, reward = entry.reward, period = periodInfo(week) }) end
    end
end

local function settleDue(def)
    if not def.compete.enabled and #def.compete.prizes == 0 then return end

    -- Any period but the current one: a switch from weeks to months settles the last week.
    local week = periodOf(def, today())
    local due = MySQL.query.await(
        "SELECT week FROM gg_studio_job_weeks WHERE job = ? AND settled = 0 AND week <> ? ORDER BY week DESC LIMIT 4",
        { def.job, week }
    ) or {}

    if #due == 0 then return end

    flush()

    for _, entry in ipairs(due) do
        local ok, err = pcall(settle, def, math.floor(tonumber(entry.week) or 0))

        if not ok then warn(("Could not settle the %s competition: %s"):format(def.job, tostring(err))) end
    end
end

-- MARK: Values

-- Everything achievements count: the engine's lifetime counters, its own six, and the
-- job's own numbers (def.values), which win where both have one.
local function valuesOf(def, row)
    local values = {}

    for name, value in pairs(row.lifetime) do values[name] = int(value) end

    local won = wins(def, row.identifier)

    values.streak = row.best
    values.podiums = won.podiums
    values.champions = won.champions
    values.prizes = won.prizes

    local extra = safe(def.values, row.identifier)

    if type(extra) == "table" then
        for name, value in pairs(extra) do values[name] = int(value) end
    end

    return values
end

local function tierOf(entry, value)
    local tier = 0

    for index, step in ipairs(entry.tiers) do
        if value >= step.goal then tier = index end
    end

    return tier
end

-- MARK: Register and track

local started = false

local function start()
    if started then return end

    started = true

    CreateThread(function()
        while true do
            Wait(FLUSH_EVERY)
            flush()
        end
    end)

    -- Faces nobody refreshed for a long time go; anyone who opens a tablet gets a new one.
    CreateThread(function()
        Wait(20000)

        local ok, err = pcall(MySQL.query.await, ("DELETE FROM gg_studio_job_faces WHERE updated_at < (NOW() - INTERVAL %d DAY)"):format(FACE_KEEP_DAYS))

        if not ok then warn(("Could not clear old faces: %s"):format(tostring(err))) end
    end)

    CreateThread(function()
        Wait(5000)

        while true do
            for _, def in pairs(defs) do
                local ok, err = pcall(settleDue, def)

                if not ok then warn(("Competition check failed for %s: %s"):format(def.job, tostring(err))) end
            end

            Wait(SETTLE_EVERY)
        end
    end)

    AddEventHandler("playerDropped", function()
        local source = source
        local identifier = sources[source]

        sources[source] = nil

        if not identifier then return end

        flush(identifier)

        for key, row in pairs(rows) do
            if row.identifier == identifier and not dirty[key] and not boardDirty[key] then rows[key] = nil end
        end
    end)

    AddEventHandler("onResourceStop", function(resource)
        if resource ~= GetCurrentResourceName() then return end

        -- Fire and forget: the resource is going, so nothing waits for the answers.
        for key in pairs(dirty) do
            local row = rows[key]

            if row then MySQL.insert(SAVE_SQL, saveArgs(row)) end
        end
    end)
end

--- Describes a job to the engine; call it again whenever the owner's settings change.
--- See knowledge/source/jobs-kit.md (§9) for every field. Returns true when the job is in.
function gg.jobs.register(job, def)
    if type(job) ~= "string" or job == "" or type(def) ~= "table" then return false end
    if not prepare() then return false end

    defs[job] = normalize(job, def)
    primary = primary or job

    -- A new pool or prize list counts from the next week; this week keeps its event.
    CreateThread(function()
        local ok, err = pcall(list, defs[job])

        if not ok then warn(("Could not list %s for the city hall: %s"):format(job, tostring(err))) end
    end)

    start()

    return true
end

function gg.jobs.registered(job)
    return defs[job or primary] ~= nil
end

--- Settles every finished competition week now instead of at the next minute's check
--- (an admin command, a test). Without a job it settles every registered job.
function gg.jobs.settle(job)
    for name, def in pairs(defs) do
        if not job or job == name then
            local ok, err = pcall(settleDue, def)

            if not ok then warn(("Could not settle the %s competition: %s"):format(name, tostring(err))) end
        end
    end
end

local function notifyCrossings(def, row, source, counter, amount)
    for index, entry in ipairs(row.daily.set) do
        if entry.counter == counter and not entry.claimed then
            local now = progressOf(row.daily.counters, entry)

            if now >= entry.goal and now - amount < entry.goal then
                local done = 0

                for _, other in ipairs(row.daily.set) do
                    if other.claimed or progressOf(row.daily.counters, other) >= other.goal then done = done + 1 end
                end

                safe(def.notify, source, "daily_done", { index = index, counter = counter, goal = entry.goal, all = done == #row.daily.set })
            end
        end
    end

    for index, entry in ipairs(row.weekly.set) do
        if entry.counter == counter then
            local now = progressOf(row.weekly.counters, entry)

            for step = 1, #MILESTONES do
                local goal = milestoneGoal(entry, step)

                if not entry.claimed[step] and now >= goal and now - amount < goal then
                    safe(def.notify, source, "weekly_milestone", { index = index, counter = counter, goal = goal, milestone = step })
                end
            end
        end
    end

    local values = nil

    for _, achievement in ipairs(def.achievements) do
        if achievement.counter == counter then
            values = values or valuesOf(def, row)

            local value = values[counter] or 0
            local before, after = tierOf(achievement, value - amount), tierOf(achievement, value)

            if after > before then safe(def.notify, source, "achievement", { id = achievement.id, tier = after }) end
        end
    end
end

--- Counts something a worker did: gg.jobs.track(source, "bags", 1). `who` is a server id
--- or an identifier; `job` defaults to the job this resource registered first.
function gg.jobs.track(who, counter, amount, job)
    local def = resolveJob(job)

    if not def or type(counter) ~= "string" or counter == "" then return false end

    amount = math.floor(tonumber(amount) or 1)

    if amount <= 0 then return false end

    local identifier, source = identify(who)

    if not identifier then return false end

    local row = rowOf(identifier, def.job)

    roll(def, row)

    if source then row.name = safe(def.name, source) or row.name or GetPlayerName(source) end

    row.lifetime[counter] = int(row.lifetime[counter]) + amount
    row.daily.counters[counter] = int(row.daily.counters[counter]) + amount
    row.weekly.counters[counter] = int(row.weekly.counters[counter]) + amount
    row.compete.counters[counter] = int(row.compete.counters[counter]) + amount

    local key = keyOf(identifier, def.job)

    dirty[key] = true

    if eventOf(def, row.compete.period) == counter then boardDirty[key] = true end

    if source then notifyCrossings(def, row, source, counter, amount) end

    return true
end

-- MARK: Claims

local function pay(def, source, total, why)
    if empty(total) then return true end

    local ok = safe(def.pay, source, total, why)

    return ok ~= false and ok ~= nil
end

local function sweepReward(def, streak)
    local sweep = def.daily.sweep
    local extra = math.min(math.max(0, streak - 1), sweep.cap) * sweep.bonus / 100

    return share(sweep.reward, 1 + extra)
end

-- The streak a sweep today would make.
local function nextStreak(row)
    if row.streakDay == row.day then return row.streak end
    if row.streakDay > 0 and dayIndex(row.streakDay) == dayIndex(row.day) - 1 then return row.streak + 1 end

    return 1
end

local function currentStreak(row)
    if row.streakDay == row.day then return row.streak end
    if row.streakDay > 0 and dayIndex(row.streakDay) == dayIndex(row.day) - 1 then return row.streak end

    return 0
end

local function allClaimed(set)
    if #set == 0 then return false end

    for _, entry in ipairs(set) do
        if not entry.claimed then return false end
    end

    return true
end

-- Each claim marks itself before anything yields, so a double click pays once.
local claimers = {}

claimers.daily = function(def, row, what, total)
    local entry = row.daily.set[int(what.index)]

    if not entry then return "missing" end
    if entry.claimed then return "claimed" end
    if progressOf(row.daily.counters, entry) < entry.goal then return "not_ready" end

    entry.claimed = true
    row.lifetime.dailies = int(row.lifetime.dailies) + 1

    addReward(total, entry.reward)

    return nil, function()
        entry.claimed = false
        row.lifetime.dailies = math.max(0, int(row.lifetime.dailies) - 1)
    end
end

claimers.sweep = function(def, row, what, total)
    if row.daily.sweep then return "claimed" end
    if not allClaimed(row.daily.set) then return "not_ready" end

    local before = { streak = row.streak, best = row.best, streakDay = row.streakDay }
    local _, into = weekOf(row.day, def.compete.starts)

    row.streak = nextStreak(row)
    row.best = math.max(row.best, row.streak)
    row.streakDay = row.day
    row.daily.sweep = true
    row.weekly.days[into + 1] = true
    row.lifetime.sweeps = int(row.lifetime.sweeps) + 1

    addReward(total, sweepReward(def, row.streak))

    return nil, function()
        row.streak, row.best, row.streakDay = before.streak, before.best, before.streakDay
        row.daily.sweep = false
        row.weekly.days[into + 1] = false
        row.lifetime.sweeps = math.max(0, int(row.lifetime.sweeps) - 1)
    end
end

claimers.weekly = function(def, row, what, total)
    local entry = row.weekly.set[int(what.index)]

    if not entry then return "missing" end

    local progress = progressOf(row.weekly.counters, entry)
    local taken = {}

    for step = 1, #MILESTONES do
        if not entry.claimed[step] and progress >= milestoneGoal(entry, step) and (not what.milestone or int(what.milestone) == step) then
            entry.claimed[step] = true
            taken[#taken + 1] = step
            addReward(total, share(entry.reward, MILESTONES[step].share))
        end
    end

    if #taken == 0 then return entry.claimed[#MILESTONES] and "claimed" or "not_ready" end

    local finished = entry.claimed[#MILESTONES] and taken[#taken] == #MILESTONES

    if finished then row.lifetime.weeklies = int(row.lifetime.weeklies) + 1 end

    return nil, function()
        for _, step in ipairs(taken) do entry.claimed[step] = false end
        if finished then row.lifetime.weeklies = math.max(0, int(row.lifetime.weeklies) - 1) end
    end
end

claimers.achievement = function(def, row, what, total, values)
    local entry = def.byId[what.id]

    if not entry then return "missing" end

    local had = int(row.claims[entry.id])
    local reached = tierOf(entry, values[entry.counter] or 0)

    if reached <= had then return had >= #entry.tiers and "claimed" or "not_ready" end

    for tier = had + 1, reached do addReward(total, entry.tiers[tier].reward) end

    row.claims[entry.id] = reached

    return nil, function() row.claims[entry.id] = had end
end

local function claimPrize(def, row, week, total)
    local prize = MySQL.single.await(
        "SELECT place, reward FROM gg_studio_job_results WHERE job = ? AND week = ? AND identifier = ? AND claimed = 0",
        { def.job, week, row.identifier }
    )

    if not prize then return "not_ready" end

    local changed = MySQL.update.await(
        "UPDATE gg_studio_job_results SET claimed = 1 WHERE job = ? AND week = ? AND place = ? AND claimed = 0",
        { def.job, week, prize.place }
    )

    if (tonumber(changed) or 0) < 1 then return "claimed" end

    addReward(total, reward(decode(prize.reward, {})))

    return nil, function()
        MySQL.update.await("UPDATE gg_studio_job_results SET claimed = 0 WHERE job = ? AND week = ? AND place = ?", { def.job, week, prize.place })
    end
end

--- Claims one thing, or everything ready (what.kind = "all", what.only = "challenges",
--- "achievements" or "compete" for one page's). what.kind is daily (index),
--- sweep, weekly (index, milestone optional), achievement (id) or prize (week optional,
--- default last week). Returns { ok, reward, claimed = n } or { ok = false, error = code }
--- with code missing, claimed, not_ready, no_worker or not_paid.
function gg.jobs.claim(who, what, job)
    local def = resolveJob(job)

    what = type(what) == "table" and what or {}

    if not def then return { ok = false, error = "missing" } end

    local identifier, source = identify(who)

    if not identifier or not source then return { ok = false, error = "no_worker" } end

    local row = rowOf(identifier, def.job)

    roll(def, row)

    local total = reward()
    local undo = {}
    local values = valuesOf(def, row)
    local last = previousPeriod(row.compete.period)
    local count = 0
    local refused = nil

    local function try(kind, args)
        local claimer = claimers[kind]
        local err, revert

        if kind == "prize" then
            err, revert = claimPrize(def, row, int(args.week) > 0 and int(args.week) or last, total)
        else
            err, revert = claimer(def, row, args, total, values)
        end

        if err then
            refused = refused or err
        else
            count = count + 1
            undo[#undo + 1] = revert
        end
    end

    if what.kind == "all" then
        local only = what.only

        if only == nil or only == "challenges" then
            for index, entry in ipairs(row.daily.set) do
                if not entry.claimed and progressOf(row.daily.counters, entry) >= entry.goal then try("daily", { index = index }) end
            end

            if not row.daily.sweep and allClaimed(row.daily.set) then try("sweep", {}) end

            for index in ipairs(row.weekly.set) do try("weekly", { index = index }) end
        end

        if only == nil or only == "achievements" then
            for _, entry in ipairs(def.achievements) do
                if tierOf(entry, values[entry.counter] or 0) > int(row.claims[entry.id]) then try("achievement", { id = entry.id }) end
            end
        end

        -- The competition sits on the Challenges page, so its Claim All takes the prize too.
        if (only == nil or only == "challenges" or only == "compete") and #def.compete.prizes > 0 then try("prize", {}) end
    elseif claimers[what.kind] or what.kind == "prize" then
        try(what.kind, what)
    else
        return { ok = false, error = "missing" }
    end

    if count == 0 then return { ok = false, error = refused or "not_ready" } end

    if not pay(def, source, total, { kind = what.kind, count = count }) then
        for index = #undo, 1, -1 do pcall(undo[index]) end

        return { ok = false, error = "not_paid" }
    end

    dirty[keyOf(identifier, def.job)] = true

    pcall(save, row)
    dirty[keyOf(identifier, def.job)] = nil

    return { ok = true, reward = total, claimed = count }
end

--- Swaps one daily challenge that is not done yet for another. Returns { ok } or { ok = false, error }.
function gg.jobs.reroll(who, index, job)
    local def = resolveJob(job)

    if not def then return { ok = false, error = "missing" } end

    local identifier = identify(who)

    if not identifier then return { ok = false, error = "no_worker" } end

    local row = rowOf(identifier, def.job)

    roll(def, row)

    local entry = row.daily.set[int(index)]

    if not entry then return { ok = false, error = "missing" } end
    if entry.claimed or progressOf(row.daily.counters, entry) >= entry.goal then return { ok = false, error = "claimed" } end
    if row.daily.rerolls >= def.daily.rerolls then return { ok = false, error = "no_rerolls" } end

    local avoid = {}

    for _, other in ipairs(row.daily.set) do avoid[other.counter] = true end

    local fresh = draw(def, "daily", identifier, row.day, 1, levelOf(def, identifier), avoid, row.daily.rerolls + 1)[1]

    -- Nothing else left in the pool: the same counter with a new goal.
    fresh = fresh or draw(def, "daily", identifier, row.day, 1, levelOf(def, identifier), nil, row.daily.rerolls + 101)[1]

    if not fresh then return { ok = false, error = "missing" } end

    fresh.base = int(row.daily.counters[fresh.counter])
    row.daily.set[int(index)] = fresh
    row.daily.rerolls = row.daily.rerolls + 1
    dirty[keyOf(identifier, def.job)] = true

    return { ok = true }
end

-- MARK: Faces
--
-- One small picture per player, shared by every job: the tablet takes it the moment it
-- opens (gg.jobs.saveFace), so a board shows the faces of players far away or offline.
-- Boards send tokens, never identifiers; the tablet asks for the pictures it has not got
-- (gg.jobs.faceImages) and keeps them. A face unrefreshed for FACE_KEEP_DAYS is deleted.

local faceSalt = ("%d:%d"):format(os.time(), math.random(1, 2147483646))
local faceMeta = {}    -- identifier -> { at, version } (version 0: no face stored)
local faceByToken = {} -- token -> identifier
local faceImage = {}   -- identifier -> { version, image }
local faceCached = 0
local faceSaved = {}   -- identifier -> when it was last saved

local function tokenOf(identifier, version)
    local token = ("f%x%x"):format(hash(faceSalt .. ":" .. identifier), hash(identifier .. ":" .. version .. ":" .. faceSalt))

    faceByToken[token] = identifier

    return token
end

local function marks(count)
    return string.rep("?", count, ",")
end

--- Tokens for players' stored faces: { [identifier] = token }; a player with none has none.
function gg.jobs.faceTokens(identifiers)
    local out, ask, now = {}, {}, os.time()

    if type(identifiers) ~= "table" or not prepare() then return out end

    for _, identifier in ipairs(identifiers) do
        if type(identifier) == "string" and identifier ~= "" then
            local meta = faceMeta[identifier]

            if not meta or now - meta.at > 300 then ask[#ask + 1] = identifier end
        end
    end

    for first = 1, #ask, 100 do
        local part = { table.unpack(ask, first, math.min(#ask, first + 99)) }

        for _, identifier in ipairs(part) do faceMeta[identifier] = { at = now, version = 0 } end

        for _, row in ipairs(MySQL.query.await(("SELECT identifier, version FROM gg_studio_job_faces WHERE identifier IN (%s)"):format(marks(#part)), part) or {}) do
            faceMeta[row.identifier] = { at = now, version = math.max(1, int(row.version)) }
        end
    end

    for _, identifier in ipairs(identifiers) do
        local meta = type(identifier) == "string" and faceMeta[identifier]

        if meta and meta.version > 0 then out[identifier] = tokenOf(identifier, meta.version) end
    end

    return out
end

--- One player's face token, or nil.
function gg.jobs.faceToken(identifier)
    return gg.jobs.faceTokens({ identifier })[identifier]
end

local function tokensFor(identifiers)
    local ok, out = pcall(gg.jobs.faceTokens, identifiers)

    return ok and type(out) == "table" and out or {}
end

--- The pictures for up to 60 tokens: { [token] = data URL }. Unknown tokens are left out.
function gg.jobs.faceImages(tokens)
    local out, ask, tokenFor = {}, {}, {}

    if type(tokens) ~= "table" or not prepare() then return out end

    for index, token in ipairs(tokens) do
        if index > 60 then break end

        local identifier = type(token) == "string" and faceByToken[token]

        if identifier then
            local cached, meta = faceImage[identifier], faceMeta[identifier]

            if cached and meta and cached.version == meta.version then
                out[token] = cached.image
            elseif not tokenFor[identifier] then
                tokenFor[identifier] = token
                ask[#ask + 1] = identifier
            end
        end
    end

    if #ask == 0 then return out end

    if faceCached > 300 then faceImage, faceCached = {}, 0 end

    for _, row in ipairs(MySQL.query.await(("SELECT identifier, image, version FROM gg_studio_job_faces WHERE identifier IN (%s)"):format(marks(#ask)), ask) or {}) do
        if type(row.image) == "string" and row.image ~= "" then
            local version = math.max(1, int(row.version))

            faceImage[row.identifier] = { version = version, image = row.image }
            faceMeta[row.identifier] = { at = os.time(), version = version }
            faceCached = faceCached + 1
            out[tokenFor[row.identifier]] = row.image
        end
    end

    return out
end

local FACE_KINDS = { "data:image/webp;base64,", "data:image/png;base64,", "data:image/jpeg;base64," }

local function faceOk(image)
    if type(image) ~= "string" or #image < 64 or #image > FACE_MAX then return false end

    for _, prefix in ipairs(FACE_KINDS) do
        if image:sub(1, #prefix) == prefix then return image:find("[^%w%+/=]", #prefix + 1) == nil end
    end

    return false
end

--- Stores a player's face (a small data URL the tablet made from the game's mugshot).
--- Returns { ok, token } or { ok = false, error = no_worker | bad_image | too_soon }.
function gg.jobs.saveFace(who, image)
    if not prepare() then return { ok = false, error = "missing" } end

    local identifier = identify(who)

    if not identifier then return { ok = false, error = "no_worker" } end
    if not faceOk(image) then return { ok = false, error = "bad_image" } end

    local now = os.time()

    if faceSaved[identifier] and now - faceSaved[identifier] < FACE_EVERY then return { ok = false, error = "too_soon" } end

    faceSaved[identifier] = now

    local cached = faceImage[identifier]

    -- The same picture again only keeps it from being cleared.
    if cached and cached.image == image then
        MySQL.update.await("UPDATE gg_studio_job_faces SET updated_at = CURRENT_TIMESTAMP WHERE identifier = ?", { identifier })

        return { ok = true, token = tokenOf(identifier, cached.version), same = true }
    end

    MySQL.insert.await(
        "INSERT INTO gg_studio_job_faces (identifier, image, version) VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE version = IF(image = VALUES(image), version, version + 1), image = VALUES(image), updated_at = CURRENT_TIMESTAMP",
        { identifier, image }
    )

    local version = math.max(1, int(MySQL.scalar.await("SELECT version FROM gg_studio_job_faces WHERE identifier = ?", { identifier })))

    if not faceImage[identifier] then faceCached = faceCached + 1 end

    faceImage[identifier] = { version = version, image = image }
    faceMeta[identifier] = { at = now, version = version }

    return { ok = true, token = tokenOf(identifier, version) }
end

-- MARK: Titles
--
-- A competition is a side bonus earned as a tag (owner 2026-11-07): every place up to
-- compete.places holds a title through the next period, shown by the worker's name on
-- the boards, their group and their profile. 1st is Champion, 2nd and 3rd the podium,
-- the rest Top N.

local function titleBoard(def)
    local period = previousPeriod(periodOf(def, today()))
    local known = titles[def.job]

    if known and known.period == period and os.time() - known.at < 120 then return known end

    local places = {}

    for _, entry in ipairs(MySQL.query.await(
        "SELECT identifier, place FROM gg_studio_job_results WHERE job = ? AND week = ? ORDER BY place ASC LIMIT ?",
        { def.job, period, def.compete.places }
    ) or {}) do
        places[entry.identifier] = int(entry.place)
    end

    known = { at = os.time(), period = period, places = places }
    titles[def.job] = known

    return known
end

local function titleOf(def, identifier)
    if not def.compete.enabled or type(identifier) ~= "string" then return false end

    local ok, board = pcall(titleBoard, def)

    if not ok then return false end

    local place = board.places[identifier]

    if not place then return false end

    local info = periodInfo(board.period)

    return { place = place, places = def.compete.places, kind = info.kind, year = info.year, month = info.month }
end

--- The titles players hold from the last competition: { [identifier] = { place, places, kind, year, month } }.
function gg.jobs.titles(identifiers, job)
    local def = resolveJob(job)
    local out = {}

    if not def or type(identifiers) ~= "table" then return out end

    for _, identifier in ipairs(identifiers) do
        local title = titleOf(def, identifier)

        if title then out[identifier] = title end
    end

    return out
end

--- One player's title, or false.
function gg.jobs.title(identifier, job)
    local def = resolveJob(job)

    return def and titleOf(def, identifier) or false
end

--- How often a player placed: { champions, podiums, prizes } (prizes = any titled place).
function gg.jobs.wins(identifier, job)
    local def = resolveJob(job)

    if not def or type(identifier) ~= "string" then return { champions = 0, podiums = 0, prizes = 0 } end

    local won = wins(def, identifier)

    return { champions = won.champions, podiums = won.podiums, prizes = won.prizes }
end

-- MARK: What the tablet shows

local function achievementList(def, row, values)
    local out, reached, total, ready = {}, 0, 0, 0

    for _, entry in ipairs(def.achievements) do
        local value = values[entry.counter] or 0
        local tier = tierOf(entry, value)
        local claimed = math.min(tier, int(row.claims[entry.id]))
        local tiers = {}

        for index, step in ipairs(entry.tiers) do tiers[index] = { goal = step.goal, reward = step.reward } end

        out[#out + 1] = {
            id       = entry.id,
            counter  = entry.counter,
            icon     = entry.icon,
            category = entry.category,
            value    = value,
            tier     = tier,
            claimed  = claimed,
            tiers    = tiers,
        }

        reached, total = reached + tier, total + #entry.tiers

        if tier > claimed then ready = ready + 1 end
    end

    return out, { reached = reached, total = total, ready = ready }
end

local function boardOf(def, week, identifier, mine)
    local counter = eventOf(def, week)

    if not counter then return nil end

    local rowsOf = MySQL.query.await(
        "SELECT identifier, name, value FROM gg_studio_job_compete WHERE job = ? AND week = ? AND value > 0 ORDER BY value DESC, updated_at ASC LIMIT ?",
        { def.job, week, BOARD_SIZE }
    ) or {}

    local entrants = int(MySQL.scalar.await("SELECT COUNT(*) FROM gg_studio_job_compete WHERE job = ? AND week = ? AND value > 0", { def.job, week }))
    local top, place, ids = {}, nil, {}

    for index, entry in ipairs(rowsOf) do ids[index] = entry.identifier end

    local faces = tokensFor(ids)

    for index, entry in ipairs(rowsOf) do
        local me = entry.identifier == identifier

        if me then place = index end

        top[index] = {
            place = index,
            name  = entry.name or "?",
            value = int(entry.value),
            me    = me,
            id    = sourceOf(entry.identifier) or 0,
            face  = faces[entry.identifier] or false,
            title = titleOf(def, entry.identifier),
        }
    end

    if not place and mine and mine > 0 then
        place = int(MySQL.scalar.await("SELECT COUNT(*) FROM gg_studio_job_compete WHERE job = ? AND week = ? AND value > ?", { def.job, week, mine })) + 1
    end

    return { counter = counter, least = leastFor(def, counter), top = top, place = place or false, entrants = entrants }
end

local function lastWeek(def, week, identifier)
    local counter = MySQL.scalar.await("SELECT counter FROM gg_studio_job_weeks WHERE job = ? AND week = ?", { def.job, week })

    if not counter then return false end

    local results = MySQL.query.await(
        "SELECT place, identifier, name, value, reward, claimed FROM gg_studio_job_results WHERE job = ? AND week = ? ORDER BY place ASC LIMIT 3",
        { def.job, week }
    ) or {}

    local top, mine, ids = {}, false, {}

    for index, entry in ipairs(results) do ids[index] = entry.identifier end

    local faces = tokensFor(ids)

    local function result(entry)
        return { place = int(entry.place), value = int(entry.value), reward = reward(decode(entry.reward, {})), claimed = tonumber(entry.claimed) == 1 }
    end

    for _, entry in ipairs(results) do
        local me = entry.identifier == identifier

        top[#top + 1] = { place = int(entry.place), name = entry.name or "?", value = int(entry.value), me = me, id = sourceOf(entry.identifier) or 0, face = faces[entry.identifier] or false }

        if me then mine = result(entry) end
    end

    if not mine and identifier then
        local own = MySQL.single.await(
            "SELECT place, value, reward, claimed FROM gg_studio_job_results WHERE job = ? AND week = ? AND identifier = ?",
            { def.job, week, identifier }
        )

        if own then mine = result(own) end
    end

    return { week = week, period = periodInfo(week), counter = counter, top = top, mine = mine }
end

--- Everything the Challenges, Compete and Achievements pages draw for one worker.
-- MARK: Bonus days

local function boostOf(def)
    local boost = def.boost

    if not boost.enabled then return false end

    local now = os.time()
    local day, dayEnds = today()
    local _, weekday = weekOf(day, 0)
    local on = boost.days[weekday + 1] == true
    local endsIn, nextIn = 0, 0

    if on then
        -- A run of bonus days ends after its last one.
        local last = dayEnds

        for step = 1, 6 do
            if not boost.days[(weekday + step) % 7 + 1] then break end

            last = last + DAY
        end

        endsIn = math.max(0, last - now)
    else
        for step = 1, 6 do
            if boost.days[(weekday + step) % 7 + 1] then
                nextIn = math.max(0, dayEnds + (step - 1) * DAY - now)

                break
            end
        end
    end

    return {
        on         = on,
        days       = copy(boost.days),
        money      = boost.money,
        experience = boost.experience,
        currency   = boost.currency,
        ends_in    = endsIn,
        next_in    = nextIn,
    }
end

--- The job's bonus days, false when it runs none: whether today is one, the seven
--- weekdays (Monday first), the multipliers and when today's ends or the next starts.
--- A day follows gg_lib's daily reset, like the challenges.
function gg.jobs.boost(job)
    local def = resolveJob(job)

    return def and boostOf(def) or false
end

--- Pay with today's bonus applied: { money, experience, currency } in, the same out,
--- and the bonus that applied (false on a normal day).
function gg.jobs.boosted(amounts, job)
    local base = reward(amounts)
    local boost = gg.jobs.boost(job)

    if not boost or not boost.on then return base, false end

    return {
        money      = math.floor(base.money * boost.money + 0.5),
        experience = math.floor(base.experience * boost.experience + 0.5),
        currency   = math.floor(base.currency * boost.currency + 0.5),
    }, boost
end

function gg.jobs.payload(who, job)
    local def = resolveJob(job)

    if not def then return { ok = false, error = "missing" } end

    local identifier, source = identify(who)

    if not identifier then return { ok = false, error = "no_worker" } end

    local row = rowOf(identifier, def.job)

    roll(def, row)

    if source then row.name = safe(def.name, source) or row.name or GetPlayerName(source) end

    flush()

    local now = os.time()
    local _, dayEnds = today()
    local week, into, weekEnds = weekOf(row.day, def.compete.starts)
    local values = valuesOf(def, row)
    local ready = { daily = 0, weekly = 0, achievements = 0, compete = 0 }

    local daily = {}

    for index, entry in ipairs(row.daily.set) do
        local progress = progressOf(row.daily.counters, entry)
        local done = progress >= entry.goal

        daily[index] = { index = index, counter = entry.counter, goal = entry.goal, progress = math.min(progress, entry.goal), reward = entry.reward, claimed = entry.claimed == true, done = done }

        if done and not entry.claimed then ready.daily = ready.daily + 1 end
    end

    local swept = row.daily.sweep == true
    local sweepReady = not swept and allClaimed(row.daily.set)

    if sweepReady then ready.daily = ready.daily + 1 end

    local weekly = {}

    for index, entry in ipairs(row.weekly.set) do
        local progress = progressOf(row.weekly.counters, entry)
        local steps = {}

        for step = 1, #MILESTONES do
            local goal = milestoneGoal(entry, step)
            local done = progress >= goal

            steps[step] = { goal = goal, reward = share(entry.reward, MILESTONES[step].share), claimed = entry.claimed[step] == true, done = done }

            if done and not entry.claimed[step] then ready.weekly = ready.weekly + 1 end
        end

        weekly[index] = { index = index, counter = entry.counter, goal = entry.goal, progress = math.min(progress, entry.goal), reward = entry.reward, milestones = steps, done = progress >= entry.goal }
    end

    local achievements, totals = achievementList(def, row, values)

    ready.achievements = totals.ready

    local compete = false

    if def.compete.enabled then
        local period = row.compete.period
        local _, periodEnds = periodOf(def, row.day)
        local board = boardOf(def, period, identifier, int(row.compete.counters[eventOf(def, period) or ""])) or {}
        local last = lastWeek(def, previousPeriod(period), identifier)

        if last and last.mine and not last.mine.claimed then ready.compete = 1 end

        compete = {
            week     = period,
            period   = periodInfo(period),
            ends_in  = math.max(0, periodEnds - now),
            counter  = board.counter,
            least    = board.least,
            value    = int(row.compete.counters[board.counter or ""]),
            place    = board.place or false,
            entrants = board.entrants or 0,
            top      = board.top or {},
            prizes   = def.compete.prizes,
            pay      = def.compete.pay,
            places   = def.compete.places,
            title    = titleOf(def, identifier),
            wins     = gg.jobs.wins(identifier, def.job),
            last     = last,
        }
    end

    return {
        ok           = true,
        day          = {
            ends_in = math.max(0, dayEnds - now),
            rerolls = math.max(0, def.daily.rerolls - row.daily.rerolls),
            set     = daily,
            sweep   = {
                ready   = sweepReady,
                claimed = swept,
                reward  = sweepReward(def, swept and row.streak or nextStreak(row)),
                base    = def.daily.sweep.reward,
                streak  = currentStreak(row),
                next    = swept and row.streak or nextStreak(row),
                best    = row.best,
                bonus   = def.daily.sweep.bonus,
                cap     = def.daily.sweep.cap,
            },
        },
        week         = { ends_in = math.max(0, weekEnds - now), into = into, starts = def.compete.starts, days = row.weekly.days, set = weekly },
        boost        = boostOf(def),
        compete      = compete,
        achievements = achievements,
        totals       = totals,
        ready        = ready,
        lifetime     = values,
    }
end

--- A worker's achievements without loading their day (another player's profile).
function gg.jobs.achievements(identifier, job)
    local def = resolveJob(job)

    if not def or type(identifier) ~= "string" or identifier == "" then return {}, { reached = 0, total = 0, ready = 0 } end

    local row = rowOf(identifier, def.job)
    local list, totals = achievementList(def, row, valuesOf(def, row))

    return list, totals, currentStreak(row), row.best
end

--- Who holds a place on this competition's board (which = "this") or the last one's results ("last").
function gg.jobs.standing(which, place, job)
    local def = resolveJob(job)

    if not def then return nil end

    local week = periodOf(def, today())

    place = int(place)

    if place < 1 then return nil end

    if which == "last" then
        return MySQL.scalar.await("SELECT identifier FROM gg_studio_job_results WHERE job = ? AND week = ? AND place = ?", { def.job, previousPeriod(week), place })
    end

    flush()

    local row = MySQL.single.await(
        "SELECT identifier FROM gg_studio_job_compete WHERE job = ? AND week = ? AND value > 0 ORDER BY value DESC, updated_at ASC LIMIT 1 OFFSET ?",
        { def.job, week, place - 1 }
    )

    return row and row.identifier or nil
end

-- MARK: Every job at once (a city hall, a phone app)

--- Every job that ever registered on this server: { [job] = listing } (label, company,
--- icon, description, places, counters, achievement count, challenges, compete).
function gg.jobs.directory()
    if not prepare() then return {} end

    local out = {}

    for _, row in ipairs(MySQL.query.await("SELECT job, data FROM gg_studio_jobs") or {}) do
        local data = decode(row.data, nil)

        if data then out[row.job] = data end
    end

    return out
end

--- One player's raw progress in every job: { [job] = { lifetime, streak, best, today = done/of } }.
function gg.jobs.summary(identifier)
    if type(identifier) ~= "string" or identifier == "" or not prepare() then return {} end

    local out = {}
    local day = today()

    for _, row in ipairs(MySQL.query.await("SELECT * FROM gg_studio_job_stats WHERE identifier = ?", { identifier }) or {}) do
        local daily = decode(row.daily, freshDaily())
        local done, of = 0, 0

        if math.floor(tonumber(row.day) or 0) == day then
            for _, entry in ipairs(daily.set or {}) do
                of = of + 1
                if entry.claimed then done = done + 1 end
            end
        end

        out[row.job] = {
            lifetime = decode(row.lifetime, {}),
            streak   = int(row.streak),
            best     = int(row.best_streak),
            today    = { done = done, of = of },
        }
    end

    return out
end

--- A job's current competition board: { counter, top = { { place, name, value } } }.
function gg.jobs.standings(job, limit)
    if type(job) ~= "string" or not prepare() then return nil end

    -- The one still running (unsettled), else the latest.
    local week = MySQL.scalar.await("SELECT week FROM gg_studio_job_weeks WHERE job = ? ORDER BY settled ASC, week DESC LIMIT 1", { job })

    if not week then return nil end

    local counter = MySQL.scalar.await("SELECT counter FROM gg_studio_job_weeks WHERE job = ? AND week = ?", { job, week })
    local top = {}

    for index, entry in ipairs(MySQL.query.await(
        "SELECT name, value FROM gg_studio_job_compete WHERE job = ? AND week = ? AND value > 0 ORDER BY value DESC, updated_at ASC LIMIT ?",
        { job, week, math.max(1, math.min(100, int(limit or 10))) }
    ) or {}) do
        top[index] = { place = index, name = entry.name or "?", value = int(entry.value) }
    end

    return { week = week, period = periodInfo(math.floor(tonumber(week) or 0)), counter = counter, top = top }
end
