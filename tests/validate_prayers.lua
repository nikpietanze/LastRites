-- Usage: lua5.1 tests/validate_prayers.lua [repo root]
-- Validates every prayer: 10-20 words as shown in chat (names count as two
-- words, since Forever names carry a surname),
-- fits WoW's 255-char chat limit at worst case, known emotes & placeholders.
local root = arg[1] or "."
local ns = {}
-- Load Prayers.lua and the class files in TOC order.
for line in io.lines(root .. "/LastRites.toc") do
	line = line:gsub("\r", "")
	if line == "Prayers.lua" or line:find("^Classes[\\/]") then
		assert(loadfile(root .. "/" .. line:gsub("\\", "/")))("LastRites", ns)
	end
end
local P = ns.Prayers
local CLASSES = { "WARRIOR", "PALADIN", "PRIEST", "SHAMAN", "DRUID", "ROGUE", "MAGE", "WARLOCK", "HUNTER" }

local MIN_WORDS, MAX_WORDS = 10, 20
local EMOTES = {
	PRAY = 1, KNEEL = 1, BOW = 1, SALUTE = 1, MOURN = 1, PITY = 1, VIOLIN = 1,
	GLOAT = 1, COMFORT = 1, SIGH = 1, CRY = 1, SHRUG = 1,
}
local WORST = {
	name = "Abcdefghijkl Mnopqrstuvwx", class = "Demon Hunter", race = "Highmountain Tauren",
	zone = "The Temple of Atal'Hakkar Sunken Depths", spell = "Righteous Defense of the Ancients",
	count = "1000", nth = "1000th",
}

local function words(s)
	local n = 0
	for tok in s:gmatch("%S+") do
		if tok:find("[%w{]") then n = n + 1 end
	end
	return n
end

-- Your faction sees the built-in emote and the line together, so a line must
-- follow on from its emote instead of restating it ("/kneel" then "kneels...").
local EMOTE_VERBS = {
	PRAY = { "pray" }, KNEEL = { "kneel" }, BOW = { "bow" }, SALUTE = { "salut" }, MOURN = { "mourn" },
	PITY = { "pit", "regards" }, VIOLIN = { "plays", "fiddles" }, GLOAT = { "gloat" }, COMFORT = { "comfort", "consol" },
	SIGH = { "sigh" }, CRY = { "weep", "cries", "cry" }, SHRUG = { "shrug" },
}

local errors, total, hist = {}, 0, {}
local seen = {}

local function check(label, pool)
	for i, entry in ipairs(pool) do
		total = total + 1
		local token, text = entry[1], entry[2]
		local where = ("%s #%d"):format(label, i)
		-- As shown in chat: Forever names carry a surname, so your auto-prefixed
		-- name and each {name} count as two words.
		local _, nameCount = text:gsub("{name}", "")
		local w = words(text) + 2 + nameCount
		hist[w] = (hist[w] or 0) + 1
		if w < MIN_WORDS or w > MAX_WORDS then
			errors[#errors + 1] = ("%s: %d words: %s"):format(where, w, text)
		end
		if not EMOTES[token] then
			errors[#errors + 1] = ("%s: unknown emote %s"):format(where, tostring(token))
		end
		for key in text:gmatch("{(%w+)}") do
			if not WORST[key] then errors[#errors + 1] = ("%s: unknown placeholder {%s}"):format(where, key) end
		end
		local filled = text:gsub("{(%w+)}", WORST)
		if #filled > 255 then
			errors[#errors + 1] = ("%s: %d chars at worst case"):format(where, #filled)
		end
		if text:sub(1, 1):match("%u") and not text:match("^{") then
			errors[#errors + 1] = ("%s: should start lowercase (your name is prefixed): %s"):format(where, text)
		end
		local first = (text:match("^(%a+)") or ""):lower()
		for _, stem in ipairs(EMOTE_VERBS[token] or {}) do
			if first:sub(1, #stem) == stem then
				errors[#errors + 1] = ("%s: restates its /%s emote: %s"):format(where, token:lower(), text)
			end
		end
		if seen[text] then errors[#errors + 1] = ("%s: duplicate of %s"):format(where, seen[text]) end
		seen[text] = where
	end
end

check("reverent", P.reverent)
check("satire", P.satire)
check("nemesis.reverent", P.nemesis.reverent)
check("nemesis.satire", P.nemesis.satire)
local classCounts = {}
for _, class in ipairs(CLASSES) do
	local pools = ns.ClassPrayers and ns.ClassPrayers[class]
	if not pools then
		errors[#errors + 1] = "missing class file for " .. class
	else
		check(class:lower() .. ".reverent", pools.reverent or {})
		check(class:lower() .. ".satire", pools.satire or {})
		classCounts[#classCounts + 1] = ("%s %d+%d"):format(class:lower(), #(pools.reverent or {}), #(pools.satire or {}))
	end
end

print(("reverent %d | satire %d | nemesis %d + %d | total %d"):format(
	#P.reverent, #P.satire, #P.nemesis.reverent, #P.nemesis.satire, total))
local dist = {}
for w = MIN_WORDS - 3, MAX_WORDS + 3 do
	if hist[w] then dist[#dist + 1] = w .. "w:" .. hist[w] end
end
print("word counts: " .. table.concat(dist, "  "))
print("class lines (reverent+satire): " .. table.concat(classCounts, "  "))

if #errors > 0 then
	for _, e in ipairs(errors) do print("FAIL " .. e) end
	print(#errors .. " problem(s)")
	os.exit(1)
end
print("all prayers valid")
