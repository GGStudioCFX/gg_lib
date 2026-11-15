# Zones

Areas in the world that run your code when the player walks in or out.

[← back to the README](../README.md)

---

gg_lib has its own zones, so they work the same on every server, whatever
ox_lib version it runs. The calls match ox_lib's `lib.zones`, so moving a
script over is a rename.

```lua
local depot = gg.zones.poly({
    points    = { vector3(865.3, -175.4, 76.7), vector3(906.8, -197.8, 72.0), vector3(931.2, -158.7, 74.6) },
    thickness = 8.0,
    onEnter   = function(zone) end,
    onExit    = function(zone) end,
})

local garage = gg.zones.box({ coords = vector3(0.0, 0.0, 70.0), size = vector3(10.0, 6.0, 4.0), rotation = 90.0 })
local stall  = gg.zones.sphere({ coords = vector3(0.0, 0.0, 70.0), radius = 2.0, inside = function(zone) end })

if garage:contains(GetEntityCoords(PlayerPedId())) then end

depot:remove()
```

| Shape | Data |
| --- | --- |
| `poly` | `points` (3 or more corners), `thickness` (default 4). The zone runs from the lowest corner minus half the thickness to the highest corner plus half, so corners can sit at different heights. Corners with no height make a zone of any height. `minZ` / `maxZ` set the band yourself. |
| `box` | `coords` (the centre), `size` (full width, length and height, default 4 each), `rotation` (heading in degrees) |
| `sphere` | `coords`, `radius` (default 2) |

Every shape also takes `onEnter`, `onExit` and `inside` (every frame while the
player is in it), `debug = true` to draw it, and `debugColour = { r, g, b, a }`.
Any other key you pass stays on the zone, so a callback can read it from `zone`.

| Call | What it does |
| --- | --- |
| `zone:contains(coords)` | Whether a point is inside; no coords means the player |
| `zone:remove()` | Take it away; safe to call twice |
| `zone:setDebug(on, colour)` | Draw it or stop drawing it |
| `zone:isActive()` | Whether it is still placed |
| `zone.insideZone`, `zone.distance` | Whether the player is in it, and how far its centre is |
| `gg.zones.getAllZones()` / `getCurrentZones()` | This script's zones, or the ones the player is in |
| `gg.zones.count()` / `clear()` | How many this script has, or remove them all |

One check runs every 300 ms for all of a script's zones. Far zones are skipped
with a distance check, and the per-frame tick only runs while the player is in
a zone with `inside` or a zone is drawing debug. A failing callback prints its
error and the other zones keep working. Turning on gg_lib's debug setting draws
every zone. Everything a script places is removed when that script stops.
