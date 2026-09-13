# Script Studio

Using the menu.

[← back to the README](../README.md)

---

## Using Script Studio

Type **`/ggsettings`** in game. It is the only command gg_lib registers.

| Page         | What it holds                                                    |
| ------------ | ---------------------------------------------------------------- |
| Your scripts | Every setting, grouped, with search                              |
| Generic      | Settings shared by all GG scripts — color, currency, daily reset |
| Bridges      | What gg_lib connected to, and whether it worked                  |
| Admins       | Who has access                                                   |
| Logs         | Who changed what, and when                                       |

Changes are staged until you press **Save**, so you can adjust several things
and apply them together. Anything needing a restart is labelled.

### Visual editors

A script can provide a dedicated design page using `settings.editor`. Its page
opens from the script's sidebar, separately from the scrolling settings and
Update Log. Controls use the same drafts, Save, Discard, reset, permissions and
server validation as ordinary settings. Unlisted settings remain in their
normal groups; search still finds fields managed by an editor.

Declare settings with `settings.define` first, then reference their paths:

```lua
settings.editor('appearance', {
    label = 'Design Editor',
    icon = 'fa-palette',
    preview = 'web/editor.html',
    sections = {
        { id = 'design', label = 'Design', fields = {
            { path = 'appearance.style', view = 'gallery', thumbnailPrefix = 'web/previews/style-' },
            { path = 'appearance.corners', view = 'cards' },
            'appearance.color',
        } },
    },
})
```

`preview` and gallery thumbnails are relative to the declaring resource and must
be included in its manifest `files`. Gallery images use `<prefix><enum-value>.svg`
and appear together in the scrolling controls pane; the preview stays fixed.
Use galleries for small visual catalogs of up to roughly 50 designs. Empty
sections are omitted when none of their fields apply. `cards` renders enum options inline. A field may
provide `icons = { value = 'fa-icon' }` or `when = { path = 'other.path', equals = value }`.
Both `when` and the setting's `depends` respond to unsaved draft changes. The
preview receives public settings only; server-only values are excluded.

The host opens `preview?studio=1&host=<host-origin>` in a visual-only iframe. The
preview must send `{ event: 'gg:editor:ready', version: 1 }` to its parent using
the supplied host origin. It then receives:

```js
{ event: 'gg:editor:preview', version: 1,
  values: { 'appearance.style': 'circle' },
  state: 'ready', scale: 2,
  context: { accent: '#c694ff', applyToAll: true } }
```

Validate `event.source === window.parent` and the supplied host origin before
handling messages. States are `ready`, `idle`, `press` and `hold`.
`scale` relates the preview viewport to the editor's viewport, so a renderer can
keep its existing vh sizes. Changes must render sample actions only: an embedded
preview must never send gameplay NUI callbacks or save settings itself. The host
keeps controls usable if the preview fails to load.

For local development, the Vite browser accepts `?scriptPreview=<localhost JSON URL>`.
The schema JSON can include `previewBase: 'http://127.0.0.1:4178/resource/'` to
resolve its resource assets. This override is restricted to the development
browser; native resource URLs always use `https://cfx-nui-<resource>/`.

Each script also has a **Factory Reset** at the bottom of its page, which puts
everything back to how it shipped.

### Import & Export

Above Factory Reset, every script's page can take its settings out as one JSON
file and bring them back in. Pick a group and a kind (positions, colours,
numbers, text, toggles, lists) to export part of a page, or leave both on
"every" for the lot.

**Export** copies the file to the clipboard, or saves it on the server as
`gg_lib/transfer/<script>.json` (next to gg_lib, not on your PC). Beside each
value the file carries a `$`-guide — label, help, type, allowed options, range,
list columns, which column identifies a row — so an AI or a person editing it
knows what each setting takes. Server-only values are never exported.

**Import** takes the file back, pasted or loaded from that same path. Chat
windows' code fences, comments and trailing commas are tolerated. **Check**
first looks at the shape — a list that is not a list, a row that lost the key
the script files it under, two rows with the same key — and then runs every
value through the script's own validation on the server without writing
anything, listing what would be refused ("Ped Position is missing its z";
"is not one of the allowed options: "warn", "block""). **Copy problems** puts
that list in the clipboard, ready to paste back to whoever made the file. When
it is clean, **Apply to page** puts the differing values on the page as unsaved
changes — highlighted like hand edits, one Undo away — and the usual **Save**
writes them, validating again. With problems present, **Apply the N that
passed** takes the rest, which is how a file that adds a rider class and then
refers to it goes in: the class first, then the reference.

The result also says what was ignored (settings this script does not know),
skipped (settings hidden right now), adjusted on the way in (rounded,
normalised, or a shipped row put back), or left alone (not in the file). A file
exported from another script is refused; one from another version is noted.

Only the `value` fields are read on import. Keys starting with `$` are ignored,
so a file with the guide stripped, or a bare `{ "path": value }` map, works too.

### Server-only settings

A setting marked **Server Only** — an upload key, an API token — is stored on
the server and never sent anywhere else. The page shows that a value is set,
not what it is, so you can replace it or clear it but not read it back. It is
left out of everything that goes to a player: the settings the client receives,
the live update after a save, and the old and new values in the log.

A script declares one by adding `server_only = true` to the setting:

```lua
settings.define("upload.api_key", {
    group       = "uploads",
    label       = "Upload API Key",
    type        = "string",
    server_only = true,
    default     = "",
})
```

Read it with `settings.read` on the **server** only — a client reading one gets
`nil`, because it was never given a value to hold. Leave `default` empty: config
files are shared scripts, so anything written there is already on every
player's disk. gg_lib prints a warning if a server-only setting ships one.
