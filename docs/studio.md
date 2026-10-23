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

### Row designers

A list whose rows are each designed (the Lucky Wheel's wheels) can open a row
beside a live picture of it instead of as a plain form: the picture on the
left, the row's fields in tabs and titled blocks on the right.

```lua
settings.define('settings.wheels.list', settings.shape.rows({
    group      = 'wheels',
    label      = 'Wheels',
    item       = WHEEL_COLUMNS,
    row_fields = { 'enabled', 'slots' }, -- said on the row's line in the list
    tabs = {
        { id = 'wheel', label = 'Wheel', icon = 'fa-location-dot' },
        { id = 'look',  label = 'Look',  icon = 'fa-palette' },
    },
    sections = {
        { id = 'spins',  tab = 'wheel', label = 'Spins' },
        { id = 'design', tab = 'look',  label = 'Design', help = 'Under the slots.' },
    },
    designer = {
        preview = 'web/dist/face/designer.html', -- in the manifest's files
        build   = 'designer_face',          -- a settings.rowAction, run on every change
        states  = {
            { id = 'idle', label = 'Wheel' },
            { id = 'spin', label = 'Spin', icon = 'fa-rotate-right' },
        },
    },
}))
```

Each column names its `section` and how many of the block's four columns it
takes (`span`); lists, positions and objects take the whole width unless given
one. A nested list (a wheel's slots) takes `sections` of its own. Columns also
take:

| Field                        | What it does                                                                   |
| ---------------------------- | ------------------------------------------------------------------------------ |
| `when`                       | Shown only while other fields of the row hold one of these values: `{ kind = { 'cash', 'item' } }` |
| `view = 'buttons'`           | An enum as a row of buttons                                                    |
| `view = 'gallery'`           | An enum as a gallery of pictures                                               |
| `allow_empty`, `empty_label` | A colour that may stay empty and then follows what it sits over                |
| `placeholder`                | Grey words in an empty box                                                     |
| `examples`                   | A text field's ready values as pictures over its box: `{ { value = 'nui://my_script/web/bg/gold.webp', label = 'Gold' } }`, `image` for a tile that is not the value |
| `sets`                       | Other fields put back when this one changes: `sets = { fill_mode = 'design' }` on a design picker |

An enum option may carry `font = { family = 'Impact', weight = 400 }` (an
installed face) or `font = { file = 'web/dist/fonts/inter-800.woff2', weight = 800 }`
(a file the script ships, listed in its manifest's `files`): the menu then
writes each name in its own font.

`type = 'icon'` is a picture picker: the script's own `packs` (files under
`pack_root`, grouped, `moving = true` for a GIF), the Font Awesome library, an
item's or a car's picture, words, or any picture or GIF by its address.
`auto = false` drops Auto (the prize's own picture).

The designer frames `preview` and, on every change, runs the row through the
`build` row action (on the client, `done(true, data)`) and posts the page:

```js
{ event: 'gg:row:preview', version: 1, row, state, nonce, focus: { key, index }, data }
```

`data` is what `build` answered, `state` the button picked under the picture,
`nonce` changes on every press (a second Spin spins again), and `focus` is the
row open in the list the picture follows (`designer.list`, else the row's first
list column). The page sends `{ event: 'gg:editor:ready', version: 1 }` once it
listens. Like a visual editor's preview it only draws: no gameplay callbacks,
no saving.

**Templates** come from another list setting. The script ships its looks there
(`merge_key` brings them back), and **Save as Template** adds the open row's
look as `saved_1`, `saved_2`... Hovering a card tries it on the picture; its
buttons put it on as unsaved changes.

```lua
templates = {
    from  = 'settings.wheels.templates',
    modes = {
        { id = 'look',  label = 'Look',           keys = LOOK_KEYS },
        { id = 'icons', label = 'Look and Icons', keys = LOOK_KEYS,
          lists = { slots = { 'icon', 'text' } }, needs = 'slots' },
    },
    image    = { { path = '{picture}', when = { design = 'picture' } }, 'web/dist/designs/{design}.jpg' },
    swatches = { 'fill_all', 'hub_fill' },
},
```

A mode copies its `keys` whole and the `lists` columns row by row, round again
where the template has fewer; `needs` is a key the template must hold for the
mode to be offered. `image` is the card's picture, a path inside the script, a
`nui://` or an `https://` address, with `{key}` filled from the template. A
list is tried in order and the first whose `when` holds and whose keys are all
filled is used. `swatches` are keys whose colour shows as dots on the card; a
card with no picture draws them as a small wheel.

Off the game, the development browser (`?scriptPreview=`) posts the build to
`<previewBase>__gg/row_preview` as `{ action, row }` and expects `{ ok, value }`
back, so a local preview server can run the script's own Lua. Needs gg_lib 1.0.22.

### Import & Export

Above Factory Reset, every script's page can take its settings out as one JSON
file and bring them back in. Export opens with every group switched on; switch
off the ones you do not want, or take the lot.

**Export** copies the file to the clipboard, or saves it on the server as
`gg_lib/transfer/<script>.json` (next to gg_lib, not on your PC). Beside each
value the file carries a `$`-guide — label, help, type, allowed options, range,
list columns, which column identifies a row — so an AI or a person editing it
knows what each setting takes. Server-only values are never exported.

**Import** takes the file back: choose it from your computer, drop it on the
box, paste it, or load the one saved on the server. Chat windows' code fences,
comments and trailing commas are tolerated. **Check**
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

### Private settings

A setting the admins should see and edit but players never get — a list of
players' identifiers let into a panel — is `private = true` instead. It is kept
from players exactly as a server-only one is (the client, the live update, the
log), but the Studio shows and edits it like any other setting, a list with its
Add button and rows. Only admins who may view the script see it.

```lua
settings.define("access.list", settings.shape.rows({
    group   = "access",
    label   = "Panel Access List",
    private = true,
    item    = {
        { key = "name",       label = "Name",       type = "string" },
        { key = "identifier", label = "Identifier", type = "string" },
    },
    default = {},
}))
```

`settings.PRIVATE` is true on a gg_lib that knows it (1.0.21 on); a script for
older ones can fall back to `server_only` when it is not.

### Dropdowns from another script

An `enum`'s `options` may be a function instead of a list. The server calls it
each time the Studio opens, so the dropdown shows what another resource holds
right now (the Casino Wheel Editor's designs, a garage list). A function that
errors gives an empty list and a line in the console.

When that list can change under a saved pick (a design deleted, the other
resource stopped), add `allow_unlisted = true`: a stored text the list does not
hold is kept instead of the whole setting falling back to its default. It must
still be short (`max_length`, 64 by default) with no control characters. Return
the stored id as an option of its own ("Deleted design") so the admin sees it.

```lua
{ key = "design", label = "Design", type = "enum", allow_unlisted = true,
  options = function()
      local list = { { value = "", label = "Default design" } }
      local ok, answer = pcall(function() return exports.gg_casinowheel:getDesigns() end)
      for _, design in ipairs(ok and answer and answer.designs or {}) do
          list[#list + 1] = { value = design.id, label = design.name }
      end
      return list
  end },
```

A rows list can also take `add_label` (the Add button's text) and
`duplicate = true` (a Duplicate action on every row); see
[Placing props](#placing-props). Needs gg_lib 1.0.22.

### Placing props

A `coords` column can pick with the prop it stands for instead of a ped: give it
`preview_object`. Parts listed in `with` sit at their offset from the model's
origin and turn with it, so a thing made of several models shows whole. The
picked coordinates are the model's origin on the ground.

```lua
settings.define("settings.wheels.list", settings.shape.rows({
    label    = "Wheels",
    auto_key = "id",
    -- The Add button places the prop first; the new row starts where it was put down
    add_place = "coords",
    add_label = "Add Wheel",
    duplicate = true,
    item = {
        { key = "id", label = "ID", type = "string", hidden = true },
        settings.column.label(),
        { key = "coords", label = "Position", type = "coords", nullable = true,
          preview_object = {
              model   = "vw_prop_vw_luckywheel_01a",
              title   = "Place Lucky Wheel",
              with    = { { model = "vw_prop_vw_luckywheel_02a", offset = { 0.0, 0.0, 1.525 } } },
              freecam = true,
          } },
    },
    item_default = { id = "1", label = "Lucky Wheel" },
    default = {},
}))
```

| Option | On | What it does |
| --- | --- | --- |
| `preview_object` | a `coords` column | `{ model, title?, with?, freecam? }`: the picker shows this prop (and its parts) instead of a ped. `freecam = true` picks from a flying camera instead of the player's eyes |
| `add_place` | a rows list | The key of a `coords` column. The Add button opens the picker first and the new row starts where the player put it down, then opens so the rest can be set up; cancelling adds nothing |
| `add_label` | a rows list | The Add button's text, `"Add Wheel"` instead of **Add Entry**. Translated like a label |
| `duplicate` | a rows list | Each row gets **Duplicate**: a copy with everything the row holds, a new `auto_key` and "(copy)" after its label. With `add_place` the copy is placed first, starting where the original stands; cancelling makes no copy |

The same keys as the ped picker apply: aim to move, Scroll to turn (Shift for fine
turns), E for the gizmo, Enter to place, Esc to cancel. With `freecam` the prop
follows the middle of the screen while WASD flies, the mouse looks, Space and Q go
up and down, and Shift is fast and Ctrl slow; in the gizmo R switches move and
turn and L-ALT brings up the cursor for the handles. The camera stays within 400 m
of the player. Needs gg_lib 1.0.22.

While any `gg.tool` is open (this picker included), `LocalPlayer.state.ggTool` is `true` on that
client. A script with its own E (or other) key mapping checks it and leaves the press alone, so
placing a lucky wheel next to another one never spins it:

```lua
RegisterCommand("my_use", function()
    if LocalPlayer.state.ggTool then return end
    -- ...
end, false)
```
