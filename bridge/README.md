# Bridges

Every bridge answers one small set of calls, whatever resource is behind it. A
script written against `gg.target` works on ox_target, sleepless_interact and
qb-target without knowing which is installed.

Detection order lives in `manifest.lua`. ox and qb candidates are listed **last**
in every category on purpose: plenty of servers run them as a dependency of the
thing they actually use, so any other started resource should win first.

Categories in `required` warn once at start when nothing is found. The rest fall
back quietly — a server with no fuel resource is not a server with a problem.
Nothing is ever left nil: `bridge/fallback.lua` fills every category that had no
provider, so a call comes back empty rather than taking the resource down.

---

## Target

The one that catches people out: **a networked entity and a local one go into
different registries.** Using the wrong one does not error — the option simply
never appears.

`gg.target.addEntity` decides for you. Call it with the entity handle either way.

```lua
-- A ped you spawned locally (CreatePed with isNetwork = false).
local ped = CreatePed(4, joaat('a_m_m_business_01'), coords.x, coords.y, coords.z, 0.0, false, false)

gg.target.addEntity(ped, {
    distance = 2.0,
    options = {
        {
            name  = 'depot:talk',            -- what removeEntity takes back
            label = 'Talk to the clerk',
            icon  = 'fa-solid fa-comment',
            groups = 'taxi',                 -- job or gang, either key works
            canInteract = function(entity, distance, coords, name, bone)
                return not IsPedInAnyVehicle(PlayerPedId(), false)
            end,
            onSelect = function(data)        -- data.entity is the entity
                print('clicked', data.entity)
            end,
        },
    },
})

-- Later, by name. Without a name every option on the entity goes.
gg.target.removeEntity(ped, 'depot:talk')
```

Remove **before** the entity is deleted. Once the handle is gone there is no way
left to tell which registry it was in.

### Zones

Every `add*Zone` answers with a handle. Keep it — it is a number on ox and a name
on qb, so never assume either.

```lua
local zoneId = gg.target.addBoxZone({
    coords   = vec3(120.5, -800.2, 31.0),
    size     = vec3(4.0, 4.0, 3.0),
    rotation = 90.0,
    options  = { { name = 'depot:board', label = 'Start shift', onSelect = startShift } },
})

gg.target.removeZone(zoneId)
```

`addSphereZone{ coords, radius, options }` and `addPolyZone{ points, thickness,
options }` work the same way.

### Models and globals

```lua
gg.target.addModel({ `prop_atm_01`, `prop_fleeca_atm` }, { options = { ... } })
gg.target.removeModel({ `prop_atm_01` }, 'atm:use')

gg.target.addGlobalPed({ options = { ... } })       -- also Vehicle, Object, Player
gg.target.removeGlobalPed('depot:talk')
```

### Cleanup

ox_target drops a resource's targets when it stops, and the qb-target bridge does
the same by hand. **You do not need an `onResourceStop` handler for targets.**

---

## Inventory

```lua
-- Server
gg.inventory.addItem(source, { item = 'water', count = 2 })
gg.inventory.removeItem(source, { item = 'water', count = 1 })
gg.inventory.hasItem(source, { item = 'water', count = 1 })
gg.inventory.canCarryitem(source, { item = 'water', count = 5 })
```

For item **data** use the catalogue rather than the bridge — it is normalized,
cached, and works the same on every inventory:

```lua
gg.items.get('water')      -- { name, label, weight, description, stack, image }
gg.items.label('water')    -- falls back to the raw name
gg.items.image('water')    -- honours the icon path override in the Items tool
gg.items.exists('plastic') -- validate a config value
gg.items.list()            -- sorted, for pickers
```

---

## Framework and vehicles

```lua
gg.framework.GetIdentifier(source)
gg.framework.GetVehicle('adder')       -- label for a spawn name
```

Same story for vehicle data — use the catalogue:

```lua
gg.vehicles.get('adder')      -- { model, label, brand, price, category }
gg.vehicles.fromHash(hash)    -- spawn name from a model hash, O(1)
gg.vehicles.categories()
```

---

## Dispatch

One call, whatever MDT is installed.

```lua
gg.dispatch.alert({
    message  = 'Taxi driver robbed',
    code     = '10-90',
    jobs     = { 'police' },
    coords   = GetEntityCoords(PlayerPedId()),
    priority = 2,
    icon     = 'fa-solid fa-taxi',
    time     = 10000,
    blipData = { sprite = 198, color = 1, scale = 1.0, radius = 0 },
})
```

---

## Fuel and keys

Optional categories. Nothing installed means the game's own fuel is used, and
handing out a key is a no-op that succeeded.

```lua
gg.fuel.getFuel(vehicle)          -- 0-100
gg.fuel.setFuel(vehicle, 75.0)

gg.keys.AddKeys(vehicle)          -- after spawning one for a player
gg.keys.RemoveKeys(vehicle)
```

Not every key resource can take a key back; those answer `false` from
`RemoveKeys` rather than pretending.

---

## Adding a provider

1. Make `bridge/<category>/<resource name>/client.lua` — the folder name must be
   the resource name exactly, because detection is `GetResourceState(folder)`.
2. Implement the same functions the other providers in that folder implement.
3. Add the name to `manifest.lua`, above `ox_*` and `qb-*`.

A resource that declares `provides { 'ox_target' }` still needs its own entry:
`provides` does not make `GetResourceState('ox_target')` report started, so
nothing would match it. `sleepless_interact` is the example — its bridge runs the
ox_target one rather than keeping a copy.
