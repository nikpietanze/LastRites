-- Behavior tests against the fake client in wowmock.lua.
-- Usage: lua5.1 tests/test_core.lua [repo root]
local root = arg[1] or "."
package.path = root .. "/tests/?.lua;" .. package.path
local mock = require("wowmock")
local realPrint = print

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	_G.print = realPrint
	if ok then
		passed = passed + 1
		print("  ok   " .. name)
	else
		failed = failed + 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end
local function eq(actual, expected, msg)
	if actual ~= expected then
		error((msg and (msg .. ": ") or "") .. "expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local ME = "Player-1-PLAYER"

local function fresh(saved)
	local W = mock.install(root, saved)
	W.players["Player-9-BOB"] = { class = "Rogue", race = "Undead", name = "Bob" }
	return W
end

local function kill(W, guid, attacker)
	W.fire("PARTY_KILL", attacker or ME, guid or "Player-9-BOB")
end

local function addPlayer(W, guid, name)
	W.players[guid] = { class = "Mage", race = "Gnome", name = name }
end

print("LastRites core tests")

test("a kill plays the emote now and the prayer on your next key press", function()
	local W = fresh()
	W.target = { name = "Bob", guid = "Player-9-BOB" }
	kill(W)
	eq(#W.emotes, 1, "emotes")
	eq(W.emotes[1][2], "target", "aimed at the corpse")
	eq(#W.chat, 0, "no key press yet")
	W.advance(0.2)
	W.press()
	eq(#W.chat, 1, "prayer on the key press")
	W.press()
	eq(#W.chat, 1, "only once")
	eq(W.chat[1][2], "EMOTE")
	assert(not W.chat[1][1]:find("[{}]"), "unfilled placeholder: " .. W.chat[1][1])
end)

test("only ever uses the EMOTE channel", function()
	local W = fresh()
	for i = 1, 40 do
		addPlayer(W, "Player-9-X" .. i, "X" .. i)
		W.advance(100)
		kill(W, "Player-9-X" .. i)
		W.press()
	end
	W.advance(5)
	eq(#W.chat, 40)
	for _, c in ipairs(W.chat) do eq(c[2], "EMOTE") end
end)

test("emote is aimed at the victim by name when they aren't targeted", function()
	local W = fresh()
	W.target = { name = "Someone", guid = "Player-9-SOME" }
	kill(W)
	eq(W.emotes[1][2], "Bob")
end)

test("emote name drops a surname and adds the realm for cross-realm victims", function()
	local W = fresh()
	W.players["Player-9-LOL"] = { class = "Shaman", race = "Orc", name = "Lolurk Shamaninema", realm = "Some Realm" }
	kill(W, "Player-9-LOL")
	eq(W.emotes[1][2], "Lolurk-SomeRealm")
	eq(W.ns.db.kills["Lolurk Shamaninema"], 1)
end)

test("emote uses the victim's nameplate unit when there is one", function()
	local W = fresh()
	W.nameplates = { { namePlateUnitToken = "nameplate3", guid = "Player-9-BOB" } }
	kill(W)
	eq(W.emotes[1][2], "nameplate3")
end)

test("emote is never aimed at yourself", function()
	local W = fresh()
	W.players["Player-1-PLAYER"] = { class = "Rogue", race = "Human", name = "Aldric" }
	W.target = { name = "Aldric", guid = "Player-1-PLAYER" }
	W.slash("test")
	eq(W.emotes[1][2], "none")
end)

test("realm suffix is stripped from the victim's name", function()
	local W = fresh()
	W.players["Player-9-BOB"].name = "Bob-Faerlina"
	W.target = { name = "Bob-Faerlina", guid = "Player-9-BOB" }
	kill(W)
	eq(W.ns.db.kills.Bob, 1)
	eq(W.emotes[1][2], "target")
end)

test("ignores NPC kills", function()
	local W = fresh()
	kill(W, "Creature-0-1-2-3-4-5")
	eq(#W.emotes, 0)
end)

test("ignores kills by someone else", function()
	local W = fresh()
	kill(W, "Player-9-BOB", "Player-1-OTHER")
	eq(#W.emotes, 0)
	eq(W.ns.db.kills.Bob, nil)
end)

test("ignores kills whose GUIDs are secret", function()
	local W = fresh()
	kill(W, mock.SECRET, ME)
	kill(W, "Player-9-BOB", mock.SECRET)
	eq(#W.emotes, 0)
end)

test("skips class and race when they come back secret", function()
	local W = fresh()
	W.players["Player-9-BOB"].class = mock.SECRET
	local ctx = W.ns.BuildContext("Bob", "Player-9-BOB", 1)
	eq(ctx.class, nil)
	eq(W.ns.Fill("{class}", ctx), "adventurer")
end)

test("cooldown blocks rapid rites but still counts kills", function()
	local W = fresh()
	addPlayer(W, "Player-9-A", "A")
	addPlayer(W, "Player-9-B", "B")
	kill(W, "Player-9-A")
	W.advance(5)
	kill(W, "Player-9-B")
	eq(#W.emotes, 1, "second rite blocked")
	eq(W.ns.db.kills.B, 1, "kill still counted")
	W.advance(20)
	kill(W, "Player-9-A")
	eq(#W.emotes, 2, "fires after cooldown")
end)

test("chance 0 never fires", function()
	local W = fresh()
	W.ns.db.chance = 0
	for _ = 1, 20 do W.advance(100); kill(W) end
	eq(#W.emotes, 0)
end)

test("off disables rites but still counts", function()
	local W = fresh()
	W.slash("off")
	kill(W)
	eq(#W.emotes, 0)
	eq(W.ns.db.kills.Bob, 1)
	W.slash("on")
	W.advance(100)
	kill(W)
	eq(#W.emotes, 1)
end)

test("no rites while you're dead", function()
	local W = fresh()
	W.dead = true
	kill(W)
	eq(#W.emotes, 0)
end)

test("zone toggles: battlegrounds, arenas, world", function()
	local W = fresh()
	local cases = {
		{ { true, "pvp" }, "battlegrounds" },
		{ { true, "arena" }, "arenas" },
		{ { false, "none" }, "world" },
	}
	for _, case in ipairs(cases) do
		W.instance = case[1]
		W.ns.db[case[2]] = false
		W.advance(100); W.clear(); kill(W)
		eq(#W.emotes, 0, case[2] .. " off")
		W.ns.db[case[2]] = true
		W.advance(100); W.clear(); kill(W)
		eq(#W.emotes, 1, case[2] .. " on")
	end
	W.instance = { true, "party" }
	W.advance(100); W.clear(); kill(W)
	eq(#W.emotes, 0, "never in dungeons")
end)

test("mode builtin only plays the built-in emote", function()
	local W = fresh()
	W.ns.db.mode = "builtin"
	kill(W); W.advance(5)
	eq(#W.emotes, 1); eq(#W.chat, 0)
end)

test("mode custom sends only the prayer", function()
	local W = fresh()
	W.ns.db.mode = "custom"
	kill(W)
	W.press()
	eq(#W.emotes, 0); eq(#W.chat, 1)
end)

test("mode builtin never waits for a key press", function()
	local W = fresh()
	W.ns.db.mode = "builtin"
	kill(W)
	assert(not W.ns.HasQueuedPrayer())
end)

test("no key press in time: the prayer is dropped, never sent late", function()
	local W = fresh()
	W.slash("debug")
	kill(W)
	W.advance(1.6)
	assert(not W.ns.HasQueuedPrayer())
	assert(table.concat(W.printed, "\n"):find("No keypress in time"), "debug explains")
	W.press()
	eq(#W.chat, 0)
end)

test("the key frame passes keys through and is set up out of combat", function()
	local W = fresh()
	local keyFrames = 0
	for _, f in ipairs(W.frames) do
		if f.keyboard then
			keyFrames = keyFrames + 1
			eq(f.propagate, true, "keys pass through to the game")
		end
	end
	eq(keyFrames, 1)
end)

test("using an ability or starting to move also sends the prayer", function()
	local W = fresh()
	kill(W)
	UseAction(1)
	eq(#W.chat, 1, "ability")
	W.advance(100)
	kill(W)
	MoveForwardStart()
	eq(#W.chat, 2, "movement")
	assert(W.hooks.UseAction and W.hooks.MoveForwardStart)
end)

test("the key frame never blocks the mouse", function()
	local W = fresh()
	for _, f in ipairs(W.frames) do
		if f.keyboard then
			eq(f.mouse, false)
			eq(f.shown, true)
		end
	end
end)

test("/rites keytest lists each kind of press once for 15 seconds", function()
	local W = fresh()
	W.slash("keytest")
	W.press("W")
	W.press("A")
	UseAction(1)
	assert(W.printed[#W.printed - 1]:find("saw key W"), W.printed[#W.printed - 1])
	assert(W.printed[#W.printed]:find("saw UseAction"), W.printed[#W.printed])
	W.advance(16)
	local n = #W.printed
	W.press("W")
	eq(#W.printed, n, "stops after 10 seconds")
end)

test("logging in during combat sets up the key frame once combat ends", function()
	local saved = nil
	local W = mock.install(root, saved, function(W) W.combat = true end)
	W.players["Player-9-BOB"] = { class = "Rogue", race = "Undead", name = "Bob" }
	local function keyFrames()
		local n = 0
		for _, f in ipairs(W.frames) do if f.keyboard then n = n + 1 end end
		return n
	end
	eq(keyFrames(), 0, "not in combat")
	W.combat = false
	W.fire("PLAYER_REGEN_ENABLED")
	eq(keyFrames(), 1, "after combat")
	W.fire("PLAYER_REGEN_ENABLED")
	eq(keyFrames(), 1, "only once")
	kill(W); W.press()
	eq(#W.chat, 1)
end)

test("a kill during chat lockdown gets no rite, now or later", function()
	local W = fresh()
	W.slash("debug")
	W.lockdown = true
	kill(W)
	eq(#W.emotes + #W.chat, 0, "nothing during lockdown")
	assert(table.concat(W.printed, "\n"):find("no rite this time"), "debug explains")
	W.lockdown = false
	W.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
	W.fire("PLAYER_REGEN_ENABLED")
	W.advance(60)
	eq(#W.emotes + #W.chat, 0, "nothing shows up later")
	eq(W.ns.db.kills.Bob, 1, "kill still counted")
end)

test("a lockdown skip doesn't use up the cooldown", function()
	local W = fresh()
	W.lockdown = true
	kill(W)
	W.lockdown = false
	W.advance(1)
	kill(W)
	eq(#W.emotes, 1)
end)

test("prayer is dropped if chat locks down before your key press", function()
	local W = fresh()
	kill(W)
	W.lockdown = true
	W.advance(0.5)
	W.press()
	W.lockdown = false
	W.advance(60)
	eq(#W.emotes, 1, "emote played")
	eq(#W.chat, 0, "prayer dropped, never sent late")
end)

test("/rites test during lockdown explains instead of performing", function()
	local W = fresh()
	W.target = { name = "Bob", guid = "Player-9-BOB" }
	W.lockdown = true
	W.slash("test")
	eq(#W.emotes + #W.chat, 0)
	assert(W.printed[#W.printed]:find("locked"), W.printed[#W.printed])
end)

test("the old pause setting is removed from saved settings", function()
	local W = fresh({ version = 2, delay = 0.5 })
	eq(W.ns.db.delay, nil)
end)

test("tone reverent only draws reverent lines", function()
	local W = fresh()
	W.ns.db.tone = "reverent"
	local set = {}
	for _, p in ipairs(W.ns.Prayers.reverent) do set[p] = true end
	for _, p in ipairs(W.ns.ClassPrayers.ROGUE.reverent) do set[p] = true end
	for _ = 1, 200 do
		local p, tone = W.ns.Pick(1)
		eq(tone, "reverent")
		assert(set[p], "not from the reverent pools (general or rogue)")
	end
end)

test("avoid poses skips /kneel lines (on by default), unless only the prayer is sent", function()
	local W = fresh()
	eq(W.ns.db.avoidPoses, true, "default")
	for _ = 1, 300 do
		local p = W.ns.Pick(1)
		assert(p[1] ~= "KNEEL", "drew a /kneel line")
		p = W.ns.Pick(5)
		assert(p[1] ~= "KNEEL", "drew a /kneel nemesis line")
	end
	W.ns.db.mode = "custom"
	local kneels = 0
	for _ = 1, 300 do
		if W.ns.Pick(1)[1] == "KNEEL" then kneels = kneels + 1 end
	end
	assert(kneels > 0, "prayer-only mode uses every line")
	W.ns.db.mode = "both"
	W.ns.db.avoidPoses = false
	kneels = 0
	for _ = 1, 300 do
		if W.ns.Pick(1)[1] == "KNEEL" then kneels = kneels + 1 end
	end
	assert(kneels > 0, "turned off uses /kneel again")
end)

test("class lines: about half of rites use your class's lines, and they can be turned off", function()
	local W = fresh()
	W.playerClass = "Warlock"
	W.ns.db.tone = "satire"
	W.ns.db.avoidPoses = false
	W.ns.ClassPrayers.WARLOCK.satire = { { "GLOAT", "tucks {name}'s soul into a shard. \"It's a little cramped in there, but cozy.\"" } }
	local classSet = { [W.ns.ClassPrayers.WARLOCK.satire[1]] = true }
	local hits = 0
	for _ = 1, 400 do
		if classSet[W.ns.Pick(1)] then hits = hits + 1 end
	end
	assert(hits > 120 and hits < 280, "about half: " .. hits)
	W.ns.db.classLines = false
	for _ = 1, 200 do
		assert(not classSet[W.ns.Pick(1)], "class line while off")
	end
end)

test("class lines are skipped for a class with no lines, and never replace nemesis lines", function()
	local W = fresh()
	W.playerClass = "Mage"
	W.ns.ClassPrayers.MAGE = { reverent = {}, satire = {} }
	for _ = 1, 100 do
		local p = W.ns.Pick(1)
		assert(p, "always picks something")
		local _, _, nem = W.ns.Pick(5)
		eq(nem, true)
	end
end)

test("mixed tone draws from both pools", function()
	local W = fresh()
	local tones = {}
	for _ = 1, 200 do
		local _, t = W.ns.Pick(1)
		tones[t] = true
	end
	assert(tones.reverent and tones.satire, "both tones should appear")
end)

test("nemesis lines start at the threshold and can be turned off", function()
	local W = fresh()
	local _, _, nem = W.ns.Pick(2)
	eq(nem, false, "below threshold")
	_, _, nem = W.ns.Pick(3)
	eq(nem, true, "at threshold")
	W.ns.db.nemesisEnabled = false
	_, _, nem = W.ns.Pick(30)
	eq(nem, false, "disabled")
end)

test("third kill of the same player gets a nemesis line", function()
	local W = fresh()
	W.ns.db.tone = "satire"
	W.ns.db.mode = "custom"
	local set = {}
	for _, p in ipairs(W.ns.Prayers.nemesis.satire) do
		set[W.ns.Fill(p[2], { name = "Bob", count = 3, nth = "3rd", zone = "Warsong Gulch" })] = true
	end
	for _ = 1, 3 do W.advance(100); kill(W); W.press() end
	assert(set[W.chat[3][1]], "3rd kill should be a nemesis line: " .. W.chat[3][1])
end)

test("shuffle bag doesn't repeat a line until the pool is used up", function()
	local W = fresh()
	W.ns.db.tone = "satire"
	W.ns.db.avoidPoses = false
	W.ns.db.classLines = false
	local pool = W.ns.Prayers.satire
	local seen = {}
	for _ = 1, #pool do
		local p = W.ns.Pick(1)
		assert(not seen[p], "repeat before exhaustion")
		seen[p] = true
	end
end)

test("{spell} is your last harmful cast, if recent", function()
	local W = fresh()
	W.spells[12294], W.harmful[12294] = "Mortal Strike", true
	W.spells[6673] = "Battle Shout"
	W.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 12294)
	W.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 6673)
	eq(W.ns.LastCastName(), "Mortal Strike", "buffs ignored")
	eq(W.ns.Fill("{spell}", W.ns.BuildContext("Bob", nil, 1)), "Mortal Strike")
	W.advance(10)
	eq(W.ns.Fill("{spell}", W.ns.BuildContext("Bob", nil, 1)), "cold steel", "stale cast ignored")
	W.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", mock.SECRET)
	eq(W.ns.LastCastName(), "Mortal Strike", "secret spell IDs ignored")
end)

test("class, race and zone fill in", function()
	local W = fresh()
	local ctx = W.ns.BuildContext("Bob", "Player-9-BOB", 1)
	eq(W.ns.Fill("{name} the {race} {class} in {zone}", ctx), "Bob the Undead Rogue in Warsong Gulch")
end)

test("every template fills cleanly with nothing but a name", function()
	local W = fresh()
	local P = W.ns.Prayers
	for _, pool in ipairs({ P.reverent, P.satire, P.nemesis.reverent, P.nemesis.satire }) do
		for _, p in ipairs(pool) do
			local out = W.ns.Fill(p[2], { name = "Bob", count = 4, nth = "4th" })
			assert(not out:find("[{}]"), "unfilled: " .. out)
		end
	end
end)

test("ordinals", function()
	local o = fresh().ns.Ordinal
	eq(o(1), "1st"); eq(o(2), "2nd"); eq(o(3), "3rd"); eq(o(4), "4th")
	eq(o(11), "11th"); eq(o(12), "12th"); eq(o(13), "13th"); eq(o(21), "21st"); eq(o(112), "112th")
end)

test("/rites opens the options panel", function()
	local W = fresh()
	W.slash("")
	eq(W.openedCategory, "Last Rites")
end)

test("/rites preview prints locally and sends nothing", function()
	local W = fresh()
	W.slash("preview Grimgor 5")
	eq(#W.emotes + #W.chat, 0)
	local line = W.printed[#W.printed]
	assert(line:find("Aldric") and line:find("nemesis"), "preview line: " .. tostring(line))
end)

test("/rites test performs on your target, ignoring cooldown and zone", function()
	local W = fresh()
	W.ns.db.world = false
	W.target = { name = "Bob", guid = "Player-9-BOB" }
	W.slash("test")
	W.slash("test")
	eq(#W.emotes, 2)
	eq(#W.chat, 2, "a slash command is a key press, so the prayer goes right away")
	eq(W.ns.db.kills.Bob, nil, "tests don't count as kills")
end)

test("/rites test without a target explains itself", function()
	local W = fresh()
	W.slash("test")
	eq(#W.emotes, 0)
	assert(W.printed[#W.printed]:find("Target a player"))
end)

test("/rites stats and status print without errors", function()
	local W = fresh()
	W.slash("stats")
	kill(W)
	W.slash("stats")
	assert(W.printed[#W.printed]:find("Bob %- 1"), W.printed[#W.printed])
	W.slash("status")
	assert(table.concat(W.printed, "\n"):find("dev on client 1.60.1"), "status shows version")
end)

test("/rites debug logs kill events", function()
	local W = fresh()
	W.slash("debug")
	kill(W, "Creature-0-1")
	assert(table.concat(W.printed, "\n"):find("PARTY_KILL"), "debug output")
end)

test("debug explains every reason a kill gets no rite", function()
	local W = fresh()
	W.slash("debug")
	local function lastDebug() return W.printed[#W.printed] end
	kill(W, "Player-9-BOB", "Player-1-OTHER")
	assert(lastDebug():find("Not your kill"), lastDebug())
	kill(W, "Creature-0-1")
	assert(lastDebug():find("Not a player"), lastDebug())
	kill(W, "Player-9-NOBODY")
	assert(lastDebug():find("Couldn't read"), lastDebug())
	W.dead = true
	kill(W)
	assert(lastDebug():find("dead"), lastDebug())
	W.dead = false
	W.ns.db.enabled = false
	kill(W)
	assert(lastDebug():find("turned off"), lastDebug())
	W.ns.db.enabled = true
	kill(W)
	W.press()
	local out = table.concat(W.printed, "\n")
	assert(out:find("Your kill: Bob") and out:find("Emote /%a+ at Bob %(WoW returned false%)") and out:find("Emote showed") and out:find("Sending prayer"), out)
end)

test("unknown command prints help", function()
	local W = fresh()
	W.slash("bogus")
	assert(W.printed[#W.printed]:find("Commands:"))
end)

test("options panel registers a setting for every option with matching defaults", function()
	local W = fresh()
	local skip = { kills = true, debug = true }
	for key, default in pairs(W.ns.DEFAULTS) do
		if not skip[key] then
			local s = W.settings[key]
			assert(s, "no setting for " .. key)
			eq(s.default, default, key .. " default")
			eq(s.kind, type(default), key .. " type")
		end
	end
	eq(W.registeredCategory and W.registeredCategory.name, "Last Rites")
end)

test("options buttons run without errors", function()
	local W = fresh()
	W.target = { name = "Bob", guid = "Player-9-BOB" }
	W.ns.db.kills.Bob = 2
	for _, init in ipairs(W.buttons) do
		if init.onClick then init.onClick() end
	end
	eq(next(W.ns.db.kills), nil, "reset cleared kills")
end)

test("compartment clicks open options and preview", function()
	local W = fresh()
	LastRites_OnCompartmentClick(nil, "LeftButton")
	eq(W.openedCategory, "Last Rites")
	local before = #W.printed
	LastRites_OnCompartmentClick(nil, "RightButton")
	eq(#W.printed, before + 1)
	LastRites_OnCompartmentEnter(nil, {})
	LastRites_OnCompartmentLeave()
end)

test("saved settings and kills survive a reload; bad values are repaired", function()
	local W = fresh()
	W.ns.SetOption("tone", "reverent")
	kill(W)
	local W2 = fresh(W.ns.db)
	eq(W2.ns.db.tone, "reverent")
	eq(W2.ns.db.kills.Bob, 1)
	local W3 = fresh({ tone = "silly", mode = "loud" })
	eq(W3.ns.db.tone, "mixed")
	eq(W3.ns.db.mode, "both")
	eq(W3.ns.db.chance, 100, "missing keys filled")
end)

test("an emote refused while moving is retried when you stop", function()
	local W = fresh()
	W.target = { name = "Bob", guid = "Player-9-BOB" }
	W.moving = true
	kill(W)
	eq(#W.emotes, 1)
	assert(not W.emotes[1].shown, "refused while moving")
	W.moving = false
	W.advance(0.3)
	W.fire("PLAYER_STOPPED_MOVING")
	eq(#W.emotes, 2, "retried")
	assert(W.emotes[2].shown, "shown on retry")
	W.fire("PLAYER_STOPPED_MOVING")
	W.press()
	eq(#W.emotes, 2, "no more retries once it showed")
	eq(#W.chat, 1, "prayer still sent")
end)

test("an emote refused while moving is retried on a key press, a few times at most", function()
	local W = fresh()
	W.target = { name = "Bob", guid = "Player-9-BOB" }
	W.moving = true
	kill(W)
	W.press()
	eq(#W.emotes, 1, "no retry straight away")
	eq(#W.chat, 1, "prayer on the key press")
	for _ = 1, 4 do W.advance(0.3); W.press() end
	eq(#W.emotes, 3, "three tries in all")
	W.moving = false
	W.fire("PLAYER_STOPPED_MOVING")
	eq(#W.emotes, 3, "gave up")
end)

test("no emote retry once the moment has passed", function()
	local W = fresh()
	W.moving = true
	kill(W)
	W.advance(2)
	W.moving = false
	W.fire("PLAYER_STOPPED_MOVING")
	eq(#W.emotes, 1)
end)

test("a shown emote is never repeated", function()
	local W = fresh()
	W.target = { name = "Bob", guid = "Player-9-BOB" }
	kill(W)
	W.advance(0.5)
	W.press()
	W.fire("PLAYER_STOPPED_MOVING")
	eq(#W.emotes, 1)
end)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
