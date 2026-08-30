# Waypoints

The world markers every GG script draws.

[← back to the README](../README.md)

---

## World waypoints

A waypoint is a distance, a unit and a label on a billboard out in the world.
It turns to face the camera, grows as you get further away so it stays
readable, and lifts itself over anything that gets between you and it.

```lua
gg.waypoint.create({
    id     = "dropoff",
    coords = vector3(-1035.7, -2731.8, 12.8),
    label  = "DROP OFF",
})

gg.waypoint.remove("dropoff")
```

Ids are scoped to the script that placed them, so `dropoff` in one script and
`dropoff` in another are two different waypoints. Everything a script places
is cleaned up for it when that script stops.

### Routes

A route is a run of waypoints where one is live at a time — race checkpoints,
a delivery round, a tow route. Setting the next point retires the one before
it, so a job only ever has to say where the player is going next.

```lua
gg.waypoint.setRoutePoint("lap", 1, checkpoints[1], { label = "CHECKPOINT 1" })
gg.waypoint.setRoutePoint("lap", 2, checkpoints[2], { label = "CHECKPOINT 2" })

gg.waypoint.clearRoute("lap")
```

Pass `keep_previous = true` to leave the last one standing and build a trail.

| Call | What it does |
| --- | --- |
| `create(data)` | Place one, or replace the one already under that id |
| `update(id, data)` | Change only the keys you pass |
| `remove(id)` / `clear()` | Take one away, or all of this script’s |
| `show(id)` / `hide(id)` | Leave it placed but stop drawing it |
| `exists(id)` | Whether it is placed |
| `setRoutePoint(routeId, index, coords, options)` | Move a route to its next point |
| `activeRoutePoint(routeId)` | `{ id, index, coords, label }`, or nil |
| `clearRoute(routeId)` | Remove every point on a route |

`data` takes `id`, `coords`, `label`, `render_distance`, `visible` and `meta`.

### Styles

The same waypoint can wear a different face depending on the job:

| Style | What it looks like |
| --- | --- |
| `race` | A big countdown you read at speed — distance, then the label |
| `taxi` | A destination plate — badge, name, then the distance |

```lua
gg.waypoint.create({ id = "fare", coords = coords, style = "taxi", label = "DROP OFF" })
```

Leave `style` out and you get `race`. Switching it on a placed waypoint takes
effect straight away — the texture behind it does not change.

Open **`/ggsettings` → Waypoints** to see every style, copy its export, change
what it says by default, and drop one in front of you for ten seconds to look
at it.

### Seeing one

There is a command for checking it works without writing any code:

```
/waypoint            place one at your feet
/waypoint map        place one at your marker on the map
/waypoint DROP OFF   place one at your feet saying something else
```

Run it again to take it away. Place one and walk off to watch it count up,
grow, switch to miles and lift itself over anything in the way. `/ggwaypoint`
does the same thing, for when another resource already owns the short name.

Each waypoint draws through its own 4096x2048 DUI, which is a real amount of
video memory. A handful at a time is fine; leaving dozens placed is not, and
gg_lib says so in the console if you do.

