# Access

Who can open Script Studio.

[← back to the README](../README.md)

---

## Giving yourself access

Script Studio is admin-only. Nobody can open it until you add yourself.

**Open `server_config.lua` in the gg_lib folder and put your license in the list:**

```lua
return {
    admins = {
        "license2:put_your_own_license_here",
    },

    ace = true,
}
```

Restart gg_lib and type **`/ggsettings`** in game.

> `server_config.lua` never reaches players. It is not downloaded to their game
> the way the rest of the resource is, so the list is safe to keep here. It does
> ship with the resource, though, so keep a copy before you update -- the same as
> `hooks/server.lua`.

### If your server already has admins

It probably does, so gg_lib uses it. Anyone holding one of the usual admin
principals — `group.admin`, `group.god`, `group.superadmin`, or the ones
qb-core and Qbox register — or sitting in their framework’s admin group gets
the **Admin** role here without being added to anything.

They never get **Owner**. Deciding who else gets in stays with the people
named in `server_config.lua`, because that file is the way back in when
everything else says no. `group.mod` and `group.moderator` get read-only
access instead.

They show on the Admins page tagged **Server**, so the page answers "who can
get in" honestly — but you cannot change or remove them there, because it was
not that page that let them in. Take away the permission on your server and
they lose this with it.

Turn it off with `auto_admin = false` in `server_config.lua`. gg_lib prints a
line the first time it lets someone in this way, so an admin appearing out of
nowhere is always explainable from the console.

### Finding your license

Join your server and check the console, or use any admin tool that shows player
identifiers. You want the one that starts with `license2:`.

### Adding everyone else

Do not edit the file again. Open **`/ggsettings` → Admins** and add them there —
online players are listed for one-click access, or you can paste an identifier.
Admins added this way are stored in your database and can be removed the same
way.

Anyone listed in `server_config.lua` **cannot** be removed in game. That is
deliberate: it is the route back in if something goes wrong. Keep yourself
there.

### If you use ACE permissions

With `ace = true`, these also grant access:

```cfg
add_ace group.admin gg.settings allow        # can edit
add_ace group.mod   gg.settings.view allow   # can look, cannot change
```

Set `ace = false` to ignore ACE entirely and use only the lists above.

### Names and pictures in the studio

The Admins page shows whoever it can work out from the identifiers a player
carries. Cfx.re and Steam answer for anyone; Discord does not answer an
anonymous caller at all, so a Discord id stays an id unless you hand gg_lib a
bot token:

```lua
return {
    admins = { "license2:put_your_own_license_here" },

    discord_bot_token = "paste it here",
}
```

Make a bot at **discord.com/developers/applications → New Application → Bot →
Reset Token** and copy the token in. It needs no permissions and does not have
to be in your server; it is only used to turn an id into a name and an avatar.

Leave it out and everything still works, with initials in place of pictures.

