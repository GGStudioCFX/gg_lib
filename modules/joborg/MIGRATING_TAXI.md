# Moving gg_taxijob's companies onto gg.joborg

Taxi's organizations were the model for this engine, so most of it maps across one to one.
This note covers the tables, the settings, the code that changes, and what stays with taxi.
Nothing here has been run against taxi's live data. Test the migration on a copy of the
database first.

## 1. Setup

```lua
gg.joborg.setup({
    job = "gg_taxijob", prefix = "gg_studio_taxijob", root = "settings", unit = "rides",
    totals = { "distance" }, today = {}, experience_share = 0,   -- taxi: the board is the only XP source
    text = function(key, ...) return lang:get(key, ...) end,
    fleet = true, pages = { "fleet", "banner" },
    hooks = { canWork = ..., levels = ..., name = ..., faces = ..., push = ..., changed = ...,
              alert = ..., watching = ..., pools = { vehicle = vehiclePool, rider = riderPool } },
})
```

With the prefix `gg_studio_taxijob`, the engine's tables are named after taxi's own tables:

| Engine | Taxi today |
| --- | --- |
| `gg_studio_taxijob_orgs` | same table, migrated in place |
| `gg_studio_taxijob_org_members` | same table, migrated in place |
| `gg_studio_taxijob_org_daily` | taxi's table is never written; replace it (see 3) |
| `gg_studio_taxijob_org_ledger` | new (taxi's ledger lived in memory) |
| `gg_studio_taxijob_org_feed` | new |
| `gg_studio_taxijob_org_invites` | new; takes `orgs.join_requests` |
| (none) | `gg_studio_taxijob_org_vehicles` stays taxi's |

## 2. Columns

`gg_studio_taxijob_orgs`

| Taxi | Engine | Notes |
| --- | --- | --- |
| id, slug, name, description, owner_identifier, owner_name, access_mode, driver_split, experience, upgrade_tier, balance, challenge_progress, challenges_reset_at | same | `challenge_progress` keeps its shape; the engine adds `__done` and `__level` beside `__rotation`. |
| total_rides | total_jobs | Copy across. The engine never reads `total_rides`. |
| total_earnings | total_earnings | Meaning changes: taxi counted cut + challenge money, the engine counts each job's gross. Keep the old values or zero them; the earnings leaderboard reads it. |
| created_at (TIMESTAMP) | created_at (INT, unix seconds) | Convert (below). oxmysql hands a TIMESTAMP back in milliseconds. |
| member_capacity | (none) | Capacity is the tier's `members` alone. If a company holds more than its tier now allows, nobody is removed; it just takes no one new. |
| join_requests (JSON) | invites rows, `kind = 'request'` | Convert (below). |
| ad_left, ad_right | (none) | Stay taxi's (banner page). The engine leaves unknown columns alone. |
| (none) | split_changed_at, totals | Added by the engine: 0 and empty. |

`gg_studio_taxijob_org_members`

| Taxi | Engine | Notes |
| --- | --- | --- |
| id, org_id, identifier, name, role_id, total_earnings, contributed, last_active | same | `role_id` NULL or unknown = the default role, as taxi. |
| role (label) | (none) | Never read. Ownership is `orgs.owner_identifier` only. |
| total_rides | total_jobs | Copy across. |
| joined_at (TIMESTAMP) | joined_at (INT) | Convert. |
| name 'Driver' (approved requests) | name | Fix from the player table where it is still `Driver`. |

## 3. One migration, run once before `gg.joborg.setup`

```lua
gg.db.migrate("taxijob_orgs_to_joborg", function()
    local orgs, members = "gg_studio_taxijob_orgs", "gg_studio_taxijob_org_members"

    -- Columns the engine would add later, added now so the copies below can fill them.
    MySQL.query.await(("ALTER TABLE %s ADD COLUMN total_jobs INT NOT NULL DEFAULT 0"):format(orgs))
    MySQL.query.await(("ALTER TABLE %s ADD COLUMN total_jobs INT NOT NULL DEFAULT 0"):format(members))
    MySQL.query.await(("UPDATE %s SET total_jobs = total_rides"):format(orgs))
    MySQL.query.await(("UPDATE %s SET total_jobs = total_rides"):format(members))

    -- TIMESTAMP to unix seconds (a MODIFY to INT would give 20261109120000-style numbers).
    for _, spec in ipairs({ { orgs, "created_at" }, { members, "joined_at" } }) do
        local tbl, col = spec[1], spec[2]
        MySQL.query.await(("ALTER TABLE %s ADD COLUMN %s_unix INT NOT NULL DEFAULT 0"):format(tbl, col))
        MySQL.query.await(("UPDATE %s SET %s_unix = IFNULL(UNIX_TIMESTAMP(%s), 0)"):format(tbl, col, col))
        MySQL.query.await(("ALTER TABLE %s DROP COLUMN %s"):format(tbl, col))
        MySQL.query.await(("ALTER TABLE %s CHANGE %s_unix %s INT NOT NULL DEFAULT 0"):format(tbl, col, col))
    end

    -- Names are unique without case in the engine (taxi checked, but had no key).
    MySQL.query.await(("ALTER TABLE %s ADD UNIQUE KEY uq_name (name)"):format(orgs))

    -- taxi's daily table was never written: move it aside, the engine creates its own.
    MySQL.query.await("RENAME TABLE gg_studio_taxijob_org_daily TO gg_studio_taxijob_org_daily_old")

    -- Join requests from JSON to rows (the engine creates the invites table on setup, so
    -- create it here first with the engine's definition from server.lua SCHEMA).
    -- for each org: for each { identifier, name, level, at } in json.decode(join_requests):
    --   INSERT IGNORE INTO gg_studio_taxijob_org_invites (org_id, identifier, kind, name, level, from_name, at)
    --   VALUES (org.id, r.identifier, 'request', r.name, r.level, '', r.at)
end)
```

If `ADD UNIQUE KEY uq_name` fails, two companies share a name in different case: rename one
first. Keep `total_rides`, `member_capacity`, `role` and `join_requests` until the move has
been seen working, then drop them in a later migration.

## 4. Settings

The engine's paths are taxi's paths under the same root, so saved owner values carry over:
`settings.organizations.required_level`, `settings.organizations.creation_cost`,
`settings.org_upgrades.list`, `settings.org_challenges.list`, `settings.org_challenges.pay_money`
and `settings.org_levels.curve`. Taxi removes its own definitions of these and calls
`gg.joborg.settings` instead:

- Upgrade rows: the engine's `members` reads taxi's saved `member_capacity` too. Taxi keeps
  its garage bays and banner faces with `tier_fields = { { key = "garage_capacity", ... },
  { key = "ad_faces", ... } }`; they come back on every tier.
- Board rows: taxi passes its five rows as `board` with `metric` or `rotates` from
  `CHALLENGE_TYPES` (`complete_fares` metric `rides`, `earn_fares` metric `earnings`,
  `driving_distance` metric `distance`, `rotating_vehicle` rotates `vehicle`,
  `rotating_rider` rotates `rider`). The pools return `vehicle:<model>` and `class:<id>`
  metrics, as taxi's rotation does now.
- `cfg.org_split` becomes the owner setting `settings.organizations.pay_split` (75-95 by default).
- `settings.organizations.tv_organization_count` and `abandon_cooldown` stay taxi's.
- The group label changes from "Organizations" to whatever taxi passes as `label`.

## 5. Code that changes in taxi

| Taxi | Engine |
| --- | --- |
| `management.lua` create/join/leave/kick/transfer/delete/settings/split, `orgrequests.lua`, `orgroles.lua`, `treasury.lua` | `joborg.call` through the `org_*` relay |
| `GetManagementData` (every company, every push) | `joborg.payload` (the viewer's company only) and the paged `org_directory` |
| `BuildFarePayout` company split and bonus, then `AddOrganizationFareIncome` | `joborg.jobDone` before paying: it answers the driver's share and the XP with the tier bonus, and books the cut, the ledger row, the daily row and the board |
| `AddOrganizationProgress` from `reportDistance` and player-booked rides | `joborg.progress(source, { distance = ... })` |
| `orgchallenges.lua` | the engine's board; taxi keeps only its two pool functions |
| `leaderboard.lua` organization boards | `joborg.leaderboard("experience" / "rides" / "earnings", page, source)` |
| Ledger in memory | `<prefix>_org_ledger` (type `route` for cuts, `upgrade` for upgrades; taxi adds its own vehicle purchases and sales through the fleet code) |

Taxi's fleet (buying, selling, servicing, checkout, impound, role blocks) and the roof banner
stay in taxi. They read the company through `joborg.summary` and spend from the account
with their own conditional UPDATE on `gg_studio_taxijob_orgs.balance` plus a ledger row.
