# Hooks

Running your own code when something happens in a GG script.

[← back to the README](../README.md)

---

## What a hook is

Every GG script reports the things worth knowing about: a job finished, money
moved, a vehicle was rented. A hook is a function of yours that runs when one
of those happens.

They all live in one file, `hooks/server.lua`. It is the only file in gg_lib
you are meant to change — keep a copy before you update, the same as your
`server_config.lua`.

---

## Getting the code

Open `/ggsettings`, go to **Logs → Activity Types**, find the action you want
and press **Code**. It shows the exact block to paste, already listing
everything that action hands you, and a **Copy** button.

Paste it into `hooks/server.lua` and restart gg_lib. The Activity Types page
marks the action **Hooked** once it is live.

```lua
-- Taxi Job Complete -- A driver finished a ride and was paid.
--
--   data.action       string
--   data.script       string
--   data.name         string
--   data.account      string
--   data.identifier   string
--   data.source       number
--   data.at           number
--   data.type         string
--   data.earnings     number
--
GGHook('gg_taxijob:job.complete', function(data)
    exports.my_battlepass:AddXP(data.source, 25)
end)
```

Add as many as you like, in any order. Registering the same action twice is
reported in the console, and the last one wins.

---

## What you can rely on

Every hook is handed one flat table. These are on every action, whatever the
script:

| Field | What it is |
|---|---|
| `data.action` | the full id, `gg_taxijob:job.complete` |
| `data.script` | which script reported it |
| `data.name` | their in-game name, from the framework |
| `data.account` | their FiveM name, the one the admin list shows |
| `data.identifier` | their account id, fivem: first, steam: last |
| `data.source` | their server id |
| `data.at` | when it happened, as `os.time()` |

Everything else comes from the action itself, and the Code panel lists exactly
what that is. A script cannot overwrite the seven above — gg_lib resolves them
itself, so `data.name` is always who it really was.

---

## Everything runs on the server

There is no client hooks file. A hook runs on the server, and if you want
something on a player's screen you trigger a client event from inside it, the
same as you would anywhere else:

```lua
GGHook('gg_taxijob:job.complete', function(data)
    TriggerClientEvent('my_script:showPayout', data.source, data.earnings)
end)
```

That keeps one place to look, and means a hook always has the server's view of
what happened rather than a copy sent to a client.

---

## What a hook cannot do

A hook runs **after** the thing has already happened. It cannot cancel it or
change the outcome. If your hook throws an error, gg_lib catches it, prints
which action caused it, and carries on — a broken hook never takes a script
down with it.

---

## Webhooks instead

If you only want the thing announced in Discord, you do not need a hook at all.
The same page has **Alert**, which takes a webhook and a message you write, with
`{name}`, `{earnings}` and anything else the action carries.
