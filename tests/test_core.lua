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

test("killing an enemy player plays a built-in emote, then the prayer", function()
	local W = fresh()
	W.target = { name = "Bob", guid = "Player-9-BOB" }
	kill(W)
	eq(#W.emotes, 1, "emotes")
	eq(W.emotes[1][2], "target", "aimed at the corpse")
	eq(#W.chat, 0, "prayer waits for the delay")
	W.advance(1.5)
	eq(#W.chat, 1, "prayer after delay")
	eq(W.chat[1][2], "EMOTE")
	assert(not W.chat[1][1]:find("[{}]"), "unfilled placeholder: " .. W.chat[1][1])
end)

test("only ever uses the EMOTE channel", function()
	local W = fresh()
	for i = 1, 40 do
		addPlayer(W, "Player-9-X" .. i, "X" .. i)
		W.advance(100)
		kill(W, "Player-9-X" .. i)
	end
	W.advance(5)
	eq(#W.chat, 40)
	for _, c in ipairs(W.chat) do eq(c[2], "EMOTE") end
end)

test("emote has no target when the corpse isn't targeted", function()
	local W = fresh()
	W.target = { name = "Someone", guid = "Player-9-SOME" }
	kill(W)
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

test("mode custom sends only the prayer, immediately", function()
	local W = fresh()
	W.ns.db.mode = "custom"
	kill(W)
	eq(#W.emotes, 0); eq(#W.chat, 1)
end)

test("delay 0 sends the prayer right away", function()
	local W = fresh()
	W.ns.db.delay = 0
	kill(W)
	eq(#W.chat, 1)
end)

test("chat lockdown holds the rite until it lifts", function()
	local W = fresh()
	W.lockdown = true
	kill(W)
	eq(#W.emotes, 0, "nothing during lockdown")
	assert(W.ns.HasPendingRite(), "rite held")
	W.lockdown = false
	W.fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
	W.advance(0.5)
	eq(#W.emotes, 1, "emote after lockdown")
	W.advance(1.5)
	eq(#W.chat, 1, "prayer after lockdown")
	assert(not W.ns.HasPendingRite())
end)

test("a held rite expires if lockdown lasts too long", function()
	local W = fresh()
	W.lockdown = true
	kill(W)
	W.advance(60)
	W.lockdown = false
	W.fire("PLAYER_REGEN_ENABLED")
	W.advance(1)
	eq(#W.emotes, 0)
end)

test("prayer is dropped if lockdown starts during the delay", function()
	local W = fresh()
	kill(W)
	W.lockdown = true
	W.advance(2)
	eq(#W.emotes, 1); eq(#W.chat, 0)
end)

test("tone reverent only draws reverent lines", function()
	local W = fresh()
	W.ns.db.tone = "reverent"
	local set = {}
	for _, p in ipairs(W.ns.Prayers.reverent) do set[p] = true end
	for _ = 1, 200 do
		local p, tone = W.ns.Pick(1)
		eq(tone, "reverent")
		assert(set[p], "not from the reverent pool")
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
	for _ = 1, 3 do W.advance(100); kill(W) end
	assert(set[W.chat[3][1]], "3rd kill should be a nemesis line: " .. W.chat[3][1])
end)

test("shuffle bag doesn't repeat a line until the pool is used up", function()
	local W = fresh()
	W.ns.db.tone = "satire"
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

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
