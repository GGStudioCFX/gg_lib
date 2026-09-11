# Support bundle

When something is wrong and you are asking GG Studio for help, the useful
things are the same every time: what the server is running, what the server
console said, and what the script printed on your screen. The support bundle
collects all of that in one click -- **Help → Still stuck? → Copy support
bundle** -- and puts it in your clipboard. Paste it into Discord: a paste that
long is sent as a file (`message.txt`), which is exactly what we want to read.

## What is in it

- **Header** -- hostname, FXServer and txAdmin versions, OneSync, game build,
  uptime and player count, the gg_lib version, which resource answers each
  bridge category, every `gg_*` resource with its version and state, and who
  sent it.
- **Server console** -- the last 1,500 lines (or 256 KB) of what the server
  console printed, from every resource, timestamped and tagged with the channel
  it came from. This is the same text txAdmin's live console shows. It needs
  the **Logs** tool; an admin without it still gets everything else.
- **Client console** -- what GG scripts printed or threw on *your* screen, the
  last 200 lines per script. A script cannot read the F8 console, so only the
  scripts that import gg_lib are in here, not the rest of your resources.
- **Studio UI** -- errors the menu itself hit.

## What is not

Nothing is sent anywhere by the button: it is your clipboard, and it goes
where you paste it. Passwords and keys are not collected, but a script that
prints them to the console has put them in the console, which is why **Open
it first** shows you the whole thing before you copy it.
