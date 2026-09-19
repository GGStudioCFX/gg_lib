# gg_lib

The shared foundation every GG Studio script runs on. Install it once and your
scripts work with whatever your server already has — your framework, your
inventory, your target system, your dispatch — with nothing to wire up.

It also gives you **Script Studio**: one in-game menu that edits the settings
for every GG script, saved to your database, so updating a script never wipes
what you configured.

---

## Install

**1.** Install [oxmysql](https://github.com/overextended/oxmysql).

**2.** Drop `gg_lib` into your resources folder.

**3.** Start it before any GG Studio script:

```cfg
ensure oxmysql
ensure gg_lib          # before the scripts below
ensure gg_taxijob
```

**4.** Open `server_config.lua`, put your license in `admins`, and restart.

Now type **`/ggsettings`** in game.

That is the whole install. gg_lib builds its own database tables the first time
it starts, so there is no `.sql` to import, and it does not need ox_lib —
though individual scripts may, so follow each one's own notes.

> To find your license, join your server and read the `license2` line off the
> console. Other ways to let people in — your framework's admins, a Discord
> role, an allow list — are in [Access](docs/access.md).

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
| [Screenshots](docs/screenshots.md) | Saving vehicle photos locally or with FiveManage |
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
- Store and docs: <https://www.ggstudio.store>

## License

See [LICENSE](LICENSE).
