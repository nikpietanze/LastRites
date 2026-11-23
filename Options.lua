-- Options under Esc > Options > AddOns > Last Rites, built from Blizzard's
-- native settings controls so it is searchable and has a Defaults button.
local _, ns = ...

local category, layout
local settings = {}

local TONES = {
	{ value = "mixed", text = "Mixed", tooltip = "A coin flip between reverent and satirical for each rite." },
	{ value = "reverent", text = "Reverent", tooltip = "Solemn, scripture-flavored last rites." },
	{ value = "satire", text = "Satirical", tooltip = "Eulogies for people who stood in the fire." },
}
local MODES = {
	{ value = "both", text = "Emote and prayer",
		tooltip = "A built-in emote like /kneel at the corpse, which both factions see, then your prayer as a /e, which only your faction can read." },
	{ value = "builtin", text = "Emote only",
		tooltip = "Just the built-in emote at the corpse. Quiet, and the enemy sees it." },
	{ value = "custom", text = "Prayer only",
		tooltip = "Just the /e prayer. The enemy faction sees \"makes some strange gestures.\"" },
}

local function register(key, varType, name, onChange)
	local variable = "LastRites_" .. key
	local setting = Settings.RegisterAddOnSetting(category, variable, key, ns.db, varType, name, ns.DEFAULTS[key])
	if onChange then
		Settings.SetOnValueChangedCallback(variable, onChange)
	end
	settings[key] = setting
	return setting
end

-- Changes an option through its registered setting, so the panel stays in sync.
function ns.SetOption(key, value)
	local setting = settings[key]
	if setting and setting.SetValue then
		setting:SetValue(value)
	else
		ns.db[key] = value
	end
end

-- Grays a control out while its parent checkbox is off.
local function dependsOn(initializer, parent, parentKey)
	if parent and initializer and initializer.SetParentInitializer then
		initializer:SetParentInitializer(parent, function() return ns.db[parentKey] end)
	end
	return initializer
end

local function checkbox(key, name, tooltip, parent, parentKey)
	local setting = register(key, Settings.VarType.Boolean, name)
	return dependsOn(Settings.CreateCheckbox(category, setting, tooltip), parent, parentKey)
end

local function dropdown(key, name, choices, tooltip, parent, parentKey)
	local setting = register(key, Settings.VarType.String, name)
	local initializer = Settings.CreateDropdown(category, setting, function()
		local container = Settings.CreateControlTextContainer()
		for _, choice in ipairs(choices) do
			container:Add(choice.value, choice.text, choice.tooltip)
		end
		return container:GetData()
	end, tooltip)
	return dependsOn(initializer, parent, parentKey)
end

local function slider(key, name, min, max, step, format, tooltip, parent, parentKey)
	local setting = register(key, Settings.VarType.Number, name)
	local options = Settings.CreateSliderOptions(min, max, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return format:format(value)
	end)
	return dependsOn(Settings.CreateSlider(category, setting, options, tooltip), parent, parentKey)
end

local function header(text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function button(name, text, onClick, tooltip)
	layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
end

ns.OnLoad(function()
	category, layout = Settings.RegisterVerticalLayoutCategory("Last Rites")
	layout = layout or SettingsPanel:GetLayout(category)

	header("Rites")

	local enabled = checkbox("enabled", "Perform last rites",
		"Emote over enemy players when you land the killing blow.")
	dropdown("tone", "Tone", TONES, "How the prayers read.", enabled, "enabled")
	dropdown("mode", "What to perform", MODES,
		"The built-in emote is what the other faction sees. The prayer is the funny part, for your side.",
		enabled, "enabled")

	header("Where")

	checkbox("battlegrounds", "Battlegrounds", "Perform rites in battlegrounds.", enabled, "enabled")
	checkbox("arenas", "Arenas", "Perform rites in arenas.", enabled, "enabled")
	checkbox("world", "World PvP", "Perform rites outside instances.", enabled, "enabled")

	header("Timing")

	slider("chance", "Chance per kill", 5, 100, 5, "%d%%",
		"How often a killing blow gets a rite. Lower it if you kill a lot of people.", enabled, "enabled")
	slider("cooldown", "Cooldown", 0, 120, 5, "%ds",
		"The shortest time between two rites. Kills during the cooldown are still counted.", enabled, "enabled")
	slider("delay", "Pause before the prayer", 0, 5, 0.5, "%.1fs",
		"Wait this long after the built-in emote before the prayer. Only used with Emote and prayer. If chat locks down for addons during the pause, the prayer is skipped.",
		enabled, "enabled")

	header("Nemesis")

	local nemesis = checkbox("nemesisEnabled", "Nemesis lines",
		"Special lines for players you keep killing. They mention how many times.", enabled, "enabled")
	slider("nemesis", "Kills to become a nemesis", 2, 20, 1, "%d",
		"How many times you kill the same player before nemesis lines take over.", nemesis, "nemesisEnabled")

	button("Preview a rite", "Preview", function() ns.Preview() end,
		"Print a sample rite in your chat window. Only you see it.")
	button("Test on your target", "Test", function() ns.TestRite() end,
		"Perform a real rite on your current target, so you can see how it looks. Everyone nearby sees it.")
	button("Your nemeses", "Show", function() ns.Commands.stats() end,
		"Print the players you've killed most on this character.")
	button("Reset kill counts", "Reset", function()
		ns.db.kills = {}
		ns.Print("Kill counts cleared for this character.")
	end, "Forget how many times you've killed each player.")

	Settings.RegisterAddOnCategory(category)
end)

function ns.OpenOptions()
	if category then
		Settings.OpenToCategory(category:GetID())
	end
end
