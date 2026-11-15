gg.joborg = gg.joborg or {}

-- MARK: Companies for every GG job
--
-- gg.joborg runs the organizations (companies) a job's workers start and join: roles and
-- permissions, the company account and its ledger, the driver pay split, company levels and
-- upgrade tiers, the daily company challenge board, invites and join requests, the activity
-- feed and the companies' leaderboards. The job keeps its own work and tells the engine
-- what a finished job was worth (gg.joborg.jobDone); the engine takes the company's cut and
-- counts it. README.md beside this file is the job-side contract.
--
-- This file is the part both sides load: the fixed ladders, the name rules and the settings
-- helper a job's schema calls. server.lua holds the engine. There is no client file: the job
-- relays its tablet's calls (README.md shows the twelve lines).

local joborg = gg.joborg

-- MARK: Fixed parts

-- What a role may do. The owner and co-owner hold all of them.
joborg.PERMISSIONS = { "manage_members", "manage_roles", "invite", "manage_company", "treasury_withdraw" }

-- The ladder every company uses (labels come from the job's locale: org_role_<id>). A
-- member may only manage members below their own rank and only give roles below it; the
-- owner is never touched. Ownership itself is the company row's owner, never a role.
joborg.ROLES = {
    { id = "owner",         rank = 100, assignable = false, permissions = "all" },
    { id = "co_owner",      rank = 80,  assignable = true,  permissions = "all" },
    { id = "manager",       rank = 60,  assignable = true,  permissions = { "manage_members", "invite" } },
    { id = "senior_driver", rank = 30,  assignable = true,  permissions = { "invite" } },
    { id = "driver",        rank = 10,  assignable = true,  permissions = {}, default = true },
    { id = "trainee",       rank = 5,   assignable = true,  permissions = {} },
}

joborg.ACCESS = { open = true, invite_only = true, closed = true }

joborg.NAME_MIN        = 3
joborg.NAME_MAX        = 20
joborg.DESCRIPTION_MAX = 100
joborg.SPLIT_STEP      = 5
joborg.SPLIT_COOLDOWN  = 30   -- minutes between two changes of a company's pay split

-- Every tablet call the engine answers (the job registers each one; README.md).
joborg.CALLS = {
    "org_directory", "org_create", "org_join", "org_cancel_request", "org_invite_answer", "org_decline",
    "org_leave", "org_delete", "org_settings", "org_split", "org_bank", "org_upgrade", "org_role",
    "org_kick", "org_owner", "org_request", "org_nearby", "org_invite", "org_ledger", "org_member",
}

-- The shipped company level curve (taxi's): total XP for levels 1..15.
joborg.LEVELS = { 0, 150, 400, 700, 1100, 1700, 2500, 3600, 5200, 7200, 10500, 15000, 21000, 60000, 140000 }

-- The shipped upgrade tiers (taxi's, without the garage and the roof banner).
joborg.TIERS = {
    { tier = 1, required_level = 0,  cost = 0,      members = 4,  challenge_slots = 1, money_bonus = 0,  experience_bonus = 0 },
    { tier = 2, required_level = 5,  cost = 50000,  members = 5,  challenge_slots = 2, money_bonus = 2,  experience_bonus = 0 },
    { tier = 3, required_level = 8,  cost = 75000,  members = 6,  challenge_slots = 3, money_bonus = 4,  experience_bonus = 3 },
    { tier = 4, required_level = 10, cost = 110000, members = 8,  challenge_slots = 4, money_bonus = 7,  experience_bonus = 5 },
    { tier = 5, required_level = 13, cost = 150000, members = 10, challenge_slots = 5, money_bonus = 10, experience_bonus = 5 },
}

-- English for every line the engine writes itself, used when the job's locale has no
-- such key. A job ships these keys in all of its languages (README.md lists them).
joborg.ENGLISH = {
    orgerr_unavailable         = "Companies are not available right now.",
    orgerr_failed              = "That did not go through. Try again.",
    orgerr_busy                = "Still working on your last request.",
    orgerr_not_found           = "That company no longer exists.",
    orgerr_not_member          = "You are not in a company.",
    orgerr_in_company          = "You are already in a company.",
    orgerr_cannot_work         = "You cannot work this job.",
    orgerr_level               = "Reach level %d to start a company.",
    orgerr_no_money            = "You need $%s in the bank.",
    orgerr_name_length         = "Company names are 3 to 20 characters.",
    orgerr_name_invalid        = "That name uses characters a company name cannot have.",
    orgerr_name_taken          = "Another company already has that name.",
    orgerr_closed              = "This company is not taking new members.",
    orgerr_full                = "This company has no free seats.",
    orgerr_requests_full       = "This company has too many requests waiting.",
    orgerr_no_permission       = "Your role cannot do that.",
    orgerr_rank                = "You can only manage members below your own role.",
    orgerr_role_invalid        = "That role cannot be given.",
    orgerr_owner_leave         = "Hand the company to another member or delete it before you leave.",
    orgerr_owner_only          = "Only the owner can do that.",
    orgerr_confirm             = "Type the company name exactly to delete it.",
    orgerr_refund_failed       = "The company account could not be paid out, so the company was kept.",
    orgerr_split_range         = "The driver share must be between %d%% and %d%%.",
    orgerr_split_cooldown      = "The share can change again in %d min.",
    orgerr_amount              = "Enter an amount between $1 and $%s.",
    orgerr_low_balance         = "The company account does not hold that much.",
    orgerr_pay_failed          = "The bank payment failed, so nothing was moved.",
    orgerr_max_tier            = "Your company has every upgrade.",
    orgerr_tier_level          = "Your company needs to reach level %d first.",
    orgerr_tier_cost           = "The company account needs $%s for this upgrade.",
    orgerr_member_gone         = "That member is no longer in your company.",
    orgerr_self                = "You cannot do that to yourself.",
    orgerr_target_gone         = "That player is no longer around.",
    orgerr_target_far          = "Stand closer to invite them.",
    orgerr_target_in_company   = "That player is already in a company.",
    orgerr_target_cannot_work  = "That player cannot work this job.",
    orgerr_already_invited     = "That player already has an invite from your company.",
    orgerr_invite_gone         = "That invite is no longer open.",
    orgerr_invites_full        = "Your company has too many invites waiting.",
    orgerr_too_soon            = "Wait a moment before sending another invite.",
    orgerr_request_gone        = "That request is no longer waiting.",

    orgnote_invite             = "%s invited you to join %s.",
    orgnote_request            = "%s asked to join your company.",
    orgnote_accepted           = "You joined %s.",
    orgnote_declined           = "%s turned down your request to join.",
    orgnote_kicked             = "You were removed from %s.",
    orgnote_role               = "You are now %s in %s.",
    orgnote_owner              = "You now own %s.",
    orgnote_level              = "%s reached company level %d.",
    orgnote_closed             = "%s was closed by its owner.",

    org_role_owner             = "Owner",
    org_role_co_owner          = "Co-Owner",
    org_role_manager           = "Manager",
    org_role_senior_driver     = "Senior Driver",
    org_role_driver            = "Driver",
    org_role_trainee           = "Trainee",

    orgset_tier_title          = "Upgrade %d",
    orgset_curve_start_zero    = "Level 1 must start at 0 XP.",
    orgset_curve_increasing    = "Level %d must need more XP than level %d.",
    orgset_tiers_increasing    = "Upgrade %d cannot open at a lower company level than upgrade %d.",
    orgset_goal_order          = "Row %d: Goal at Max Level must be at least Goal at Level 1.",
}

-- MARK: Text

-- The job's text function (from setup or the settings helper), else the English above.
joborg.textFn = joborg.textFn or nil

function joborg.say(key, ...)
    local fn = joborg.textFn

    if type(fn) == "function" then
        local ok, text = pcall(fn, key, ...)

        if ok and type(text) == "string" and text ~= "" and text ~= key then return text end
    end

    local base = joborg.ENGLISH[key] or tostring(key)

    if select("#", ...) == 0 then return base end

    local ok, text = pcall(string.format, base, ...)

    return ok and text or base
end

--- Whole dollars with thousands commas, for lines that name an amount.
function joborg.money(amount)
    local text = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
    local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()

    return (out:gsub("^,", ""))
end

-- MARK: Names

-- Codepoints a company name or description drops: control characters, zero-width and
-- direction marks, the symbol and dingbat blocks, variation selectors, specials, every
-- 4-byte character (emoji) and the two hate symbols taxi already strips.
local function dropped(code)
    if code < 32 or code == 127 then return true end
    if code >= 0x80 and code <= 0x9F then return true end
    if code >= 0x200B and code <= 0x200F then return true end
    if code >= 0x202A and code <= 0x202E then return true end
    if code >= 0x2060 and code <= 0x206F then return true end
    if code >= 0x2600 and code <= 0x27BF then return true end
    if code >= 0xFE00 and code <= 0xFE0F then return true end
    if code >= 0xFFF0 then return true end
    if code == 0x5350 or code == 0x534D then return true end

    return false
end

--- Cleans free text: drops what dropped() names, folds whitespace, trims, and cuts it to
--- `limit` characters. Returns the text and its length in characters, or nil when the
--- input is not text or not valid UTF-8.
function joborg.clean(raw, limit)
    if type(raw) ~= "string" then return nil end
    if #raw > 2048 then raw = raw:sub(1, 2048) end
    if not utf8.len(raw) then
        -- Cut through a character at the 2048 byte mark, or never UTF-8 at all.
        raw = raw:gsub("[\128-\255]+$", "")

        if not utf8.len(raw) then return nil end
    end

    local parts = {}

    for _, code in utf8.codes(raw) do
        if code == 9 or code == 10 or code == 13 then
            parts[#parts + 1] = " "
        elseif not dropped(code) then
            parts[#parts + 1] = utf8.char(code)
        end
    end

    local text = table.concat(parts):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local count = utf8.len(text) or 0

    if limit and count > limit then
        text = text:sub(1, utf8.offset(text, limit + 1) - 1):gsub(" $", "")
        count = utf8.len(text) or limit
    end

    return text, count
end

--- A company name by the rules (3 to 20 characters, nothing dropped() names), or nil and
--- the reason key.
function joborg.normalizeName(raw)
    local text, count = joborg.clean(raw)

    if not text then return nil, "orgerr_name_invalid" end
    if count < joborg.NAME_MIN or count > joborg.NAME_MAX then return nil, "orgerr_name_length" end

    return text
end

--- The same name for a compare: trimmed, folded spaces, ASCII lower case.
function joborg.sameName(a, b)
    local left, right = joborg.clean(a), joborg.clean(b)

    return left ~= nil and right ~= nil and left:lower() == right:lower()
end

-- MARK: Settings helper

local function copy(value)
    if type(value) ~= "table" then return value end

    local out = {}

    for key, entry in pairs(value) do out[key] = copy(entry) end

    return out
end

joborg.copy = copy

-- What each board row counts, by its id: { metric = "routes" } or { rotates = "route" }.
-- Filled by joborg.settings from the job's board; read by the engine.
joborg.board = joborg.board or {}
joborg.boardOrder = joborg.boardOrder or {}

-- The shipped wording of the board and tier rows: while a row still reads the same, the
-- tablet shows it in the player's language (orgch_<id>_label / _desc, orgset_tier_title).
joborg.shipped = joborg.shipped or { board = {}, tiers = {} }

joborg.root = joborg.root or "settings"

-- The upgrade row keys the engine owns; a job's tier_fields cannot reuse them.
local TIER_KEYS = {
    tier = true, title = true, required_level = true, cost = true, members = true,
    challenge_slots = true, money_bonus = true, experience_bonus = true,
}

local function moveGroup(group, before)
    if type(before) ~= "string" or type(settings.group_order) ~= "table" then return end

    local order = settings.group_order
    local from, to

    for index, id in ipairs(order) do
        if id == group then from = index end
        if id == before then to = index end
    end

    if not from or not to or from < to then return end

    table.remove(order, from)
    table.insert(order, to, group)
end

--- Defines the company settings under the job's root. Call it from the job's shared
--- schema file, once. opts (all optional but board):
---   root        "settings" (paths <root>.organizations.*, <root>.org_upgrades.list, ...)
---   group       "organizations"; label "Companies"; icon "fa-building"; help; before = a
---               group id to list it ahead of (e.g. "advanced")
---   text        function(key, ...) -> the job's localized line (lang:get)
---   words       { worker = "driver", work = "route", works = "routes", level = "driver level" }
---   levels      function() -> { { value, label } } the worker levels a founder may need
---   defaults    { required_level = 5, creation_cost = 25000, split = { min = 75, max = 95 },
---                 pay_money = true, levels = { ... }, tiers = { ... } }
---   board       { { id, label, description, icon, metric | rotates, target_min,
---                   target_max, experience, money }, ... } the challenge board, in order
---   tier_fields { { key, label, type, default, ... }, ... } the job's own upgrade fields
---               (taxi: garage bays, banner faces); every tier carries them back
function joborg.settings(opts)
    opts = type(opts) == "table" and opts or {}

    local root = type(opts.root) == "string" and opts.root or "settings"
    local group = type(opts.group) == "string" and opts.group or "organizations"
    local words = opts.words or {}
    local worker = words.worker or "worker"
    local works = words.works or "jobs"
    local levelWord = words.level or "level"
    local defaults = opts.defaults or {}

    joborg.root = root

    if type(opts.text) == "function" then joborg.textFn = opts.text end

    settings.group(group, {
        label = opts.label or "Companies",
        icon  = opts.icon or "fa-building",
        help  = opts.help or ("Companies %ss start and join: who may start one, its upgrades, its daily challenges and how pay is shared."):format(worker),
    })

    moveGroup(group, opts.before)

    -- MARK: Starting one

    local function levelOptions()
        local ok, list = pcall(opts.levels or function() return nil end)

        if ok and type(list) == "table" and #list > 0 then return list end

        local out = {}

        for level = 1, 10 do out[level] = { value = level, label = ("Level %d"):format(level) } end

        return out
    end

    settings.define(root .. ".organizations.required_level", {
        group   = group,
        label   = "Level to Start a Company",
        help    = ("The %s a %s must reach before they can start a company."):format(levelWord, worker),
        type    = "enum",
        options = levelOptions,
        default = math.floor(tonumber(defaults.required_level) or 5),
    })

    settings.define(root .. ".organizations.creation_cost", {
        group   = group,
        label   = "Cost to Start",
        help    = "Taken from the founder's bank account when the company is registered. It is a fee: the company account starts empty.",
        type    = "currency",
        min     = 0,
        max     = 10000000,
        default = math.floor(tonumber(defaults.creation_cost) or 25000),
    })

    local split = defaults.split or {}

    settings.define(root .. ".organizations.pay_split", {
        group  = group,
        label  = ("%s Share of Pay"):format(worker:sub(1, 1):upper() .. worker:sub(2)),
        help   = ("How much of each %s's pay a company may let its %s keep; the company account takes the rest. Each company picks its share in this range, in steps of %d%%, at most once every %d minutes."):format(words.work or "job", worker .. "s", joborg.SPLIT_STEP, joborg.SPLIT_COOLDOWN),
        type   = "object",
        fields = {
            { key = "min", label = "Lowest",  type = "integer", min = 50, max = 100, step = 5, suffix = "%", edit_mode = "slider" },
            { key = "max", label = "Highest", type = "integer", min = 50, max = 100, step = 5, suffix = "%", edit_mode = "slider" },
        },
        default = { min = math.floor(tonumber(split.min) or 75), max = math.floor(tonumber(split.max) or 95) },
    })

    -- MARK: Upgrades

    local tierDefault = {}

    -- A job's own upgrade fields (taxi: garage bays, banner faces), each a settings field
    -- with a key and a default; the engine hands them back on every tier untouched.
    local tierFields = {}

    for _, field in ipairs(type(opts.tier_fields) == "table" and opts.tier_fields or {}) do
        if type(field) == "table" and type(field.key) == "string" and not TIER_KEYS[field.key] then tierFields[#tierFields + 1] = field end
    end

    for index, row in ipairs(defaults.tiers or joborg.TIERS) do
        local title = row.title or ("Upgrade %d"):format(row.tier or index)

        tierDefault[index] = {
            tier             = row.tier or index,
            title            = title,
            required_level   = row.required_level or 0,
            cost             = row.cost or 0,
            members          = row.members or row.member_capacity or 4,
            challenge_slots  = row.challenge_slots or index,
            money_bonus      = row.money_bonus or 0,
            experience_bonus = row.experience_bonus or 0,
        }

        for _, field in ipairs(tierFields) do
            if row[field.key] ~= nil then tierDefault[index][field.key] = row[field.key] else tierDefault[index][field.key] = field.default end
        end

        joborg.shipped.tiers[tierDefault[index].tier] = title
    end

    local tierItem = {
        { key = "tier",             label = "Tier",            type = "integer", min = 1, hidden = true },
        { key = "title",            label = "Name",            type = "string" },
        { key = "required_level",   label = "Company Level",   type = "integer", min = 0, help = "The company level this upgrade opens at." },
        { key = "cost",             label = "Cost",            type = "currency", min = 0 },
        { key = "members",          label = "Seats",           type = "integer", min = 1, max = 100, help = "How many members the company can hold." },
        { key = "challenge_slots",  label = "Challenge Slots", type = "integer", min = 0, max = 5, help = "How many goals of the challenge board are open." },
        { key = "money_bonus",      label = "Pay Bonus",       type = "integer", min = 0, max = 100, step = 1, suffix = "%", edit_mode = "slider" },
        { key = "experience_bonus", label = "XP Bonus",        type = "integer", min = 0, max = 100, step = 1, suffix = "%", edit_mode = "slider" },
    }

    local tierItemDefault = {
        tier = 1, title = "Upgrade", required_level = 0, cost = 0, members = 4,
        challenge_slots = 1, money_bonus = 0, experience_bonus = 0,
    }

    for _, field in ipairs(tierFields) do
        local column = {}

        for key, value in pairs(field) do
            if key ~= "default" then column[key] = value end
        end

        tierItem[#tierItem + 1] = column
        tierItemDefault[field.key] = field.default
    end

    settings.define(root .. ".org_upgrades.list", settings.shape.rows({
        group = group,
        label = "Company Upgrades",
        help  = ("The upgrades a company buys from its own account, in order. Each one opens at a company level and raises the seats, the open challenge slots and the bonus on every %s its %ss finish."):format(words.work or "job", worker),
        item         = tierItem,
        item_default = tierItemDefault,
        row_fields = { "required_level", "cost", "members" },
        min_items  = #tierDefault,
        max_items  = #tierDefault,
        default    = tierDefault,
        unique_key = "tier",
        validate   = function(rows)
            for index = 2, #rows do
                if (tonumber(rows[index].required_level) or 0) < (tonumber(rows[index - 1].required_level) or 0) then
                    return false, joborg.say("orgset_tiers_increasing", index, index - 1)
                end
            end

            return true
        end,
    }))

    -- MARK: The challenge board

    local boardDefault = {}

    joborg.board, joborg.boardOrder = {}, {}

    for index, row in ipairs(opts.board or {}) do
        if type(row.id) == "string" then
            joborg.board[row.id] = { metric = row.metric, rotates = row.rotates }
            joborg.boardOrder[#joborg.boardOrder + 1] = row.id
            joborg.shipped.board[row.id] = { label = row.label, description = row.description }

            boardDefault[#boardDefault + 1] = {
                id          = row.id,
                label       = row.label or row.id,
                description = row.description or "",
                icon        = row.icon or "fa-flag",
                target_min  = row.target_min or 1,
                target_max  = row.target_max or row.target_min or 1,
                experience  = row.experience or 0,
                money       = row.money or 0,
            }
        end
    end

    if #boardDefault > 0 then
        settings.define(root .. ".org_challenges.list", {
            group = group,
            label = "Challenge Board",
            help  = ("The goals every %s in a company works on together each day, in this order; upgrades open more of them. What each goal counts is fixed; its name, its goal and its reward are yours. The goal grows from the level 1 figure to the max level figure with the company's level, as it stood when the day began."):format(worker),
            type  = "list",
            item  = {
                { key = "id",          label = "ID",                type = "string", hidden = true },
                { key = "label",       label = "Name",              type = "string" },
                { key = "description", label = "Description",       type = "string" },
                { key = "icon",        label = "Icon",              type = "string", help = "A Font Awesome name, like fa-route." },
                { key = "target_min",  label = "Goal at Level 1",   type = "integer", min = 1 },
                { key = "target_max",  label = "Goal at Max Level", type = "integer", min = 1 },
                { key = "experience",  label = "Company XP",        type = "integer", min = 0 },
                { key = "money",       label = "Company Payout",    type = "currency", min = 0 },
            },
            item_default = copy(boardDefault[1]),
            row_fields   = { "target_min", "target_max", "experience", "money" },
            min_items    = #boardDefault,
            max_items    = #boardDefault,
            default      = boardDefault,
            unique_key   = "id",
            validate     = function(rows)
                for index, row in ipairs(rows) do
                    if (tonumber(row.target_max) or 0) < (tonumber(row.target_min) or 0) then
                        return false, joborg.say("orgset_goal_order", index)
                    end
                end

                return true
            end,
        })

        settings.define(root .. ".org_challenges.pay_money", {
            group   = group,
            label   = "Challenges Pay Cash",
            help    = "A finished goal pays its Company Payout into the company account on top of the company XP. Off: goals pay XP only.",
            type    = "boolean",
            default = defaults.pay_money ~= false,
        })
    end

    -- MARK: Company levels

    local curve = {}

    for index, experience in ipairs(defaults.levels or joborg.LEVELS) do curve[index] = { experience = experience } end

    settings.define(root .. ".org_levels.curve", {
        group = group,
        label = "Company Level Curve",
        help  = ("Total company XP for each level, in order: level 1 starts at 0 and every later level needs more. Add or remove rows to set the highest level. Companies earn XP from the challenge board and a little from every %s their %ss finish."):format(words.work or "job", worker),
        type  = "list",
        item  = {
            { key = "experience", label = "XP Needed", type = "integer", min = 0 },
        },
        item_default = { experience = 0 },
        min_items    = 1,
        max_items    = 50,
        default      = curve,
        validate     = function(rows)
            if (tonumber(rows[1].experience) or 0) ~= 0 then return false, joborg.say("orgset_curve_start_zero") end

            for level = 2, #rows do
                if (tonumber(rows[level].experience) or 0) <= (tonumber(rows[level - 1].experience) or 0) then
                    return false, joborg.say("orgset_curve_increasing", level, level - 1)
                end
            end

            return true
        end,
    })

    -- `works` is kept for jobs that phrase help text with it.
    joborg.words = { worker = worker, works = works, level = levelWord, work = words.work or "job" }

    return true
end
