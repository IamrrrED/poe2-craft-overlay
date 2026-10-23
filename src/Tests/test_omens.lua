-- PoE2 Craft Overlay : Tests/test_omens.lua
-- Omens are modelled as first-class operations: each one changes exactly one rule of
-- its paired currency, and that change has to be reflected in the odds the panel shows.

local Parser = require("Item.Parser")
local Advisor = require("Craft.Advisor")
local league = require("Data.league_0_5_5")

-- Three prefixes and one suffix open: only the suffix side has room.
local PREFIXES_FULL = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
4% increased maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
]]

-- Two prefixes and two suffixes: two slots are free, so a two-modifier orb fits.
local TWO_OPEN = [[
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

-- Six modifiers: the rule for a full rare (Chaos Orb) applies.
local RARE_FULL = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
4% increased maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
+30 to Strength
]]

-- Magic item that already carries a crafted modifier (the 0.5 one-crafted-mod limit).
local MAGIC_CRAFTED = [[
Item Class: Boots
Rarity: Magic
Runed Slippers of the Whelpling
--------
Item Level: 65
--------
+25% to Movement Speed (crafted)
]]

-- Item with an implicit: Divine + Omen of the Blessed rerolls implicits only.
local WITH_IMPLICIT = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+30 to Strength (implicit)
--------
+120 to maximum Life
+45% to Fire Resistance
]]

local function findOption(advice, omenId)
	for _, option in ipairs(advice.omenOptions or { }) do
		if option.omenId == omenId then
			return option
		end
	end
	return nil
end

return function(H)
	-- Data integrity of the omen table.
	local omens = league.omens
	H.eq("omens: table present", type(omens), "table")
	local count, problems, withCurrency = 0, { }, 0
	for id, omen in pairs(omens) do
		count = count + 1
		-- English only: `ru`/`effect` were dropped with the language switch.
		for _, field in ipairs({ "en", "effectEn" }) do
			if type(omen[field]) ~= "string" or omen[field] == "" then
				problems[#problems + 1] = id .. "." .. field
			end
		end
		-- An omen either rewrites a currency or it does not touch items at all (experience on death,
		-- a Shrine, a vendor, a Strongbox). The ones that do rewrite a currency have to name one that
		-- exists, and `utility` is how the catalogue says "this one is not a crafting step".
		--
		-- The five Sagas are the other kind of non-item omen: they shape the next Expedition Logbook, so they
		-- carry `target` instead of `applies` and must never be offered for a piece of gear.
		if omen.utility or omen.notItemCrafting then
			if omen.applies ~= nil then
				problems[#problems + 1] = id .. ".not-item but applies=" .. tostring(omen.applies)
			end
			if omen.notItemCrafting and type(omen.target) ~= "string" then
				problems[#problems + 1] = id .. ".notItemCrafting without a target"
			end
		else
			withCurrency = withCurrency + 1
			if type(omen.applies) ~= "string" or omen.applies == "" then
				problems[#problems + 1] = id .. ".applies missing"
			elseif not league.currencies[omen.applies] then
				problems[#problems + 1] = id .. ".applies=" .. tostring(omen.applies)
			end
		end
		if omen.side and omen.side ~= "prefix" and omen.side ~= "suffix" then
			problems[#problems + 1] = id .. ".side=" .. tostring(omen.side)
		end
		-- "desecrated" is a real target: Omen of Light aims the Annulment at a desecrated modifier.
		local removalKinds = { lowest = true, prefix = true, suffix = true, random = true, desecrated = true }
		if omen.removal and not removalKinds[omen.removal] then
			problems[#problems + 1] = id .. ".removal=" .. tostring(omen.removal)
		end
		-- "removed" is a real state: the item exists (Standard) but a 0.5 league cannot obtain it, so the adviser
		-- must not offer it. Without this the validator would push such omens back into "core".
		if omen.status ~= "core" and omen.status ~= "league" and omen.status ~= "unverified"
			and omen.status ~= "removed" then
			problems[#problems + 1] = id .. ".status=" .. tostring(omen.status)
		end
	end
	H.eq("omens: catalogue populated", count >= 15, true)
	H.check("omens: every entry is well formed", #problems == 0, table.concat(problems, ", "))

	-- The game has 45 omens; every one of them has to be named in the ruleset, or the panel ends up
	-- advising an item the engine does not know (which is exactly what happened with Omen of Light).
	local GAME_OMENS = {
		"Amelioration", "Answered Prayers", "Bartering", "Catalysing Exaltation", "Chance",
		"Chaotic Effectiveness", "Chaotic Monsters", "Chaotic Quantity", "Chaotic Rarity", "Corruption",
		"Dextral Alchemy", "Dextral Annulment", "Dextral Coronation", "Dextral Crystallisation",
		"Dextral Erasure", "Dextral Exaltation", "Dextral Necromancy", "Gambling", "Greater Annulment",
		"Greater Exaltation", "Homogenising Coronation", "Homogenising Exaltation", "Light",
		"Putrefaction", "Recombination", "Refreshment", "Reinforcements", "Resurgence",
		"Sanctification", "Secret Compartments", "Sinistral Alchemy", "Sinistral Annulment",
		"Sinistral Coronation", "Sinistral Crystallisation", "Sinistral Erasure", "Sinistral Exaltation",
		"Sinistral Necromancy", "Whittling", "Abyssal Echoes", "the Ancients", "the Blackblooded",
		"the Blessed", "the Hunt", "the Liege", "the Sovereign",
	}
	local byName = { }
	for _, omen in pairs(omens) do
		byName[omen.en] = true
	end
	local missing = { }
	for _, short in ipairs(GAME_OMENS) do
		if not byName["Omen of " .. short] then
			missing[#missing + 1] = short
		end
	end
	H.check("omens: all 45 of the game's omens are named", #missing == 0, table.concat(missing, ", "))
	H.eq("omens: the game's list is complete", #GAME_OMENS, 45)
	H.eq("omens: Omen of Light is a real entry, not just advice text",
		(omens.omen_of_light or { }).applies, "annulment")
	H.eq("omens: and it targets desecrated modifiers", (omens.omen_of_light or { }).removal, "desecrated")
	H.eq("omens: Omen of Sanctification is described", (omens.omen_of_sanctification or { }).sanctifies, true)

	-- The desecration advice has to name the bone, not say "a bone": the bone decides which item
	-- classes can be desecrated at all, and its grade decides how good the offered modifier can be.
	-- These come from the ruleset's bones table, checked here so a typo cannot silently remove one.
	H.eq("omens: the bones are catalogued", #(league.bones or { }), 12)
	local bonesBySlot = { }
	for _, bone in ipairs(league.bones or { }) do
		bonesBySlot[bone.slot] = (bonesBySlot[bone.slot] or 0) + 1
	end
	H.eq("omens: weapon, armour and jewellery each have all three grades", bonesBySlot.weapon, 3)
	H.eq("omens: armour too", bonesBySlot.armour, 3)
	H.eq("omens: jewellery carries the altered bone as well", bonesBySlot.jewellery, 4)
	H.eq("omens: jewels and waystones have their preserved bone", bonesBySlot.jewel, 1)

	-- An armour item above the campaign cap must be offered the Preserved bone; a low-level one the
	-- Gnawed one, because Gnawed only fits items up to level 64.
	local function desecrationBoneFor(rules, itemText)
		local report = Advisor.analyze(Parser.parse(itemText), rules)
		for _, entry in ipairs(report.omenOptions or { }) do
			if entry.bone then
				return entry.bone
			end
		end
		return nil
	end
	local HIGH_ARMOUR = table.concat({
		"Item Class: Body Armours", "Rarity: Rare", "Chimeric Reflection", "Vile Robe",
		"--------", "Item Level: 82", "--------", "+120 to maximum Life",
	}, "\n")
	local LOW_ARMOUR = table.concat({
		"Item Class: Body Armours", "Rarity: Rare", "Chimeric Reflection", "Vile Robe",
		"--------", "Item Level: 40", "--------", "+40 to maximum Life",
	}, "\n")
	H.eq("omens: a high-level armour asks for the Preserved bone",
		desecrationBoneFor(league, HIGH_ARMOUR), "Preserved Rib")
	H.eq("omens: a low-level armour can use the Gnawed bone",
		desecrationBoneFor(league, LOW_ARMOUR), "Gnawed Rib")
	local WAND = table.concat({
		"Item Class: Wands", "Rarity: Rare", "Test Name", "Test Base",
		"--------", "Item Level: 80", "--------", "+50 to maximum Mana",
	}, "\n")
	H.eq("omens: a weapon asks for a jawbone", desecrationBoneFor(league, WAND), "Preserved Jawbone")

	-- Whittling removes the lowest mod level, and the overlay must name that modifier.
	local full = Advisor.analyze(Parser.parse(RARE_FULL), league)
	local whittling = findOption(full, "whittling")
	H.eq("omens: whittling offered for a full rare", whittling ~= nil, true)
	H.eq("omens: whittling is deterministic", whittling and whittling.deterministic ~= nil, true)
	H.eq("omens: whittling targets the weakest modifier",
		whittling and whittling.deterministic.text, "+22 to maximum Mana")
	-- Base-awareness check: the (20-28) mana ladder exists on staves only, so on
	-- gloves the correct tier for 22 mana is (15-24) at mod level 6, not level 1.
	H.eq("omens: whittling reports the base-correct mod level",
		whittling and whittling.deterministic.level, 6)
	H.eq("omens: whittling reports the side",
		whittling and whittling.deterministic.side, "prefix")
	H.eq("omens: whittling still shows the new roll pool",
		whittling ~= nil and whittling.pool ~= nil and #whittling.pool.groups > 0, true)

	-- Erasure restricts removal to one side: chance = 1 / modifiers on that side.
	local erasure = findOption(full, "sinistral_erasure")
	H.eq("omens: erasure offered for the same side", erasure ~= nil, true)
	H.eq("omens: erasure chance is per modifier on that side",
		erasure and math.abs(erasure.deterministic.chance - 100 / 3) < 0.01, true)

	-- Side-locked Exaltation when exactly one side is open.
	local sideOnly = Advisor.analyze(Parser.parse(PREFIXES_FULL), league)
	local dextral = findOption(sideOnly, "dextral_exaltation")
	H.eq("omens: side-locked exaltation offered", dextral ~= nil, true)
	H.eq("omens: side-locked pool follows the open side", dextral and dextral.poolSide, "suffix")

	-- Greater Exaltation rolls twice, so it needs two free slots; with a single free
	-- slot the overlay must not offer it (the affix cap would block the second roll).
	local twoOpen = Advisor.analyze(Parser.parse(TWO_OPEN), league)
	local greater = findOption(twoOpen, "greater_exaltation")
	H.eq("omens: greater exaltation offered with two slots free", greater ~= nil, true)
	H.eq("omens: greater exaltation is not offered with one slot",
		findOption(sideOnly, "greater_exaltation"), nil)
	H.eq("omens: greater exaltation rolls twice", greater and greater.multiRoll, 2)
	H.eq("omens: at-least-once odds are computed", greater ~= nil and #greater.atLeastOnce > 0, true)
	H.eq("omens: at-least-once exceeds a single roll",
		greater and greater.atLeastOnce[1].chance > greater.atLeastOnce[1].single, true)
	H.eq("omens: at-least-once stays below 100%",
		greater and greater.atLeastOnce[1].chance < 100, true)

	-- Blessed pairs with Divine for implicit rerolls.
	local implicit = Advisor.analyze(Parser.parse(WITH_IMPLICIT), league)
	H.eq("omens: blessed offered with implicits", findOption(implicit, "blessed") ~= nil, true)

	-- Desecration is a separate slot. Its pool comes from the veiled table's
	-- "breach_desecration" weights, so the overlay shows real odds (a specific bone can
	-- still narrow the offering, which is noted in the panel).
	local desecration = findOption(sideOnly, "sinistral_necromancy")
	H.eq("omens: desecration offered when a slot is free", desecration ~= nil, true)
	H.eq("omens: desecration carries a weighted pool",
		desecration ~= nil and desecration.pool ~= nil and desecration.pool.tierCount > 0, true)
	H.eq("omens: desecration does not claim unknown odds", desecration.oddsUnknown, false)

	-- One crafted modifier per item: warn when the plan would use that slot again.
	local magic = Advisor.analyze(Parser.parse(MAGIC_CRAFTED), league)
	local codes = { }
	for _, note in ipairs(magic.notes) do
		if note.code then codes[note.code] = true end
	end
	H.eq("omens: crafted slot limit warned", codes.crafted_slot_taken, true)
	H.eq("omens: crafted modifier counted", magic.craftedModCount, 1)

	-- A ruleset without omens must not break the advisor.
	local bare = {
		league = "bare",
		currencies = { exalted = { en = "Exalted Orb", ru = "Сфера", effect = "", effectEn = "", cost = "low", status = "core", adds = 1 } },
		rules = { { id = "any", when = { rarity = "RARE" }, min = { "exalted" }, max = { "exalted" } } },
	}
	local bareAdvice = Advisor.analyze(Parser.parse(RARE_FULL), bare)
	-- The list also carries the other league methods (runes, alloys), so only entries
	-- that come from the omen table are counted here.
	local bareOmens = 0
	for _, option in ipairs(bareAdvice.omenOptions) do
		if option.omenId then
			bareOmens = bareOmens + 1
		end
	end
	H.eq("omens: missing omen table yields no omen options", bareOmens, 0)
end
