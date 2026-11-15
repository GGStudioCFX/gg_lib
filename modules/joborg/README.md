# gg.joborg - companies for a GG job

Players start a company, join one (open, by request or by invite), share a company account,
get a share of every job they finish, level the company up, buy its upgrades and work a daily
challenge board together. The engine holds all of it: roles and the rank rule, permissions,
the ledger, the daily member stats, the board and its rotations, levels, tiers, invites,
requests, leaderboards and live pushes. A job adds four things: one settings call, one setup
call, a relay for the tablet's calls, and one call for every finished job.

It runs inside the job's own Lua VM (gg_lib loads `modules/joborg/shared.lua`, then
`server.lua`, when the job first reads `gg.joborg`). Every job has its own tables, named from
the prefix it passes. There is no client file: the job's client only relays tablet calls.

## 1. Settings (shared)

From the job's shared schema file, once:

```lua
local ok, engine = pcall(function() return gg.joborg end)

if ok and engine then
    engine.settings({
        root     = "settings",             -- paths below hang off this
        group    = "organizations",        -- settings group id
        label    = "Companies",            -- group label in /ggsettings
        icon     = "fa-building",
        before   = "advanced",             -- list the group ahead of this one
        text     = function(key, ...) return lang:get(key, ...) end,
        words    = { worker = "driver", work = "route", works = "routes", level = "driver level" },
        levels   = function() return { { value = 1, label = "Level 1" }, ... } end,
        defaults = { required_level = 5, creation_cost = 25000, split = { min = 75, max = 95 }, pay_money = true },
        board    = BOARD,                  -- the challenge board, below
        tier_fields = nil,                 -- optional: the job's own upgrade fields (taxi: garage bays)
    })
end
```

It defines, under `<root>`:

| Path | Label | What it is |
| --- | --- | --- |
| `organizations.required_level` | Level to Start a Company | The worker level a founder needs (options from `levels`). |
| `organizations.creation_cost` | Cost to Start | A fee taken from the founder's bank. The company account starts empty. |
| `organizations.pay_split` | (worker's share) | `{ min, max }`, 50-100 in steps of 5: the range each company picks its worker share from. |
| `org_upgrades.list` | Company Upgrades | Rows: name, company level, cost, seats, challenge slots, pay bonus %, XP bonus %. |
| `org_challenges.list` | Challenge Board | Rows: name, description, icon, goal at level 1, goal at max level, company XP, company payout. |
| `org_challenges.pay_money` | Challenges Pay Cash | Off: a cleared goal pays XP only. |
| `org_levels.curve` | Company Level Curve | XP needed per level; level 1 at 0, each level above the last. |

Roles, permissions, the split step (5) and cooldown (30 min) are fixed in `shared.lua`.

`tier_fields` adds the job's own columns to the upgrade rows, each a settings field with a
`key` and a `default` (an engine key cannot be taken over); every tier in `constants()` and
the engine's own reads carries them back untouched.

The board (`board`) is a list of rows, in order. Each row counts one metric the job reports,
or rotates daily through a pool the job hands over:

```lua
{ id = "finish_routes", label = "Keep the Wheels Turning", description = "...", icon = "fa-route",
  metric = "routes", target_min = 5, target_max = 20, experience = 150, money = 0 },
{ id = "route_of_the_day", label = "Route of the Day", description = "...", icon = "fa-map-location-dot",
  rotates = "route", target_min = 3, target_max = 10, experience = 450, money = 4000 },
```

`metric = "earnings"` counts the gross pay of finished jobs (the engine adds it). A goal's size
runs from `target_min` at company level 1 to `target_max` at the top level, using the level
the company had when the day began.

## 2. Setup (server)

Once, from the job's server code, after `functions` exist:

```lua
gg.joborg.setup({
    job              = "gg_busjob",        -- for logs
    prefix           = "gg_studio_busjob", -- tables: <prefix>_orgs, _org_members, ...
    root             = "settings",         -- same root as the settings call
    unit             = "routes",           -- the job's word for one finished job (a metric key)
    totals           = { "riders", "distance" }, -- metrics kept as company all-time totals
    today            = { "riders" },       -- metrics shown in the company's "today"
    experience_share = 5,                  -- % of each job's XP the company also earns (0 = board only)
    text             = function(key, ...) return lang:get(key, ...) end,
    roles            = nil,                -- optional; joborg.ROLES by default
    fleet            = false,              -- true: the tablet shows the job's Fleet page
    pages            = {},                 -- extra page ids the job's tablet adds
    hooks            = hooks,
})
```

### Hooks

Every hook is optional unless marked. Each runs inside `pcall`.

| Hook | Called as | Answers |
| --- | --- | --- |
| `identifier` | `(source)` | The character id. Default: `gg.framework.GetIdentifier`. |
| `canWork` | `(source)` | `false` when this player may not do the job (they cannot start, join or be invited). `nil` = no check. |
| `level` | `(identifier)` | The worker level (founder check, nearby list). **Needed** unless `levels` is given. |
| `levels` | `({ identifiers })` | `{ [identifier] = level }` in one read (roster, requests). Falls back to `level`. |
| `name` | `(source)` | The character name. Default: `GetPlayerName`. |
| `faces` | `({ identifiers })` | `{ [identifier] = face token }` for the roster and requests. |
| `bankPay` | `(source, amount, reason)` | `true` once paid. Default: `gg.framework.AddMoney(src, "bank", ...)`. |
| `bankCharge` | `(source, amount, reason)` | `true` once taken. Default: `gg.framework.RemoveMoney(src, "bank", ...)`. |
| `push` | `(source, payload)` | **Needed** for live pages: send the OrgPayload to that client. |
| `watching` | `(source)` | `true` while that player's tablet is open. `nil`: the engine uses `joborg.watch`. |
| `changed` | `(source)` | That player's company name, level, role or membership changed (refresh the job's player block). |
| `player` | `(source)` | The job's fresh player block; sent back as `player` in answers that change membership. |
| `alert` | `(source, { kind, msg, status, data })` | Show a notification line. Kinds: `org_invite`, `org_request`, `org_accepted`, `org_role`, `org_kicked`, `org_level`, `org`. `data` carries `org` (name), and for an invite `id` (slug), `invite` (id) and `from`. |
| `pools.<kind>` | `(org)` | For a rotating board row (`rotates = "<kind>"`): `{ { metric, description, scale } }`. `org` = `{ id, level, tier, identifiers }`. `scale` multiplies the goal. An empty pool falls back to the job's unit with `orgch_fallback_<kind>`. |

## 3. Calls

| Function | What it does |
| --- | --- |
| `joborg.call(source, name, body)` | Answers one tablet call (`joborg.CALLS`, the `org_*` names). Every write answers `org` (a fresh OrgPayload) and, when membership changed, `player`. Failures are `{ ok = false, error = <localized line>, code = <key> }`. |
| `joborg.payload(source)` | OrgPayload: `{ can_create, create_reason?, invites, requested, org = Org or false }`. |
| `joborg.summary(identifier)` | `{ id, name, level, members, role, role_id, tier }` or `nil`. |
| `joborg.constants()` | Roles, permissions, tiers, levels, split, limits, creation, fleet, pages, unit. |
| `joborg.leaderboard(board, page, source?)` | `{ rows = { { position, id, name, value, members, level } }, total, pages, page, size, org?, me? }`; `board` = `"experience"`, the unit, or `"earnings"`. |
| `joborg.jobDone(source, { money, experience, metrics })` | Before paying a finished job. Answers `{ money, experience, cut, gross?, split?, company? }`: pay after the company's cut (the tier's pay bonus added first), XP with the tier's XP bonus. A worker in no company gets the input back. |
| `joborg.progress(source, metrics)` | Counts unpaid work (taxi: distance, player-booked rides) on the board, the totals and the worker's day. No money; the unit and `earnings` are ignored. Answers `true` when counted. |
| `joborg.watch(source, on)` | Marks a tablet open or shut when the job has no `watching` hook. |
| `joborg.ready()` | `true` once the tables are there. |

`metrics` for `jobDone`: the unit (`routes = 1`), any totals or today keys, and whatever the
board rows count (`route:<id>`, `class:<id>`, ...). Only positive whole numbers count.

### Relay (the bus job's, as a pattern)

```lua
-- server
for _, name in ipairs(gg.joborg.CALLS) do
    lib.callback.register("gg_busjob:server:" .. name, function(source, body)
        local ok, answer = pcall(gg.joborg.call, source, name, body)
        return ok and answer or { ok = false, error = lang:get("orgerr_failed") }
    end)
end

-- client
for _, name in ipairs(CALLS) do
    RegisterNUICallback(name, function(data, cb)
        local ok, result = pcall(lib.callback.await, "gg_busjob:server:" .. name, false, data or {})
        cb(ok and type(result) == "table" and result or { ok = false, error = lang:get("orgerr_failed") })
    end)
end

RegisterNetEvent("gg_busjob:client:org", function(payload) gg.nui.emit("org", payload) end)
```

## 4. Tables

Created on start if missing; missing columns are added; nothing is dropped. Times are unix
seconds; days are the start of the gg.daily day.

| Table | Holds |
| --- | --- |
| `<prefix>_orgs` | slug, name (unique, case-insensitive), description, owner_identifier, owner_name, access_mode, driver_split, split_changed_at, experience, upgrade_tier, balance, total_earnings (gross), total_jobs, totals (JSON), challenge_progress (JSON), challenges_reset_at, created_at |
| `<prefix>_org_members` | org_id, identifier (unique: one company per player), name, role_id, joined_at, total_jobs, total_earnings, contributed, last_active |
| `<prefix>_org_ledger` | org_id, type (`deposit`, `withdraw`, `route`, `upgrade`, `challenge`), actor, amount (signed), balance_after, at; kept 60 days |
| `<prefix>_org_daily` | org_id, identifier, day, jobs, earnings, metrics (JSON); kept 8 days |
| `<prefix>_org_feed` | org_id, kind, actor, target, detail, at; kept 30 days |
| `<prefix>_org_invites` | org_id, identifier, kind (`invite` or `request`), name, level, from_name, at; invites last 3 days, requests 7 |

## 5. Locale keys a job ships

Every key in `joborg.ENGLISH` (`orgerr_*`, `orgnote_*`, `org_role_*`, `orgset_*`) in all of the
job's languages; the English there is only a fallback. For each board row
`orgch_<id>_label` and `orgch_<id>_desc` (used while the owner keeps the shipped text), for each
rotating kind `orgch_fallback_<kind>`, and whatever the job's pools say (bus: `orgch_route_desc`,
`orgch_class_desc`).

## 6. Rules the engine keeps

- Ownership is `owner_identifier`, never a role. Nobody below the owner acts on someone of
  their rank or above, or gives a role at or above their own.
- Every permission and limit is checked on the server, again under the player's and the
  company's lock. Numbers from the client are floored and range-checked.
- Money moves in one conditional UPDATE (`balance >= ?`); a failed bank pay puts it back, a
  failed save after a charge pays it back, a company is deleted only after its balance reached
  the owner's bank.
- One write per player at a time (`orgerr_busy`).
