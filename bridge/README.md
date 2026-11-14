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

The same item API works on all fifteen inventories, metadata included. Rows
always read `{ name, label, count, slot, metadata, weight }`: qb-style `amount`
and `info` are read as `count` and `metadata`, and `metadata` is always a table.
Metadata matches the way ox_inventory's `Search` does: every key you ask for has
to be there with the same value, and the item may carry more.

```lua
-- Server
gg.inventory.getItems(source)                          -- every row, sorted by slot
gg.inventory.getSlot(source, 3)                        -- one row, or nil
gg.inventory.findItem(source, 'radio', { serial = s }) -- the first matching row
gg.inventory.getCount(source, 'radio', { serial = s }) -- metadata is optional
gg.inventory.setMetadata(source, 3, { serial = s })    -- replaces it; true once saved
gg.inventory.canCarryWeight(source, 2500)

gg.inventory.addItem(source, { item = 'radio', count = 1, metadata = { serial = s } })
gg.inventory.hasItem(source, { item = 'radio', metadata = { serial = s } })
gg.inventory.removeItem(source, { item = 'radio', metadata = { serial = s } }) -- that radio, not another
gg.inventory.removeItem(source, { item = 'radio', slot = 3 })

-- cb(source, row): the inventory's own usable items where it has them
-- (qs-inventory, jaksam_inventory, wasabi_inventory), the framework's otherwise.
gg.inventory.registerUsable('radio', function(source, row) end)

-- ox_inventory and wasabi_inventory: false from cb stops the move. nil on the others.
local hook = gg.inventory.onSwap(function(payload) end, { itemFilter = { radio = true } })
gg.inventory.removeHook(hook)

gg.inventory.hasMetadata() -- false only on the fallback (no inventory running)

-- Client
gg.inventory.getItems()
gg.inventory.getCount('radio', { serial = s })
gg.inventory.hasItem('radio', 1, { serial = s })
-- ox_inventory plays the use animation and takes the item, then calls back;
-- other inventories call back straight away.
gg.inventory.useItem(data, function(data) end)
gg.inventory.getImageDirectory()
```

Never call an inventory's exports from a resource: what an inventory has no
export for (a slot read on qs-inventory, a metadata count on qb-inventory) is
worked out here from its rows, so the call is the same everywhere. The shared
layer is `bridge/inventory/_common/<context>.lua`; it runs after whichever
bridge (or the fallback) installed, again whenever a late inventory takes over.

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

### wasabi_inventory

Wasabi's manifest provides `ox_inventory` and answers the exports it supports, so
`GetResourceState('ox_inventory')` can report started on a Wasabi server, and the
ox bridge would then point every picture at a folder that is not there. So it has
its own entry above ox_inventory, and every call goes to `exports.wasabi_inventory`.

Pictures load from `wasabi_inventory/ui/images/` with no setup: `client.image` on
the item picks the file, `<item>.png` otherwise, and a full `https://` or `nui://`
`ImagePath` in `config/client/config.lua` replaces the folder. Icon Path in the
Items tool still wins over all of it.

`registerUsable` is the inventory's own `registerUsableItem`, and the row comes
from `context.slot`. `onSwap` works as it does on ox_inventory. A use has already
gone through when a script hears of it, so `useItem` calls back straight away, and
it drops the second arrival of one press (an item with a `client.export` as well
as a registered use).
`RemoveItem` documents no `strict` option, so a metadata removal goes by the slot
`_common` found. Item definitions follow ox_inventory's schema in `data/items.lua`,
but `consume` defaults to zero, even with a `client.usetime` or `server.export`.

Written from the [exports][wasabi-exports], [items][wasabi-items] and
[configuration][wasabi-config] pages, and not yet run on the real inventory.

[wasabi-exports]: https://docs.wasabiscripts.com/core-ui-series/wasabi-inventory/exports
[wasabi-items]: https://docs.wasabiscripts.com/core-ui-series/wasabi-inventory/items-and-weapons
[wasabi-config]: https://docs.wasabiscripts.com/core-ui-series/wasabi-inventory/configuration

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

### Jobs

Server only. A script that runs on a job of its own can make it when the server
does not have it, the framework's own way, and never changes one it has.

```lua
gg.framework.GetJob('belladonna')     -- the framework's own job table, or nil
gg.framework.CreateJob('belladonna', {
    label = 'Belladonna', type = 'casino', defaultDuty = true,
    grades = {
        [0] = { name = 'Dealer', payment = 60 },
        [1] = { name = 'Owner', payment = 150, isboss = true },
    },
})                                    -- true once the framework shows it, or false, why ('exists')
```

| Framework | How | Kept |
|---|---|---|
| qbx_core | `exports.qbx_core:CreateJob` (grades keyed 0, 1, ...) | this run only: shared/jobs.lua is not written |
| qb-core | `exports['qb-core']:AddJob` (grades keyed '0', '1', ...) | this run only: shared/jobs.lua is not written |
| es_extended | `ESX.CreateJob`; an older ESX: its `jobs` and `job_grades` tables, then `ESX.RefreshJobs` | in its database |

A job kept for the run only is made again by the script at each start, before
players join (a qbx or qb player whose job the framework does not know is put
back to unemployed when they load). On es_extended a grade's `name` is its id:
the boss grade is `boss`, the rest come from their labels, and the label is the
name given.

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

Fourteen resource names, one API. Detection order is `sd-phone`, `sky_phone`, `gksphone`,
`jpr-phonesystem`, `roadphone`, `codem-phone`, `17mov_Phone`, `apex_phone`, `qs-smartphone-pro`, `qs-smartphone`, `yseries`, `yphone`,
`yflip-phone`, then `lb-phone` — sd-phone and
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
    description = '...',         -- lb-phone and apex_phone only
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

`drain` exists for the phones that cannot push into an app (JPR, RoadPhone, CodeM,
Apex and both Quasar phones, below). A page that polls it through its own resource
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

### roadphone

RoadPhone Pro registers custom apps from its `public/static/config/config.json`
`AppStore` array. Its public client and server export lists do not expose a
runtime custom-app registration or removal call. The product's `!SETUP` kit
provides the one-time entries and icons. Selecting `roadphone` in the Bridges
page (or detecting it) routes phone numbers and notifications through its
documented exports; `app.add` records a logical registration but cannot edit
RoadPhone's app catalog. `app.remove` clears that registration and any queued
messages, not the phone's config entry.

RoadPhone's custom-app iframe loads each product page with `?phone=roadphone`.
There is no documented custom-app push channel. `send()` keeps at most 50 updates
per app until the page drains them through the product's NUI callback. The page
calls `window.parent.roadphone.inputFocus` for text fields and reads its dark-mode
setting. The app entries use `default: true`, so players see them after the
operator adds the entries and restarts RoadPhone. The public references are
[Custom App API][roadphone-apps], [Client Exports][roadphone-client], and
[Server Exports][roadphone-server].

[roadphone-apps]: https://docs.roadshop.org/roadphonepro/custom-apps
[roadphone-client]: https://docs.roadshop.org/roadphonepro/api/client
[roadphone-server]: https://docs.roadshop.org/roadphonepro/api/server

### codem-phone

CodeM mPhone 2.5 registers apps at runtime through its client `AddCustomApp`.
The bridge maps the key to `identifier` and passes `name`, `description`,
`developer`, `icon` and `fixBlur`. A `defaultApp` goes on the home grid; any
other app is published to the phone's App Store (`addAppStore`) for players to
install. The ui URL is iframed as given, with `?phone=codem-phone` appended.
Every added app is registered again two seconds after `codem-phone:phoneLoaded`,
as the phone's own example app does, and a refused add is kept for that retry.

There is no documented push-to-app, removal or installed-query export. `send()`
keeps at most 50 updates per app until the page drains them through its own NUI
callback. `remove` returns false for a registered app; disable the setting and
restart the phone to clear it. `installed` tracks this consumer's registration.
The page is cross-origin to the phone, so it reports focused text fields through
`gg.phone.app.focus`, which calls `SetInputFocus`.

The number is a server export only (`GetPhoneNumberBySource`), so the client asks
the server over `gg.callback`. Notifications are the server `SendNotify`, styled
by the app key; the client relays its own up. Mail to a source uses
`SendMailBySource`; a number is turned into the phone's address with
`GetSocialMediaUsername(number, 'mail')` and sent with `SendMail`, which also
reaches offline owners. References: [Custom App][codem-apps],
[Client Exports][codem-client], [Server Exports][codem-server].

[codem-apps]: https://codem.gitbook.io/codem-documentation/m-series/essentials/mphone-2.5/custom-app
[codem-client]: https://codem.gitbook.io/codem-documentation/m-series/essentials/mphone-2.5/exports-and-events/client-exports
[codem-server]: https://codem.gitbook.io/codem-documentation/m-series/essentials/mphone-2.5/exports-and-events/server-exports

### 17mov_Phone

17mov's phone registers external apps at runtime through its client
`AddApplication`, as its own [boilerplate][17mov-boilerplate] does. The bridge maps
the key to `name` and `name` to `label`, and passes the ui and icon URLs, an
`iconBackground` (`spec.iconBackground`, default `#151519`), `rating` (default 5),
`resourceName` (the importing resource) and an optional `job` restriction. A
`defaultApp` is sent as `default` and `preInstalled`: it shows on every phone,
existing ones included, and cannot be uninstalled. Any other app waits in the
phone's store. The phone takes no description or developer; a translated label and
store text go in the phone's own locale files (`Appname:Title`,
`Store:Appname:Description`). The ui URL is framed as given, with
`?phone=17mov_Phone` appended. Every added app is registered again on
`17mov_Phone:Client:Ready`, and a refused add is kept for that retry. `remove` is
`RemoveApplication` without `uninstall`, so the player's install stays.

`send()` is `SendAppMessage(key, { action, payload })`. The phone posts that into
the app's frame, so a page reads `payload` where other phones give `data`, and
`drain` is always empty. The phone calls the page's `window.LoadRoot()` once it has
injected its helpers into the frame, and posts to `https://<window.name>/<callback>`,
where `window.name` is the resource name. Pages hold `setKeepInput(false)` while a
text field has the keyboard, register their routes with `setExternalRouting`, and
answer the phone's `window.__dispatchAction` (`GetCurrentRoute`, `Navigate`), as the
boilerplate's `ExternalRpcBridge` does. `gg.phone.app.focus` has nothing to do here.

The number is the client `GetPlayerNumber` and the server
`GetNumberFromPlayer(source)`; `hasPhone` on the client is `HasPhoneItem`.
Notifications are the client `CreateNotification` and the server
`SendNotificationToSrc`, both `{ app, title, message }`, with `app` defaulting to
`SYSTEM`. Mail to a source or a number uses `Email_SendEmailBySrc` /
`Email_SendEmailByNumber` with a named sender (`customUser`), or the system mail
exports without one. A mail address target answers false. References:
[Custom apps][17mov-apps], [Registering][17mov-register],
[Client exports][17mov-client], [Server exports][17mov-server], [Email][17mov-email].

[17mov-boilerplate]: https://github.com/17movement-net/17mov_Phone_app_boilerplate
[17mov-apps]: https://docs.17movement.net/phone/building-custom-apps
[17mov-register]: https://docs.17movement.net/phone/building-custom-apps/registering-the-application
[17mov-client]: https://docs.17movement.net/phone/exports/global-exports/client-exports
[17mov-server]: https://docs.17movement.net/phone/exports/global-exports/server-exports
[17mov-email]: https://docs.17movement.net/phone/exports/email/server-exports

### apex_phone

Apex Phone registers external apps at runtime through its client `RegisterApp`
(`{ id, name, url, icon, category, description }`). The bridge sends the key as
`id`, the ui URL framed as given with `?phone=apex_phone` appended, the icon URL,
and `spec.category`, `spec.description` and an optional `job` as they come. Every
registered app goes on the home screen, so `defaultApp` has nothing to choose, and
the phone takes no developer or size. A refused add (`RegisterApp` answers false)
is kept, and every added app is registered again when the phone starts. The phone
takes an app off by itself when the resource that added it stops; `remove` is
`UnregisterApp`.

The phone has no export that posts into an app's frame, so `send()` queues the
message (the last 50 per app) and the page drains it through its own resource,
like JPR and RoadPhone. Pages learn the phone from `?phone=apex_phone` and their
resource from the `cfx-nui-<resource>` host. `gg.phone.app.focus` has nothing to
do here. Scripts that open their own app call `OpenApp(id)` and close it with
`ClosePhone()`; the phone fires the local events `apex_phone:client:opened` and
`apex_phone:client:closed`.

The number is the client `GetPhoneNumber` and the server `GetNumber(citizenid)`,
with the citizen id from `gg.framework.GetIdentifier`. Notifications are the
client and server `SendNotification` in the table form `{ app, title, msg, icon,
duration }`; one without `app` lands under the phone's Settings app. Mail to a
source (by its citizen id), a number or a citizen id is the server `SendMail` with
`{ sender, email, subject, body, attachments }`. Only plain http(s) photo links up
to 512 characters go as attachments, at most 4, because one the phone refuses
refuses the whole mail. A mail address target answers false. Reference:
[Exports][apex-exports].

[apex-exports]: https://docs.apexscripts.xyz/apex-phone/exports

### qs-smartphone and qs-smartphone-pro

Quasar has two phones that take custom apps, with different APIs. One file,
`qs-smartphone`, speaks both; the `qs-smartphone-pro` folder runs it with
`GG_PHONE_EXPORT` set, the way yphone runs yseries.

- **Smartphone V3** (also sold as Smartphone 2026), resource `qs-smartphone`.
  The bridge registers from the client with `addCustomApp({ id, label, icon,
  iframe = { url } })`, plus `description`, `creator`, `sizeMb` and
  `appStoreOnly` (set for `defaultApp = false`), as Quasar's own example app does.
  `removeCustomApp(id)` takes it off, and the phone also drops it by itself when
  the resource that added it stops. `installed` asks `getCustomApps`.
  Notifications are a server export, `sendPhoneNotification(source, { appId,
  title, text })`; the client relays its own up. The number is the server
  `GetCurrentPhoneNumber(source)`, and the client asks for it over
  `gg.callback`. Mail is `SendMail(source, subject, message)`. A number target
  is matched to the online player holding it, because V3 has no lookup from a
  number. An address target answers false.
- **Smartphone PRO**, resource `qs-smartphone-pro`. Apps are registered from the
  client with `addCustomApp({ app, label, ui, image, ... })` and removed with
  `removeCustomApp(app)`. The bridge fills every field of Quasar's template
  (`creator`, `category`, `age`, `isGame`, `job`, `blockedJobs`, `timeout`,
  `extraDescription`), and sends the icon as both `image` and `icon`.
  Notifications are the client `SendTempNotification({ title, text, app,
  timeout })`, and the server sends its own down to the client. The number is
  the server `GetPhoneNumberFromIdentifier(identifier, false)`, tried with the
  framework's character identifier and then the player's first identifier. PRO
  documents no mail export, so `gg.phone.mail` answers false and warns once.
- **The classic Quasar phone** (`qs-smartphone` with `qs-base`) has no custom-app
  API. `add` then fails, and the reason it gives names this case.

PRO is also found installed in a folder still called `qs-smartphone`, and
classic shares that name with V3. So under `qs-smartphone` the bridge checks
which exports the resource answers rather than trusting the name. If
`getCustomApps` answers, it is V3. Otherwise, if `InPhone` answers, it is PRO
(or classic). The server makes the same call the first time a V3-only export
turns out not to exist.

Neither phone offers Lua a way to post into an app's frame. `SendNUIMessage`
only reaches the calling resource's own `ui_page`, never an iframe inside
another resource's NUI. Quasar's own V3 example app polls an NUI callback for
its updates instead. So `send()` keeps at most 50 updates per app, and the page
drains them through its own resource like on JPR, RoadPhone and CodeM. The ui
URL is iframed as given, with `?phone=qs-smartphone` or
`?phone=qs-smartphone-pro` appended. The page's own NUI callbacks
(`https://<resource>/<name>`) work from inside both phones. Neither phone
documents an input-focus export, so there is no `gg.phone.app.focus` here.

Quasar ships no lb-phone compatibility layer. None of its docs or manifests
`provide 'lb-phone'` or implement lb-phone's exports. The phones that do are
sd-phone and sky_phone, which also `provide 'qs-smartphone'`, and both are
detected before Quasar. References: [V3 developer API][qs-v3-api],
[V3 example app][qs-v3-example], [PRO custom apps][qs-pro-apps],
[PRO app template][qs-pro-template], [PRO notifications][qs-pro-notify],
[PRO number lookup][qs-pro-number].

[qs-v3-api]: https://www.quasar-store.com/docs/smartphone/developer-api
[qs-v3-example]: https://github.com/imnotquasar/phone-framebook
[qs-pro-apps]: https://github.com/imnotquasar/docs/blob/main/player-systems/smartphone-pro/create-custom-apps.md
[qs-pro-template]: https://github.com/quasar-store-organizations/custom-app-template
[qs-pro-notify]: https://github.com/imnotquasar/docs/blob/main/player-systems/smartphone-pro/user-guide/using-phone-notifications.md
[qs-pro-number]: https://github.com/imnotquasar/docs/blob/main/player-systems/smartphone-pro/exports-and-commands/server-side-exports/getphonenumberfromidentifier.md

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
A server can run the real lb-phone beside it and keep sd-phone only for sd-tablet
(sd-phone's lb-phone layer stands down while the real one runs). Then lb-phone is
the phone (`beside` in the manifest), and the tablet still goes through sd-phone.

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

## Tablet

Two resource names, one app API shaped like `gg.phone.app`. Detection order is
`sd-tablet`, then `lb-tablet`. Apps are added and messaged from the client; the
server gets the same table with every call answering `false`, and with no tablet
the client does too (`add` with a reason), so nothing is ever nil.

```lua
gg.tablet.resource              -- 'sd-tablet', 'lb-tablet', or nil with no tablet
gg.tablet.shared                -- the phone whose app list the tablet shows: 'sd-phone' on sd-tablet, else nil

gg.tablet.app.ready()           -- the resource that holds the app list is started
gg.tablet.app.add({
    identifier  = 'gg_casino',  -- `key` works too, as on gg.phone
    name        = 'Casino',
    description = '...',
    developer   = 'GG Studio',  -- lb-tablet only
    defaultApp  = true,
    size        = 2400,
    ui          = 'https://cfx-nui-gg_casino/web/phone/index.html',
    icon        = 'https://cfx-nui-gg_casino/web/phone/icon.png',
    devices     = { 'tablet' }, -- sd-tablet only: 'phone', 'tablet' or both; tablet when left out
})
gg.tablet.app.send('gg_casino', 'balance', { total = 500 })
gg.tablet.app.remove('gg_casino')
gg.tablet.app.installed('gg_casino')  -- added by this resource
gg.tablet.app.drain('gg_casino')      -- always {}: both tablets push into the app
```

Both bridges add every app again when the resource holding the list restarts
(lb-tablet, or sd-phone under sd-tablet). There is no `gg.tablet.app.focus`:
neither tablet documents an input-focus export (see each below).

Nothing here has been run in game. What each part rests on:

### lb-tablet

**Checked against LB's docs** ([client exports][lbt-client],
[custom apps][lbt-apps]) **and its own [app templates][lbt-templates]:**

- `AddCustomApp(app)` answers `success, reason`, the reason
  `"APP_ALREADY_EXISTS"`. The bridge passes `identifier`, `resource` (the importing
  resource), `name`, `description`, `developer`, `defaultApp`, `removable`,
  `size`, `price`, `images`, `ui`, `icon` and the `onInstall`, `onUninstall`,
  `onOpen` and `onClose` hooks. An app that already exists is removed and added
  again.
- `RemoveCustomApp(identifier)` answers `success, reason` (`"INVALID_APP"`,
  `"WRONG_RESOURCE"`).
- `SendCustomAppMessage(identifier, event, data)` takes the event on its own,
  where lb-phone takes one message table. `send(id, action, data)` passes the
  action as the event.
- The page gets its globals once the tablet posts `componentsLoaded`:
  `resourceName`, `appName`, `settings`, `fetchNui(event, data, scriptName)`,
  `onNuiEvent(event, cb)` (the templates call it `useNuiEvent`),
  `onSettingsChange`, `setPopUp`, `setContextMenu`, `setGallery`,
  `setIndicatorVisible` and the rest. A page subscribes to each event by name.
- The templates add their app again on lb-tablet's `onResourceStart`, as the
  bridge does.
- The screen is landscape. LB gives no pixel size; the templates' browser frame
  is 4:3 (`aspect-ratio: 4/3`, scaled from a 1920-wide screen).

**Assumed:**

- A full `https://cfx-nui-<resource>/...` ui and icon are used as given, so the
  `?tablet=lb-tablet` the bridge appends reaches the page. The templates pass full
  http urls for both while developing, and `"ui/index.html"` (resource-relative,
  without the resource name lb-phone wants) once built.
- How a message gets into the frame is not documented: a posted `{ action, data }`
  as lb-phone does, or a direct call of the `onNuiEvent` callback. A page should
  take either without acting twice; gg_casino's `web/phone/host.js` does.
- No input-focus export is documented, as on lb-phone, which handles its own.

[lbt-client]: https://docs.lbscripts.com/tablet/script-integration/client-exports/
[lbt-apps]: https://docs.lbscripts.com/tablet/script-integration/custom-apps/
[lbt-templates]: https://github.com/lbphone/lb-tablet-app-templates

### sd-tablet

**Checked against the source** ([sd-tablet][sdt], [sd-phone][sdp]) **and
[sd-phone's custom app docs][sdp-apps]:**

- sd-tablet has no apps of its own. It runs sd-phone's interface on a tablet
  screen (sd-phone is a hard dependency) and shows sd-phone's custom apps, each
  filtered by its `devices` list: `'phone'`, `'tablet'` or both, case-insensitive,
  every device when left out (`customAppsStore.ts`, `forThisDevice`).
- So the bridge adds the app to sd-phone with sd-phone's own client exports,
  `addCustomApp(app)` and `removeCustomApp(id)` (`ok, err`) and
  `sendCustomAppMessage(id, message)`. Not through its lb-phone layer, which
  `sd_phone_lbcompat false` or a leftover lb-phone folder switches off.
  Adding the same identifier again from the same resource replaces it.
- A message goes to sd-phone's page as `customApps:message`. sd-phone mirrors
  every push to sd-tablet while the tablet is open (`client/companion.lua`,
  sd-tablet `client/mirror.lua`), and the app frame posts the message table into
  the iframe as it is (`CustomAppFrame.tsx`), held until the SDK it injects has
  loaded and `componentsLoaded` was posted. `send()` sends `{ action, data }`, the
  shape the lb-phone bridge sends.
- A `ui` is `"<resource>/path"` or a full http(s) url, used as given
  (`customUrl.ts`).
- Text fields are wired by that SDK (`sd-phone:typing`, which the tablet answers
  itself), so there is nothing for a focus call to do.
- The screen is 1366 x 1024, landscape (sd-tablet `web/device.ts`), and the app
  frame fills it. sd-phone's own phone is 440 x 956.
- sd-phone keeps its app list in its client, so a restart of sd-phone forgets
  every app.
- sd-phone declares `provide 'lb-tablet'`, but its lb-tablet layer answers only
  dispatch and MDT exports, no apps, and `provide` does not make
  `GetResourceState` say lb-tablet is started (sd-phone's docs). sd-tablet is
  checked first all the same.

**One app list for two screens.** When `gg.tablet.shared == gg.phone.resource`
(sd-tablet beside sd-phone), adding the app to the phone through `gg.phone` gives
it no `devices`, so it shows on the tablet as well, and adding it through both
leaves whichever came last. A script that lets the owner choose registers once,
through `gg.tablet`, with `devices` naming the screens it wants, and skips
`gg.phone.app.add` for that app. `send` then reaches whichever screen has it open.

**Assumed:** the iframe's parent is `https://cfx-nui-sd-tablet` (sd-tablet's own
`ui_page`). The same url serves both screens, so `?tablet=sd-tablet` is only added
when the tablet is the app's one screen; a page on both reads
`location.ancestorOrigins` (or `document.referrer`) to tell them apart.

[sdt]: https://github.com/Samuels-Development/sd-tablet
[sdp]: https://github.com/Samuels-Development/sd-phone
[sdp-apps]: https://docs.samueldev.shop/resources/phone/custom-apps

### What the app page sees

| | lb-tablet | sd-tablet |
|---|---|---|
| Knows it is there by | `?tablet=lb-tablet` | `?tablet=sd-tablet` on a tablet-only app, else a `cfx-nui-sd-tablet` parent |
| Gets a message as | `onNuiEvent(action, cb)` after `componentsLoaded` | a window `message` of `{ action, data }`, as on lb-phone |
| Answers to | its own `https://<resource>/<callback>` | the same |
| Screen | landscape, 4:3 | 1366 x 1024, landscape |

---

## Door locks

Optional, like phone. ox_doorlock is the only one so far. With none running every
call answers `nil` or `false` (the make and change calls `false, why`) and nothing
is printed; `gg.doorlock.resource` is `nil`, which is how a script tells.

A door is its id or its name, on either side. A name that matches no door and
reads as a number is tried as an id; `getDoorByName` never does that.

```lua
-- Either side
gg.doorlock.resource                -- the resolved resource, nil with no door lock
gg.doorlock.ready()                 -- started, and on the server its doors are loaded
gg.doorlock.getDoor('shop back')    -- { id, name, locked, coords, maxDistance, ... } or nil
gg.doorlock.getDoorByName('shop back')
gg.doorlock.isLocked(12)            -- true / false, nil for no such door
gg.doorlock.setState('shop back', true)    -- setLocked with true / 1 / 'locked'

-- Server
gg.doorlock.setLocked('shop back', true)   -- unconditional; true if the door exists
gg.doorlock.getDoors()                     -- every door, same shape as getDoor
gg.doorlock.onChange(function(doorId, locked, source, usedItem) end)

gg.doorlock.createDoor({                   -- id, 'live' | 'saved', or false, why[, id already there]
    name = 'myshop:back',                  -- unique, up to 50 characters
    model = 'v_ilev_gtdoor', coords = vec3(1.0, 2.0, 3.0), heading = 90.0,
    -- or a double door: doors = { { model, coords, heading }, { model, coords, heading } }
    locked = true,                         -- default true
    groups = { police = 0 },               -- { job = least grade }; nil: only admins
    maxDistance = 2.0, autolock = 10,      -- and items, characters, lockpick, hideUi, auto, doorRate,
})                                         -- passcode, lockSound, unlockSound
gg.doorlock.editDoor('myshop:back', { groups = { police = 2 }, locked = false })  -- true, 'live' | 'saved'
gg.doorlock.saved('myshop:back')           -- the door as saved: createDoor's keys + id, live; nil
gg.doorlock.saved()                        -- every saved door
gg.doorlock.shapeOf(def)                   -- createDoor's def as saved() would hand it back; nothing written
gg.doorlock.features()                     -- { create = 'live' | 'saved' | nil, edit, reload }
gg.doorlock.loadSaved()                    -- true, why / false, why (below)

-- Client
gg.doorlock.setLocked('shop back', false)  -- the player's own request (below)
gg.doorlock.closest()                      -- { id, name, locked, coords, entity, distance, maxDistance, reachable }
gg.doorlock.useClosest()                   -- toggles it, as its E key would
gg.doorlock.pickClosest()                  -- ox_doorlock's own lockpick skill check
gg.doorlock.idOf(entity)                   -- the door id an entity belongs to
```

**From the server, `setLocked` is not checked.** It is the script's own decision.
From the client it is the player asking: it sends ox_doorlock's own
`ox_doorlock:setState`, so their groups, items and passcode are checked there
and ox_doorlock tells them if they are refused. `true` on the client means it
was asked, not that it was allowed; watch `onChange` on the server for the
outcome.

**Doors are read from the database after ox_doorlock starts.** Until then every
lookup is empty and `setLocked` answers `false`. A script that locks a door at
start waits on `ready()`. ox_doorlock fires `ox_doorlock:loaded` once; a script
that starts after that is ready as soon as one door exists.

**Making a door.** ox_doorlock 1.21 (the CommunityOx line Qbox ships) has no
export that makes or removes one: its `/doorlock` menu writes a row to its
`ox_doorlock` table and adds it to the doors it holds, and only an admin's menu
may. So `createDoor` writes the same row the menu writes (its `encodeData`
shape: models as signed hashes, coords `{ x, y, z }`, a double door's middle as
its coords) and answers `'saved'`: ox_doorlock holds it from its next start.
`loadSaved()` makes that now by stopping and starting ox_doorlock, and only while
nobody is on the server and no started resource names ox_doorlock as a
dependency (stopping it would stop those); otherwise, or when the server will
not let a script stop it, it answers `false, why` and the doors come at the
next server restart. A script makes its doors at boot and
calls `loadSaved()` once after. On an ox_doorlock with a `createDoor` export (the
Overextended line, 1.22.1) that is used instead and the answer is `'live'`.
Writing needs MySQL in the resource that asks: `@oxmysql/lib/MySQL.lua` in its
`server_scripts`. A name already saved is never made twice (`false, 'exists', id`).

**Changing a door.** `editDoor` takes any key `createDoor` takes; `false` clears
one (`groups = false`: no job opens it). A door ox_doorlock holds takes it at
once through its `editDoor` export, which also saves it. Its model or place, or a
door saved but not held yet, is changed in its row and taken at the next start
(`'saved'`, and `loadSaved()` as above).

**The server's `getDoor` carries the access lists** (`groups`, `items`,
`characters`). The client's comes from this resource's own server over
`gg.callback`, because ox_doorlock has no client lookup by id or name, and
carries only `id`, `name`, `locked`, `coords` and `maxDistance`. `saved` reads the
row itself, so it has everything `createDoor` took, and `live` says whether
ox_doorlock holds it now.

`onChange` listeners added while no door lock runs are kept, and hear changes
once one starts. `source` is `nil` for a change made by the server or by
autolock; `usedItem` is the item that opened it, when one did. Server only:
ox_doorlock raises the event only there.

`closest()` is whatever ox_doorlock holds as the closest door. It keeps one until
no door is within 20 m, so it can be a door past its interact distance;
`reachable` says whether it is usable from here. `useClosest` and `pickClosest`
act only on a reachable door, which ox_doorlock's own exports do not check.
`pickClosest` waits for the skill check and returns `true` once the attempt was
made; a double door has no single entity and cannot be picked.

### ox_doorlock

Every call is from ox_doorlock's [documentation][ox-door-docs] or its
[source][ox-door-src]: server `getDoor`, `getDoorFromName`, `getAllDoors`,
`setDoorState`, `editDoor` and the `ox_doorlock:stateChanged` and
`ox_doorlock:loaded` events; client `getClosestDoor`, `useClosestDoor`,
`pickClosestDoor` and `getDoorIdFromEntity`; its `ox_doorlock` table (`id`,
`name` varchar(50), `data` JSON). States are `0` unlocked and `1` locked. Calls
are guarded like the target ones, and a stopped ox_doorlock is not called at
all. Checked against 1.21.0, the version the Qbox recipe ships. Who a door's
`groups` let in is ox_doorlock's own framework file: qbx_core, es_extended,
ox_core and nd_core. It has none for qb-core, so there groups open nothing and
only a door's ace (`doorlock.<name>`) does.

`createDoor` is used when the export is there (Overextended 1.22.1); its
`removeDoor` and the `registerHook` authorization hooks (1.22+) are not mapped.

[ox-door-docs]: https://overextended.dev/docs/ox_doorlock
[ox-door-src]: https://github.com/communityox/ox_doorlock

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
HUD usually still wants the minimap.

**A HUD with no bridge gets an event.** With no HUD below running, `hide` and
`show` send the client event in Generic Settings > General > Custom HUD Event
(`general.hud_event`, default `hud:client:ToggleHud`) with `false` to hide and
`true` to show, so a server's own HUD only needs a handler for it. Empty sends
nothing, and with nothing listening the event does nothing. It cannot say whether
the HUD is showing, so `show` always brings it back. `native` still works.

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
anything, unless the server gives it a handler for the Custom HUD Event.
cd_carhud only toggles, with no state. uz_PureHud documents an export
its source does not have. izzy-hudv7 and tgiann's Modern HUD have no confirmed
folder name. Several more appear in other libraries' bridges with no
documentation behind them, and wait for some.

---

## Adding a provider

1. Make `bridge/<category>/<resource name>/client.lua` — the folder name must be
   the resource name exactly, because detection is `GetResourceState(folder)`.
2. Implement the same functions the other providers in that folder implement.
   An inventory also defines `getItems` and `setMetadata`, plus `getSlot`,
   `getCount`, `canCarryWeight` and `registerUsable` where it has exports for
   them; `_common` builds the rest of the API from those.
3. Add the name to `manifest.lua`, above `ox_*` and `qb-*`.

A resource that declares `provides { 'ox_target' }` still needs its own entry,
above the name it provides: whether `GetResourceState('ox_target')` then reports
started depends on the FiveM build, so either nothing matches it or the wrong
bridge does. `sleepless_interact` and `lation_interact` are the
examples — their bridges run the ox_target one rather than keeping a copy.
`lation_interact` hands it `GG_TARGET_EXPORT`, so every call goes to
`exports.lation_interact` rather than to the `ox_target` alias, which a server
still running the real ox_target would answer instead.
