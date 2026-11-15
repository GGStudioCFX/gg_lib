# Images

Keeping pictures in the database instead of image files.

[← back to the README](../README.md)

---

A script can keep its pictures (vehicle photos, item icons) as text in the
`gg_lib_images` table instead of WebP files in its `web/dist` folder. A saved
picture is there straight away: nothing to restart, nothing added to the files a
player downloads when they join, and nothing to back up before an update. Players
fetch a picture when a screen needs it.

Each picture belongs to an **owner**, the resource it is for, and has a **name**
that is unique within that owner. Every save of the same name raises its
**version** by one, starting at 1, so a screen can tell an old copy from a new one.

The table is made when gg_lib starts. It needs oxmysql, like the rest of gg_lib's
storage.

## Saving and reading (server)

```lua
local version, reason = gg.images.save(GetCurrentResourceName(), "v001", base64, "image/webp")

if not version then
    print("not saved: " .. reason)
end
```

| Call | Returns |
| --- | --- |
| `gg.images.save(owner, name, base64, mime)` | The new version, or `nil` and a reason |
| `gg.images.delete(owner, name)` | `true` when a picture was removed |
| `gg.images.versions(owner)` | `{ [name] = version }` for every picture the owner has |
| `gg.images.get(owner, name)` | A `data:` URL and its version, or `nil` |
| `gg.images.onStored(handler)` | Runs `handler(owner, name, version)` after every save and delete |

The same calls are exports for code outside the gg_lib import:
`exports.gg_lib:ggImageSave`, `ggImageDelete`, `ggImageVersions` and `ggImageGet`.
They wait for the database, so call them from a thread or an event handler.

- `base64` may be plain base64 or a whole `data:image/webp;base64,...` URL. Without a
  `mime`, the type comes from the URL, otherwise `image/webp`.
- One picture can be up to 4 MB of base64 text (about 3 MB of image).
- `versions` is read from the database once per owner and kept in memory after
  that, so it is cheap to call often.
- After every save and delete, gg_lib fires the server event
  `gg_lib:image:stored` with `owner, name, version`. On a delete the version is
  `nil`. A delete fires the event only when a picture was actually removed.

## Fetching (client)

```lua
CreateThread(function()
    local images = gg.images.fetch(GetCurrentResourceName(), { "v001", "v002" })

    for name, image in pairs(images) do
        -- image.data is "data:image/webp;base64,...", ready for an <img> src
        -- image.version is the version it was saved as
    end
end)
```

`gg.images.fetch(owner, names, timeoutMs)` waits for the pictures, so run it in a
thread. `names` is a list or one name. It returns `{ [name] = { data, version } }`.
A name with no picture is left out. If the fetch fell short (it timed out or the
server refused it), the reason comes back as a second value, alongside whatever
did arrive. `timeoutMs` defaults to 30 seconds. Any player can fetch any owner's
pictures.

The pictures come over a latent event, a few at a time and at about 1 MB a
second for each player. A large list doesn't stall the player's connection or
anyone else's. A long list is split into requests of 60 names. If the server asks
the player to slow down, the fetch waits and tries again.

To show the same picture again without fetching it, keep the `data` in your NUI
and compare versions. Fetch again when `gg.images.versions` (sent from your
server) or `gg_lib:image:stored` says a version changed.

## Limits

| | |
| --- | --- |
| One picture | 4 MB of base64 text |
| Names in one request | 60 (the client splits longer lists) |
| Pictures in one event | 4, or 192 KB |
| Speed | About 1 MB a second for each player, 2 events on the way at once |
| Requests a player can have waiting | 4 |
| Requests a player can make | 20 every 10 seconds |
| Players answered at the same time | 16 (the rest wait their turn) |
| Server memory cache | 32 MB of the most recently read pictures |

## Names

An owner is up to 64 letters, digits, `-`, `_` or `.`. That fits a resource name.
A name is up to 128 characters of any text without control characters, and with no
space at either end. A number is used as its text (`7` is `"7"`). Names are
case-sensitive: `V001` and `v001` are two pictures.

## Script Studio

A setting of type `image` that holds `db:<name>` shows that picture from the store.
The owner is the script whose settings are open. Script Studio fetches it once per
session and fetches it again after the field's capture action runs, so a new
capture shows at once. Plain paths and URLs, `image_base` and `image_root` work as
before.

## Captures

`gg.screenshot.vehicles` saves its pictures here with `storage = "database"`; see
[Screenshots](screenshots.md#database).
