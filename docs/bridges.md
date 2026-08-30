# Bridges

What gg_lib connects our scripts to, and how to override it.

[← back to the README](../README.md)

---

## Bridges

The **Bridges** page shows what gg_lib connected to and whether each connection
worked. If a script is not behaving, look here first.

Everything is detected automatically. To force a choice instead, open
`utility.lua` and name the resource:

```lua
framework = "qb-core",   -- leave blank to auto detect
```

A forced name that is not running is shown in red on the Bridges page, so a typo
is visible instead of silent.

The same page lets you choose who draws notifications, progress bars and text
prompts. Those apply the moment you pick them — no restart.


---

## Adding a fuel or keys script

Fuel and keys live in one file each — `bridge/fuel/client.lua` and
`bridge/keys/client.lua`. Add a row and restart:

```lua
['my_fuel'] = {
    get = function(veh) return exports['my_fuel']:GetFuel(veh) end,
    set = function(veh, level) return exports['my_fuel']:SetFuel(veh, level) end,
},
```

```lua
['my_keys'] = {
    add    = function(veh, plate) return exports['my_keys']:GiveKey(plate) end,
    remove = function(veh, plate) return exports['my_keys']:RemoveKey(plate) end,
},
```

Then add the resource name to its category in `bridge/manifest.lua` so it gets
detected. Leave `remove` out if the script has no way to take keys back — it
returns false on its own.

The vehicle is already checked before your function runs, and `plate` is handed
to you, so there is no guard to write.

Everything else — framework, inventory, target, dispatch — is a folder per
resource, holding `client.lua`, `server.lua` or both. Those genuinely differ
from one script to the next, so they stay separate files.
