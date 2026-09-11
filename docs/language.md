# Language

What Script Studio speaks, and how to translate it.

[← back to the README](../README.md)

---

## Setting it

Script Studio → **General** → **Language**.

The list only offers languages that are actually **translated**, not merely
present. The seven files below ship empty, and offering one would put a German
name on an English menu — which reads as something being broken rather than as
a translation nobody has written yet. A language appears once a quarter of its
strings have been filled in.

The choice is a setting like any other: it lives in your database, it applies
live, it survives an update, and only somebody who can already edit settings
can change it.

### What ships

| | | |
| --- | --- | --- |
| `en` | English | built in |
| `de` | Deutsch | empty |
| `es` | Espanol | empty |
| `fr` | Francais | empty |
| `ja` | Japanese | empty |
| `nl` | Nederlands | empty |
| `pt-br` | Portugues (Brasil) | empty |
| `zh-cn` | Chinese (Simplified) | empty |

Seven, chosen from store visitor numbers rather than from a hunch: together
with English they cover 88% of the people who visit the store. The list is
deliberately short — every language is one more file to keep up with on every
release.

Arabic ranked seventh by audience and is deliberately absent. It reads right to
left, which is a layout job across every panel rather than a translation, and
half a mirrored menu is worse than an English one.

Anything a translation has not covered stays in English, which means a half
finished translation is a working one — and a gg_lib update that adds new
strings never leaves a language full of blanks.

---

## Translating

Every string lives in `locales/<code>.json`. `locales/en.json` is the source;
it is generated from the strings the editor actually ships with, so it is
always complete and always current.

**Start a new language:**

```
node tools/locales.mjs --new fr
```

That writes `locales/fr.json` with every key in place and **nothing in any of
them**:

```json
{
    "access_close_hint": "",
    "access_copy": "",
    ...
}
```

Empty rather than a copy of English, on purpose. English sitting in a French
file looks translated at a glance, and later nobody can tell which lines were
done and which were never touched. An empty value is unambiguous: what is
filled in is what is finished.

Translate the values, leave the keys alone, and add a line for it in
`core/shared/locale_names.lua` so the picker can name it.

**After a gg_lib update adds strings:**

```
node tools/locales.mjs --sync
```

New keys arrive empty in every language, keys nothing uses any more are
dropped, and not one translated line is touched. That is the whole cost of a
release — no merging, and nothing to redo per script.

**Check what is left:**

```
node tools/locales.mjs
```

```
en: 497 strings
de: 0/497 translated (0%)  -- not offered in the menu until 25%
  497 still to do
fr: 358/497 translated (72%)
  139 still to do
```

It never writes to a translation. A tool that "fixes" a language by filling it
with English is a tool that quietly un-translates things.

A language is read once and kept, so a file edited while the server is up is
picked up on the next restart.

---

## The one rule

`%s` is a placeholder, filled in order with a number or a name. A line that
loses one — or has them in an order that no longer matches — renders with a
hole in it, and nothing errors. `tools/locales.mjs` reports any line whose
count of `%s` does not match English, and the test suite fails on it.

```json
"updates_running": "Running %s",
"updates_out": "%s is out"
```

Where a language needs a different word order, move the whole clause rather
than the `%s`:

```json
"home_ends_in": "Ends in %s"
```

---

## Adding a language to the list

`core/shared/locale_names.lua`:

```lua
{ code = "fr", label = "Francais" },
```

Endonyms in plain ASCII — the picker is drawn in the game's own font, and a
name nobody can read is worse than a name that has lost its accents.

A line here with no file shows nothing; a file with no line here loads but
cannot be picked. Both are needed.
