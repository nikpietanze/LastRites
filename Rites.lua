-- Kill detection and performing the rite.
--
-- Forever's client is Midnight-derived: the combat log is restricted for
-- addons, so kills come from the standalone PARTY_KILL event and the killing
-- spell from the player's own successful casts. Chat can be locked down by the
-- client; rites that land during a lockdown wait for it to lift.
local _, ns = ...

local SPELL_WINDOW = 6 -- A cast this recent counts as the killing spell.
local PENDING_TTL = 30 -- A rite held back by chat lockdown expires after this.

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
local pending -- { prayer, ctx, time }
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

function ns.HasPendingRite()
	return pending ~= nil
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
function ns.Pick(killCount)
	local prayers = ns.Prayers
	local tone = ns.ResolveTone()
	if ns.db.nemesisEnabled and killCount >= ns.db.nemesis then
		return draw("nemesis-" .. tone, prayers.nemesis[tone]), tone, true
	end
	return draw(tone, prayers[tone]), tone, false
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
	local ctx = { name = name, count = count, nth = ns.Ordinal(count) }
	if guid and GetPlayerInfoByGUID then
		local class, _, race = GetPlayerInfoByGUID(guid)
		if not isSecret(class) then ctx.class = class end
		if not isSecret(race) then ctx.race = race end
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

local function corpseTargeted(name)
	return UnitExists("target") and not UnitIsUnit("target", "player") and stripRealm(UnitName("target")) == name
end

local function hold(prayer, ctx, prayerOnly, reason)
	pending = { prayer = prayer, ctx = ctx, time = now(), prayerOnly = prayerOnly }
	ns.Debug(reason)
end

local function sendPrayer(prayer, ctx, text)
	if ns.InChatLockdown() then
		hold(prayer, ctx, true, "Chat locked down before the prayer; it will follow when it lifts.")
		return
	end
	ns.Debug("Sending prayer.")
	sendEmote(text)
end

-- prayerOnly: the built-in emote already played; only the prayer is left.
local function deliver(prayer, ctx, prayerOnly)
	local token, text = prayer[1], ns.Fill(prayer[2], ctx)
	local mode = ns.db.mode
	if mode ~= "custom" and not prayerOnly then
		-- Aim at the corpse only while it's still targeted, never at someone else.
		performEmote(token, corpseTargeted(ctx.name) and "target" or "none")
	end
	if mode ~= "builtin" then
		local delay = (mode == "both" and not prayerOnly) and ns.db.delay or 0
		if delay > 0 then
			C_Timer.After(delay, function() sendPrayer(prayer, ctx, text) end)
		else
			sendPrayer(prayer, ctx, text)
		end
	end
	return text
end

-- Performs now, or holds the rite until chat lockdown lifts.
function ns.Perform(prayer, ctx)
	if ns.InChatLockdown() then
		hold(prayer, ctx, false, "Chat is locked down; the rite will follow when it lifts.")
		return nil
	end
	return deliver(prayer, ctx, false)
end

function ns.FlushPending()
	if not pending or ns.InChatLockdown() then return end
	local rite = pending
	pending = nil
	if now() - rite.time > PENDING_TTL then
		ns.Debug("Held rite expired.")
		return
	end
	deliver(rite.prayer, rite.ctx, rite.prayerOnly)
end

function ns.OnKill(guid, rawName)
	local name = stripRealm(rawName)
	if not name then return end
	local db = ns.db
	db.kills[name] = (db.kills[name] or 0) + 1
	local count = db.kills[name]
	local ctx = ns.BuildContext(name, guid, count)

	if not db.enabled then return end
	if not ns.ZoneAllowed() then
		ns.Debug("Rites are off for " .. ns.ZoneType() .. ".")
		return
	end
	if UnitIsDeadOrGhost("player") then return end
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
function ns.TestRite(name)
	local guid
	if not name and UnitExists("target") and UnitIsPlayer("target") then
		name = stripRealm(UnitName("target"))
		guid = UnitGUID("target")
	end
	if not name then
		ns.Print("Target a player or give a name: /rites test Name")
		return
	end
	local count = (ns.db.kills[name] or 0) + 1
	ns.Perform(ns.Pick(count), ns.BuildContext(name, guid, count))
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
	if not playerGUID or attackerGUID ~= playerGUID then return end
	if type(targetGUID) ~= "string" or not targetGUID:find("^Player%-") then return end
	local _, _, _, _, _, name = GetPlayerInfoByGUID(targetGUID)
	if not name or isSecret(name) then
		ns.Debug("Couldn't read the victim's name.")
		return
	end
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

ns.OnLogin(function()
	playerGUID = UnitGUID("player")
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PARTY_KILL")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "PARTY_KILL" then
			ns.OnPartyKill(...)
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			local _, _, spellID = ...
			ns.OnSpellCast(spellID)
		elseif pending then
			-- Restrictions report inactive during this event's dispatch, so check
			-- again a moment later.
			C_Timer.After(0.5, ns.FlushPending)
		end
	end)
end)
