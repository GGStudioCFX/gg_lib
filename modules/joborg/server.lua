-- MARK: The company engine (server)
--
-- One setup call from the job (gg.joborg.setup, README.md), then the job forwards its
-- tablet's org_* calls to gg.joborg.call and reports every finished job through
-- gg.joborg.jobDone. Everything else lives here: the tables (named from the job's prefix,
-- created on start, missing columns added, nothing dropped), roles and the rank rule,
-- the company account and its ledger, the pay split, levels, upgrades, the daily
-- challenge board, invites and join requests, the activity feed, the leaderboards and the
-- live pushes to open tablets.
--
-- Money only moves in single conditional UPDATEs (a company never goes below zero, a tier
-- is bought once), and a bank payment that fails puts the money back. Every permission and
-- every limit is checked here, never trusted from the tablet. Writes for one company run
-- one at a time (a lock per player, then per company, always in that order).

local joborg = gg.joborg

local DAY = 86400

local PUSH_DELAY       = 250        -- ms: changes to one company go out together
local DIRECTORY_PAGE   = 6
local LEDGER_PAGE      = 8
local BOARD_PAGE       = 8
local NEWEST           = 20         -- ledger and feed rows in the payload
local SEARCH_MAX       = 32
local INVITE_TTL       = 3 * DAY
local REQUEST_TTL      = 7 * DAY
local REQUEST_MAX      = 25         -- join requests waiting per company (taxi's)
local INVITE_MAX       = 25         -- invites waiting per company
local INVITE_GAP       = 3          -- seconds between one player's invites
local NEARBY           = 10.0       -- metres: who org_nearby lists
local NEARBY_ALLOW     = 15.0       -- metres: how far an invite may still reach (they walk)
local NEARBY_MAX       = 12
local TRANSFER_MAX     = 10000000   -- one deposit or withdrawal (taxi's ceiling)
local DAILY_KEEP_DAYS  = 8
local FEED_KEEP_DAYS   = 30
local LEDGER_KEEP_DAYS = 60
local BOARD_CACHE_MS   = 10000

local say = joborg.say
local copy = joborg.copy

local job = nil       -- the job's setup, nil until gg.joborg.setup
local T = {}          -- table names
local ready, preparing = false, false

local function warn(text)
    if gg.print and gg.print.warn then gg.print.warn(text) else print(text) end
end

local function complain(text)
    if gg.print and gg.print.error then gg.print.error(text) else print(text) end
end

local function note(text)
    if gg.print and gg.print.log then gg.print.log(text) else print(text) end
end

local function int(value, fallback)
    local number = tonumber(value)

    if not number or number ~= number or number == math.huge or number == -math.huge then return fallback or 0 end

    return math.floor(number)
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function fail(key, ...)
    return { ok = false, error = say(key, ...), code = key }
end

-- The job's localized line, or `fallback` when its locale has no such key.
local function sayOr(key, fallback)
    local text = say(key)

    if text == key then return fallback end

    return text
end

-- MARK: Hooks

local function hook(name, ...)
    local fn = job and job.hooks[name]

    if type(fn) ~= "function" then return nil end

    local ok, a, b = pcall(fn, ...)

    if not ok then
        warn(("Companies: the job's %s hook failed: %s"):format(name, tostring(a)))

        return nil
    end

    return a, b
end

-- MARK: Tables

local sqlCache = {}

-- SQL with {orgs}, {members}, ... swapped for this job's table names.
local function S(text)
    local hit = sqlCache[text]

    if hit then return hit end

    hit = text:gsub("{(%w+)}", function(key)
        return "`" .. assert(T[key], key) .. "`"
    end)

    sqlCache[text] = hit

    return hit
end

local function query(sql, params)
    return MySQL.query.await(S(sql), params or {}) or {}
end

local function single(sql, params)
    return query(sql, params)[1]
end

local function update(sql, params)
    return int(MySQL.update.await(S(sql), params or {}), 0)
end

local function insert(sql, params)
    return MySQL.insert.await(S(sql), params or {})
end

local function marks(count)
    return string.rep("?", count, ",")
end

local function decode(raw)
    if type(raw) ~= "string" or raw == "" then return {} end

    local ok, value = pcall(json.decode, raw)

    return ok and type(value) == "table" and value or {}
end

local SCHEMA = {
    {
        key = "orgs",
        create = [[
            CREATE TABLE IF NOT EXISTS {orgs} (
                `id` INT NOT NULL AUTO_INCREMENT,
                `slug` VARCHAR(64) NOT NULL,
                `name` VARCHAR(64) NOT NULL,
                `description` VARCHAR(255) NOT NULL DEFAULT '',
                `owner_identifier` VARCHAR(100) NULL DEFAULT NULL,
                `owner_name` VARCHAR(100) NOT NULL DEFAULT '',
                `access_mode` VARCHAR(16) NOT NULL DEFAULT 'open',
                `driver_split` INT NOT NULL DEFAULT 80,
                `split_changed_at` INT NOT NULL DEFAULT 0,
                `experience` INT NOT NULL DEFAULT 0,
                `upgrade_tier` INT NOT NULL DEFAULT 1,
                `balance` BIGINT NOT NULL DEFAULT 0,
                `total_earnings` BIGINT NOT NULL DEFAULT 0,
                `total_jobs` INT NOT NULL DEFAULT 0,
                `totals` LONGTEXT NULL,
                `challenge_progress` LONGTEXT NULL,
                `challenges_reset_at` INT NOT NULL DEFAULT 0,
                `created_at` INT NOT NULL DEFAULT 0,
                PRIMARY KEY (`id`) USING BTREE,
                UNIQUE KEY `uq_slug` (`slug`),
                UNIQUE KEY `uq_name` (`name`),
                KEY `idx_experience` (`experience`),
                KEY `idx_earnings` (`total_earnings`),
                KEY `idx_jobs` (`total_jobs`)
            ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]],
        columns = {
            { "description", "VARCHAR(255) NOT NULL DEFAULT ''" },
            { "owner_identifier", "VARCHAR(100) NULL DEFAULT NULL" },
            { "owner_name", "VARCHAR(100) NOT NULL DEFAULT ''" },
            { "access_mode", "VARCHAR(16) NOT NULL DEFAULT 'open'" },
            { "driver_split", "INT NOT NULL DEFAULT 80" },
            { "split_changed_at", "INT NOT NULL DEFAULT 0" },
            { "experience", "INT NOT NULL DEFAULT 0" },
            { "upgrade_tier", "INT NOT NULL DEFAULT 1" },
            { "balance", "BIGINT NOT NULL DEFAULT 0" },
            { "total_earnings", "BIGINT NOT NULL DEFAULT 0" },
            { "total_jobs", "INT NOT NULL DEFAULT 0" },
            { "totals", "LONGTEXT NULL" },
            { "challenge_progress", "LONGTEXT NULL" },
            { "challenges_reset_at", "INT NOT NULL DEFAULT 0" },
            { "created_at", "INT NOT NULL DEFAULT 0" },
        },
    },
    {
        key = "members",
        create = [[
            CREATE TABLE IF NOT EXISTS {members} (
                `id` INT NOT NULL AUTO_INCREMENT,
                `org_id` INT NOT NULL,
                `identifier` VARCHAR(100) NOT NULL,
                `name` VARCHAR(100) NOT NULL DEFAULT '',
                `role_id` VARCHAR(32) NULL DEFAULT NULL,
                `joined_at` INT NOT NULL DEFAULT 0,
                `total_jobs` INT NOT NULL DEFAULT 0,
                `total_earnings` BIGINT NOT NULL DEFAULT 0,
                `contributed` BIGINT NOT NULL DEFAULT 0,
                `last_active` INT NOT NULL DEFAULT 0,
                PRIMARY KEY (`id`) USING BTREE,
                UNIQUE KEY `unique_member` (`identifier`),
                KEY `idx_org` (`org_id`)
            ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]],
        columns = {
            { "name", "VARCHAR(100) NOT NULL DEFAULT ''" },
            { "role_id", "VARCHAR(32) NULL DEFAULT NULL" },
            { "joined_at", "INT NOT NULL DEFAULT 0" },
            { "total_jobs", "INT NOT NULL DEFAULT 0" },
            { "total_earnings", "BIGINT NOT NULL DEFAULT 0" },
            { "contributed", "BIGINT NOT NULL DEFAULT 0" },
            { "last_active", "INT NOT NULL DEFAULT 0" },
        },
    },
    {
        key = "ledger",
        create = [[
            CREATE TABLE IF NOT EXISTS {ledger} (
                `id` INT NOT NULL AUTO_INCREMENT,
                `org_id` INT NOT NULL,
                `type` VARCHAR(16) NOT NULL,
                `actor` VARCHAR(100) NOT NULL DEFAULT '',
                `amount` BIGINT NOT NULL DEFAULT 0,
                `balance_after` BIGINT NOT NULL DEFAULT 0,
                `at` INT NOT NULL DEFAULT 0,
                PRIMARY KEY (`id`) USING BTREE,
                KEY `idx_org` (`org_id`, `id`),
                KEY `idx_at` (`at`)
            ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]],
        columns = {
            { "actor", "VARCHAR(100) NOT NULL DEFAULT ''" },
            { "balance_after", "BIGINT NOT NULL DEFAULT 0" },
            { "at", "INT NOT NULL DEFAULT 0" },
        },
    },
    {
        key = "daily",
        create = [[
            CREATE TABLE IF NOT EXISTS {daily} (
                `id` INT NOT NULL AUTO_INCREMENT,
                `org_id` INT NOT NULL,
                `identifier` VARCHAR(100) NOT NULL,
                `day` INT NOT NULL,
                `jobs` INT NOT NULL DEFAULT 0,
                `earnings` BIGINT NOT NULL DEFAULT 0,
                `metrics` LONGTEXT NULL,
                PRIMARY KEY (`id`) USING BTREE,
                UNIQUE KEY `uq_day` (`org_id`, `identifier`, `day`),
                KEY `idx_day` (`day`)
            ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]],
        columns = {
            { "jobs", "INT NOT NULL DEFAULT 0" },
            { "earnings", "BIGINT NOT NULL DEFAULT 0" },
            { "metrics", "LONGTEXT NULL" },
        },
    },
    {
        key = "feed",
        create = [[
            CREATE TABLE IF NOT EXISTS {feed} (
                `id` INT NOT NULL AUTO_INCREMENT,
                `org_id` INT NOT NULL,
                `kind` VARCHAR(16) NOT NULL,
                `actor` VARCHAR(100) NOT NULL DEFAULT '',
                `target` VARCHAR(100) NOT NULL DEFAULT '',
                `detail` VARCHAR(100) NOT NULL DEFAULT '',
                `at` INT NOT NULL DEFAULT 0,
                PRIMARY KEY (`id`) USING BTREE,
                KEY `idx_org` (`org_id`, `id`),
                KEY `idx_at` (`at`)
            ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]],
        columns = {
            { "target", "VARCHAR(100) NOT NULL DEFAULT ''" },
            { "detail", "VARCHAR(100) NOT NULL DEFAULT ''" },
            { "at", "INT NOT NULL DEFAULT 0" },
        },
    },
    {
        key = "invites",
        create = [[
            CREATE TABLE IF NOT EXISTS {invites} (
                `id` INT NOT NULL AUTO_INCREMENT,
                `org_id` INT NOT NULL,
                `identifier` VARCHAR(100) NOT NULL,
                `kind` VARCHAR(8) NOT NULL DEFAULT 'invite',
                `name` VARCHAR(100) NOT NULL DEFAULT '',
                `level` INT NOT NULL DEFAULT 1,
                `from_name` VARCHAR(100) NOT NULL DEFAULT '',
                `at` INT NOT NULL DEFAULT 0,
                PRIMARY KEY (`id`) USING BTREE,
                UNIQUE KEY `uq_invite` (`org_id`, `identifier`, `kind`),
                KEY `idx_player` (`identifier`, `kind`)
            ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;
        ]],
        columns = {
            { "name", "VARCHAR(100) NOT NULL DEFAULT ''" },
            { "level", "INT NOT NULL DEFAULT 1" },
            { "from_name", "VARCHAR(100) NOT NULL DEFAULT ''" },
            { "at", "INT NOT NULL DEFAULT 0" },
        },
    },
}

local function addMissingColumns(entry)
    local name = T[entry.key]
    local present = {}

    for _, row in ipairs(MySQL.query.await("SELECT COLUMN_NAME AS col FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?", { name }) or {}) do
        present[row.col] = true
    end

    for _, column in ipairs(entry.columns) do
        if not present[column[1]] then
            MySQL.query.await(("ALTER TABLE `%s` ADD COLUMN `%s` %s"):format(name, column[1], column[2]))
            note(("Companies: added column %s.%s"):format(name, column[1]))
        end
    end
end

--- Creates the job's tables once (later calls return at once). Waits while another call
--- is creating them. False when the database is not there.
local function prepare()
    if ready then return true end
    if not job or not MySQL then return false end

    if preparing then
        local waited = 0

        while preparing and waited < 20000 do
            Wait(50)
            waited = waited + 50
        end

        return ready
    end

    preparing = true

    local ok, err = pcall(function()
        for _, entry in ipairs(SCHEMA) do
            MySQL.query.await(S(entry.create))
            addMissingColumns(entry)
        end
    end)

    preparing = false

    if not ok then
        complain(("Companies: could not prepare the tables: %s"):format(tostring(err)))

        return false
    end

    ready = true

    return true
end

-- MARK: The day

local clock = { day = 0, next = 0 }

local function daily(name)
    local ok, value = pcall(function() return gg.daily[name]() end)

    return ok and tonumber(value) or nil
end

--- The start of the current day (gg_lib's daily reset).
local function today()
    local now = os.time()

    if clock.day > 0 and now < clock.next then return clock.day end

    local last = daily("lastAt") or 0
    local nextAt = daily("nextAt") or 0

    if last <= 0 or last > now then last = now - now % DAY end
    if nextAt <= last then nextAt = last + DAY end

    if now < nextAt then
        clock.day, clock.next = math.floor(last), math.floor(nextAt)
    end

    return math.floor(last)
end

local function resetsIn()
    local left = daily("secondsUntil")

    if left and left > 0 then return math.floor(left) end

    return math.max(0, (today() + DAY) - os.time())
end

-- MARK: Locks

local held = {}

local function acquire(key)
    local co = coroutine.running()
    local entry = held[key]

    if entry and entry.co == co then
        entry.depth = entry.depth + 1

        return true
    end

    local waited = 0

    while held[key] do
        if waited >= 10000 then return false end

        Wait(25)
        waited = waited + 25
    end

    held[key] = { co = co, depth = 1 }

    return true
end

local function release(key)
    local entry = held[key]

    if not entry then return end

    entry.depth = entry.depth - 1

    if entry.depth <= 0 then held[key] = nil end
end

--- Runs fn holding a lock on every player and company named: players first, then
--- companies, each in order, so two writes never wait on each other in a circle.
local function guarded(players, companies, fn)
    local keys, seen = {}, {}
    local people, firms = {}, {}

    for _, id in ipairs(players or {}) do
        if id and not seen["p:" .. id] then
            seen["p:" .. id] = true
            people[#people + 1] = "p:" .. id
        end
    end

    for _, id in ipairs(companies or {}) do
        if id and not seen["o:" .. id] then
            seen["o:" .. id] = true
            firms[#firms + 1] = ("o:%010d"):format(int(id))
        end
    end

    table.sort(people)
    table.sort(firms)

    for _, key in ipairs(people) do keys[#keys + 1] = key end
    for _, key in ipairs(firms) do keys[#keys + 1] = key end

    local taken = {}

    for _, key in ipairs(keys) do
        if not acquire(key) then
            for index = #taken, 1, -1 do release(taken[index]) end

            return fail("orgerr_busy")
        end

        taken[#taken + 1] = key
    end

    local ok, result = pcall(fn)

    for index = #taken, 1, -1 do release(taken[index]) end

    if not ok then error(result, 0) end

    return result
end

-- MARK: Owner settings

local function read(path)
    return settings.read(job.root .. "." .. path)
end

local function levelCurve()
    local out = {}
    local rows = read("org_levels.curve")

    if type(rows) == "table" then
        for index, row in ipairs(rows) do
            out[index] = math.max(0, int(type(row) == "table" and row.experience or row))
        end
    end

    if #out == 0 then out = copy(joborg.LEVELS) end

    out[1] = 0

    return out
end

local function levelOf(experience, curve)
    curve = curve or levelCurve()

    local xp = math.max(0, int(experience))
    local level = 1

    for index = 2, #curve do
        if xp >= curve[index] then level = index else break end
    end

    return level
end

local function levelInfo(experience)
    local curve = levelCurve()
    local xp = math.max(0, int(experience))
    local level = levelOf(xp, curve)
    local floor = curve[level] or 0
    local following = curve[level + 1]
    local progress = 1

    if following then progress = clamp((xp - floor) / math.max(1, following - floor), 0, 1) end

    return {
        level            = level,
        max_level        = following == nil,
        experience       = xp,
        level_experience = floor,
        next_experience  = following,
        progress         = progress,
    }
end

local function tierList()
    local out = {}
    local rows = read("org_upgrades.list")

    if type(rows) ~= "table" or #rows == 0 then rows = joborg.TIERS end

    for index, row in ipairs(rows) do
        if type(row) == "table" then
            local tier = math.max(1, int(row.tier, index))
            local title = type(row.title) == "string" and row.title or ""

            if title == "" or title == joborg.shipped.tiers[tier] then title = say("orgset_tier_title", tier) end

            out[#out + 1] = {
                tier             = tier,
                title            = title,
                required_level   = math.max(0, int(row.required_level)),
                cost             = math.max(0, int(row.cost)),
                members          = math.max(1, int(row.members or row.member_capacity, 4)),
                challenge_slots  = clamp(int(row.challenge_slots, index), 0, 5),
                money_bonus      = clamp(int(row.money_bonus), 0, 100),
                experience_bonus = clamp(int(row.experience_bonus), 0, 100),
            }

            -- The job's own fields (tier_fields) ride along untouched.
            for key, value in pairs(row) do
                if out[#out][key] == nil and type(key) == "string" then out[#out][key] = value end
            end
        end
    end

    table.sort(out, function(a, b) return a.tier < b.tier end)

    return out
end

local function payMoney()
    return read("org_challenges.pay_money") ~= false
end

local function creation()
    return {
        required_level = math.max(1, int(read("organizations.required_level"), 5)),
        cost           = math.max(0, int(read("organizations.creation_cost"), 25000)),
    }
end

local function splitRange()
    local value = read("organizations.pay_split")

    value = type(value) == "table" and value or {}

    local low = clamp(int(value.min, 75), 1, 100)
    local high = clamp(int(value.max, 95), low, 100)

    return { min = low, max = high, step = joborg.SPLIT_STEP, cooldown_minutes = joborg.SPLIT_COOLDOWN }
end

local function splitOf(org, range)
    range = range or splitRange()

    return clamp(int(org.driver_split, 80), range.min, range.max)
end

-- The board rows the owner set, with what each one counts.
local function boardRows()
    local out = {}
    local rows = read("org_challenges.list")

    if type(rows) ~= "table" then return out end

    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.id) == "string" then
            local kind = joborg.board[row.id] or {}
            local shipped = joborg.shipped.board[row.id] or {}
            local label = type(row.label) == "string" and row.label or ""
            local description = type(row.description) == "string" and row.description or ""

            if label == "" or label == shipped.label then label = sayOr(("orgch_%s_label"):format(row.id), label ~= "" and label or row.id) end
            if description == shipped.description then description = sayOr(("orgch_%s_desc"):format(row.id), description) end

            local low = math.max(1, int(row.target_min, 1))

            out[#out + 1] = {
                id          = row.id,
                label       = label,
                description = description,
                icon        = type(row.icon) == "string" and row.icon ~= "" and row.icon or "fa-flag",
                metric      = kind.metric or (not kind.rotates and job.unit or nil),
                rotates     = kind.rotates,
                target_min  = low,
                target_max  = math.max(low, int(row.target_max, low)),
                experience  = math.max(0, int(row.experience)),
                money       = math.max(0, int(row.money)),
            }
        end
    end

    return out
end

-- What a tier has: the best of every tier up to it (taxi's rule).
local function perksOf(tier, tiers, boardSize)
    tiers = tiers or tierList()

    local perks = { members = 1, slots = 0, money = 0, experience = 0 }

    for _, row in ipairs(tiers) do
        if row.tier <= tier then
            perks.members = math.max(perks.members, row.members)
            perks.slots = math.max(perks.slots, row.challenge_slots)
            perks.money = math.max(perks.money, row.money_bonus)
            perks.experience = math.max(perks.experience, row.experience_bonus)
        end
    end

    perks.slots = math.min(boardSize or #boardRows(), math.max(1, perks.slots))

    return perks
end

-- The tier that opens board slot `index`.
local function unlockTier(index, tiers)
    local best = 0

    for _, row in ipairs(tiers) do
        best = math.max(best, row.challenge_slots)

        if math.max(1, best) >= index then return row.tier end
    end

    return 0
end

-- MARK: Roles

local roleIndex = {}

local function roles()
    return job and job.roles or joborg.ROLES
end

local function ownerRole()
    local best

    for _, role in ipairs(roles()) do
        if role.id == "owner" then return role end
        if not best or role.rank > best.rank then best = role end
    end

    return best
end

local function defaultRole()
    local lowest

    for _, role in ipairs(roles()) do
        if role.default then return role end
        if not lowest or role.rank < lowest.rank then lowest = role end
    end

    return lowest
end

-- Ownership is the company row's owner, never a stored role.
local function roleOf(org, member)
    if member.identifier == org.owner_identifier then return ownerRole() end

    local role = roleIndex[member.role_id]

    if not role or role == ownerRole() then return defaultRole() end

    return role
end

local function permissionsOf(role)
    if role.permissions == "all" then return copy(joborg.PERMISSIONS) end

    local out = {}

    for _, permission in ipairs(role.permissions or {}) do out[#out + 1] = permission end

    return out
end

local function can(role, permission)
    if role.permissions == "all" then return true end

    for _, held in ipairs(role.permissions or {}) do
        if held == permission then return true end
    end

    return false
end

local function roleLabel(role)
    return sayOr("org_role_" .. role.id, role.label or role.id)
end

-- MARK: Who is who

local seen = {}       -- source -> { id, at }
local watchers = {}   -- source -> true while the job says nothing about its tablet

--- A player's identifier; `fresh` asks the job again (writes always do).
local function identify(source, fresh)
    source = tonumber(source)

    if not source or source <= 0 or not GetPlayerName(source) then return nil end

    local hit = seen[source]
    local now = os.time()

    if hit and not fresh and now - hit.at < 30 then return hit.id end

    local id = hook("identifier", source)

    if type(id) ~= "string" or id == "" then
        seen[source] = nil

        return nil
    end

    seen[source] = { id = id, at = now }

    return id
end

local online = { at = -60000, map = {} }

local function onlineMap()
    local now = GetGameTimer()

    if now - online.at < 5000 then return online.map end

    local map = {}

    for _, raw in ipairs(GetPlayers()) do
        local source = tonumber(raw)
        local id = source and identify(source)

        if id then map[id] = source end
    end

    online.at, online.map = now, map

    return map
end

local function sourceOf(identifier)
    local source = identifier and onlineMap()[identifier]

    if source and GetPlayerName(source) then return source end

    return nil
end

local function nameOf(source)
    local name = hook("name", source)

    if type(name) ~= "string" or name == "" then name = GetPlayerName(source) or "" end

    return joborg.clean(name, 50) or "?"
end

local function levelsOf(identifiers)
    local out = {}

    if #identifiers == 0 then return out end

    local map = hook("levels", identifiers)

    if type(map) == "table" then
        for _, id in ipairs(identifiers) do out[id] = math.max(1, int(map[id], 1)) end

        return out
    end

    for _, id in ipairs(identifiers) do out[id] = math.max(1, int(hook("level", id), 1)) end

    return out
end

local function facesOf(identifiers)
    if #identifiers == 0 then return {} end

    local map = hook("faces", identifiers)

    return type(map) == "table" and map or {}
end

local function watching(source)
    local on = hook("watching", source)

    if on ~= nil then return on == true end

    return watchers[source] == true
end

-- MARK: Memberships

local memberCache = {}

local function membership(identifier)
    if not identifier then return nil end

    local hit = memberCache[identifier]

    if hit and os.time() - hit.at < 60 then return hit.row or nil end

    local row = single("SELECT * FROM {members} WHERE identifier = ? LIMIT 1", { identifier })

    memberCache[identifier] = { row = row or false, at = os.time() }

    return row
end

local function forget(identifier)
    if identifier then memberCache[identifier] = nil end
end

local function membershipFresh(identifier)
    forget(identifier)

    return membership(identifier)
end

local function orgById(id)
    return single("SELECT * FROM {orgs} WHERE id = ? LIMIT 1", { int(id) })
end

local function orgBySlug(slug)
    if type(slug) ~= "string" or slug == "" or #slug > 64 then return nil end

    return single("SELECT * FROM {orgs} WHERE slug = ? LIMIT 1", { slug })
end

local function orgByName(name)
    if type(name) ~= "string" or name == "" or #name > 128 then return nil end

    return single("SELECT * FROM {orgs} WHERE name = ? LIMIT 1", { name })
end

-- A company by its id (the slug) or, for a notification line, its name.
local function findOrg(key)
    if type(key) ~= "string" then return nil end

    return orgBySlug(key) or orgByName(joborg.clean(key, 64))
end

local function memberCount(orgId)
    return int((single("SELECT COUNT(*) AS n FROM {members} WHERE org_id = ?", { orgId }) or {}).n)
end

local function memberById(orgId, id)
    local number = int(id, 0)

    if number <= 0 then return nil end

    return single("SELECT * FROM {members} WHERE id = ? AND org_id = ? LIMIT 1", { number, orgId })
end

local function identifiersOf(orgId)
    local out = {}

    for _, row in ipairs(query("SELECT identifier FROM {members} WHERE org_id = ?", { orgId })) do out[#out + 1] = row.identifier end

    return out
end

--- The caller's membership, company and role, or nil when they are in none. A member row
--- whose company is gone is removed.
local function mine(ctx)
    local member = membershipFresh(ctx.identifier)

    if not member then return nil end

    local org = orgById(member.org_id)

    if not org then
        update("DELETE FROM {members} WHERE id = ?", { member.id })
        forget(ctx.identifier)

        return nil
    end

    return member, org, roleOf(org, member)
end

-- Invites and requests of a player who just joined a company are done with.
local function clearPending(identifier)
    update("DELETE FROM {invites} WHERE identifier = ?", { identifier })
end

-- MARK: Ledger and feed

local function balanceOf(orgId)
    return int((single("SELECT balance FROM {orgs} WHERE id = ?", { orgId }) or {}).balance)
end

-- amount is signed: money in is positive, money out negative.
local function ledger(orgId, kind, actor, amount)
    local ok, err = pcall(function()
        insert("INSERT INTO {ledger} (org_id, type, actor, amount, balance_after, at) VALUES (?, ?, ?, ?, ?, ?)",
            { orgId, kind, tostring(actor or ""):sub(1, 100), int(amount), balanceOf(orgId), os.time() })
    end)

    if not ok then complain(("Companies: a %s ledger line for company %s was not written: %s"):format(kind, tostring(orgId), tostring(err))) end
end

local function feed(orgId, kind, actor, target, detail)
    local ok, err = pcall(function()
        insert("INSERT INTO {feed} (org_id, kind, actor, target, detail, at) VALUES (?, ?, ?, ?, ?, ?)", {
            orgId, kind, tostring(actor or ""):sub(1, 100), tostring(target or ""):sub(1, 100),
            detail ~= nil and tostring(detail):sub(1, 100) or "", os.time(),
        })
    end)

    if not ok then warn(("Companies: a feed line for company %s was not written: %s"):format(tostring(orgId), tostring(err))) end
end

-- MARK: Pushes and alerts

local pending = {}

local function pushPayload(source)
    if not GetPlayerName(source) then return end

    local ok, payload = pcall(joborg.payload, source)

    if not ok then
        warn(("Companies: could not build the company page for %s: %s"):format(tostring(source), tostring(payload)))

        return
    end

    if payload then hook("push", source, payload) end
end

local function flush(orgId)
    local entry = pending[orgId]

    pending[orgId] = nil

    if not entry then return end

    local ids = {}

    if orgId ~= 0 then
        for _, id in ipairs(identifiersOf(orgId)) do ids[id] = true end
    end

    for id in pairs(entry.extra) do ids[id] = true end

    for id in pairs(ids) do
        local source = sourceOf(id)

        if source then
            if watching(source) then pushPayload(source) end
            if entry.summary then hook("changed", source) end
        end
    end
end

--- Sends every online member of the company (and `extra` identifiers) their fresh page,
--- once for every change made in the next PUSH_DELAY. `summary` also tells the job each
--- one's player block changed (company name, level, role or membership).
local function refresh(orgId, opts)
    orgId = orgId or 0

    local entry = pending[orgId]

    if not entry then
        entry = { summary = false, extra = {} }
        pending[orgId] = entry

        SetTimeout(PUSH_DELAY, function()
            local ok, err = pcall(flush, orgId)

            if not ok then warn(("Companies: a live update failed: %s"):format(tostring(err))) end
        end)
    end

    if opts then
        if opts.summary then entry.summary = true end

        for _, id in ipairs(opts.extra or {}) do
            if id then entry.extra[id] = true end
        end
    end
end

-- A line in the player's notification center, when they are online.
local function alertSource(source, kind, key, args, data)
    if not source then return end

    hook("alert", source, {
        kind   = kind,
        msg    = say(key, table.unpack(args or {})),
        status = "info",
        data   = data or {},
    })
end

local function alert(identifier, kind, key, args, data)
    alertSource(sourceOf(identifier), kind, key, args, data)
end

local function membersWith(org, permission)
    local out = {}

    for _, row in ipairs(query("SELECT identifier, role_id FROM {members} WHERE org_id = ?", { org.id })) do
        if can(roleOf(org, row), permission) then out[#out + 1] = row.identifier end
    end

    return out
end

-- MARK: Company XP

local function addExperience(org, amount)
    amount = math.max(0, int(amount))

    if amount <= 0 then return end

    local before = levelOf(org.experience)

    update("UPDATE {orgs} SET experience = experience + ? WHERE id = ?", { amount, org.id })

    org.experience = int((single("SELECT experience FROM {orgs} WHERE id = ?", { org.id }) or {}).experience, int(org.experience) + amount)

    local after = levelOf(org.experience)

    if after <= before then return end

    feed(org.id, "level", org.name, nil, after)

    for _, id in ipairs(identifiersOf(org.id)) do
        alert(id, "org_level", "orgnote_level", { org.name, after }, { org = org.name, level = after })
    end

    refresh(org.id, { summary = true })

    note(("Companies: %s reached level %d"):format(org.name, after))
end

-- MARK: The challenge board

local rotations = {}   -- org id -> { day, pools = { [kind] = list } }

local function pickIndex(seed, count)
    if count <= 0 then return nil end

    -- A small polynomial hash: it stays below 2^37, so it is exact as an integer or a float.
    local hash = 7

    for position = 1, #seed do
        hash = (hash * 31 + string.byte(seed, position)) % 2147483647
    end

    return (hash % count) + 1
end

-- Today's pick for a rotating row: yesterday's seed never decides today, and once a pick
-- is stored it stays for the day (a company growing mid-day does not swap it).
local function rotationPick(org, entry, day, previous, level)
    local cache = rotations[org.id]

    if not cache or cache.day ~= day then
        cache = { day = day, pools = {} }
        rotations[org.id] = cache
    end

    local pool = cache.pools[entry.rotates]

    if pool == nil then
        pool = {}

        local fn = job.pools[entry.rotates]

        if type(fn) == "function" then
            local ok, list = pcall(fn, {
                id          = org.slug,
                level       = level,
                tier        = int(org.upgrade_tier, 1),
                identifiers = identifiersOf(org.id),
            })

            if ok and type(list) == "table" then
                for _, item in ipairs(list) do
                    if type(item) == "table" and type(item.metric) == "string" then pool[#pool + 1] = item end
                end
            elseif not ok then
                warn(("Companies: the %s rotation failed: %s"):format(tostring(entry.rotates), tostring(list)))
            end
        end

        cache.pools[entry.rotates] = pool
    end

    for _, item in ipairs(pool) do
        if item.metric == previous then return item end
    end

    local pick = pool[pickIndex(("%s:%s:%s"):format(tostring(org.id), tostring(day), tostring(entry.id)), #pool) or 0]

    if pick then return pick end

    return { metric = job.unit, description = sayOr("orgch_fallback_" .. tostring(entry.rotates), entry.description), scale = 1 }
end

--- The company's board for today: progress (reset when the day turned), level and the
--- resolved rows. Never writes; jobDone saves it.
local function boardState(org)
    local day = today()
    local progress = decode(org.challenge_progress)
    local started = int(org.challenges_reset_at)
    local dirty = false

    if started < day then
        progress, started, dirty = {}, day, true
    end

    -- The day's goals are sized by the company's level when the day began, so a level-up
    -- mid-day never moves a goal the drivers are working on.
    local level = int(progress.__level, 0)

    if level < 1 then
        level = levelOf(org.experience)
        progress.__level = level
        dirty = true
    end

    local picks = type(progress.__rotation) == "table" and progress.__rotation or {}
    local done = type(progress.__done) == "table" and progress.__done or {}
    local entries = {}

    for index, row in ipairs(boardRows()) do
        local entry = copy(row)

        entry.scale = 1

        if row.rotates then
            local pick = rotationPick(org, row, started, picks[row.id], level)

            entry.metric = pick.metric

            if type(pick.description) == "string" and pick.description ~= "" then entry.description = pick.description end

            entry.scale = tonumber(pick.scale) or 1

            if picks[row.id] ~= pick.metric then
                if picks[row.id] ~= nil then
                    progress[row.id] = nil
                    done[row.id] = nil
                end

                picks[row.id] = pick.metric
                dirty = true
            end
        end

        entries[index] = entry
    end

    progress.__rotation = picks
    progress.__done = done

    return { progress = progress, started = started, level = level, entries = entries, dirty = dirty }
end

local function targetOf(entry, level, cap)
    local span = math.max(1, cap - 1)
    local steps = clamp(level - 1, 0, span)
    local base = entry.target_min + ((entry.target_max - entry.target_min) * steps) / span

    return math.max(1, math.floor(base * (entry.scale or 1) + 0.5))
end

local function boardView(org, state, tiers)
    state = state or boardState(org)
    tiers = tiers or tierList()

    local cap = #levelCurve()
    local perks = perksOf(int(org.upgrade_tier, 1), tiers, #state.entries)
    local pay = payMoney()
    local list = {}

    for index, entry in ipairs(state.entries) do
        local locked = index > perks.slots
        local target = targetOf(entry, state.level, cap)
        local finished = not locked and state.progress.__done[entry.id] == true
        local current = locked and 0 or math.max(0, int(state.progress[entry.id]))

        list[index] = {
            id          = entry.id,
            label       = entry.label,
            description = entry.description,
            icon        = entry.icon,
            locked      = locked,
            unlock_tier = unlockTier(index, tiers),
            progress    = finished and target or math.min(current, target),
            target      = target,
            complete    = finished or (not locked and current >= target),
            reward      = { experience = entry.experience, money = pay and entry.money or 0 },
        }
    end

    return { list = list, slots = perks.slots, resets_in = resetsIn() }
end

local function saveBoard(orgId, state)
    update("UPDATE {orgs} SET challenge_progress = ?, challenges_reset_at = ? WHERE id = ?", { json.encode(state.progress), state.started, orgId })
end

-- A cleared goal pays the company: XP, and its cash when the owner lets the board pay.
local function award(org, entry, actor)
    local money = payMoney() and entry.money or 0

    if money > 0 then
        update("UPDATE {orgs} SET balance = balance + ? WHERE id = ?", { money, org.id })
        ledger(org.id, "challenge", entry.label, money)
    end

    feed(org.id, "challenge", actor, nil, entry.label)
    addExperience(org, entry.experience)

    note(("Companies: %s cleared the board goal %s"):format(org.name, entry.label))
end

-- Counts a finished job on the board. Runs under the company's lock (jobDone).
local function addProgress(org, deltas, actor)
    local state = boardState(org)
    local perks = perksOf(int(org.upgrade_tier, 1), nil, #state.entries)
    local cap = #levelCurve()
    local cleared = {}
    local changed = state.dirty

    for index, entry in ipairs(state.entries) do
        local amount = index <= perks.slots and entry.metric and int(deltas[entry.metric]) or 0

        if amount > 0 and not state.progress.__done[entry.id] then
            local target = targetOf(entry, state.level, cap)
            local after = math.min(target, int(state.progress[entry.id]) + amount)

            state.progress[entry.id] = after
            changed = true

            if after >= target then
                state.progress.__done[entry.id] = true
                cleared[#cleared + 1] = entry
            end
        end
    end

    if changed then saveBoard(org.id, state) end

    for _, entry in ipairs(cleared) do award(org, entry, actor) end
end

-- MARK: What the tablet shows

local function memberView(org, row, ctx)
    local role = roleOf(org, row)
    local isOnline = ctx.online[row.identifier] ~= nil
    local day = ctx.today[row.identifier]
    local unit = job.unit

    return {
        id          = tostring(row.id),
        name        = row.name ~= "" and row.name or "?",
        role        = role.id,
        role_label  = roleLabel(role),
        rank        = role.rank,
        level       = ctx.levels[row.identifier] or 1,
        online      = isOnline,
        src         = ctx.online[row.identifier],
        face        = ctx.faces[row.identifier] or false,
        is_self     = row.identifier == ctx.viewer,
        owner       = row.identifier == org.owner_identifier,
        joined_at   = int(row.joined_at),
        last_active = isOnline and os.time() or int(row.last_active),
        [unit]      = int(row.total_jobs),
        earnings    = int(row.total_earnings),
        contributed = int(row.contributed),
        today       = { [unit] = day and int(day.jobs) or 0, earnings = day and int(day.earnings) or 0 },
    }
end

local function ledgerRow(row)
    return {
        id            = int(row.id),
        type          = row.type,
        actor         = row.actor,
        amount        = int(row.amount),
        balance_after = int(row.balance_after),
        at            = int(row.at),
    }
end

local function feedRow(row)
    local detail = row.detail

    if row.kind == "role" and roleIndex[detail] then detail = roleLabel(roleIndex[detail]) end

    return {
        id     = int(row.id),
        kind   = row.kind,
        actor  = row.actor,
        target = row.target ~= "" and row.target or nil,
        detail = detail ~= "" and detail or nil,
        at     = int(row.at),
    }
end

local function memberContext(org, rows, viewer)
    local ids = {}

    for index, row in ipairs(rows) do ids[index] = row.identifier end

    local map = onlineMap()
    local present = {}

    for _, id in ipairs(ids) do
        if map[id] and GetPlayerName(map[id]) then present[id] = map[id] end
    end

    local days = {}

    for _, row in ipairs(query("SELECT identifier, jobs, earnings, metrics FROM {daily} WHERE org_id = ? AND day = ?", { org.id, today() })) do
        days[row.identifier] = row
    end

    return { viewer = viewer, online = present, levels = levelsOf(ids), faces = facesOf(ids), today = days }
end

--- The viewer's own company in full (Org in ORG_CONTRACT.md).
local function orgView(org, viewer)
    local rows = query("SELECT * FROM {members} WHERE org_id = ? ORDER BY joined_at ASC, id ASC", { org.id })
    local ctx = memberContext(org, rows, viewer)
    local tiers = tierList()
    local state = boardState(org)
    local perks = perksOf(int(org.upgrade_tier, 1), tiers, #state.entries)
    local info = levelInfo(org.experience)
    local range = splitRange()
    local unit = job.unit
    local roster, me, ownerId = {}, nil, ""
    local present = 0

    for _, row in ipairs(rows) do
        local view = memberView(org, row, ctx)

        roster[#roster + 1] = view

        if view.online then present = present + 1 end
        if row.identifier == viewer then me = row end
        if view.owner then ownerId = view.id end
    end

    table.sort(roster, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.rank ~= b.rank then return a.rank > b.rank end
        if a.name ~= b.name then return a.name < b.name end

        return int(a.id) < int(b.id)
    end)

    local role = me and roleOf(org, me) or defaultRole()

    local requests = {}

    if can(role, "manage_members") then
        local asked = query(("SELECT * FROM {invites} WHERE org_id = ? AND kind = 'request' AND at > ? ORDER BY at ASC LIMIT %d"):format(REQUEST_MAX), { org.id, os.time() - REQUEST_TTL })
        local ids = {}

        for index, row in ipairs(asked) do ids[index] = row.identifier end

        local levels, faces = levelsOf(ids), facesOf(ids)

        for _, row in ipairs(asked) do
            requests[#requests + 1] = {
                id    = tostring(row.id),
                name  = row.name,
                level = levels[row.identifier] or math.max(1, int(row.level, 1)),
                at    = int(row.at),
                face  = faces[row.identifier] or false,
            }
        end
    end

    local ledgerRows, feedRows = {}, {}

    for _, row in ipairs(query(("SELECT * FROM {ledger} WHERE org_id = ? ORDER BY id DESC LIMIT %d"):format(NEWEST), { org.id })) do
        ledgerRows[#ledgerRows + 1] = ledgerRow(row)
    end

    for _, row in ipairs(query(("SELECT * FROM {feed} WHERE org_id = ? ORDER BY id DESC LIMIT %d"):format(NEWEST), { org.id })) do
        feedRows[#feedRows + 1] = feedRow(row)
    end

    local stored = decode(org.totals)
    local totals = { [unit] = int(org.total_jobs), earnings = int(org.total_earnings) }

    for _, key in ipairs(job.totals) do totals[key] = int(stored[key]) end

    local todays = { [unit] = 0, earnings = 0 }

    for _, key in ipairs(job.today) do todays[key] = 0 end

    for _, row in pairs(ctx.today) do
        todays[unit] = todays[unit] + int(row.jobs)
        todays.earnings = todays.earnings + int(row.earnings)

        local metrics = decode(row.metrics)

        for _, key in ipairs(job.today) do todays[key] = todays[key] + int(metrics[key]) end
    end

    return {
        id               = org.slug,
        name             = org.name,
        description      = org.description or "",
        access           = joborg.ACCESS[org.access_mode] and org.access_mode or "open",
        owner            = { id = ownerId, name = org.owner_name or "" },
        created_at       = int(org.created_at),

        level            = info.level,
        max_level        = info.max_level,
        experience       = info.experience,
        level_experience = info.level_experience,
        next_experience  = info.next_experience,
        progress         = info.progress,

        tier             = int(org.upgrade_tier, 1),
        members          = #rows,
        capacity         = perks.members,
        online           = present,

        balance          = int(org.balance),
        split            = splitOf(org, range),
        split_ready_in   = math.max(0, int(org.split_changed_at) + range.cooldown_minutes * 60 - os.time()),
        bonus            = { money = perks.money, experience = perks.experience },

        totals           = totals,
        today            = todays,
        challenges       = boardView(org, state, tiers),

        roster           = roster,
        requests         = requests,
        ledger           = ledgerRows,
        feed             = feedRows,

        viewer           = {
            id    = me and tostring(me.id) or "",
            role  = role.id,
            rank  = role.rank,
            owner = me ~= nil and me.identifier == org.owner_identifier,
            can   = permissionsOf(role),
        },
    }
end

local function unavailable()
    return { can_create = false, create_reason = say("orgerr_unavailable"), invites = {}, requested = {}, org = false }
end

--- OrgPayload for a player: their company in full, or (in none) whether they may start
--- one, the invites waiting for them and the companies they asked to join.
function joborg.payload(source)
    if not job or not prepare() then return unavailable() end

    local identifier = identify(source)

    if not identifier then return unavailable() end

    local member = membership(identifier)
    local org = member and orgById(member.org_id)

    if org then
        return { can_create = false, create_reason = say("orgerr_in_company"), invites = {}, requested = {}, org = orgView(org, identifier) }
    end

    if member then forget(identifier) end

    local out = { can_create = true, invites = {}, requested = {}, org = false }
    local rules = creation()

    if hook("canWork", source) == false then
        out.can_create, out.create_reason = false, say("orgerr_cannot_work")
    elseif int(hook("level", identifier), 1) < rules.required_level then
        out.can_create, out.create_reason = false, say("orgerr_level", rules.required_level)
    end

    local now = os.time()

    for _, row in ipairs(query([[
        SELECT i.id, i.from_name, i.at, o.slug, o.name, o.experience,
            (SELECT COUNT(*) FROM {members} m WHERE m.org_id = o.id) AS member_count
        FROM {invites} i JOIN {orgs} o ON o.id = i.org_id
        WHERE i.identifier = ? AND i.kind = 'invite' AND i.at > ?
        ORDER BY i.at DESC LIMIT 20
    ]], { identifier, now - INVITE_TTL })) do
        out.invites[#out.invites + 1] = {
            id       = tostring(row.id),
            org      = row.slug,
            org_name = row.name,
            level    = levelOf(row.experience),
            members  = int(row.member_count),
            from     = row.from_name,
            at       = int(row.at),
        }
    end

    for _, row in ipairs(query("SELECT o.slug FROM {invites} i JOIN {orgs} o ON o.id = i.org_id WHERE i.identifier = ? AND i.kind = 'request' AND i.at > ?", { identifier, now - REQUEST_TTL })) do
        out.requested[#out.requested + 1] = row.slug
    end

    return out
end

--- The company block of the job's Player: { id, name, level, members, role, role_id, tier }
--- or nil.
function joborg.summary(identifier)
    if not job or type(identifier) ~= "string" or not prepare() then return nil end

    local member = membership(identifier)

    if not member then return nil end

    local org = orgById(member.org_id)

    if not org then
        forget(identifier)

        return nil
    end

    local role = roleOf(org, member)

    return {
        id      = org.slug,
        name    = org.name,
        level   = levelOf(org.experience),
        members = memberCount(org.id),
        role    = roleLabel(role),
        role_id = role.id,
        tier    = int(org.upgrade_tier, 1),
    }
end

--- OrgConstants: the ladders and limits the tablet draws from.
function joborg.constants()
    local roleList = {}

    for index, role in ipairs(roles()) do
        roleList[index] = {
            id          = role.id,
            label       = roleLabel(role),
            rank        = role.rank,
            permissions = permissionsOf(role),
            assignable  = role.assignable ~= false,
            default     = role.default == true,
        }
    end

    local tiers = {}

    for index, row in ipairs(tierList()) do
        tiers[index] = {
            tier             = row.tier,
            title            = row.title,
            required_level   = row.required_level,
            cost             = row.cost,
            members          = row.members,
            challenge_slots  = row.challenge_slots,
            money_bonus      = row.money_bonus,
            experience_bonus = row.experience_bonus,
        }

        for key, value in pairs(row) do
            if tiers[index][key] == nil then tiers[index][key] = value end
        end
    end

    return {
        roles             = roleList,
        permissions       = copy(joborg.PERMISSIONS),
        tiers             = tiers,
        levels            = levelCurve(),
        split             = splitRange(),
        name_limit        = joborg.NAME_MAX,
        description_limit = joborg.DESCRIPTION_MAX,
        creation          = creation(),
        fleet             = job and job.fleet or false,
        pages             = job and job.pages or {},
        unit              = job and job.unit or "jobs",
    }
end

--- Marks a player's tablet open or closed, for a job that does not answer the watching hook.
function joborg.watch(source, on)
    source = tonumber(source)

    if source then watchers[source] = on == true or nil end
end

-- MARK: Joining

-- Seats the player in the company (the caller holds the player's and the company's locks).
local function admit(identifier, org, name)
    local perks = perksOf(int(org.upgrade_tier, 1))

    if memberCount(org.id) >= perks.members then return fail("orgerr_full") end

    local now = os.time()
    local ok, id = pcall(insert, "INSERT INTO {members} (org_id, identifier, name, role_id, joined_at, last_active) VALUES (?, ?, ?, ?, ?, ?)",
        { org.id, identifier, tostring(name or ""):sub(1, 100), defaultRole().id, now, now })

    forget(identifier)

    if not ok or not id then
        if membership(identifier) then return fail("orgerr_in_company") end

        warn(("Companies: could not seat %s in %s: %s"):format(identifier, org.name, tostring(id)))

        return fail("orgerr_failed")
    end

    clearPending(identifier)
    feed(org.id, "join", name)
    refresh(org.id, { summary = true, extra = { identifier } })

    return { ok = true, changed = true }
end

local function admitByInvite(ctx, inviteId)
    if hook("canWork", ctx.source) == false then return fail("orgerr_cannot_work") end

    local first = single("SELECT org_id FROM {invites} WHERE id = ? AND identifier = ? AND kind = 'invite' LIMIT 1", { inviteId, ctx.identifier })

    if not first then return fail("orgerr_invite_gone") end

    return guarded({ ctx.identifier }, { first.org_id }, function()
        local invite = single("SELECT * FROM {invites} WHERE id = ? AND identifier = ? AND kind = 'invite' LIMIT 1", { inviteId, ctx.identifier })

        if not invite or int(invite.at) <= os.time() - INVITE_TTL then return fail("orgerr_invite_gone") end
        if membershipFresh(ctx.identifier) then return fail("orgerr_in_company") end

        local org = orgById(invite.org_id)

        if not org then return fail("orgerr_not_found") end

        return admit(ctx.identifier, org, nameOf(ctx.source))
    end)
end

local function askToJoin(ctx, org)
    return guarded({ ctx.identifier }, { org.id }, function()
        if membershipFresh(ctx.identifier) then return fail("orgerr_in_company") end

        local fresh = orgById(org.id)

        if not fresh then return fail("orgerr_not_found") end
        if fresh.access_mode == "closed" then return fail("orgerr_closed") end

        local now = os.time()
        local waiting = int((single("SELECT COUNT(*) AS n FROM {invites} WHERE org_id = ? AND kind = 'request' AND at > ? AND identifier <> ?", { org.id, now - REQUEST_TTL, ctx.identifier }) or {}).n)

        if waiting >= REQUEST_MAX then return fail("orgerr_requests_full") end

        local name = nameOf(ctx.source)
        local level = levelsOf({ ctx.identifier })[ctx.identifier] or 1
        local already = single("SELECT id FROM {invites} WHERE org_id = ? AND identifier = ? AND kind = 'request' AND at > ? LIMIT 1", { org.id, ctx.identifier, now - REQUEST_TTL })

        insert("INSERT INTO {invites} (org_id, identifier, kind, name, level, from_name, at) VALUES (?, ?, 'request', ?, ?, '', ?) ON DUPLICATE KEY UPDATE name = VALUES(name), level = VALUES(level), at = VALUES(at)",
            { org.id, ctx.identifier, name, level, now })

        if not already then
            for _, id in ipairs(membersWith(fresh, "manage_members")) do
                alert(id, "org_request", "orgnote_request", { name }, { org = fresh.name, from = name })
            end
        end

        refresh(org.id, { extra = { ctx.identifier } })

        return { ok = true, requested = true }
    end)
end

-- MARK: Calls

local actions = {}

actions.org_directory = function(ctx, body)
    local where, params = { "1 = 1" }, {}
    local search = joborg.clean(body.search, SEARCH_MAX)

    if search and search ~= "" then
        local like = "%" .. search:gsub("[\\%%_]", "\\%0") .. "%"

        where[#where + 1] = "(o.name LIKE ? OR o.description LIKE ?)"
        params[#params + 1] = like
        params[#params + 1] = like
    end

    if body.access == "open" or body.access == "invite_only" or body.access == "closed" then
        where[#where + 1] = "o.access_mode = ?"
        params[#params + 1] = body.access
    end

    local orders = { level = "o.experience DESC", members = "member_count DESC", split = "o.driver_split DESC" }
    local order = orders[body.sort] or orders.level
    local filter = table.concat(where, " AND ")
    local total = int((single("SELECT COUNT(*) AS n FROM {orgs} o WHERE " .. filter, params) or {}).n)
    local pages = math.max(1, math.ceil(total / DIRECTORY_PAGE))
    local page = clamp(int(body.page, 1), 1, pages)

    local rows = query(("SELECT o.*, (SELECT COUNT(*) FROM {members} m WHERE m.org_id = o.id) AS member_count FROM {orgs} o WHERE %s ORDER BY %s, o.id ASC LIMIT %d OFFSET %d")
        :format(filter, order, DIRECTORY_PAGE, (page - 1) * DIRECTORY_PAGE), params)

    local present, ids = {}, {}

    for index, row in ipairs(rows) do ids[index] = row.id end

    if #ids > 0 then
        local map = onlineMap()

        for _, row in ipairs(query(("SELECT org_id, identifier FROM {members} WHERE org_id IN (%s)"):format(marks(#ids)), ids)) do
            if map[row.identifier] then present[row.org_id] = (present[row.org_id] or 0) + 1 end
        end
    end

    local asked = {}

    for _, row in ipairs(query("SELECT org_id FROM {invites} WHERE identifier = ? AND kind = 'request' AND at > ?", { ctx.identifier, os.time() - REQUEST_TTL })) do
        asked[row.org_id] = true
    end

    local tiers = tierList()
    local boardSize = #boardRows()
    local range = splitRange()
    local list = {}

    for _, row in ipairs(rows) do
        local tier = int(row.upgrade_tier, 1)

        list[#list + 1] = {
            id          = row.slug,
            name        = row.name,
            description = row.description or "",
            access      = joborg.ACCESS[row.access_mode] and row.access_mode or "open",
            level       = levelOf(row.experience),
            tier        = tier,
            members     = int(row.member_count),
            capacity    = perksOf(tier, tiers, boardSize).members,
            online      = present[row.id] or 0,
            split       = splitOf(row, range),
            owner       = row.owner_name or "",
            requested   = asked[row.id] == true,
        }
    end

    return { ok = true, list = list, total = total, pages = pages, page = page, size = DIRECTORY_PAGE }
end

local function freeSlug(name)
    local base = name:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")

    base = base:sub(1, 48)

    if base == "" then base = "company" end

    local candidate = base

    for suffix = 2, 100 do
        if not single("SELECT id FROM {orgs} WHERE slug = ? LIMIT 1", { candidate }) then return candidate end

        candidate = ("%s_%d"):format(base, suffix)
    end

    return ("%s_%d"):format(base, math.random(1000, 9999999))
end

actions.org_create = function(ctx, body)
    if hook("canWork", ctx.source) == false then return fail("orgerr_cannot_work") end

    local name, why = joborg.normalizeName(body.name)

    if not name then return fail(why) end

    local description = joborg.clean(type(body.description) == "string" and body.description or "", joborg.DESCRIPTION_MAX) or ""
    local access = joborg.ACCESS[body.access] and body.access or "open"
    local rules = creation()

    return guarded({ ctx.identifier }, {}, function()
        if membershipFresh(ctx.identifier) then return fail("orgerr_in_company") end

        if int(hook("level", ctx.identifier), 1) < rules.required_level then return fail("orgerr_level", rules.required_level) end
        if orgByName(name) then return fail("orgerr_name_taken") end

        if rules.cost > 0 and hook("bankCharge", ctx.source, rules.cost, "Company registration") ~= true then
            return fail("orgerr_no_money", joborg.money(rules.cost))
        end

        local founder = nameOf(ctx.source)
        local range = splitRange()
        local split = clamp(80, range.min, range.max)
        local now = os.time()
        local orgId

        local ok, err = pcall(function()
            orgId = insert([[
                INSERT INTO {orgs} (slug, name, description, owner_identifier, owner_name, access_mode, driver_split,
                    split_changed_at, experience, upgrade_tier, balance, total_earnings, total_jobs, totals,
                    challenge_progress, challenges_reset_at, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 1, 0, 0, 0, '{}', '{}', ?, ?)
            ]], { freeSlug(name), name, description, ctx.identifier, founder, access, split, today(), now })

            if not orgId then error("the company row was not written") end

            local memberId = insert("INSERT INTO {members} (org_id, identifier, name, role_id, joined_at, last_active) VALUES (?, ?, ?, ?, ?, ?)",
                { orgId, ctx.identifier, founder, ownerRole().id, now, now })

            if not memberId then error("the owner's member row was not written") end
        end)

        if not ok then
            if orgId then pcall(update, "DELETE FROM {orgs} WHERE id = ?", { orgId }) end

            forget(ctx.identifier)

            if rules.cost > 0 and hook("bankPay", ctx.source, rules.cost, "Company registration returned") ~= true then
                complain(("Companies: could not return the $%d registration to %s after the company failed to save"):format(rules.cost, ctx.identifier))
            end

            warn(("Companies: a company failed to save: %s"):format(tostring(err)))

            if orgByName(name) then return fail("orgerr_name_taken") end
            if membershipFresh(ctx.identifier) then return fail("orgerr_in_company") end

            return fail("orgerr_failed")
        end

        forget(ctx.identifier)
        clearPending(ctx.identifier)
        feed(orgId, "join", founder)

        note(("Companies: %s started %s"):format(founder, name))

        return { ok = true, changed = true }
    end)
end

actions.org_join = function(ctx, body)
    local org = findOrg(body.id or body.org)

    if not org then return fail("orgerr_not_found") end
    if hook("canWork", ctx.source) == false then return fail("orgerr_cannot_work") end
    if membershipFresh(ctx.identifier) then return fail("orgerr_in_company") end

    -- An invite from this company is taken at once, whatever its access.
    local invite = single("SELECT id FROM {invites} WHERE org_id = ? AND identifier = ? AND kind = 'invite' AND at > ? LIMIT 1", { org.id, ctx.identifier, os.time() - INVITE_TTL })

    if invite then return admitByInvite(ctx, invite.id) end

    if org.access_mode == "closed" then return fail("orgerr_closed") end
    if org.access_mode == "invite_only" then return askToJoin(ctx, org) end

    return guarded({ ctx.identifier }, { org.id }, function()
        if membershipFresh(ctx.identifier) then return fail("orgerr_in_company") end

        local fresh = orgById(org.id)

        if not fresh then return fail("orgerr_not_found") end
        if fresh.access_mode == "closed" then return fail("orgerr_closed") end

        -- Switched to invite only in the meantime: ask instead.
        if fresh.access_mode ~= "open" then return askToJoin(ctx, fresh) end

        return admit(ctx.identifier, fresh, nameOf(ctx.source))
    end)
end

actions.org_cancel_request = function(ctx, body)
    local org = findOrg(body.id or body.org)

    if not org then return { ok = true } end

    update("DELETE FROM {invites} WHERE org_id = ? AND identifier = ? AND kind = 'request'", { org.id, ctx.identifier })
    refresh(org.id)

    return { ok = true }
end

actions.org_invite_answer = function(ctx, body)
    local inviteId = int(body.id, 0)
    local row = inviteId > 0 and single("SELECT * FROM {invites} WHERE id = ? AND identifier = ? AND kind = 'invite' LIMIT 1", { inviteId, ctx.identifier })

    if not row then return fail("orgerr_invite_gone") end

    if body.accept ~= true then
        update("DELETE FROM {invites} WHERE id = ?", { row.id })
        refresh(row.org_id)

        return { ok = true }
    end

    if int(row.at) <= os.time() - INVITE_TTL then
        update("DELETE FROM {invites} WHERE id = ?", { row.id })

        return fail("orgerr_invite_gone")
    end

    return admitByInvite(ctx, row.id)
end

-- Turns an invite down from the notification line, which knows the company, not the invite.
actions.org_decline = function(ctx, body)
    local inviteId = int(body.invite, 0)

    if inviteId > 0 then
        update("DELETE FROM {invites} WHERE id = ? AND identifier = ? AND kind = 'invite'", { inviteId, ctx.identifier })

        return { ok = true }
    end

    local org = findOrg(body.id or body.org)

    if org then
        update("DELETE FROM {invites} WHERE org_id = ? AND identifier = ? AND kind = 'invite'", { org.id, ctx.identifier })
        refresh(org.id)
    end

    return { ok = true }
end

actions.org_leave = function(ctx)
    local member, org = mine(ctx)

    if not member then return fail("orgerr_not_member") end

    return guarded({ ctx.identifier }, { org.id }, function()
        local me, fresh = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if fresh.owner_identifier == ctx.identifier then return fail("orgerr_owner_leave") end

        update("DELETE FROM {members} WHERE id = ?", { me.id })
        forget(ctx.identifier)
        feed(fresh.id, "leave", me.name)
        refresh(fresh.id, { summary = true })

        return { ok = true, changed = true }
    end)
end

actions.org_delete = function(ctx, body)
    local member, org = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if org.owner_identifier ~= ctx.identifier then return fail("orgerr_owner_only") end
    if not joborg.sameName(body.confirm, org.name) then return fail("orgerr_confirm") end

    return guarded({ ctx.identifier }, { org.id }, function()
        local me, fresh = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if fresh.owner_identifier ~= ctx.identifier then return fail("orgerr_owner_only") end

        local ids = identifiersOf(fresh.id)
        local balance = int(fresh.balance)

        -- The account goes back to the owner's bank first; if the bank says no, nothing
        -- is deleted.
        if balance > 0 then
            if update("UPDATE {orgs} SET balance = balance - ? WHERE id = ? AND balance >= ?", { balance, fresh.id, balance }) ~= 1 then
                return fail("orgerr_failed")
            end

            if hook("bankPay", ctx.source, balance, "Company closed") ~= true then
                update("UPDATE {orgs} SET balance = balance + ? WHERE id = ?", { balance, fresh.id })

                return fail("orgerr_refund_failed")
            end
        end

        update("DELETE FROM {orgs} WHERE id = ?", { fresh.id })

        local ok, err = pcall(function()
            update("DELETE FROM {members} WHERE org_id = ?", { fresh.id })
            update("DELETE FROM {invites} WHERE org_id = ?", { fresh.id })
            update("DELETE FROM {feed} WHERE org_id = ?", { fresh.id })
            update("DELETE FROM {ledger} WHERE org_id = ?", { fresh.id })
            update("DELETE FROM {daily} WHERE org_id = ?", { fresh.id })
        end)

        if not ok then warn(("Companies: %s was deleted but some of its rows stayed: %s"):format(fresh.name, tostring(err))) end

        for _, id in ipairs(ids) do forget(id) end

        rotations[fresh.id] = nil

        for _, id in ipairs(ids) do
            if id ~= ctx.identifier then alert(id, "org", "orgnote_closed", { fresh.name }, { org = fresh.name }) end
        end

        refresh(0, { summary = true, extra = ids })

        note(("Companies: %s deleted %s and took back $%d"):format(me.name, fresh.name, balance))

        return { ok = true, changed = true, refunded = balance }
    end)
end

actions.org_settings = function(ctx, body)
    local member, org, role = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if not can(role, "manage_company") then return fail("orgerr_no_permission") end

    return guarded({ ctx.identifier }, { org.id }, function()
        local me, fresh, mineRole = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if not can(mineRole, "manage_company") then return fail("orgerr_no_permission") end

        local sets, params = {}, {}
        local renamed

        if body.name ~= nil then
            local name, why = joborg.normalizeName(body.name)

            if not name then return fail(why) end

            if name ~= fresh.name then
                local other = orgByName(name)

                if other and other.id ~= fresh.id then return fail("orgerr_name_taken") end

                sets[#sets + 1] = "name = ?"
                params[#params + 1] = name
                renamed = name
            end
        end

        if body.description ~= nil then
            local description = joborg.clean(type(body.description) == "string" and body.description or "", joborg.DESCRIPTION_MAX) or ""

            if description ~= fresh.description then
                sets[#sets + 1] = "description = ?"
                params[#params + 1] = description
            end
        end

        if body.access ~= nil then
            if not joborg.ACCESS[body.access] then return fail("orgerr_failed") end

            if body.access ~= fresh.access_mode then
                sets[#sets + 1] = "access_mode = ?"
                params[#params + 1] = body.access
            end
        end

        if #sets == 0 then return { ok = true } end

        params[#params + 1] = fresh.id

        local ok, err = pcall(update, ("UPDATE {orgs} SET %s WHERE id = ?"):format(table.concat(sets, ", ")), params)

        if not ok then
            if renamed then return fail("orgerr_name_taken") end

            warn(("Companies: settings for %s were not saved: %s"):format(fresh.name, tostring(err)))

            return fail("orgerr_failed")
        end

        if renamed then feed(fresh.id, "rename", me.name, nil, renamed) end

        refresh(fresh.id, { summary = renamed ~= nil })

        return { ok = true }
    end)
end

actions.org_split = function(ctx, body)
    local member, org, role = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if not can(role, "manage_company") then return fail("orgerr_no_permission") end

    local range = splitRange()
    local value = int(body.split, -1)

    if value < range.min or value > range.max or ((value - range.min) % range.step ~= 0 and value ~= range.max) then
        return fail("orgerr_split_range", range.min, range.max)
    end

    return guarded({ ctx.identifier }, { org.id }, function()
        local me, fresh, mineRole = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if not can(mineRole, "manage_company") then return fail("orgerr_no_permission") end
        if value == splitOf(fresh, range) then return { ok = true } end

        local now = os.time()
        local wait = int(fresh.split_changed_at) + range.cooldown_minutes * 60 - now

        if wait > 0 then return fail("orgerr_split_cooldown", math.ceil(wait / 60)) end

        if update("UPDATE {orgs} SET driver_split = ?, split_changed_at = ? WHERE id = ? AND split_changed_at = ?", { value, now, fresh.id, int(fresh.split_changed_at) }) ~= 1 then
            return fail("orgerr_failed")
        end

        refresh(fresh.id)

        return { ok = true }
    end)
end

actions.org_bank = function(ctx, body)
    local amount = int(body.amount, 0)

    if amount < 1 or amount > TRANSFER_MAX then return fail("orgerr_amount", joborg.money(TRANSFER_MAX)) end

    local member, org, role = mine(ctx)

    if not member then return fail("orgerr_not_member") end

    if body.direction == "deposit" then
        return guarded({ ctx.identifier }, { org.id }, function()
            local me = mine(ctx)

            if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end

            if hook("bankCharge", ctx.source, amount, "Company deposit") ~= true then
                return fail("orgerr_no_money", joborg.money(amount))
            end

            local ok, changed = pcall(update, "UPDATE {orgs} SET balance = balance + ? WHERE id = ?", { amount, org.id })

            if not ok or changed ~= 1 then
                if hook("bankPay", ctx.source, amount, "Company deposit returned") ~= true then
                    complain(("Companies: could not return a $%d deposit to %s"):format(amount, ctx.identifier))
                end

                return fail("orgerr_failed")
            end

            ledger(org.id, "deposit", me.name, amount)
            refresh(org.id)

            return { ok = true }
        end)
    end

    if body.direction ~= "withdraw" then return fail("orgerr_failed") end
    if not can(role, "treasury_withdraw") then return fail("orgerr_no_permission") end

    return guarded({ ctx.identifier }, { org.id }, function()
        local me, _, mineRole = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if not can(mineRole, "treasury_withdraw") then return fail("orgerr_no_permission") end

        if update("UPDATE {orgs} SET balance = balance - ? WHERE id = ? AND balance >= ?", { amount, org.id, amount }) ~= 1 then
            return fail("orgerr_low_balance")
        end

        if hook("bankPay", ctx.source, amount, "Company withdrawal") ~= true then
            update("UPDATE {orgs} SET balance = balance + ? WHERE id = ?", { amount, org.id })

            return fail("orgerr_pay_failed")
        end

        ledger(org.id, "withdraw", me.name, -amount)
        refresh(org.id)

        return { ok = true }
    end)
end

actions.org_upgrade = function(ctx)
    local member, org, role = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if not can(role, "manage_company") then return fail("orgerr_no_permission") end

    return guarded({ ctx.identifier }, { org.id }, function()
        local me, fresh, mineRole = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if not can(mineRole, "manage_company") then return fail("orgerr_no_permission") end

        local current = int(fresh.upgrade_tier, 1)
        local following

        for _, row in ipairs(tierList()) do
            if row.tier == current + 1 then following = row end
        end

        if not following then return fail("orgerr_max_tier") end
        if levelOf(fresh.experience) < following.required_level then return fail("orgerr_tier_level", following.required_level) end

        if update("UPDATE {orgs} SET balance = balance - ?, upgrade_tier = ? WHERE id = ? AND upgrade_tier = ? AND balance >= ?",
            { following.cost, following.tier, fresh.id, current, following.cost }) ~= 1 then
            return fail("orgerr_tier_cost", joborg.money(following.cost))
        end

        if following.cost > 0 then ledger(fresh.id, "upgrade", me.name, -following.cost) end

        feed(fresh.id, "upgrade", me.name, nil, following.tier)
        rotations[fresh.id] = nil
        refresh(fresh.id, { summary = true })

        return { ok = true }
    end)
end

-- Checks the rank rule for `me` acting on `target` (both member rows of `org`).
local function outranks(org, me, target)
    if target.identifier == org.owner_identifier then return false end
    if me.identifier == org.owner_identifier then return true end

    return roleOf(org, target).rank < roleOf(org, me).rank
end

actions.org_role = function(ctx, body)
    local member, org, role = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if not can(role, "manage_roles") then return fail("orgerr_no_permission") end

    local wanted = type(body.role) == "string" and roleIndex[body.role] or nil

    if not wanted or wanted.assignable == false or wanted == ownerRole() then return fail("orgerr_role_invalid") end

    local target = memberById(org.id, body.id)

    if not target then return fail("orgerr_member_gone") end
    if target.identifier == ctx.identifier then return fail("orgerr_self") end

    return guarded({ ctx.identifier, target.identifier }, { org.id }, function()
        local me, fresh, mineRole = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if not can(mineRole, "manage_roles") then return fail("orgerr_no_permission") end

        local other = memberById(fresh.id, body.id)

        if not other then return fail("orgerr_member_gone") end
        if not outranks(fresh, me, other) then return fail("orgerr_rank") end

        -- Below the owner, nobody gives a role at or above their own.
        if me.identifier ~= fresh.owner_identifier and wanted.rank >= mineRole.rank then return fail("orgerr_rank") end
        if roleOf(fresh, other) == wanted then return { ok = true } end

        update("UPDATE {members} SET role_id = ? WHERE id = ?", { wanted.id, other.id })
        forget(other.identifier)
        feed(fresh.id, "role", me.name, other.name, wanted.id)
        alert(other.identifier, "org_role", "orgnote_role", { roleLabel(wanted), fresh.name }, { org = fresh.name, role = wanted.id })
        refresh(fresh.id, { summary = true })

        return { ok = true }
    end)
end

actions.org_kick = function(ctx, body)
    local member, org, role = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if not can(role, "manage_members") then return fail("orgerr_no_permission") end

    local target = memberById(org.id, body.id)

    if not target then return fail("orgerr_member_gone") end
    if target.identifier == ctx.identifier then return fail("orgerr_self") end

    return guarded({ ctx.identifier, target.identifier }, { org.id }, function()
        local me, fresh, mineRole = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if not can(mineRole, "manage_members") then return fail("orgerr_no_permission") end

        local other = memberById(fresh.id, body.id)

        if not other then return fail("orgerr_member_gone") end
        if not outranks(fresh, me, other) then return fail("orgerr_rank") end

        update("DELETE FROM {members} WHERE id = ? AND org_id = ?", { other.id, fresh.id })
        forget(other.identifier)
        feed(fresh.id, "kick", me.name, other.name)
        alert(other.identifier, "org_kicked", "orgnote_kicked", { fresh.name }, { org = fresh.name })
        refresh(fresh.id, { summary = true, extra = { other.identifier } })

        return { ok = true }
    end)
end

actions.org_owner = function(ctx, body)
    local member, org = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if org.owner_identifier ~= ctx.identifier then return fail("orgerr_owner_only") end

    local target = memberById(org.id, body.id)

    if not target then return fail("orgerr_member_gone") end
    if target.identifier == ctx.identifier then return fail("orgerr_self") end

    return guarded({ ctx.identifier, target.identifier }, { org.id }, function()
        local me, fresh = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if fresh.owner_identifier ~= ctx.identifier then return fail("orgerr_owner_only") end

        local other = memberById(fresh.id, body.id)

        if not other then return fail("orgerr_member_gone") end

        if update("UPDATE {orgs} SET owner_identifier = ?, owner_name = ? WHERE id = ? AND owner_identifier = ?",
            { other.identifier, other.name, fresh.id, ctx.identifier }) ~= 1 then
            return fail("orgerr_failed")
        end

        update("UPDATE {members} SET role_id = ? WHERE id = ?", { ownerRole().id, other.id })
        update("UPDATE {members} SET role_id = ? WHERE id = ?", { defaultRole().id, me.id })
        forget(other.identifier)
        forget(me.identifier)
        feed(fresh.id, "owner", me.name, other.name)
        alert(other.identifier, "org", "orgnote_owner", { fresh.name }, { org = fresh.name })
        refresh(fresh.id, { summary = true })

        return { ok = true, changed = true }
    end)
end

actions.org_request = function(ctx, body)
    local member, org, role = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if not can(role, "manage_members") then return fail("orgerr_no_permission") end

    local requestId = int(body.id, 0)
    local request = requestId > 0 and single("SELECT * FROM {invites} WHERE id = ? AND org_id = ? AND kind = 'request' LIMIT 1", { requestId, org.id })

    if not request then return fail("orgerr_request_gone") end

    return guarded({ ctx.identifier, request.identifier }, { org.id }, function()
        local me, fresh, mineRole = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if not can(mineRole, "manage_members") then return fail("orgerr_no_permission") end

        local asked = single("SELECT * FROM {invites} WHERE id = ? AND org_id = ? AND kind = 'request' LIMIT 1", { requestId, fresh.id })

        if not asked then return fail("orgerr_request_gone") end

        if body.approve ~= true then
            update("DELETE FROM {invites} WHERE id = ?", { asked.id })
            alert(asked.identifier, "org", "orgnote_declined", { fresh.name }, { org = fresh.name })
            refresh(fresh.id, { extra = { asked.identifier } })

            return { ok = true }
        end

        if membershipFresh(asked.identifier) then
            update("DELETE FROM {invites} WHERE id = ?", { asked.id })
            refresh(fresh.id)

            return fail("orgerr_target_in_company")
        end

        -- The name they asked with, never a placeholder (taxi stored "Driver").
        local answer = admit(asked.identifier, fresh, asked.name)

        if answer.ok then
            alert(asked.identifier, "org_accepted", "orgnote_accepted", { fresh.name }, { org = fresh.name })
            answer.changed = nil
        end

        return answer
    end)
end

local function pedCoords(source)
    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then return nil end

    return GetEntityCoords(ped)
end

actions.org_nearby = function(ctx)
    local member, org, role = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if not can(role, "invite") then return fail("orgerr_no_permission") end

    local origin = pedCoords(ctx.source)

    if not origin then return { ok = true, list = {} } end

    local found = {}

    for _, raw in ipairs(GetPlayers()) do
        local source = tonumber(raw)

        if source and source ~= ctx.source then
            local coords = pedCoords(source)
            local distance = coords and #(coords - origin)

            if distance and distance <= NEARBY then
                local id = identify(source)

                if id then found[#found + 1] = { source = source, id = id, distance = distance } end
            end
        end
    end

    table.sort(found, function(a, b) return a.distance < b.distance end)

    while #found > NEARBY_MAX do table.remove(found) end

    local ids = {}

    for index, entry in ipairs(found) do ids[index] = entry.id end

    local levels = levelsOf(ids)
    local invited = {}

    if #ids > 0 then
        local params = { org.id, os.time() - INVITE_TTL }

        for _, id in ipairs(ids) do params[#params + 1] = id end

        for _, row in ipairs(query(("SELECT identifier FROM {invites} WHERE org_id = ? AND kind = 'invite' AND at > ? AND identifier IN (%s)"):format(marks(#ids)), params)) do
            invited[row.identifier] = true
        end
    end

    local list = {}

    for _, entry in ipairs(found) do
        list[#list + 1] = {
            id         = entry.source,
            name       = nameOf(entry.source),
            level      = levels[entry.id] or 1,
            in_company = membership(entry.id) ~= nil,
            invited    = invited[entry.id] == true,
        }
    end

    return { ok = true, list = list }
end

local lastInvite = {}

actions.org_invite = function(ctx, body)
    local member, org, role = mine(ctx)

    if not member then return fail("orgerr_not_member") end
    if not can(role, "invite") then return fail("orgerr_no_permission") end

    local target = int(body.target, 0)

    if target == ctx.source then return fail("orgerr_self") end
    if target <= 0 or not GetPlayerName(target) then return fail("orgerr_target_gone") end

    local here, there = pedCoords(ctx.source), pedCoords(target)

    if not here or not there then return fail("orgerr_target_gone") end
    if #(there - here) > NEARBY_ALLOW then return fail("orgerr_target_far") end

    local now = os.time()

    if lastInvite[ctx.source] and now - lastInvite[ctx.source] < INVITE_GAP then return fail("orgerr_too_soon") end

    local targetId = identify(target, true)

    if not targetId then return fail("orgerr_target_gone") end
    if hook("canWork", target) == false then return fail("orgerr_target_cannot_work") end

    return guarded({ ctx.identifier, targetId }, { org.id }, function()
        local me, fresh, mineRole = mine(ctx)

        if not me or me.org_id ~= org.id then return fail("orgerr_not_member") end
        if not can(mineRole, "invite") then return fail("orgerr_no_permission") end
        if membershipFresh(targetId) then return fail("orgerr_target_in_company") end
        if memberCount(fresh.id) >= perksOf(int(fresh.upgrade_tier, 1)).members then return fail("orgerr_full") end

        if single("SELECT id FROM {invites} WHERE org_id = ? AND identifier = ? AND kind = 'invite' AND at > ? LIMIT 1", { fresh.id, targetId, now - INVITE_TTL }) then
            return fail("orgerr_already_invited")
        end

        local waiting = int((single("SELECT COUNT(*) AS n FROM {invites} WHERE org_id = ? AND kind = 'invite' AND at > ?", { fresh.id, now - INVITE_TTL }) or {}).n)

        if waiting >= INVITE_MAX then return fail("orgerr_invites_full") end

        local name = nameOf(target)
        local level = levelsOf({ targetId })[targetId] or 1

        insert("INSERT INTO {invites} (org_id, identifier, kind, name, level, from_name, at) VALUES (?, ?, 'invite', ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), level = VALUES(level), from_name = VALUES(from_name), at = VALUES(at)",
            { fresh.id, targetId, name, level, me.name, now })

        lastInvite[ctx.source] = now

        local row = single("SELECT id FROM {invites} WHERE org_id = ? AND identifier = ? AND kind = 'invite' LIMIT 1", { fresh.id, targetId })

        alertSource(target, "org_invite", "orgnote_invite", { me.name, fresh.name }, {
            org    = fresh.name,
            id     = fresh.slug,
            invite = row and tostring(row.id) or nil,
            from   = me.name,
        })

        refresh(fresh.id, { extra = { targetId } })

        return { ok = true }
    end)
end

actions.org_ledger = function(ctx, body)
    local member, org = mine(ctx)

    if not member then return fail("orgerr_not_member") end

    local total = int((single("SELECT COUNT(*) AS n FROM {ledger} WHERE org_id = ?", { org.id }) or {}).n)
    local pages = math.max(1, math.ceil(total / LEDGER_PAGE))
    local page = clamp(int(body.page, 1), 1, pages)
    local list = {}

    for _, row in ipairs(query(("SELECT * FROM {ledger} WHERE org_id = ? ORDER BY id DESC LIMIT %d OFFSET %d"):format(LEDGER_PAGE, (page - 1) * LEDGER_PAGE), { org.id })) do
        list[#list + 1] = ledgerRow(row)
    end

    return { ok = true, list = list, total = total, pages = pages, page = page, size = LEDGER_PAGE }
end

actions.org_member = function(ctx, body)
    local member, org = mine(ctx)

    if not member then return fail("orgerr_not_member") end

    local row = memberById(org.id, body.id)

    if not row then return fail("orgerr_member_gone") end

    local view = memberView(org, row, memberContext(org, { row }, ctx.identifier))
    local day = today()
    local buckets = {}

    for _, entry in ipairs(query("SELECT day, jobs, earnings FROM {daily} WHERE org_id = ? AND identifier = ? AND day > ?", { org.id, row.identifier, day - 7 * DAY })) do
        local back = math.ceil((day - int(entry.day)) / DAY)

        if back >= 0 and back <= 6 then
            local bucket = buckets[back] or { jobs = 0, earnings = 0 }

            bucket.jobs = bucket.jobs + int(entry.jobs)
            bucket.earnings = bucket.earnings + int(entry.earnings)
            buckets[back] = bucket
        end
    end

    local history = {}

    for back = 6, 0, -1 do
        local at = day - back * DAY
        local bucket = buckets[back] or { jobs = 0, earnings = 0 }

        history[#history + 1] = { day = os.date("%Y-%m-%d", at), at = at, [job.unit] = bucket.jobs, earnings = bucket.earnings }
    end

    view.history = history

    return { ok = true, member = view }
end

-- Calls that only read: answered without the busy guard and without a fresh page.
local READS = { org_directory = true, org_nearby = true, org_ledger = true, org_member = true }

local busy = {}

--- Answers one tablet call: { ok, error?, code?, org?, player?, ... }. Every write answers
--- the caller's fresh OrgPayload as `org`, and their fresh Player when their company changed.
function joborg.call(source, name, body)
    if not job then return fail("orgerr_unavailable") end

    local action = actions[name]

    if not action then return fail("orgerr_failed") end
    if not prepare() then return fail("orgerr_unavailable") end

    source = tonumber(source)

    local write = not READS[name]
    local identifier = identify(source, write)

    if not identifier then return fail("orgerr_unavailable") end

    if write then
        if busy[source] then return fail("orgerr_busy") end

        busy[source] = true
        online.map[identifier] = source
    end

    local ok, answer = pcall(action, { source = source, identifier = identifier }, type(body) == "table" and body or {})

    if write then busy[source] = nil end

    if not ok then
        complain(("Companies: %s failed: %s"):format(tostring(name), tostring(answer)))

        answer = fail("orgerr_failed")
    end

    if type(answer) ~= "table" then answer = { ok = answer == true } end

    if write then
        local built, payload = pcall(joborg.payload, source)

        answer.org = built and payload or nil

        if answer.changed then
            answer.player = hook("player", source)
            hook("changed", source)
        end
    end

    answer.changed = nil

    return answer
end

-- MARK: A finished job

--- The job reports a finished job before paying it:
---   report = { money, experience, metrics = { <unit> = 1, ... } }
--- Answers what the worker gets: { money, experience, cut, gross?, split?, company? } -
--- money after the company's cut (the tier's pay bonus first), experience with the tier's
--- XP bonus. A worker in no company gets money and experience back unchanged.
function joborg.jobDone(source, report)
    report = type(report) == "table" and report or {}

    local money = math.max(0, int(report.money))
    local experience = math.max(0, int(report.experience))
    local plain = { money = money, experience = experience, cut = 0 }

    if not job or not prepare() then return plain end

    local identifier = identify(source, true)
    local member = identifier and membership(identifier)

    if not member then return plain end

    local metrics = {}

    if type(report.metrics) == "table" then
        for key, value in pairs(report.metrics) do
            local amount = int(value)

            if type(key) == "string" and amount > 0 then metrics[key] = amount end
        end
    end

    local ok, result = pcall(guarded, { identifier }, { member.org_id }, function()
        local me = membershipFresh(identifier)

        if not me or me.org_id ~= member.org_id then return plain end

        local org = orgById(me.org_id)

        if not org then
            forget(identifier)

            return plain
        end

        local perks = perksOf(int(org.upgrade_tier, 1))
        local split = splitOf(org)
        local gross = money + math.floor(money * perks.money / 100)
        local pay = math.floor(gross * split / 100)
        local cut = gross - pay
        local earned = experience + math.floor(experience * perks.experience / 100)
        local jobs = int(metrics[job.unit])

        metrics.earnings = gross

        local totals = decode(org.totals)

        for _, key in ipairs(job.totals) do
            if metrics[key] then totals[key] = int(totals[key]) + metrics[key] end
        end

        if update("UPDATE {orgs} SET balance = balance + ?, total_earnings = total_earnings + ?, total_jobs = total_jobs + ?, totals = ? WHERE id = ?",
            { cut, gross, jobs, json.encode(totals), org.id }) ~= 1 then
            return plain
        end

        -- The cut is in the company's account now, so the worker is paid the split whatever
        -- happens to the bookkeeping below (a failure there must not pay the cut twice).
        local booked, err = pcall(function()
            local now = os.time()

            update("UPDATE {members} SET total_jobs = total_jobs + ?, total_earnings = total_earnings + ?, contributed = contributed + ?, last_active = ? WHERE id = ?",
                { jobs, gross, cut, now, me.id })

            local day = today()
            local kept = single("SELECT id, metrics FROM {daily} WHERE org_id = ? AND identifier = ? AND day = ? LIMIT 1", { org.id, identifier, day })
            local counted = decode(kept and kept.metrics)

            for _, key in ipairs(job.today) do
                if metrics[key] then counted[key] = int(counted[key]) + metrics[key] end
            end

            if kept then
                update("UPDATE {daily} SET jobs = jobs + ?, earnings = earnings + ?, metrics = ? WHERE id = ?", { jobs, gross, json.encode(counted), kept.id })
            else
                insert("INSERT INTO {daily} (org_id, identifier, day, jobs, earnings, metrics) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE jobs = jobs + VALUES(jobs), earnings = earnings + VALUES(earnings), metrics = VALUES(metrics)",
                    { org.id, identifier, day, jobs, gross, json.encode(counted) })
            end

            if cut > 0 then ledger(org.id, "route", me.name, cut) end

            addProgress(org, metrics, me.name)
            addExperience(org, math.floor(experience * job.share / 100))
        end)

        if not booked then
            complain(("Companies: a finished job for %s was paid but not fully counted: %s"):format(identifier, tostring(err)))
        end

        refresh(org.id)

        return { money = pay, experience = earned, cut = cut, gross = gross, split = split, company = org.slug }
    end)

    if not ok then
        complain(("Companies: a finished job was not counted for %s: %s"):format(tostring(identifier), tostring(result)))

        return plain
    end

    if type(result) ~= "table" or result.ok == false then return plain end

    return result
end

--- Counts work that is not a paid job (taxi: distance driven, rides booked by players) on
--- the company's board, its all-time totals and the worker's day. No money moves.
---   metrics = { distance = 420, ... }  (positive whole numbers; earnings and the unit are ignored)
--- Answers true when the worker is in a company and it was counted.
function joborg.progress(source, metrics)
    if not job or type(metrics) ~= "table" or not prepare() then return false end

    local identifier = identify(source)
    local member = identifier and membership(identifier)

    if not member then return false end

    local deltas = {}

    for key, value in pairs(metrics) do
        local amount = int(value)

        if type(key) == "string" and amount > 0 and key ~= "earnings" and key ~= job.unit then deltas[key] = amount end
    end

    if next(deltas) == nil then return false end

    local ok, result = pcall(guarded, { identifier }, { member.org_id }, function()
        local me = membershipFresh(identifier)
        local org = me and me.org_id == member.org_id and orgById(me.org_id)

        if not org then return false end

        local totals, changed = decode(org.totals), false

        for _, key in ipairs(job.totals) do
            if deltas[key] then
                totals[key] = int(totals[key]) + deltas[key]
                changed = true
            end
        end

        if changed then update("UPDATE {orgs} SET totals = ? WHERE id = ?", { json.encode(totals), org.id }) end

        local day = today()
        local kept = single("SELECT id, metrics FROM {daily} WHERE org_id = ? AND identifier = ? AND day = ? LIMIT 1", { org.id, identifier, day })
        local counted, touched = decode(kept and kept.metrics), false

        for _, key in ipairs(job.today) do
            if deltas[key] then
                counted[key] = int(counted[key]) + deltas[key]
                touched = true
            end
        end

        if touched then
            if kept then
                update("UPDATE {daily} SET metrics = ? WHERE id = ?", { json.encode(counted), kept.id })
            else
                insert("INSERT INTO {daily} (org_id, identifier, day, jobs, earnings, metrics) VALUES (?, ?, ?, 0, 0, ?) ON DUPLICATE KEY UPDATE metrics = VALUES(metrics)",
                    { org.id, identifier, day, json.encode(counted) })
            end
        end

        addProgress(org, deltas, me.name)
        refresh(org.id)

        return true
    end)

    if not ok then
        complain(("Companies: progress was not counted for %s: %s"):format(tostring(identifier), tostring(result)))

        return false
    end

    return result == true
end

-- MARK: Leaderboards

local boardCache = {}

--- The companies' board: { rows = { { position, id, name, value, members, level } }, total,
--- pages, page, size, me? }. board: "experience", the job's unit (e.g. "routes") or
--- "earnings". `source` (optional) adds `me`, the asker's company's place.
function joborg.leaderboard(board, page, source)
    local out = { rows = {}, total = 0, pages = 1, page = 1, size = BOARD_PAGE }

    if not job or not prepare() then return out end

    local columns = { experience = "experience", earnings = "total_earnings", [job.unit] = "total_jobs" }
    local column = columns[board] or "experience"

    board = columns[board] and board or "experience"

    local key = ("%s:%d"):format(board, int(page, 1))
    local cached = boardCache[key]

    if not cached or GetGameTimer() - cached.at > BOARD_CACHE_MS then
        local total = int((single(("SELECT COUNT(*) AS n FROM {orgs} WHERE %s > 0"):format(column)) or {}).n)
        local pages = math.max(1, math.ceil(total / BOARD_PAGE))
        local at = clamp(int(page, 1), 1, pages)
        local rows = {}

        for index, row in ipairs(query(("SELECT o.slug, o.name, o.experience, o.%s AS value, (SELECT COUNT(*) FROM {members} m WHERE m.org_id = o.id) AS member_count FROM {orgs} o WHERE o.%s > 0 ORDER BY o.%s DESC, o.id ASC LIMIT %d OFFSET %d")
            :format(column, column, column, BOARD_PAGE, (at - 1) * BOARD_PAGE))) do
            rows[index] = {
                position = (at - 1) * BOARD_PAGE + index,
                id       = row.slug,
                name     = row.name,
                value    = int(row.value),
                members  = int(row.member_count),
                level    = levelOf(row.experience),
            }
        end

        cached = { at = GetGameTimer(), rows = rows, total = total, pages = pages, page = at }
        boardCache[key] = cached
    end

    out.rows, out.total, out.pages, out.page = cached.rows, cached.total, cached.pages, cached.page

    local identifier = source and identify(source)
    local member = identifier and membership(identifier)
    local org = member and orgById(member.org_id)

    if org then
        local value = int(org[column])

        out.org = { id = org.slug, name = org.name, members = memberCount(org.id) }

        if value > 0 then
            local above = int((single(("SELECT COUNT(*) AS n FROM {orgs} WHERE %s > ? OR (%s = ? AND id < ?)"):format(column, column), { value, value, org.id }) or {}).n)

            out.me = { position = above + 1, id = org.slug, name = org.name, value = value, members = out.org.members, level = levelOf(org.experience) }
        end
    end

    return out
end

-- MARK: The daily reset

local function pushOpenPages()
    for _, raw in ipairs(GetPlayers()) do
        local source = tonumber(raw)

        if source and watching(source) then
            pushPayload(source)
            Wait(0)
        end
    end
end

local function onDailyReset(boundary)
    local ok, err = pcall(function()
        if not prepare() then return end

        local day = int(boundary, 0)

        clock.day, clock.next = 0, 0
        rotations = {}

        day = day > 0 and day or today()

        local now = os.time()

        -- Boards reset themselves on the first read of the new day; this only tidies up.
        update("DELETE FROM {daily} WHERE day < ?", { day - DAILY_KEEP_DAYS * DAY })
        update("DELETE FROM {invites} WHERE (kind = 'invite' AND at < ?) OR (kind = 'request' AND at < ?)", { now - INVITE_TTL, now - REQUEST_TTL })
        update("DELETE FROM {feed} WHERE at < ?", { now - FEED_KEEP_DAYS * DAY })
        update("DELETE FROM {ledger} WHERE at < ?", { now - LEDGER_KEEP_DAYS * DAY })
    end)

    if not ok then complain(("Companies: the daily tidy-up failed: %s"):format(tostring(err))) end

    CreateThread(function()
        Wait(1000)
        pcall(pushOpenPages)
    end)

    return true
end

-- MARK: Setup

--- Wires the engine for one job. Call once, from the job's server code. README.md lists
--- every option and hook; the job's schema calls gg.joborg.settings for the settings.
function joborg.setup(opts)
    if job then return joborg end

    opts = type(opts) == "table" and opts or {}

    local prefix = opts.prefix

    if type(prefix) ~= "string" or not prefix:match("^[%w_]+$") or #prefix > 40 then
        error("gg.joborg.setup needs a table prefix (letters, digits and _)", 2)
    end

    T = {
        orgs    = prefix .. "_orgs",
        members = prefix .. "_org_members",
        ledger  = prefix .. "_org_ledger",
        daily   = prefix .. "_org_daily",
        feed    = prefix .. "_org_feed",
        invites = prefix .. "_org_invites",
    }

    sqlCache = {}

    local hooks = {}

    for key, value in pairs(type(opts.hooks) == "table" and opts.hooks or {}) do hooks[key] = value end

    -- Without the job's own: the character id and the bank through gg_lib's framework bridge.
    hooks.identifier = hooks.identifier or function(source)
        local ok, id = pcall(gg.framework.GetIdentifier, source)

        return ok and id or nil
    end

    hooks.bankPay = hooks.bankPay or function(source, amount, reason)
        local ok, paid = pcall(gg.framework.AddMoney, source, "bank", amount, reason)

        return ok and paid == true
    end

    hooks.bankCharge = hooks.bankCharge or function(source, amount, reason)
        local ok, taken = pcall(gg.framework.RemoveMoney, source, "bank", amount, reason)

        return ok and taken == true
    end

    local function list(value)
        local out = {}

        for _, entry in ipairs(type(value) == "table" and value or {}) do
            if type(entry) == "string" then out[#out + 1] = entry end
        end

        return out
    end

    job = {
        id     = type(opts.job) == "string" and opts.job or GetCurrentResourceName(),
        prefix = prefix,
        root   = type(opts.root) == "string" and opts.root or joborg.root or "settings",
        unit   = type(opts.unit) == "string" and opts.unit or "jobs",
        totals = list(opts.totals),
        today  = list(opts.today),
        share  = clamp(int(opts.experience_share, 0), 0, 100),
        hooks  = hooks,
        pools  = type(hooks.pools) == "table" and hooks.pools or {},
        roles  = type(opts.roles) == "table" and #opts.roles > 0 and opts.roles or joborg.ROLES,
        fleet  = opts.fleet == true,
        pages  = type(opts.pages) == "table" and opts.pages or {},
    }

    if type(opts.text) == "function" then joborg.textFn = opts.text end

    roleIndex = {}

    for _, role in ipairs(job.roles) do roleIndex[role.id] = role end

    pcall(function() gg.daily.onReset(onDailyReset) end)

    if settings and settings.onChange then
        settings.onChange(function()
            rotations = {}
            boardCache = {}
        end)
    end

    AddEventHandler("playerDropped", function()
        local src = source
        local hit = seen[src]

        seen[src], watchers[src], busy[src], lastInvite[src] = nil, nil, nil, nil
        online.at = -60000

        if not hit or not ready then return end

        local member = memberCache[hit.id] and memberCache[hit.id].row

        pcall(update, "UPDATE {members} SET last_active = ? WHERE identifier = ?", { os.time(), hit.id })

        if member then refresh(member.org_id) end
    end)

    CreateThread(function()
        Wait(0)
        prepare()
    end)

    return joborg
end

--- True once the tables are there.
function joborg.ready()
    return ready
end
