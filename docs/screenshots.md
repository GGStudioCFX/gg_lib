# Vehicle screenshots

`gg.screenshot.vehicles(entries, options)` photographs vehicles, turns each picture into a WebP and waits for storage to finish before returning. gg_lib takes the picture itself, from the game frame in its own NUI, so `screenshot-basic` and `screencapture` are not needed. The upload and local save logic run on the gg_lib server. Screenshots can be saved in a resource's web folder or uploaded to FiveManage.

## Green screen cutout

**Green Screen Cutout** in `/ggsettings` > Shared Settings > Screenshots is on by default. On, the vehicle comes out on a see-through background, cropped to the vehicle. Off, the picture is the whole frame the camera sees at the **Capture Spot**, so pick a spot with a view worth keeping. A call can choose for itself with `options.greenscreen = true` or `false`.

The cutout takes the same moment twice, once in front of a green backdrop and once in front of a magenta one of the same brightness, and works out how see-through every pixel is from the difference between the two (triangulation matting). Nothing is keyed by colour, so green paint stays, glass comes out partly see-through, and soft edges keep their blend. Each picture waits until the game frame actually shows its backdrop, so a slow frame never gives a half-changed picture. The HUD is hidden while the camera runs.

## Storage

In `/ggsettings` > Shared Settings > Screenshots, set **Image Storage** to Automatic, Local web folder, or FiveManage. Automatic uses FiveManage when a key is present and local storage otherwise. Set the **FiveManage API Key** in the same group. The key is server-only and is never sent back to a client. Existing installations with a key keep their automatic FiveManage behavior.

```lua
local ok, result = gg.screenshot.vehicles({
    { id = "taxi", vehicle = "taxi", mods = vehicleProperties },
}, {
    target = GetCurrentResourceName(),
    folder = "vehicles",
})

if ok and result.stored.taxi then
    local location = result.stored.taxi
    -- Save location alongside the vehicle's other settings.
end
```

`result.stored[id]` is the confirmed storage location. It is an HTTPS URL after a successful FiveManage upload, or a relative path such as `vehicles/taxi.webp` for local storage. Keep the full returned value in the product's image record: a later change to the local screenshot folder should not redirect earlier captures. `result.captured` contains only images whose storage completed. `result.failed` contains capture, processing, or storage failures. Each picture goes to the server in one latent event, so a large image never stalls the connection; the limit is 4 MB of WebP. If a FiveManage request fails, gg_lib logs the failure and saves locally; the returned location identifies that local file.

A call may override the generic choice with `options.storage = "local"` or `"fivemanage"`. The API key remains server-side. `options.folder` is a safe relative folder under the target resource's `web/dist`; an absolute filesystem path is rejected. The target resource must serve local files through its manifest. Render HTTPS URLs directly and resolve relative paths against that product's web root.

After saving a new local screenshot, restart the target resource to refresh the files available to its NUI. Taxi's Image editor shows this reminder after a local capture. FiveManage images use their returned URL and do not need a Taxi resource restart to be fetched.

Local screenshots are files inside the target resource. Back up its configured image folder before replacing the resource during an update, then restore that folder. Saved relative paths still point to those files after a folder setting change; a FiveManage URL is unaffected by resource file replacement.

## Database

`options.storage = "database"` keeps each picture in gg_lib's [image store](images.md) instead of a file. It is saved under the target resource as the owner, named by the entry's `id`. The **Image Storage** setting does not change this: only a call that asks for it uses the database.

```lua
local ok, result = gg.screenshot.vehicles(entries, {
    target = GetCurrentResourceName(),
    storage = "database",
    maxWidth = 800,
})

if ok and result.stored.taxi then
    local location = result.stored.taxi -- "db:taxi"
end
```

`result.stored[id]` is `"db:" .. id`. Players fetch the picture with `gg.images.fetch(owner, { id })`, and Script Studio shows a `db:` value in an image setting by itself. There is no file and no resource restart, and a new capture of the same id is a new version of the same picture. `options.folder` is not used.

`options.maxWidth` and `options.maxHeight` scale each picture down before it is turned into a WebP, keeping its shape, and work with every kind of storage. A picture already within the limits is left as it is. A vehicle list stays small this way: at 800 wide, a cut-out is about 35 KB of text.
