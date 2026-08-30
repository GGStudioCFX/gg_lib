# Daily reset

The clock every script shares.

[← back to the README](../README.md)

---

## Daily reset

One clock for every GG script. Whatever resets each day — progress, streaks,
claims, payouts — rolls over at the same moment, set once under
**Generic → Daily Reset** rather than in each script’s own config.

```lua
gg.daily.onReset(function()
    MySQL.query.await("UPDATE gg_studio_taxijob SET daily_progress = ?", { json.encode(FRESH) })
end)
```

And for the countdown every one of these ends up drawing:

```lua
gg.daily.clock()          -- "05:12:44"
gg.daily.secondsUntil()   -- 18764
gg.daily.remaining()      -- 5, 12, 44
```

### It is not a cron

A cron fires at a time, so a server that was switched off at that time never
gets it. gg_lib stores the last reset boundary each script dealt with, so the
question on startup is not "is it midnight" but "has a midnight passed since
this script last looked". Down for two hours across the reset, or down for a
week — it runs once on the way back up, either way.

A handler returning `false`, or throwing, means the day is **not** written off:
gg_lib tries again rather than losing the reset. Nothing is marked done until
the script says it finished.

A script gg_lib has never seen starts caught up, so installing something new
does not wipe what it shipped with. Move the reset time and the next one lands
on the new time, without waiting out the old one.

`gg_daily_reset` in the server console rolls everything over now, for testing.

