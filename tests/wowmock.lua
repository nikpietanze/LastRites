-- A fake WoW Forever client: just enough API to load LastRites from its TOC
-- and drive it with events. Run the tests from the repo root.
local M = {}

-- A stand-in for the client's secret values.
M.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local function tocFiles(root)
	local files = {}
	for line in io.lines(root .. "/LastRites.toc") do
		line = line:gsub("\r", "")
		if line ~= "" and not line:find("^#") then files[#files + 1] = line end
	end
	return files
end

function M.install(root, savedDB)
	local W = {
		time = 1000,
		emotes = {}, -- { token, target }
		chat = {}, -- { text, channel }
		printed = {},
		timers = {},
		target = nil, -- { name, guid, player = true }
		zone = "Warsong Gulch",
		instance = { false, "none" },
		dead = false,
		lockdown = false,
		players = {}, -- [guid] = { class, race, name }
		harmful = {}, -- [spellID] = true
		spells = {}, -- [spellID] = name
		frames = {},
		settings = {}, -- [key] = { setting, kind, name, default }
		buttons = {},
		openedCategory = nil,
	}

	_G.issecretvalue = function(v) return v == M.SECRET end
	_G.GetTime = function() return W.time end
	_G.GetBuildInfo = function() return "1.60.1", "99999", "Nov 1 2026", 16001 end
	_G.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
	_G.UnitGUID = function(unit)
		if unit == "player" then return "Player-1-PLAYER" end
		if unit == "target" and W.target then return W.target.guid end
	end
	_G.UnitName = function(unit)
		if unit == "player" then return "Nik" end
		if unit == "target" and W.target then return W.target.name end
	end
	_G.UnitExists = function(unit) return unit == "player" or (unit == "target" and W.target ~= nil) end
	_G.UnitIsUnit = function(a, b) return a == b end
	_G.UnitIsPlayer = function(unit) return unit == "player" or (unit == "target" and W.target and W.target.player ~= false) end
	_G.UnitIsDeadOrGhost = function() return W.dead end
	_G.IsInInstance = function() return W.instance[1], W.instance[2] end
	_G.GetRealZoneText = function() return W.zone end
	_G.GetPlayerInfoByGUID = function(guid)
		local p = W.players[guid]
		if p then return p.class, "X", p.race, "X", 2, p.name, "Realm" end
	end
	_G.C_Spell = {
		GetSpellName = function(id) return W.spells[id] end,
		IsSpellHarmful = function(id) return W.harmful[id] == true end,
	}
	_G.C_ChatInfo = {
		PerformEmote = function(token, target) W.emotes[#W.emotes + 1] = { token, target }; return true end,
		SendChatMessage = function(text, channel) W.chat[#W.chat + 1] = { text, channel } end,
		InChatMessagingLockdown = function() return W.lockdown end,
	}
	_G.C_Timer = { After = function(delay, fn) W.timers[#W.timers + 1] = { at = W.time + delay, fn = fn } end }
	_G.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
		W.printed[#W.printed + 1] = table.concat(parts, " ")
	end
	_G.GameTooltip = setmetatable({}, { __index = function() return function() end end })
	_G.SlashCmdList = {}
	_G.CreateFrame = function()
		local f = { events = {} }
		function f:RegisterEvent(e) self.events[e] = true end
		function f:RegisterUnitEvent(e) self.events[e] = true end
		function f:UnregisterEvent(e) self.events[e] = nil end
		function f:SetScript(_, fn) self.onEvent = fn end
		W.frames[#W.frames + 1] = f
		return f
	end

	-- Native settings panel stubs.
	local currentCategory
	local function initializer() return { SetParentInitializer = function(self, parent) self.parent = parent end } end
	_G.Settings = {
		VarType = { Boolean = "boolean", String = "string", Number = "number" },
		RegisterVerticalLayoutCategory = function(name)
			currentCategory = { name = name, GetID = function() return name end }
			return currentCategory, { AddInitializer = function(_, init) W.buttons[#W.buttons + 1] = init end }
		end,
		RegisterAddOnSetting = function(_, variable, key, tbl, varType, name, default)
			local setting = { key = key, variable = variable }
			function setting:SetValue(v) tbl[key] = v end
			W.settings[key] = { setting = setting, kind = varType, name = name, default = default }
			return setting
		end,
		SetOnValueChangedCallback = function() end,
		CreateCheckbox = initializer,
		CreateDropdown = initializer,
		CreateSlider = initializer,
		CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
		CreateControlTextContainer = function() return { Add = function() end, GetData = function() end } end,
		RegisterAddOnCategory = function(cat) W.registeredCategory = cat end,
		OpenToCategory = function(id) W.openedCategory = id end,
	}
	_G.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
	_G.CreateSettingsListSectionHeaderInitializer = function(text) return { header = text } end
	_G.CreateSettingsButtonInitializer = function(name, text, onClick) return { button = name, onClick = onClick } end

	function W.fire(event, ...)
		for _, f in ipairs(W.frames) do
			if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
		end
	end
	function W.advance(seconds)
		W.time = W.time + seconds
		local due = {}
		for i = #W.timers, 1, -1 do
			if W.timers[i].at <= W.time then
				table.insert(due, 1, table.remove(W.timers, i))
			end
		end
		for _, t in ipairs(due) do t.fn() end
	end
	function W.clear() W.emotes, W.chat, W.printed = {}, {}, {} end
	function W.slash(msg) SlashCmdList.LASTRITES(msg) end

	_G.LastRitesDB = savedDB
	local ns = {}
	for _, file in ipairs(tocFiles(root)) do
		assert(loadfile(root .. "/" .. file))("LastRites", ns)
	end
	W.ns = ns
	W.fire("ADDON_LOADED", "LastRites")
	W.fire("PLAYER_LOGIN")
	return W
end

return M
