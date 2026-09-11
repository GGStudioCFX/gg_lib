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

## Importing only declared modules

A resource that only needs Script Studio can skip automatic bridges and gameplay
modules in its manifest:

```lua
shared_scripts { '@gg_lib/init.lua' }
gg_lib_mode 'modules'
gg_lib 'settings'

server_scripts { '@oxmysql/lib/MySQL.lua' }
dependencies { 'gg_lib', 'oxmysql' }
```

This loads the declared settings module and its dependencies as needed. It does
not detect bridges, install bridge fallbacks, or watch for bridge providers
starting later. Declare the resource's own settings with `settings.script`,
`settings.group` and `settings.define`; they appear in `/ggsettings` with the
usual permissions, database storage and live updates.

Omit `gg_lib_mode` for the standard job import. Existing consumers keep their
automatic bridges, default modules and missing-provider warnings.

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


---

## Start order and restarts

A script does not have to start after its target script, and it does not
have to notice when that one restarts. Every zone, ped and model it registers
through `gg.target` is journaled in its own VM -- a removal cancels its add --
and the journal is played back into the target script whenever that starts,
the first time or the fiftieth. While there is no target script the calls are
simply held: the console says so, and then how many were replayed. A zone's
handle is its name, before and after: `addBoxZone` answers with it, and it is
what `removeZone` takes.

The framework and inventory bridges answer questions rather than take
registrations, so those still want their script started first.

`restart gg_lib` stops every resource that declares `dependency 'gg_lib'`,
and FXServer does not start them again -- its own source calls that a TODO.
gg_lib brings back what went down with it, target and framework scripts
first, so the scripts that need them find them started. For that it needs
one line in server.cfg:

```cfg
add_ace resource.gg_lib command.ensure allow
```

Without it, it prints the `ensure` lines to run, in order, for you to paste
into the console. `set gg_lib_restart_dependants false` turns the automatic
part off.

A script that gg_lib bridges *to* and that also uses gg_lib -- a target
script with its settings in Script Studio, say -- should not declare
`dependency 'gg_lib'`. Keep `@gg_lib/init.lua` and start it after gg_lib in
server.cfg: it stays up when gg_lib restarts, and Script Studio finds its
settings again within a couple of seconds, because it finds scripts by
asking them rather than by remembering them.
