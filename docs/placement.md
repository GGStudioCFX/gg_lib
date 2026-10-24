# Placement

Letting a player set a prop down in the world, with the same tool Script Studio uses.

[← back to the README](../README.md)

---

## Placing an object

```lua
CreateThread(function()
    local placed = gg.placement.placeObject({
        model       = "prop_boombox_01",
        title       = "Place Boombox",
        maxDistance = 2.8,
    })

    if type(placed) == "table" then
        -- placed.x, placed.y, placed.z, placed.heading
    end
end)
```

The call waits for the player, so run it inside a thread. While it is open the
player sees a see-through preview of the model and the key legend:

| Key | Does |
| --- | --- |
| Aim | The preview sits wherever the camera points, on the ground or on top of an object |
| Scroll | Turn it (hold Shift for fine turns) |
| E | Switch to the gizmo: drag to move, **R** to switch between move and turn, **L-Alt** frees the cursor |
| Enter | Place it |
| Esc / Backspace | Cancel |

The spot is kept within `maxDistance` metres of the player's centre (default 3),
measured in 3D, so a server checking the same distance never refuses it.

### Options

| Option | Default | What it does |
| --- | --- | --- |
| `model` | required | Model name or hash to preview |
| `title` | `"Place Object"` | Heading on the key legend |
| `placeLabel` | `"Place"` | Label on the Enter key |
| `heading` | the player's | Starting heading |
| `maxDistance` | `3` | Reach from the player, in metres |
| `tint` | none | Texture variation (tint palette row) the preview wears, so it shows the paint it will have |
| `with` | none | More models set down on the same origin and heading, for a thing built from several (a cabinet and its animated screens) |

### What comes back

| Result | Means |
| --- | --- |
| `{ x, y, z, heading }` | Placed. The coordinates are the object's position: set it with `SetEntityCoordsNoOffset` |
| `nil` | The player cancelled, got into a car, died, or the script cancelled it |
| a string | The tool could not open (another placement is open, or the model is not streamed) |

`gg.placement.cancel()` closes a placement your script opened. It also closes if
your script stops. Only one placement can be open at a time. Needs gg_lib 1.0.23.

Script Studio settings place props with the same tool: see
[Placing props](studio.md#placing-props).

