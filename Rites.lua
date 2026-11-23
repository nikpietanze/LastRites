-- Kill detection and performing the rite.
--
-- Forever's client is Midnight-derived: the combat log is restricted for
-- addons, so kills come from the standalone PARTY_KILL event and the killing
-- spell from the player's own successful casts. Chat can be locked down by the
-- client; a rite is only worth it in the moment, so a kill during a lockdown
-- gets no rite, and a prayer blocked when it would go out is dropped.
--
-- WoW only lets addons send /e text during a real keypress or click. The
-- built-in emote plays right away on the kill; the prayer goes out on your
-- next keypress, which in PvP is a fraction of a second later. No keypress
-- within KEY_WINDOW and the prayer is dropped, never sent late.
local _, ns = ...

local SPELL_WINDOW = 6 -- A cast this recent counts as the killing spell.
local KEY_WINDOW = 1.5 -- Seconds the prayer waits for a keypress before it's dropped.

local FALLBACK = {
	class = "adventurer",
	race = "soul",
	zone = "this place",
	spell = "cold steel",
}

local isSecret = issecretvalue or function() return false end
ns.IsSecret = isSecret

local playerGUID
local lastFire = -math.huge
local lastCast -- { name = spell name, time = GetTime() }
local bags = {} -- Shuffle bags: no line repeats until its pool runs out.

local function now()
	return GetTime()
end

local function stripRealm(name)
	if type(name) ~= "string" then return nil end
	return (name:gsub("%-.*$", ""))
end
ns.StripRealm = stripRealm

function ns.Ordinal(n)
	local suffix = "th"
	local mod100 = n % 100
	if mod100 < 11 or mod100 > 13 then
		local mod10 = n % 10
		if mod10 == 1 then
			suffix = "st"
		elseif mod10 == 2 then
			suffix = "nd"
		elseif mod10 == 3 then
			suffix = "rd"
		end
	end
	return n .. suffix
end

----------------------------------------------------------------------
-- Where rites are allowed
----------------------------------------------------------------------

function ns.ZoneType()
	local inInstance, instanceType = IsInInstance()
	if instanceType == "pvp" then return "battleground" end
	if instanceType == "arena" then return "arena" end
	if not inInstance or instanceType == "none" then return "world" end
	return instanceType
end

function ns.ZoneAllowed()
	local zone = ns.ZoneType()
	if zone == "battleground" then return ns.db.battlegrounds end
	if zone == "arena" then return ns.db.arenas end
	if zone == "world" then return ns.db.world end
	return false
end

function ns.InChatLockdown()
	return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

----------------------------------------------------------------------
-- Choosing and filling a prayer
----------------------------------------------------------------------

local function draw(key, pool)
	local bag = bags[key]
	if not bag or #bag == 0 then
		bag = {}
		for i = 1, #pool do bag[i] = i end
		for i = #bag, 2, -1 do
			local j = math.random(i)
			bag[i], bag[j] = bag[j], bag[i]
		end
		bags[key] = bag
	end
	return pool[table.remove(bag)]
end

function ns.ResolveTone()
	local tone = ns.db.tone
	if tone == "mixed" then
		return math.random(2) == 1 and "reverent" or "satire"
	end
	return tone
end

-- Returns prayer, tone, isNemesis.
-- Emotes that hold your character in a pose until you move.
ns.POSE_EMOTES = { KNEEL = true }

local filtered = {}

-- The pool, minus pose emotes when those are avoided (and the emote plays).
local function poolFor(key, pool)
	if not ns.db.avoidPoses or ns.db.mode == "custom" then
		return key, pool
	end
	if not filtered[key] then
		local list = {}
		for _, prayer in ipairs(pool) do
			if not ns.POSE_EMOTES[prayer[1]] then list[#list + 1] = prayer end
		end
		filtered[key] = #list > 0 and list or pool
	end
	return key .. "-noposes", filtered[key]
end

function ns.Pick(killCount)
	local prayers = ns.Prayers
	local tone = ns.ResolveTone()
	if ns.db.nemesisEnabled and killCount >= ns.db.nemesis then
		return draw(poolFor("nemesis-" .. tone, prayers.nemesis[tone])), tone, true
	end
	return draw(poolFor(tone, prayers[tone])), tone, false
end

function ns.Fill(template, ctx)
	local text = template:gsub("{(%w+)}", function(key)
		local value = ctx[key]
		if value == nil or value == "" then value = FALLBACK[key] end
		return value ~= nil and tostring(value) or ("{" .. key .. "}")
	end)
	if #text > 255 then
		text = text:sub(1, 252) .. "..."
	end
	return text
end

function ns.BuildContext(name, guid, count)
	local ctx = { name = name, guid = guid, count = count, nth = ns.Ordinal(count) }
	if guid and GetPlayerInfoByGUID then
		local class, _, race, _, _, fullName, realm = GetPlayerInfoByGUID(guid)
		if not isSecret(class) then ctx.class = class end
		if not isSecret(race) then ctx.race = race end
		-- For aiming the emote by name: the bare character name (Forever can
		-- add a surname after a space), plus the realm for cross-realm players.
		if type(fullName) == "string" and not isSecret(fullName) then
			local base = stripRealm(fullName):match("^(%S+)")
			if base and type(realm) == "string" and not isSecret(realm) and realm ~= "" then
				base = base .. "-" .. realm:gsub("[%s%-]", "")
			end
			ctx.emoteName = base
		end
	end
	ctx.zone = GetRealZoneText and GetRealZoneText() or nil
	if lastCast and now() - lastCast.time <= SPELL_WINDOW then
		ctx.spell = lastCast.name
	end
	return ctx
end

----------------------------------------------------------------------
-- Performing
----------------------------------------------------------------------

local function performEmote(token, target)
	if C_ChatInfo and C_ChatInfo.PerformEmote then
		return C_ChatInfo.PerformEmote(token, target)
	elseif DoEmote then
		return DoEmote(token, target)
	end
end

local function sendEmote(text)
	if C_ChatInfo and C_ChatInfo.SendChatMessage then
		C_ChatInfo.SendChatMessage(text, "EMOTE")
	elseif SendChatMessage then
		SendChatMessage(text, "EMOTE")
	end
end

local UNIT_TOKENS = { "target", "softenemy", "mouseover", "focus" }

local function sameGUID(unit, guid)
	local unitGUID = UnitGUID(unit)
	return unitGUID ~= nil and not isSecret(unitGUID) and unitGUID == guid
end

-- A unit token for the victim if they're your target, soft target, mouseover,
-- focus or have a nameplate.
local function findUnit(guid)
	for _, unit in ipairs(UNIT_TOKENS) do
		if sameGUID(unit, guid) then return unit end
	end
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
			local unit = plate.namePlateUnitToken
			if unit and sameGUID(unit, guid) then return unit end
		end
	end
end

-- Who to aim the built-in emote at: the victim's unit if we can find one, else
-- their name, else the current target if it's them by name, else nobody.
-- Never yourself.
local function emoteTarget(ctx)
	if ctx.guid and ctx.guid ~= UnitGUID("player") then
		local unit = findUnit(ctx.guid)
		if unit then return unit end
		if ctx.emoteName then return ctx.emoteName end
	end
	if UnitExists("target") and not UnitIsUnit("target", "player") and stripRealm(UnitName("target")) == ctx.name then
		return "target"
	end
	return "none"
end

local queued -- { text, from, to }: a prayer waiting for a keypress

local function sendPrayer(text)
	if ns.InChatLockdown() then
		ns.Debug("Chat locked down; prayer dropped.")
		return
	end
	ns.Debug("Sending prayer.")
	sendEmote(text)
end

-- Called on every key press (the keys still reach the game as normal).
local keyTestUntil, keyTestSeen = 0, {}

-- Called on every key press, ability use and movement start (the input still
-- reaches the game as normal). source says what was seen, for /rites keytest.
function ns.OnKeyPress(source)
	if now() < keyTestUntil then
		-- Each kind once (every key counts as one kind), so abilities and
		-- movement aren't crowded out by a stream of keys.
		local kind = tostring(source):match("^key ") and "a key" or tostring(source)
		if not keyTestSeen[kind] then
			keyTestSeen[kind] = true
			ns.Print(("Key test: saw %s%s."):format(tostring(source),
				InCombatLockdown() and " (in combat)" or ""))
		end
	end
	if not queued then return end
	local t = now()
	if t < queued.from then return end
	local entry = queued
	queued = nil
	if t > entry.to then return end
	ns.Debug("Key press seen (" .. tostring(source) .. ").")
	sendPrayer(entry.text)
end

function ns.KeyTest()
	keyTestUntil, keyTestSeen = now() + 15, {}
	ns.Print("Key test: for 15 seconds, each kind of press Last Rites can see is listed once. Try a key, an ability by keybind, an ability by clicking, moving and jumping. Best done while in combat.")
end

local function queuePrayer(text)
	local t = now()
	local entry = { text = text, from = t, to = t + KEY_WINDOW }
	queued = entry
	ns.Debug("Prayer waits for your next keypress.")
	C_Timer.After(KEY_WINDOW, function()
		if queued == entry then
			queued = nil
			ns.Debug("No keypress in time; prayer dropped.")
		end
	end)
end

function ns.HasQueuedPrayer()
	return queued ~= nil
end

-- Plays the built-in emote, then the prayer on your next key press. fromKeypress:
-- this call already runs inside a keypress or click (slash command, button),
-- so the prayer can go out right away.
function ns.Perform(prayer, ctx, fromKeypress)
	local token, text = prayer[1], ns.Fill(prayer[2], ctx)
	local mode = ns.db.mode
	if mode ~= "custom" then
		-- Aim at the corpse only while it's still targeted, never at someone else.
		local target = emoteTarget(ctx)
		local result = performEmote(token, target)
		ns.Debug(("Emote /%s at %s (WoW returned %s)."):format(token:lower(), target, tostring(result)))
	end
	if mode ~= "builtin" then
		if fromKeypress then
			sendPrayer(text)
		else
			queuePrayer(text)
		end
	end
	return text
end

function ns.OnKill(guid, rawName)
	local name = stripRealm(rawName)
	if not name then return end
	local db = ns.db
	db.kills[name] = (db.kills[name] or 0) + 1
	local count = db.kills[name]
	local ctx = ns.BuildContext(name, guid, count)

	if not db.enabled then
		ns.Debug("Rites are turned off.")
		return
	end
	if not ns.ZoneAllowed() then
		ns.Debug("Rites are off for " .. ns.ZoneType() .. ".")
		return
	end
	if UnitIsDeadOrGhost("player") then
		ns.Debug("You're dead; no rite.")
		return
	end
	if ns.InChatLockdown() then
		ns.Debug("Chat is locked down; no rite this time.")
		return
	end
	local t = now()
	if t - lastFire < db.cooldown then
		ns.Debug("On cooldown.")
		return
	end
	if math.random(100) > db.chance then
		ns.Debug("Skipped by chance.")
		return
	end
	lastFire = t
	return ns.Perform(ns.Pick(count), ctx)
end

----------------------------------------------------------------------
-- Preview and test
----------------------------------------------------------------------

local SAMPLE = { class = "Rogue", race = "Undead", spell = "Mortal Strike" }

function ns.Preview(name, kills)
	local count = kills or 1
	local ctx = ns.BuildContext(name or "Victim", nil, count)
	for key, value in pairs(SAMPLE) do ctx[key] = ctx[key] or value end
	local prayer, tone, nemesis = ns.Pick(count)
	local me = UnitName("player") or "You"
	local tag = tone .. (nemesis and ", nemesis" or "")
	ns.Print(("|cff888888[/%s, %s]|r %s %s"):format(prayer[1]:lower(), tag, me, ns.Fill(prayer[2], ctx)))
end

-- Performs a real rite, ignoring cooldown, chance and zone settings.
function ns.TestRite(name, fromKeypress)
	local guid
	if not name and UnitExists("target") and UnitIsPlayer("target") then
		name = stripRealm(UnitName("target"))
		guid = UnitGUID("target")
	end
	if not name then
		ns.Print("Target a player or give a name: /rites test Name")
		return
	end
	if ns.InChatLockdown() then
		ns.Print("WoW has chat locked for addons right now. Try again in a moment.")
		return
	end
	local count = (ns.db.kills[name] or 0) + 1
	ns.Perform(ns.Pick(count), ns.BuildContext(name, guid, count), fromKeypress)
end

function ns.ResetCooldown()
	lastFire = -math.huge
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

function ns.OnPartyKill(attackerGUID, targetGUID)
	if isSecret(attackerGUID) or isSecret(targetGUID) then
		ns.Debug("PARTY_KILL with hidden GUIDs; skipped.")
		return
	end
	ns.Debug(("PARTY_KILL %s -> %s"):format(tostring(attackerGUID), tostring(targetGUID)))
	playerGUID = playerGUID or UnitGUID("player")
	if attackerGUID ~= playerGUID then
		ns.Debug(("Not your kill (you are %s)."):format(tostring(playerGUID)))
		return
	end
	if type(targetGUID) ~= "string" or not targetGUID:find("^Player%-") then
		ns.Debug("Not a player; no rite.")
		return
	end
	local _, _, _, _, _, name = GetPlayerInfoByGUID(targetGUID)
	if not name or isSecret(name) then
		ns.Debug("Couldn't read the victim's name.")
		return
	end
	ns.Debug("Your kill: " .. name .. ".")
	ns.OnKill(targetGUID, name)
end

local getSpellName = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end
local isHarmful = C_Spell and C_Spell.IsSpellHarmful

function ns.OnSpellCast(spellID)
	if not spellID or isSecret(spellID) then return end
	if isHarmful and not isHarmful(spellID) then return end
	local name = getSpellName(spellID)
	if name and not isSecret(name) then
		lastCast = { name = name, time = now() }
	end
end

function ns.LastCastName()
	return lastCast and lastCast.name
end

-- A keyboard-enabled frame that passes every key through to the game. Its
-- propagation can't be set during combat, so set it up once out of combat.
local keyFrame
local function setupKeyFrame()
	if keyFrame then return true end
	if InCombatLockdown() then return false end
	-- Full screen and on top so keys reach it before other keyboard frames.
	-- Mouse stays disabled, so it never blocks clicks.
	keyFrame = CreateFrame("Frame", "LastRitesKeyFrame", UIParent)
	keyFrame:SetAllPoints(UIParent)
	keyFrame:SetFrameStrata("TOOLTIP")
	keyFrame:EnableMouse(false)
	keyFrame:SetPropagateKeyboardInput(true)
	keyFrame:EnableKeyboard(true)
	keyFrame:SetScript("OnKeyDown", function(_, key) ns.OnKeyPress("key " .. tostring(key)) end)
	keyFrame:Show()
	return true
end

-- Backup: the game's own functions for using an ability (key or click) and
-- starting to move run inside your press, so hooking them counts too.
local HOOKS = {
	"UseAction", "JumpOrAscendStart", "MoveForwardStart", "MoveBackwardStart",
	"StrafeLeftStart", "StrafeRightStart", "TurnLeftStart", "TurnRightStart",
}
local function hookInputs()
	for _, name in ipairs(HOOKS) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function() ns.OnKeyPress(name) end)
		end
	end
end

ns.OnLogin(function()
	playerGUID = UnitGUID("player")
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PARTY_KILL")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	frame:RegisterEvent("ADDON_ACTION_BLOCKED")
	if not setupKeyFrame() then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
	hookInputs()
	frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "PARTY_KILL" then
			ns.OnPartyKill(...)
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			local _, _, spellID = ...
			ns.OnSpellCast(spellID)
		elseif event == "PLAYER_REGEN_ENABLED" then
			if setupKeyFrame() then frame:UnregisterEvent("PLAYER_REGEN_ENABLED") end
		elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
			local addon, func = ...
			ns.Debug(("%s: %s tried %s."):format(event, tostring(addon), tostring(func)))
		end
	end)
end)
