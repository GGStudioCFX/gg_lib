# Bridges

Every bridge answers one small set of calls, whatever resource is behind it. A
script written against `gg.target` works on lation_interact, sleepless_interact,
ox_target and qb-target without knowing which is installed.

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

### When the target script is the one that breaks

Every call the target bridge makes into ox_target, sleepless_interact or
lation_interact goes through a guard. If that resource throws -- a bad release, a
renamed export, an export dropped between versions -- the error never reaches the
GG script that happened to be registering a zone at the time. The call fails
quietly, the script carries on, and the console says once, per export, whose code
broke:

```
[gg_lib] lation_interact:addBoxZone() threw. That is lation_interact's code, not
gg_lib's -- send them this:
  An error occurred while calling export addBoxZone in resource lation_interact: ...
```

Counts land on `gg.bridge_status.target.provider_failures`, and because the line
is printed client-side it is picked up by the support bundle -- so a customer's
paste already carries the evidence of whose resource failed.

Looking an export up is itself what throws in FiveM when it does not exist, so
the lookup happens inside the guard rather than at the call site. Any bridge
that calls a third-party resource should do the same.

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

## Phone

Seven resource names, one API. Detection order is `gksphone`, `sd-phone`,
`jpr-phonesystem`, `yseries`, `yphone`, `yflip-phone`, then `lb-phone` — lb-phone last for the same reason
ox and qb are: it is the one most likely to be sitting on a server as a
dependency of the phone actually in use.

```lua
-- Either side
gg.phone.resource               -- the resolved resource name, nil with no phone
gg.phone.number(source)         -- server takes a source; client takes nothing
gg.phone.hasPhone(source)

-- Server
gg.phone.notify(source, { app = 'gg_taxi', title = 'Taxi', content = 'On the way' })
gg.phone.mail(source_or_number, { sender = 'no-reply', subject = '...', message = '...' })

-- Client
gg.phone.notify({ app = 'gg_taxi', title = 'Taxi', content = 'On the way' })
```

### Custom apps

A script registers one app once, against `gg.phone.app`, and never names a
phone. Pass the ui and icon as full `https://cfx-nui-<resource>/...` URLs; each
bridge reshapes them to what its phone wants.

```lua
gg.phone.app.ready()            -- the phone is up and, on yseries, has loaded its data
gg.phone.app.add({
    key         = 'gg_taxi',
    name        = 'Taxi',
    description = '...',         -- lb-phone only
    developer   = 'GG Studio',   -- lb-phone only
    defaultApp  = true,
    size        = 21400,         -- lb-phone only
    ui          = 'https://cfx-nui-gg_taxijob/phone/dist/index.html',
    icon        = 'https://cfx-nui-gg_taxijob/phone/dist/icon.png',
    fixBlur     = true,          -- lb-phone only
})
gg.phone.app.send('gg_taxi', 'taxi_update', { status = 'accepted' })
gg.phone.app.remove('gg_taxi')
gg.phone.app.drain('gg_taxi')   -- messages send() could not push; {} on every phone that could
```

`drain` exists for JPR (below). A page that polls it through its own resource
every second or so works on every phone; on the ones that push, it just always
comes back empty.

### jpr-phonesystem

No export adds an app, and this has been checked against JPR's own documentation
rather than assumed: its [Custom APPs page][jpr-apps] installs one entirely inside
the phone, and its [exports list][jpr-exports] carries `isPhoneOpen`, `openPhone`,
`closePhone`, `isCamaraOpen`, `getPhoneNumber`, `sendWhatsapp` and `sendiMessage`,
with nothing that registers an app. JPR's apps are entries in its own `main_config.lua` and a
`<div class="app-<name>">` pane in its own `index.html`, all in its
`escrow_ignore`, so the app is installed by hand from the kit the script ships
under `!SETUP/JPR Phone/`. `add()` therefore has nothing to do and answers
`true`. The pane is an iframe of the script's own page inside the phone's NUI
page, and Lua cannot post into another resource's NUI -- so `send()` queues and
the page drains through `gg.phone.app.drain`.

[jpr-apps]: https://joaos-organization-3.gitbook.io/jpresources-documentation/installation/phone-system/custom-apps
[jpr-exports]: https://joaos-organization-3.gitbook.io/jpresources-documentation/installation/phone-system/events-and-commands

The number is a client export only (`getPhoneNumber`), so the server asks the
client over `gg.callback`. Notifications are the phone's own client event with a
fixed payload whose `app` must stay `"Custom"`. There is no mail export. JPR
runs on QBCore only.

### gksphone

GKS Phone v2 registers apps automatically through its client `AddCustomApp`.
The bridge maps the key to `name`, UI to `appurl`, and icon to `icons`, with
`startapp` for default apps and optional `labelLangs`. No phone files need edits.
Start `gksphone` before importing resources. The app URL gets `phone=gksphone`;
the page can use the injected `window.gksphone` for theme changes. Taxi callbacks
must still POST to Taxi's own resource; GKS `fetchNui` addresses the phone.
`NuiSendMessage` pushes messages into the calling resource's iframe. Optional
`gg.phone.app.focus(boolean)` calls `InputChange` to protect typing.

There is no documented custom-app removal/query export. `installed` tracks this
consumer's registration, not the player's App Gallery installation. `remove`
returns false for a registered app; disable the setting and restart the phone
and consumer to clear it. Resource stop closes the app. Online mail accepts a
player source or phone number; unsupported offline/action payloads are not mapped.

Wait on `ready()` rather than on `GetResourceState`. On yseries the resource is
"started" well before `GetDataLoaded()` is true, and `AddCustomApp` before that
is dropped.

### What the app page sees

lb-phone injects `fetchNui`, `useNuiEvent`, `onSettingsChange`, `settings` and
`resourceName` into the iframe and only posts `componentsLoaded` once it wants
the page rendered. yseries injects nothing and expects the page to render on its
own; the bridge appends `?phone=<resource>` to the ui URL so the page knows
which resource answers `main:get-settings`. A page that checks for the injected
`fetchNui` and falls back to its own `fetch` runs on every phone here unchanged.

### sd-phone

Ships an lb-phone compatibility layer, on by default, that answers
`exports['lb-phone']` and serves lb-phone custom apps as they are. Its manifest
declares `provide 'lb-phone'`, which satisfies dependencies but does not make
`GetResourceState('lb-phone')` report started — so it has its own entry here
under `sd-phone`, and that folder runs the lb-phone bridge with the resource
name swapped and the export name left alone.

### yphone and yflip-phone

yseries under other resource names, same exports. Their folders run the
`yseries` file with `GG_PHONE_EXPORT` set, the way `lation_interact` runs the
`ox_target` one.

---

## Adding a provider

1. Make `bridge/<category>/<resource name>/client.lua` — the folder name must be
   the resource name exactly, because detection is `GetResourceState(folder)`.
2. Implement the same functions the other providers in that folder implement.
3. Add the name to `manifest.lua`, above `ox_*` and `qb-*`.

A resource that declares `provides { 'ox_target' }` still needs its own entry:
`provides` does not make `GetResourceState('ox_target')` report started, so
nothing would match it. `sleepless_interact` and `lation_interact` are the
examples — their bridges run the ox_target one rather than keeping a copy.
`lation_interact` hands it `GG_TARGET_EXPORT`, so every call goes to
`exports.lation_interact` rather than to the `ox_target` alias, which a server
still running the real ox_target would answer instead.
