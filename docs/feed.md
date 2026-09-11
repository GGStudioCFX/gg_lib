# Home feed

Publishing the home page, the shop and the update logs.

[← back to the README](../README.md)

---

## Home page

The first tab in Script Studio is a home page: whatever is on right now, a
shop of the GG scripts this server is *not* already running, and a rail of
every installed script's releases. Its content comes from the `feed/` folder
of this repo, fetched from the main branch every half hour, so a sale, a drop
or a release is a push to a file and nothing else -- every server running
gg_lib picks it up on its next refresh, and the Home tab shows a badge until
it has been looked at.

Four kinds of file, because they change for different reasons:

| File | What it holds | Who edits it |
| --- | --- | --- |
| `feed/home.json` | the ticker, the promos, the links | you, when something is on |
| `feed/products.json` | the catalogue behind the shop | generated from the store |
| `feed/updates/<resource>.json` | one release log per script | per release |
| `feed/bridges.json` | every resource gg_lib bridges to, by category | generated, never by hand |

Splitting them means a marketing edit and a release edit never touch the same
file, and a botched promo cannot take the changelogs down with it. Update logs
are fetched **only for scripts this server is actually running**, so the
request count is what is installed and no more.

The copies that shipped with your version are shown until the repo answers,
and kept if it stops answering. A file that answers with something that is not
the file asked for -- a list, or a table carrying none of the keys that file is
read for -- is refused rather than allowed to blank a page that was fine.
A server that cannot reach GitHub, or a fork that publishes its own, can
point every fetch elsewhere with `set gg_home_feed "https://..."` in
server.cfg -- it names the folder, exactly as the default does.

### feed/home.json

A promo is one of `sale`, `giveaway`, `announcement` or `release`. Whatever is
at the top of the page is the newest one still running, or the one named in
`featured` if that is still running: an ended sale stops being the headline on
its own, rather than the day somebody remembers to edit the file. With nothing
on, there is no headline at all, which is most days.

A `release` is a script version going out. It names the script in `resource`
and the version in `version`: on a server already running that script the
button opens the script's own page in the studio, and on one that is not it
goes to `url` -- the store page, usually. Releases and announcements that are
not the headline sit in the news rail.

An `image` is a picture beside the copy; a `video` -- an mp4 address or a
YouTube link -- plays there instead. `url` is where the button goes and `cta`
is what it says; the game asks the player before opening anything. Dates are
unix seconds, as `os.time()` gives them; something you would type
(`"2026-09-01"`) is taken too, but it is midnight, and every time on these
pages is drawn as a distance from now.

```json
{
    "publishedAt": 1787767200,
    "version": "1.0.2",
    "ticker": ["gg_taxijob 2.0 is out", "25% off everything until Sunday -- SUMMER25"],
    "links": { "discord": "https://discord.gg/...", "store": "https://..." },
    "featured": "taxi-2-0",
    "promos": [
        {
            "id": "taxi-2-0",
            "kind": "release",
            "title": "gg_taxijob 2.0 is out",
            "body": "The whole job rebuilt on Script Studio.",
            "version": "2.0.0",
            "resource": "gg_taxijob",
            "at": 1787866200,
            "image": "https://.../taxi.png",
            "url": "https://www.ggstudio.store/scripts/taxi-job",
            "cta": "Open the taxi job"
        },
        {
            "id": "summer-sale",
            "kind": "sale",
            "title": "End of summer sale",
            "body": "Every GG script for less until Sunday night.",
            "discount": "25% off",
            "code": "SUMMER25",
            "at": 1787673600,
            "endsAt": 1790812740,
            "image": "https://.../summer.jpg",
            "url": "https://...",
            "cta": "Visit the store"
        }
    ]
}
```

### feed/products.json

The shop. Every row is matched against what this server is running by its
`"resource"` name, and anything already installed is left out -- a catalogue
that lists what somebody has already bought is a list of their own receipts.
That makes `resource` the load-bearing field; the rest is presentation.

```json
{
    "publishedAt": 1787767200,
    "products": [
        {
            "id": "gg_police",
            "resource": "gg_police",
            "name": "gg_police",
            "blurb": "Duty, dispatch, evidence and a garage.",
            "price": "$24.99",
            "status": "SOON",
            "icon": "fa-shield-halved",
            "image": "https://.../police.jpg",
            "url": "https://www.ggstudio.store/scripts/police"
        }
    ]
}
```

### feed/updates/&lt;resource&gt;.json

> **gg_lib itself has no file here.** It is open source, so its log is read
> straight from its own [releases page](https://github.com/GGStudioCFX/gg_lib/releases)
> -- tag, date and the bullet points of the release notes. Cutting a release
> IS publishing the changelog. Every other script has a private repository,
> so a published file is the only way to tell a customer a newer version
> exists.

One file per script, named for the resource. Every script also carries its own
log declared in its schema, and the two are merged: the script's copy is what
a customer with no internet sees, and the feed adds the versions they have not
got yet, which is how a private-repo script can still tell somebody a newer
version is out and what is in it.

```json
{
    "label": "gg_taxijob",
    "resource": "gg_taxijob",
    "latest": "2.0.0",
    "url": "https://discord.gg/...",
    "updates": [
        {
            "version": "2.0.0",
            "at": 1787866200,
            "kind": "major",
            "important": true,
            "title": "The rebuild",
            "changes": ["...", "..."]
        }
    ]
}
```

`kind` is how big the release was -- `major`, `feature` or `fix`, defaulting to
`feature` -- and `important` is whether it is worth reading before updating.
They are separate questions: a one-line fix can be the one that unbreaks a
server, and a big release can be all features nobody will turn on.

The same shape is what a script declares for itself:

```lua
settings.script({
    label   = "Advanced Taxi Job",
    updates = {
        {
            version   = "2.0.0",
            at        = 1787866200,   -- os.time() when it was pushed
            kind      = "major",      -- major | feature | fix
            important = true,
            title     = "The rebuild",
            changes   = { "...", "..." },
        },
    },
})
```

It is its own tab at the bottom of the script's rail and opens as a page of its
own: a release timeline, the version running as the filled node, and anything
newer above it and marked. The tab lights while there is something unread and
goes quiet once the page has been opened -- there is nothing to dismiss, and
the next release lights it again on its own.

The one button on the page goes and gets the update. Where it goes depends on
what the script is: everything sold is a granted asset, so the button searches
the CFX portal for that resource name, which means a script that ships tomorrow
has a working download without anything being configured. gg_lib is not sold,
so it is not on the portal at all -- its button goes to the latest release on
the repo.

`web/src/lib/homeCases.ts` has a worked example of every case the page can be
asked to draw, including a server that already owns everything.

### feed/bridges.json

Every framework, inventory, target, dispatch, fuel, keys and phone resource
gg_lib bridges to, grouped by category. Script Studio does not read it; it is
there for the website, which fetches it straight off the repo:

```
https://raw.githubusercontent.com/GGStudioCFX/gg_lib/main/feed/bridges.json
```

GitHub serves that with open CORS, so a page can fetch it from the browser
with nothing in between.

```json
{
    "library": "gg_lib",
    "source": "bridge/manifest.lua",
    "total": 69,
    "categories": [
        {
            "id": "inventory",
            "label": "Inventories",
            "required": true,
            "count": 13,
            "resources": ["ak47_inventory", "codem-inventory", "..."]
        }
    ]
}
```

Resources are resource names, sorted. `required` marks the categories a
server has to have one of. Nothing in the file changes unless the list does --
there is no timestamp -- so a diff on it is always a real change.

It is written from `bridge/manifest.lua` by `node tools/bridges.mjs`, and the
pre-push hook refuses a push where the two disagree. A name is only written out
if a bridge actually handles it, so the list cannot claim support that is not
there.
