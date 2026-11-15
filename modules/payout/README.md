# gg.payout: pay that waits at the depot

A finished job does not drop money into the worker's pocket. It waits at the depot and the worker
collects it in person. Each depot picks how (an owner setting, one per depot):

| mode | what the worker sees |
| --- | --- |
| `table` | A small square table at the depot with one pile of cash for every finished job not yet collected (up to five: an open cash case, a cash bag, a roll of notes, two money bags). The worker clicks it, steps up to its nearest edge and takes the pay in one quick grab. |
| `ped` | The depot ped turns and hands it over: an envelope, or the briefcase from the job's Briefcase From amount. |
| `instant` | Paid the moment the job ends, as before. |

Everything is stock GTA V, nothing is streamed: the table `prop_rub_table_01` (every build), the piles
`prop_cash_case_01`, `h4_prop_h4_cash_bag_01a`, `ex_cash_roll_01` and `prop_poly_bag_money` (a build
without a DLC pile shows `prop_cash_pile_01` in its place), `bkr_prop_money_wrapped_01` in the hand,
and the one-hand grab `anim@scripted@player@freemode@gen_grab@male@` (`mp_common` before build 2802).
The ped hands over `prop_cash_envelope_01` or `prop_ld_case_01`.

The table and the pay on it are client-only objects: only the worker sees their own pay. The
worker's own moves are ordinary scripted anims, so the players around see them.

The ledger is `gg_studio_job_payouts` (one row per worker and job), so pay survives a job restart,
a log-off and a server restart. The ledger is cleared before anything is paid, and put back if the
job's pay function fails, so a pay can never be taken twice.

## Server

```lua
gg.payout.setup({
    job    = "gg_busjob",                       -- ledger key (default: the resource)
    pay    = function(source, owed) ... end,    -- pays { money, experience, count, data }; returns a table or false, err
    points = function(source) return {{ id = 1, x = .., y = .., z = .., mode = "table" }} end,
    reach  = 4.0,                               -- metres from a point that count as there
    collected = function(source, result, taken) end, -- counters, notices
})

gg.payout.add(source, { money = 820, experience = 140, data = { stops = 12 } })   -- waits at the depot
gg.payout.add(source, { money = 820, experience = 140 }, { instant = true })      -- paid now
gg.payout.owed(source)  -- { money, experience, count }
gg.payout.collect(source, pointId, anywhere)  -- what the client callback runs
```

`add` pushes the new total to the worker's game (`<resource>:payout:owed`).

## Client

```lua
gg.payout.setup({
    label = locale("payout.collect"), icon = "fas fa-sack-dollar", reach = 2.0,
    caseFrom   = function() return cfg.payout.case_from end,
    canCollect = function() return not bus.working end,
    collected  = function(result) end,   -- notify, refresh the tablet
    refused    = function(code) end,     -- not_ready, nothing_owed, too_far, busy, failed
    changed    = function(owed) end,     -- the total changed
})

gg.payout.table(depotIndex, vector4(x, y, z, heading))  -- a table depot (ground position)
gg.payout.removeTable(depotIndex); gg.payout.clearTables()
gg.payout.fromPed(depotIndex, ped, "WORLD_HUMAN_CLIPBOARD")  -- from the depot ped's target
gg.payout.collect(depotIndex)  -- what the table's target does; false when out of reach
gg.payout.owed(); gg.payout.busy()
```

Tables are built within 45 m and taken down past 55 m. The pay is collected from any side.

`gg.payout.piles(owed)` (shared) is how many piles a pay shows.

## Settings

`gg.payout.previewParts()` returns every pile for a settings `preview_object.with`, so placing a pay
table in /ggsettings shows the whole set:

```lua
preview_object = { model = gg.payout.TABLES[1].model, with = gg.payout.previewParts() }
```

## Not done yet

- Nothing here has been seen in game since the table went small (2026-11-09).
