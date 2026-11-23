# In-game test checklist

Run through this list before tagging a release. Note your client build from `/rites status`, keep BugSack open, and turn on `/rites debug` while testing kills.

LastRites' logic is covered by the mocked-client tests in `tests/`, but kill events, emotes, chat lockdown and the options panel need a real client. A friend on the other faction makes the visibility checks much easier.

## Setup and options

| Check | Expected result |
|---|---|
| Load | No Lua errors on login or `/reload`. LastRites appears in the AddOns list with its icon. |
| Options | `/rites` opens Esc → Options → AddOns → LastRites with the Rites, Where, Timing and Nemesis sections. |
| Gray out | Turning off **Perform last rites** grays out everything under it. Turning off **Nemesis lines** grays out its slider. |
| Defaults | The panel's Defaults button restores every setting. |
| Compartment | The LastRites entry in the minimap addons menu opens options on left-click and prints a preview on right-click. |
| Preview | `/rites preview` prints a line only you see. `/rites preview Bob 5` shows a nemesis line mentioning the 5th time. |
| Status | `/rites status` prints the version, client build, settings, zone type and lockdown state. |

## Emotes

| Check | Expected result |
|---|---|
| Built-in emotes | Each emote token works on this client: `/pray`, `/kneel`, `/bow`, `/salute`, `/mourn`, `/pity`, `/violin`, `/gloat`, `/comfort`, `/sigh`, `/cry`, `/shrug`. |
| Test | Target a player and `/rites test`. Your character plays the emote at them ("Aldric kneels before Bob."), and the prayer appears as an emote right after. |
| No target | `/rites test Bob` with nothing targeted plays the emote with no target ("Aldric kneels."), not at anyone else. |
| Modes | Emote only plays just the emote. Prayer only sends just the `/e` line, right away. |

## Kills

| Check | Expected result |
|---|---|
| Detection | Land a killing blow on an enemy player. Debug prints `PARTY_KILL` with your GUID, `Your kill`, the emote, then `Prayer waits for your next keypress`. Your next key press sends the prayer. |
| No key press | After a kill, press nothing for 2 seconds. Debug says the prayer was dropped, and it never appears later. |
| Moving | Kill while running. Debug says `while moving`, then retries on your next key press or when you stop, until `Emote showed`. The emote never shows twice, aims at the victim even if you've retargeted, and the prayer comes after it. |
| Corpse target | When the corpse is still targeted, the emote names the victim. |
| Others' kills | A kill by a teammate prints `PARTY_KILL` in debug but performs nothing. |
| NPCs | Killing a creature performs nothing. |
| Spell | A kill with a spell can name it in lines with `{spell}`. A melee kill says "cold steel". |
| Cooldown | A second kill within 20 seconds performs nothing, but `/rites stats` counts it. |
| Zones | Each of Battlegrounds, Arenas and World PvP turns rites off in that kind of zone. |
| Nemesis | The third kill of the same player uses a nemesis line with the right count. |
| Dead | Trading kills (you die at the same moment) performs nothing. Dying right after a kill still sends the prayer on your next key press, unless chat locked down, in which case debug says it was dropped. |

## Visibility (needs someone on the other faction)

| Check | Expected result |
|---|---|
| Built-in emote | The victim sees "Aldric kneels before you." (or similar) while standing at their corpse. |
| Prayer | The enemy faction sees "Aldric makes some strange gestures." Your faction sees the full line. |

## Chat lockdown

| Check | Expected result |
|---|---|
| Lockdown | If `/rites status` ever shows `chatLockdown=true`, a kill during it gets no rite and debug says why; the rite never shows up later. No `ADDON_ACTION_BLOCKED` or `ADDON_ACTION_FORBIDDEN` errors. |

## Needs confirming on a live client

- `PARTY_KILL` fires for your own killing blows in the open world and in battlegrounds, with your GUID as the attacker. Its GUIDs are marked secret "when the unit isn't player-controlled or in the party/raid"; enemy players should be readable. If debug shows `hidden GUIDs` on player kills, detection needs a different source.
- `C_ChatInfo.PerformEmote(token, "target")` aims at the target and `"none"` aims at nobody, as with the old `DoEmote`.
- `C_Spell.IsSpellHarmful` exists and filters out buffs for `{spell}`.
- When chat lockdown applies to emotes in PvP on this client.
