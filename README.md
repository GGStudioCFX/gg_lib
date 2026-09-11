# gg_lib

The shared foundation every GG Studio script runs on. Install it once and every
GG Studio resource you own works with your server — your framework, your
inventory, your target system, your dispatch — with nothing to configure.

It also gives you **Script Studio**: one in-game menu where you edit the
settings for all of them, with everything saved to your database rather than to
a file, so updating a script never wipes what you configured.

---

## Install

**1. Install the one thing gg_lib needs**

- [oxmysql](https://github.com/overextended/oxmysql)

**2. Drop `gg_lib` into your resources folder**

**3. Start it before any GG Studio script**

```cfg
ensure oxmysql
ensure gg_lib          # must come before the scripts below
ensure gg_taxijob
```

gg_lib itself does not require ox_lib. Individual GG scripts may still list it
in their own manifests — follow each script's install notes.

That is the whole install. gg_lib builds its own database tables the first time
it starts — there is no `.sql` file to import.

---

## Open the menu

Script Studio is admin-only, so nothing opens until you add yourself. The
quickest way, in `server.cfg`:

```cfg
add_ace group.admin gg.settings allow
add_principal identifier.license:YOUR_LICENSE group.admin
```

Then, in game:

```
/ggsettings
```

Other ways to grant access — a framework job, a Discord role, an allow list —
are in [docs/access.md](docs/access.md).

---

## Documentation

| | |
| --- | --- |
| [Access](docs/access.md) | Who can open Script Studio, and how to grant it |
| [Language](docs/language.md) | Setting the language, and translating it yourself |
| [Script Studio](docs/studio.md) | Using the menu: search, presets, placing things in the world |
| [Hooks](docs/hooks.md) | Running your own code when a GG script reports something |
| [Bridges](docs/bridges.md) | Forcing a framework, inventory, target or dispatch |
| [Waypoints](docs/waypoints.md) | The shared world markers every script draws |
| [Daily reset](docs/daily-reset.md) | The clock every script's daily counters share |
| [Home feed](docs/feed.md) | Publishing the home page, the shop and the update logs |
| [Support bundle](docs/support.md) | One click to copy what a ticket needs: versions, the server console and what a script printed |

---

## Updating

Replace the folder and restart. Your settings live in your database, so nothing
you changed in game is lost.

Two files are yours and are replaced along with everything else, so keep a copy
of them first: `server_config.lua`, which holds your admins, and
`hooks/server.lua`, if you have written anything in it.

---

## Support

- Discord: <https://discord.gg/DqMXJzATph>
- Store: <https://www.ggstudio.store>

## License

See [LICENSE](LICENSE).
