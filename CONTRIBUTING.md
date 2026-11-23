# Contributing

Thanks for helping out. A few ground rules keep LastRites small and keep people from reporting you:

- **Emotes only.** Rites use a built-in emote and the `EMOTE` chat channel. No `/say`, `/yell`, whispers, channels or addon messages.
- **One rite per kill, at most.** No streak announcements, no chat summaries, no sounds.
- **No protected calls.** Nothing that needs a hardware event or secure code. Respect the client's chat lockdown.
- **Run the tests.** `lua5.1 tests/validate_prayers.lua .` and `lua5.1 tests/test_core.lua .` must pass.
- **Test in game.** Say in your PR what you tested, on which client build, and what you couldn't verify.
- Use tabs for indentation in Lua.

## Writing prayers

Each prayer in [Prayers.lua](Prayers.lua) is `{ "EMOTE", "line" }`.

- **The emote** is a built-in emote token the enemy faction will see: `PRAY`, `KNEEL`, `BOW`, `SALUTE`, `MOURN`, `PITY`, `VIOLIN`, `GLOAT`, `COMFORT`, `SIGH`, `CRY` or `SHRUG`. Pick one that matches the line.
- **The line** follows your character's name, so it starts with a lowercase verb: `kneels beside {name}...`
- **10 to 20 words**, counting your name as one word. Placeholders count as one word each.
- **Placeholders:** `{name}`, `{class}`, `{race}`, `{zone}`, `{spell}`, and in nemesis lines `{count}` and `{nth}` (3rd, 4th...). Every one except `{name}` can fall back to a generic word ("adventurer", "this place", "cold steel"), so the line has to read well either way.
- **Reverent** lines are sincere, scripture-flavored and light on jokes. **Satirical** lines can be as rude as you like about the victim's play, but nothing about real people, real-world religion, race or anything that'd get the player reported.
- Use "they" for the victim and "their" for yourself.

The validator catches word counts, unknown emotes and placeholders, duplicates, and lines that could pass WoW's 255-character limit.
