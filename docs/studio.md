# Script Studio

Using the menu.

[← back to the README](../README.md)

---

## Using Script Studio

Type **`/ggsettings`** in game.
script also gets its own shortcut — `/taxisettings` opens straight to the taxi
job.

| Page         | What it holds                                                    |
| ------------ | ---------------------------------------------------------------- |
| Your scripts | Every setting, grouped, with search                              |
| Generic      | Settings shared by all GG scripts — color, currency, daily reset |
| Bridges      | What gg_lib connected to, and whether it worked                  |
| Admins       | Who has access                                                   |
| Logs         | Who changed what, and when                                       |

Changes are staged until you press **Save**, so you can adjust several things
and apply them together. Anything needing a restart is labelled.

Each script also has a **Factory Reset** at the bottom of its page, which puts
everything back to how it shipped.

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
