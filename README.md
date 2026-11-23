<p align="center">
  <img src="docs/logo/logo.png" alt="Last Rites logo" width="160">
</p>

<h1 align="center">Last Rites</h1>

<p align="center">
  A small World of Warcraft: Forever addon for PvP. When you land a killing blow on an enemy player, your character performs a short funeral over the body. Reverent, satirical, or both.
</p>

<p align="center">
  <a href="https://github.com/nikpietanze/LastRites/releases/latest"><img src="https://img.shields.io/github/v/release/nikpietanze/LastRites?color=d4af37" alt="Latest release"></a>
  <a href="https://www.curseforge.com/projects/1825204"><img src="https://img.shields.io/badge/CurseForge-Last%20Rites-f16436?logo=curseforge" alt="Get it on CurseForge"></a>
  <a href="https://github.com/nikpietanze/LastRites/actions/workflows/tests.yml"><img src="https://img.shields.io/github/actions/workflow/status/nikpietanze/LastRites/tests.yml?label=tests" alt="Tests"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/nikpietanze/LastRites?color=b48352" alt="MIT license"></a>
</p>

```
Aldric kneels before Grimgor.
Aldric kneels beside Grimgor. "Blessed are the repair bills, for they shall be many."
```

- **Emote only.** No `/say`, no `/yell`, no chat spam. Every rite is a built-in emote at the corpse plus one `/e` line.
- **The other faction sees it.** Built-in emotes like `/kneel`, `/pray` and `/violin` cross factions, so your victim sees "Aldric kneels before you." Your faction reads the full prayer. The enemy sees "Aldric makes some strange gestures," which somehow makes it better.
- **Two tones.** 100 reverent prayers in the King James style, 100 satirical eulogies, or a coin flip between them.
- **Short.** Every line is 10 to 20 words, so people actually read it mid-fight.
- **Personal.** Lines can name the victim's class, race, the zone and the spell that killed them.
- **Nemesis lines.** Kill the same player three times and the rites start keeping count: "Aldric holds Grimgor's 5th funeral. The mourners have stopped bringing casseroles."

## Settings

Everything is under **Esc → Options → AddOns → Last Rites** (or type `/rites`, or click Last Rites in the minimap's addons menu):

| Section | Settings |
|---|---|
| Rites | Perform last rites (master switch), tone (mixed, reverent or satirical), what to perform (emote and prayer, emote only, or prayer only) |
| Where | Battlegrounds, arenas, world PvP |
| Timing | Chance per kill, cooldown between rites, pause before the prayer |
| Nemesis | Nemesis lines, kills to become a nemesis |

Plus **Preview** (a sample only you see), **Test** (a real rite on your target), **Your nemeses** and **Reset kill counts**. Options that depend on another one gray out while it's off, and the panel's **Defaults** button restores everything.

Kills are counted even when a rite is skipped by the cooldown, the chance setting or a zone toggle, so nemesis counts stay honest.

## How it works

LastRites listens for the client's `PARTY_KILL` event and only reacts when you're the killer and the victim is a player. The killing spell is your last harmful spell cast within a few seconds; melee kills get "cold steel."

WoW Forever restricts chat for addons at certain times. If a rite lands during one of those lockdowns, it waits and plays when the lockdown lifts, or quietly expires after 30 seconds. LastRites never makes protected calls and never sends anything but emotes.

## Commands

| Command | What it does |
|---|---|
| `/rites` | Open the options |
| `/rites on` / `/rites off` | Turn rites on or off |
| `/rites preview [name] [kills]` | Print a sample rite only you can see. Give a kill count of 3 or more for a nemesis line |
| `/rites test [name]` | Perform a real rite on your target (or a name), ignoring cooldown, chance and zone |
| `/rites stats` | Your ten most-killed players on this character |
| `/rites status` | Print client, settings and lockdown details for bug reports |
| `/rites debug` | Print every kill event LastRites sees, to check detection |

## Install

Download the latest release and extract it into your AddOns folder:

```
World of Warcraft/_forever_/Interface/AddOns/LastRites/LastRites.toc
```

You can also clone this repo into that folder as `LastRites`. Target client: WoW Forever, Interface `16001`.

## Writing prayers

Prayers live in [Prayers.lua](Prayers.lua). Each one pairs a built-in emote with a line that follows your character's name, and must be 10 to 20 words including that name. See [CONTRIBUTING.md](CONTRIBUTING.md) for the placeholders and rules, or suggest one with the prayer issue template.

## Tests

The logic runs against a mocked client outside the game:

```
lua5.1 tests/validate_prayers.lua .
lua5.1 tests/test_core.lua .
```

The validator checks every prayer's word count, length at worst-case names, emotes and placeholders. The test suite covers kill detection, cooldowns, zones, chat lockdown, nemesis lines, slash commands and the options panel. [docs/TESTING.md](docs/TESTING.md) is the in-game checklist.

## Bugs and ideas

Open an [issue](https://github.com/nikpietanze/LastRites/issues). For bugs, include the output of `/rites status` and any Lua error text (BugSack makes this easy). Pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).
