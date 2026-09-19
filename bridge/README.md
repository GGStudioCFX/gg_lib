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

Dispatch is optional. A missing or stopped dispatch provider stays quiet at
startup; the first attempted `gg.dispatch.alert` prints one warning and returns
`false`. Later attempts return `false` without repeating the warning.

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

A key script that only trusts a request made beside the car gets its keys from
this resource's server instead, and only for a car spawned with
`gg.vehicleManager.spawnVehicle`. Anything else falls back to the plain request.
`RemoveKeys` waits for that answer when it can, so deleting the car straight
after it is safe.

---

## Phone

Eight resource names, one API. Detection order is `sd-phone`, `sky_phone`, `gksphone`,
`jpr-phonesystem`, `yseries`, `yphone`, `yflip-phone`, then `lb-phone` — sd-phone and
sky_phone first because each stands in for several of the others (below),
lb-phone last for the same reason ox and qb are: it is the one most likely to be
sitting on a server as a dependency of the phone actually in use.

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

Mail on lb-phone and sd-phone goes to the phone's email account: a number or a
source is looked up with `GetEmailAddress`, and a target containing `@` is used
as the address itself.

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
fixed payload whose `app` must stay `"Custom"`. Mail goes through the phone's
documented server event, `jpr-phonesystem:server:sendEmail`, with `subject`,
`message` and `sender`, addressed to a player source. The phone has no
server-side lookup from a number to a player, so a phone-number target answers
`false`. Its optional `event` button and its offline `sendNewMailToOffline`
export are not mapped. JPR's documentation covers QBCore, QBox, ESX and VRPex.

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
`exports['lb-phone']` and serves lb-phone custom apps as they are. It has its own
entry here under `sd-phone`, and that folder runs the lb-phone bridge with the
resource name swapped and the export name left alone. Its manifest also declares
`provide` for `lb-phone`, `gksphone` and `yseries`, among others; on FiveM builds
where that makes `GetResourceState` report those names started, an sd-phone
server would otherwise be detected as GKS Phone, so `sd-phone` is checked first.
A server running the real phone has no sd-phone, and nothing changes there.

### sky_phone

Sky-Systems' free phone. Like sd-phone it answers `exports['lb-phone']` on the
client (it registers the lb-phone export names and declares `provide` for
`lb-phone`, `yseries`, `17mov_Phone`, `high-phone` and `qs-smartphone`),
with nothing to switch on, so its folder runs the lb-phone bridge under its own
name and is checked before the phones it stands in for. It serves an lb-phone
app from a `srcdoc` frame with a `<base>` pointing at the app's folder, the
lb-phone helpers injected and `componentsLoaded` posted, so the page has no
`cfx-nui-` origin of its own; the injected `settings.version` is `sky_phone`.

Three differences from lb-phone:

- `SendNotification` returns `false` with a reason instead of throwing. It
  refuses an empty title or text, and an app the calling resource did not add,
  and `gg.phone.notify` reports that as `false`.
- On the server it answers only the number lookups. It exports no way to send
  mail, so `gg.phone.mail` returns `false` and warns once.
- Game keys stay live while it is open, and it cannot tell that a field inside
  an app's frame has focus. `gg.phone.app.focus(boolean)` calls its
  `SetPhoneGameInputEnabled` to hold game input while typing. It only hands
  input back if it was on beforehand, so a server that turned `AllowMovement`
  off keeps it off.

### yphone and yflip-phone

yseries under other resource names, same exports. Their folders run the
`yseries` file with `GG_PHONE_EXPORT` set, the way `lation_interact` runs the
`ox_target` one.

---

## HUD

Client only. A script hides the server's HUD for a camera, a tablet or a
cutscene, and gives it back when done, without knowing which HUD is installed.

```lua
gg.hud.hide()                    -- the HUD resource
gg.hud.hide({ native = true })   -- and the game's own HUD and minimap, every frame
gg.hud.show()
gg.hud.isHidden()                -- any script hiding it right now
gg.hud.resource                  -- the bridged HUD, nil with none
```

**Every script shares one hide.** Each GG script runs its own copy of gg_lib,
so who is hiding the HUD lives on the player's state bag (local, never sent to
the server). The HUD goes away when the first script hides it and comes back
when the last one shows it — one script finishing its camera never brings the
HUD back over another's. `hide` twice is still one hide; there is no count.

**A script that stops gives its hide back.** Every copy watches resource stops,
so a restart or crash mid-camera cannot leave the player without a HUD.

**A HUD that restarts is hidden again.** HUDs show themselves on start; a script
still holding the hide tells it again once it has settled.

**So is one the pause menu brings back.** Some HUDs show themselves whenever
the pause menu closes, hidden or not. A second after it closes, a script still
holding the hide tells the HUD again.

**A HUD the player had hidden stays hidden.** Where a HUD can say whether it is
showing, that is asked before the first hide, and the last `show` leaves it
hidden if it already was. The rest cannot say, so `show` brings them back.

`native` is per script and off by default: a race HUD that replaces the server's
HUD usually still wants the minimap. With no HUD resource at all, `hide` still
works and `native` is the only thing it can do.

Every call into the HUD resource is guarded like the target ones, and a stopped
HUD is not called at all.

### What each HUD can do

Each call below is from the HUD's own documentation or source, never from
another library's bridge. Only esx_hud and qbx_hud have been run in game.

| Resource | Call | Knows if showing | Source |
| --- | --- | --- | --- |
| 0r-hud-v3 | `ToggleVisible(bool)` | | [docs](https://docs.0resmon.org/0resmon/0r-resources/0r-hud-v3/integrations-and-events) |
| 17mov_Hud | `ToggleDisplay(bool)` | | [docs](https://docs.17movement.net/advanced-hud/usage-in-other-resources) |
| 17mov_Interface | `toggleDisplay(bool)` | | [docs](https://docs.17movement.net/complete-interface-system/api/client-exports) |
| ak47_hud | `ToggleHudElement('all', bool)` | `GetHudState` | [docs](https://docs.menanak47.com/multi-framework/ak47_hud/exports/client) |
| Codem-BlackHUDV2 | event `codem-blackhudv2:SetForceHide` | `IsVisible` | [docs](https://codem.gitbook.io/codem-documentation/blvck/huds/hud-v2/events-and-exports) |
| codem-supreme-hud | `HideHud()` / `ShowHud()` | `IsHudHidden` | [docs](https://codem.gitbook.io/codem-documentation/supreme-series/essentials/hud-all-in-one/events-and-exports) |
| cx-hud | `hideHud()` / `showHud()` | | [source](https://github.com/JustCxsper/cx-hud/blob/f397af6d76aca042ba07755f6ff39a33aeb47b6f/client/main.lua#L45-L60) |
| dusa_hud | `HideHud()` / `ShowHud()` | | [docs](https://dusadev.gitbook.io/dusa-all-scripts-documentation/scripts/editor-2/client/exports) |
| envi-hud | `ToggleHUD(bool)` | | [docs](https://envi-scripts-organization.gitbook.io/documentation/premium-scripts/envi-hud/exports-and-events) |
| esx_hud | `HudToggle(bool)` | | [source](https://github.com/esx-framework/ESX-Legacy-Addons/blob/main/%5Besx_addons%5D/esx_hud/client/main.lua) |
| gfx-hud_aty | event `aty_hud:toggle` | | [docs](https://github.com/GFX-Fivem/gfx-docs/blob/main/scripts/gfx-hud_aty.md) |
| izzy-hudv5, v6, v8 | `setDisplay(bool)` | | [docs](https://docs.izzyshop.info/docs.html) |
| jg-hud | `toggleHud(bool)` | | [docs](https://docs.jgscripts.com/hud/exports) |
| mHud, mhud | events `mHud:HideHud` / `mHud:ShowHud` | | [docs](https://codem.gitbook.io/codem-documentation/m-series/huds/mhud-aio/how-to) |
| qbx_hud | events `qbx_hud:client:hideHud` / `showHud` | | [source](https://github.com/Qbox-project/qbx_hud/blob/main/client/main.lua) |
| qs-interface | `ToggleHud(bool)` | | [docs](https://www.quasar-store.com/docs/interface/commands-and-exports) |
| rhud | `set_visible(bool)` | `get_visible` | [docs](https://github.com/Raxdiam/rHUD/blob/main/docs/content/exports/client.mdx) |
| tgiann-hud | event `tgiann-hud:ui` | | [docs](https://tgiann.gitbook.io/tgiann/scripts/tgiann-hudv2/event-list) |
| tgiann-lumihud | event `tgiann-lumihud:ui` | | [docs](https://tgiann.gitbook.io/tgiann/scripts/tgiann-lumihud/events-exports) |
| vms_hud | `Display(bool)` | | [docs](https://docs.vames-store.com/assets/vms_hud/developer-api/client-exports) |
| wais-hudv5 | event `wais:hideHud` | | [readme](https://github.com/ayazwai/wais-hudv5-readme/blob/main/README.md) |
| wais-hudv6 | `hideHud()` / `showHud()` | | [docs](https://docs.0resmon.org/0resmon/wais-resoucres/wais-hudv6/exports) |
| ZSX_UI | `HideUI(bool)` | | [docs](https://zsx-development.gitbook.io/docs/resources/user-interface/functions) |
| ZSX_UIV2 | `HideInterface(bool)` | | [docs](https://zsx-development.gitbook.io/docs/resources/user-interface-v2/configurating/handling-ui/hud/show-hide-ui) |

Detection order puts the all-in-one interfaces and `tgiann-hud` (a dependency of
other tgiann scripts) after the dedicated HUDs, and esx_hud and qbx_hud last:
servers often leave the stock HUD running after installing another.

Worth knowing about particular ones:

- **esx_hud** hides the whole page, and its own pause menu handler respects it.
- **qbx_hud** only hides its vehicle panel and minimap, and only in a vehicle.
  Its status panel has no way to be hidden from outside, and its own loop puts
  the vehicle panel back as soon as the vehicle moves -- both checked in game.
  Use `native = true` with it.
- **ZSX_UIV2** hides the whole interface, notifications included.
- **Codem-BlackHUDV2** is told to keep the minimap, which is left to `native`.
  Owners often rename its folder; a renamed copy is not detected.
- **mHud** is listed under both spellings its own documentation uses.

Not listed, because they have no documented way to be hidden from another
resource: qb-hud, ps-hud, mri_Qhud, Renewed-Hud, gfx-hud, fd_hud, CodeM Venice
HUD and BLVCK HUD v1. With one of those running, only `native = true` hides
anything. cd_carhud only toggles, with no state. uz_PureHud documents an export
its source does not have. izzy-hudv7 and tgiann's Modern HUD have no confirmed
folder name. Several more appear in other libraries' bridges with no
documentation behind them, and wait for some.

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
