# Vehicle screenshots

`gg.screenshot.vehicles(entries, options)` captures vehicle images with `screenshot-basic`, converts them to WebP, and waits for storage to finish before returning. The upload and local save logic run on the gg_lib server. Screenshots can be saved in a resource's web folder or uploaded to FiveManage.

In `/ggsettings` > Generic Settings > Screenshots, set **Image Storage** to Automatic, Local web folder, or FiveManage. Automatic uses FiveManage when a key is present and local storage otherwise. Set the **FiveManage API Key** in the same group. The key is server-only and is never sent back to a client. Existing installations with a key keep their automatic FiveManage behavior.

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

`result.stored[id]` is the confirmed storage location. It is an HTTPS URL after a successful FiveManage upload, or a relative path such as `vehicles/taxi.webp` for local storage. Keep the full returned value in the product's image record: a later change to the local screenshot folder should not redirect earlier captures. `result.captured` contains only images whose storage completed. `result.failed` contains capture, processing, or storage failures. If a FiveManage request fails, gg_lib logs the failure and saves locally; the returned location identifies that local file.

A call may override the generic choice with `options.storage = "local"` or `"fivemanage"`. The API key remains server-side. `options.folder` is a safe relative folder under the target resource's `web/dist`; an absolute filesystem path is rejected. The target resource must serve local files through its manifest. Render HTTPS URLs directly and resolve relative paths against that product's web root.

After saving a new local screenshot, restart the target resource to refresh the files available to its NUI. Taxi's Image editor shows this reminder after a local capture. FiveManage images use their returned URL and do not need a Taxi resource restart to be fetched.

Local screenshots are files inside the target resource. Back up its configured image folder before replacing the resource during an update, then restore that folder. Saved relative paths still point to those files after a folder setting change; a FiveManage URL is unaffected by resource file replacement.
