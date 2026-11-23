# Changelog

## 1.0.0

First release.

- A short funeral emote over enemy players you land the killing blow on: a built-in emote at the corpse that both factions see, then a `/e` prayer for your side.
- 100 reverent prayers, 100 satirical ones, and a mixed tone that flips between them. Every line is 10 to 20 words.
- Lines name the victim's class, race, the zone and the spell that killed them.
- Nemesis lines once you've killed the same player a few times, counting the funerals.
- Native options panel: master switch, tone, what to perform (emote and prayer, emote only, prayer only), battlegrounds, arenas and world PvP toggles, chance per kill, cooldown, pause before the prayer, nemesis lines and threshold. Preview, Test, Your nemeses and Reset kill counts buttons included.
- The prayer goes out on your next key press after the kill, since WoW only sends addon emote text during a key press. No key press within 1.5 seconds, no prayer.
- Prayers follow on from their emote instead of restating it.
- No late rites: a kill while WoW has chat locked for addons gets no rite, rather than one that shows up after the moment has passed.
- Addon compartment entry: left-click for options, right-click to preview.
- `/rites status` and `/rites debug` for bug reports.
