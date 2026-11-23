-- Last Rites: a short funeral emote over the players you kill in PvP.

local ADDON_NAME, ns = ...

ns.COLOR = "d4af37"

local DB_VERSION = 3
ns.DEFAULTS = {
	enabled = true,
	tone = "mixed", -- "reverent" | "satire" | "mixed"
	mode = "both", -- "both" (emote + prayer) | "builtin" (emote only) | "custom" (prayer only)
	avoidPoses = true, -- Skip lines whose emote holds you in a pose (/kneel).
	classLines = true, -- Mix in lines themed on your own class.
	-- Where
	battlegrounds = true,
	arenas = true,
	world = true,
	-- Timing
	chance = 100, -- Percent of eligible kills that get a rite.
	cooldown = 20, -- Seconds between rites.
	-- Nemesis
	nemesisEnabled = true,
	nemesis = 3, -- Kills on the same player before nemesis lines take over.
	kills = {}, -- Kill count by player name.
	debug = false,
}

local loadCallbacks, loginCallbacks = {}, {}
function ns.OnLoad(fn) loadCallbacks[#loadCallbacks + 1] = fn end
function ns.OnLogin(fn) loginCallbacks[#loginCallbacks + 1] = fn end

function ns.Print(message)
	print("|cff" .. ns.COLOR .. "Last Rites|r " .. tostring(message))
end

function ns.Debug(message)
	if ns.db and ns.db.debug then
		ns.Print("|cff888888" .. tostring(message) .. "|r")
	end
end

function ns.Version()
	local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	local version = getMetadata and getMetadata(ADDON_NAME, "Version")
	-- Split the token so the packager only substitutes it in the TOC.
	if not version or version == "@project" .. "-version@" then
		return "dev"
	end
	return version
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[k] = copy(v) end
	return out
end

function ns.Migrate(db)
	-- Versions 1 and 2 had a pause before the prayer. The prayer now goes out
	-- on your next key press, which is pause enough.
	db.delay = nil
	for key, value in pairs(ns.DEFAULTS) do
		if db[key] == nil then
			db[key] = copy(value)
		end
	end
	if not ns.TONES[db.tone] then db.tone = ns.DEFAULTS.tone end
	if not ns.MODES[db.mode] then db.mode = ns.DEFAULTS.mode end
	db.version = DB_VERSION
	return db
end

ns.TONES = { reverent = true, satire = true, mixed = true }
ns.MODES = { both = true, builtin = true, custom = true }

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" then
		if name ~= ADDON_NAME then return end
		self:UnregisterEvent("ADDON_LOADED")
		LastRitesDB = ns.Migrate(LastRitesDB or {})
		ns.db = LastRitesDB
		for _, fn in ipairs(loadCallbacks) do fn() end
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		for _, fn in ipairs(loginCallbacks) do fn() end
	end
end)

local function printStatus()
	local version, build, _, interface = GetBuildInfo()
	ns.Print(("%s on client %s (%s), interface %s"):format(ns.Version(), tostring(version), tostring(build),
		tostring(interface)))
	local d = ns.db
	print(("  %s | tone=%s mode=%s | bg=%s arena=%s world=%s | chance=%d%% cooldown=%ds | nemesis=%s at %d"):format(
		d.enabled and "on" or "off", d.tone, d.mode, tostring(d.battlegrounds), tostring(d.arenas),
		tostring(d.world), d.chance, d.cooldown, tostring(d.nemesisEnabled), d.nemesis))
	print(("  zone=%s allowed=%s chatLockdown=%s debug=%s"):format(ns.ZoneType(),
		tostring(ns.ZoneAllowed()), tostring(ns.InChatLockdown()), tostring(d.debug)))
end

local function printStats()
	local list = {}
	for name, count in pairs(ns.db.kills) do list[#list + 1] = { name, count } end
	if #list == 0 then
		ns.Print("No kills recorded on this character yet.")
		return
	end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		return a[1] < b[1]
	end)
	ns.Print(("Most prayed for (%d players):"):format(#list))
	for i = 1, math.min(10, #list) do
		print(("  %d. %s - %d"):format(i, list[i][1], list[i][2]))
	end
end

-- Addon compartment (the addons button by the minimap).
function LastRites_OnCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then
		ns.Preview()
	else
		ns.OpenOptions()
	end
end

function LastRites_OnCompartmentEnter(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText("Last Rites")
	GameTooltip:AddDoubleLine("Left-click", "Options", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine("Right-click", "Preview a rite", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:Show()
end

function LastRites_OnCompartmentLeave()
	GameTooltip:Hide()
end

local function setEnabled(value)
	if ns.SetOption then ns.SetOption("enabled", value) else ns.db.enabled = value end
	ns.Print(value and "Rites on." or "Rites off.")
end

local commands = {
	on = function() setEnabled(true) end,
	off = function() setEnabled(false) end,
	preview = function(args)
		local name, kills = args:match("^(%S*)%s*(%d*)$")
		ns.Preview(name ~= "" and name or nil, tonumber(kills))
	end,
	test = function(args) ns.TestRite(args ~= "" and args or nil, true) end,
	stats = printStats,
	keytest = function() ns.KeyTest() end,
	status = printStatus,
	debug = function()
		ns.db.debug = not ns.db.debug
		ns.Print("Debug " .. (ns.db.debug and "on: kill events will be printed." or "off."))
	end,
}

ns.Commands = commands

SLASH_LASTRITES1 = "/rites"
SLASH_LASTRITES2 = "/lastrites"
SlashCmdList.LASTRITES = function(input)
	local command, args = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = command:lower()
	if command == "" or command == "options" or command == "config" then
		ns.OpenOptions()
	elseif commands[command] then
		commands[command](args)
	else
		ns.Print("Commands: /rites [options | on | off | preview [name] [kills] | test [name] | stats | keytest | status | debug]")
	end
end
