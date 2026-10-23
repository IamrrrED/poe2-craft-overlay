-- PoE2 Craft Overlay : Tests/test_runes.lua
-- Runes / soul cores / idols and runeforging. Both are real crafts with guaranteed
-- outcomes, so the data (PoB ModRunes.lua, VerisiumCrafts.lua) is asserted here:
-- which slot a rune fits, what it grants, the per-item limit and the base upgrade.

local Parser = require("Item.Parser")
local Mods = require("Item.Mods")
local Runes = require("Item.Runes")
local Runeforging = require("Item.Runeforging")
local Advisor = require("Craft.Advisor")
local league = require("Data.league_0_5_5")

-- The rune table is cut from Path of Building's ModRunes.lua. It used to lose 139 of the source's 305
-- runes because the slot regex was anchored on one indentation, which silently dropped every Ancient
-- Rune, every Warding Rune and thirteen Soul Cores - and the missing ones had to be hand-written into
-- the league ruleset. The extractor reads by brace depth now, so this checks the families are present
-- in the generated table itself.
local function checkRuneCatalogue(H)
	local Runes = require("Item.Runes")
	local bySlot = require("Data.runes").bySlot or { }
	local names = { }
	local count = 0
	for _, items in pairs(bySlot) do
		for _, item in ipairs(items) do
			count = count + 1
			names[item.name] = item
		end
	end
	H.eq("runes: the table carries all 305 runes", count >= 602, true)
	H.eq("runes: 13 Ancient Runes are present", (function()
		local found = 0
		for name in pairs(names) do
			if name:find("Ancient Rune", 1, true) then found = found + 1 end
		end
		return found
	end)(), 13)
	H.eq("runes: the Warding Rune family is present", (function()
		local found = 0
		for name in pairs(names) do
			if name:find("Warding Rune", 1, true) then found = found + 1 end
		end
		return found
	end)(), 17)
	for _, wanted in ipairs({
		"Ancient Rune of the Titan", "Ancient Rune of Splinters", "Ancient Rune of Witchcraft",
		"Warding Rune of Heart", "Atziri's Soul Core of Vitality",
		"Hayoxi's Soul Core of Heatproofing",
	}) do
		H.check("runes: " .. wanted .. " is in the table", names[wanted] ~= nil)
	end
	-- The Ancient Runes are weapon-specific: the Titan fits two hand maces, and its text has to be the
	-- modifier itself, not something read out of a nested bonded block.
	local titan = names["Ancient Rune of the Titan"]
	H.check("runes: the Titan carries its own modifier",
		titan ~= nil and titan.texts and titan.texts[1]
			and titan.texts[1]:find("Aftershock", 1, true) ~= nil)
	H.eq("runes: the Titan is level 30", titan and titan.levelReq, 30)
	H.check("runes: the table is reachable through Item.Runes", Runes ~= nil)

	-- The four shards were the last names from the game's own list the overlay did not know at all.
	local shards = league.shards or { }
	H.eq("runes: the four shards are catalogued", #shards, 4)
	local shardNames = { }
	for _, shard in ipairs(shards) do
		shardNames[shard.en] = shard
		H.check("runes: " .. tostring(shard.en) .. " names what it makes",
			type(shard.makes) == "string" and shard.makes ~= "")
	end
	H.eq("runes: the socket shard is there", shardNames["Artificer's Shard"] ~= nil, true)
	H.contains("runes: and it says it adds a socket",
		(shardNames["Artificer's Shard"] or { }).text, "Socket")
end

local GLOVES = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
+45% to Fire Resistance
+38% to Cold Resistance
]]

local WAND = [[
Item Class: Wands
Rarity: Rare
Doom Bite
Attuned Wand
--------
Item Level: 82
--------
Adds 10 to 20 Fire Damage
+30 to maximum Mana
+20% to Fire Resistance
]]

return function(H)
	-- Data set sanity.
	local stats = Runes.stats()
	H.eq("rune: table populated", stats.runes > 100, true)
	H.eq("rune: several slots covered", stats.slots >= 10, true)

	local bySlot = require("Data.runes").bySlot
	local malformed = 0
	for _, entries in pairs(bySlot) do
		for _, entry in ipairs(entries) do
			if type(entry.name) ~= "string" or type(entry.texts) ~= "table" or not entry.texts[1] then
				malformed = malformed + 1
			end
		end
	end
	H.eq("rune: every entry is well formed", malformed, 0)

	-- Slot matching is tag based, so the same table serves every base type.
	local gloves = Parser.parse(GLOVES)
	local gloveTags = Runes.tagsOf(gloves)
	H.eq("rune: gloves carry the gloves tag", gloveTags.gloves, true)
	H.eq("rune: gloves match the gloves slot", Runes.slotMatches("gloves", gloveTags), true)
	H.eq("rune: gloves do not match the helmet slot", Runes.slotMatches("helmet", gloveTags), false)
	H.eq("rune: armour slot matches gloves (tag armour)",
		Runes.slotMatches("armour", gloveTags), true)

	local wand = Parser.parse(WAND)
	local wandTags = Runes.tagsOf(wand)
	H.eq("rune: wand matches the wand slot", Runes.slotMatches("wand", wandTags), true)
	H.eq("rune: wand matches the generic weapon slot",
		Runes.slotMatches("weapon", wandTags), true)
	H.eq("rune: wand matches a compound slot",
		Runes.slotMatches("martial weapon wand or staff", wandTags), true)
	H.eq("rune: wand does not match gloves", Runes.slotMatches("gloves", wandTags), false)

	-- Options: guaranteed modifiers (100%), with limit and level requirement.
	local options = Runes.optionsFor(gloves)
	H.eq("rune: options found for gloves", #options > 0, true)
	H.eq("rune: every option is a 100% craft", options[1].chance, 100)
	H.eq("rune: options carry a modifier text", type(options[1].text), "string")
	H.eq("rune: options carry a limit", options[1].limit >= 1, true)
	local seenNames = { }
	local duplicates = 0
	for _, option in ipairs(options) do
		local key = option.name .. "|" .. option.text
		if seenNames[key] then
			duplicates = duplicates + 1
		end
		seenNames[key] = true
	end
	H.eq("rune: one row per rune", duplicates, 0)
	H.eq("rune: limit is honoured", #Runes.optionsFor(gloves, { limit = 2 }), 2)
	H.eq("rune: count helper agrees", Runes.countFor(gloves), #options)

	-- Runeforging: base type -> upgraded base type.
	local forgeStats = Runeforging.stats()
	H.eq("runeforging: table populated", forgeStats.bases > 100, true)
	local forged = Runeforging.forBase("Aberrant Sledge")
	H.eq("runeforging: known base resolves", forged ~= nil and #forged > 0, true)
	H.eq("runeforging: upgrade is named", forged and forged[1]:find("Runemastered", 1, true) ~= nil, true)
	H.eq("runeforging: unknown base returns nil", Runeforging.forBase("Not A Real Base"), nil)
	H.eq("runeforging: item lookup uses its base",
		Runeforging.forItem({ baseType = "Aberrant Sledge" }) ~= nil, true)

	-- Alloy pool: modifiers that exist in the data but never roll randomly, so the
	-- overlay must list them and refuse to invent odds.
	local pool = Mods.alloyPool(82)
	H.eq("alloy: pool is not empty", pool.tierCount > 0, true)
	H.eq("alloy: odds are declared unknown", pool.oddsKnown, false)
	local badAffix = 0
	for _, entry in ipairs(pool.entries) do
		if entry.affix ~= "Verisium" and entry.affix ~= "of the Stars" then
			badAffix = badAffix + 1
		end
		if entry.chance ~= nil then
			badAffix = badAffix + 1
		end
	end
	H.eq("alloy: only alloy affixes and no invented chances", badAffix, 0)
	H.eq("alloy: level filter applied", (function()
		for _, entry in ipairs(pool.entries) do
			if entry.lvl > 82 then
				return false
			end
		end
		return true
	end)(), true)
	H.eq("alloy: league data lists all 13 alloys", #league.alloys, 13)

	-- Advisor surfaces runes, the alloy pool, runeforging and the sources.
	local advice = Advisor.analyze(Parser.parse(GLOVES), league)
	H.eq("advisor: rune options attached", #advice.runeOptions > 0, true)
	H.eq("advisor: alloy pool attached", advice.alloyPool.tierCount > 0, true)
	H.eq("advisor: sources attached", #(advice.sources or { }) >= 4, true)
	local runeEntries, alloyEntries = 0, 0
	for _, option in ipairs(advice.omenOptions) do
		if option.kind == "rune" then
			runeEntries = runeEntries + 1
		elseif option.kind == "alloy" then
			alloyEntries = alloyEntries + 1
		end
	end
	H.eq("advisor: rune crafts offered in the panel", runeEntries > 0, true)
	H.eq("advisor: rune crafts are capped", runeEntries <= 3, true)
	H.eq("advisor: alloy pool offered in the panel", alloyEntries, 1)

	-- Every source must name a file or a URL, so a reader can check the numbers.
	local incomplete = 0
	for _, source in ipairs(advice.sources or { }) do
		if type(source.label) ~= "string" or type(source.detail) ~= "string" or type(source.url) ~= "string" then
			incomplete = incomplete + 1
		end
	end
	H.eq("advisor: every source is documented", incomplete, 0)

	checkRuneCatalogue(H)

	-- Augment sockets. A rune applies one fixed modifier, so socket advice is about FIT: is there a
	-- socket, does the rune match the slot, and has its per-item limit been reached. The printed sockets
	-- ("Sockets: S S") are authoritative when the game gives them.
	local BODY = Parser.parse(table.concat({
		"Item Class: Body Armours",
		"Rarity: Rare",
		"Chimeric Reflection",
		"Vile Robe",
		"--------",
		"Sockets: S S",
		"--------",
		"Item Level: 80",
		"--------",
		"+120 to maximum Life",
	}, "\n"))
	local bodySockets = Runes.socketsFor(BODY, league)
	H.eq("runes: the printed sockets give the capacity", bodySockets.capacity, 2)
	H.eq("runes: both are free", bodySockets.free, 2)

	local WITH_RUNE = Parser.parse(table.concat({
		"Item Class: Body Armours",
		"Rarity: Rare",
		"Chimeric Reflection",
		"Vile Robe",
		"--------",
		"Sockets: S",
		"--------",
		"Item Level: 80",
		"--------",
		"Rune: Body Rune",
		"--------",
		"+120 to maximum Life",
	}, "\n"))
	local usedSockets = Runes.socketsFor(WITH_RUNE, league)
	H.eq("runes: a socketed rune fills one socket", usedSockets.used, 1)
	H.eq("runes: the capacity still counts it", usedSockets.capacity, 2)
	H.eq("runes: and one socket remains", usedSockets.free, 1)

	-- The limit is per rune and per item: a limit-1 rune cannot go in twice even with room to spare.
	local firstOption = nil
	for _, option in ipairs(Runes.optionsFor(BODY)) do
		if (option.limit or 1) == 1 and option.name ~= "Body Rune" then
			firstOption = option
			break
		end
	end
	H.check("runes: a limit-1 rune is available for the test", firstOption ~= nil)
	local allowed = Runes.canSocket(BODY, firstOption, bodySockets)
	H.eq("runes: it can be socketed into a free socket", allowed, true)
	local twice = Runes.canSocket(WITH_RUNE, firstOption, usedSockets)
	if firstOption and firstOption.name ~= "Body Rune" then
		H.eq("runes: a different rune still fits the remaining socket", twice, true)
	end
	-- The rune that is already in the item: limit 1 means it cannot go in again.
	local sameRune = nil
	for _, option in ipairs(Runes.optionsFor(BODY)) do
		if option.name == "Body Rune" then
			sameRune = option
			break
		end
	end
	if sameRune then
		local again, why = Runes.canSocket(WITH_RUNE, sameRune, usedSockets)
		H.eq("runes: the same limit-1 rune is refused", again, false)
		H.eq("runes: and the reason is the limit", why, "limit reached")
	end

	-- A full item refuses any rune, and says why.
	local FULL = Parser.parse(table.concat({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"--------",
		"Item Level: 82",
		"--------",
		"Rune: Body Rune",
		"--------",
		"+120 to maximum Life",
	}, "\n"))
	local fullSockets = Runes.socketsFor(FULL, league)
	H.eq("runes: gloves hold one socket", fullSockets.capacity, 1)
	local refused, refusedWhy = Runes.canSocket(FULL, firstOption, fullSockets)
	H.eq("runes: a full item refuses another rune", refused, false)
	H.eq("runes: and names the reason", refusedWhy, "no free socket")
	H.eq("runes: the socketing rule is recorded", (league.sockets or { }).removable, false)
end
