-- PoE2 Craft Overlay : Tests/test_advisor.lua
-- Rules are data, so the advisor is tested against both the shipped league file
-- and a synthetic ruleset (to prove the module has no hidden coupling).

local Parser = require("Item.Parser")
local Advisor = require("Craft.Advisor")

local RARE_OPEN = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
]]

-- A realistic full rare: three prefixes and three suffixes (verified against
-- Data/mods.lua group types), so every affix slot is genuinely taken.
local RARE_FULL = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
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

local RARE_CORRUPTED = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
--------
Corrupted
]]

local NORMAL = [[
Item Class: Bows
Rarity: Normal
Composite Bow
--------
Item Level: 55
]]

local UNIQUE = [[
Item Class: Body Armours
Rarity: Unique
Widowhail
Ornate Quiver
--------
Item Level: 70
--------
+50 to maximum Life
]]

-- Five affixes with all three prefix slots taken: only suffixes can be added now.
-- (Ranges verified against Data/mods.lua: IncreasedLife, IncreasedMana,
--  MaximumLifeIncreasePercent are Prefix; Fire/Cold resistance are Suffix.)
local PREFIXES_FULL = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
4% increased maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
]]

-- Mirror case: all three suffix slots taken, prefixes still open.
local SUFFIXES_FULL = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
+45% to Fire Resistance
+38% to Cold Resistance
+30 to Strength
]]

return function(H)
	local league = require("Data.league_0_5_5")

	-- Sanity of the shipped data file.
	H.eq("data: league name present", type(league.league), "string")
	H.eq("data: currencies present", type(league.currencies.transmutation), "table")
	H.eq("data: rules non-empty", #league.rules > 0, true)

	-- Every currency referenced by a rule must exist in the catalog.
	local missing = { }
	for _, rule in ipairs(league.rules) do
		for _, key in ipairs({ "min", "max" }) do
			for _, currencyId in ipairs(rule[key] or { }) do
				if not league.currencies[currencyId] then
					missing[#missing + 1] = rule.id .. "/" .. currencyId
				end
			end
		end
	end
	H.eq("data: all rule currencies exist", #missing, 0)

	local open = Advisor.analyze(Parser.parse(RARE_OPEN), league)
	H.eq("advisor: open rare -> rule", open.ruleId, "rare_open_affix")
	H.eq("advisor: open rare -> affix count", open.affixes, 3)
	H.eq("advisor: open rare -> open slots", open.openAffixes, 3)
	H.eq("advisor: min plan exists", open.plans[1].id, "min")
	H.eq("advisor: max plan exists", open.plans[2].id, "max")
	-- Quality comes AFTER the modifier steps, by the customer's rule: "quality last, right before the step
	-- after which nothing can be done". Vaal is that step, and it belongs to the MAX plan only: on the MIN
	-- plan it was the immediate follow-up to a single move, which is far too soon for a one-way step.
	local openSteps = open.plans[1].steps
	H.eq("advisor: the modifier step is first", openSteps[1].id, "exalted")
	-- The minimal plan carries the value reroll followed by quality, so quality has the reroll to follow.
	H.eq("advisor: then the value reroll", openSteps[2].id, "divine")
	H.eq("advisor: and the minimal plan closes with quality", openSteps[#openSteps].id, "scrap")
	H.eq("advisor: nothing else was added", #openSteps, 3)
	local openMax = open.plans[2].steps
	H.eq("advisor: the maximum plan ends with the Vaal Orb", openMax[#openMax].id, "vaal")
	-- Quality goes AFTER the value reroll, by the customer's rule: it multiplies the item's own numbers, so
	-- it is worth most once those numbers are final.
	H.eq("advisor: with the value reroll before quality", openMax[#openMax - 2].id, "divine")
	H.eq("advisor: and quality right after it", openMax[#openMax - 1].id, "scrap")
	local minHasVaal = false
	for _, step in ipairs(openSteps) do
		if step.id == "vaal" then minHasVaal = true end
	end
	H.eq("advisor: the minimal plan never offers Vaal", minHasVaal, false)
	-- The reason now reaches the panel in Russian: English used to win even when a Russian
	-- explanation existed, which is the leak this test used to encode.
	local openReason = open.plans[1].reason or ""
	H.check("advisor: min plan has a description",
		openReason:find("Экзальт", 1, true) ~= nil
			or openReason:find("Exalted", 1, true) ~= nil, openReason)

	local full = Advisor.analyze(Parser.parse(RARE_FULL), league)
	H.eq("advisor: full rare -> rule", full.ruleId, "rare_full")
	H.eq("advisor: full rare -> no open slots", full.openAffixes, 0)
	-- The "no free slots" rule must require no free slots. It used to match ANY rare, so it acted as the
	-- catch-all for a rare that matched nothing else: the customer's sceptre had five modifiers and an
	-- open suffix, and the panel answered with a Chaos reroll.
	local SCEPTRE = table.concat({
		"Item Class: Sceptres",
		"Rarity: Rare",
		"Dire Growth",
		"Rattling Sceptre",
		"--------",
		"Spirit: 114 (augmented)",
		"--------",
		"Item Level: 79",
		"--------",
		'{ Prefix Modifier "of the Priest" (Tier: 2) - Spirit }',
		"14% increased Spirit",
		'{ Prefix Modifier "of Mana" (Tier: 3) - Mana }',
		"+35 to maximum Mana",
		'{ Prefix Modifier "of the Seer" (Tier: 1) - Mana }',
		"+17 to maximum Mana",
		'{ Suffix Modifier "of Minions" (Tier: 1) - Minions }',
		"Allies in your Presence deal 31% increased Damage",
		'{ Suffix Modifier "of Skills" (Tier: 3) }',
		"+3 to Level of all Minion Skills",
	}, "\n")
	local sceptre = Advisor.analyze(Parser.parse(SCEPTRE), league)
	H.eq("advisor: a rare with an open suffix is not called full", sceptre.ruleId, "rare_prefixes_full")
	H.eq("advisor: and the panel offers to add a modifier",
		((sceptre.plans[1] or { }).steps[1] or { }).id, "exalted")
	-- Nothing can be added, so the minimal plan is the reroll, then the value step, then quality.
	H.eq("advisor: full rare -> min starts with chaos", full.plans[1].steps[1].id, "chaos")
	H.eq("advisor: full rare -> then the value reroll", full.plans[1].steps[2].id, "divine")
	H.eq("advisor: full rare -> and quality last", full.plans[1].steps[3].id, "scrap")
	H.eq("advisor: full rare -> and the maximum plan ends with Vaal",
		full.plans[2].steps[#full.plans[2].steps].id, "vaal")

	local corrupted = Advisor.analyze(Parser.parse(RARE_CORRUPTED), league)
	H.eq("advisor: corrupted -> locked rule", corrupted.ruleId, "locked")
	H.eq("advisor: corrupted -> blocker set", corrupted.blocker ~= nil, true)
	H.eq("advisor: corrupted -> plan has no steps", #corrupted.plans[1].steps, 0)
	-- A corrupted item can never be Vaaled again: the locked plan is empty and the step must not appear.
	local corruptedVaal = false
	for _, plan in ipairs(corrupted.plans) do
		for _, step in ipairs(plan.steps or { }) do
			if step.id == "vaal" then corruptedVaal = true end
		end
	end
	H.eq("advisor: a corrupted item is never offered Vaal", corruptedVaal, false)

	local normal = Advisor.analyze(Parser.parse(NORMAL), league)
	H.eq("advisor: normal -> rule", normal.ruleId, "normal_base")
	-- A Normal item has no modifiers yet, so quality belongs after them: the plan opens with the
	-- transmutation, not with the whetstone.
	H.eq("advisor: normal -> the modifier steps come first", normal.plans[1].steps[1].id, "transmutation")
	H.check("advisor: normal -> quality is not the first step",
		normal.plans[1].steps[1].id ~= "whetstone" and normal.plans[1].steps[1].id ~= "quality")
	local sawQualityLate = false
	for position, step in ipairs(normal.plans[1].steps) do
		if (step.id == "whetstone" or step.id == "quality") and position > 1 then
			sawQualityLate = true
		end
	end
	H.eq("advisor: normal -> quality appears later in the plan", sawQualityLate, true)
	H.eq("advisor: normal -> max is longer than min", #normal.plans[2].steps > #normal.plans[1].steps, true)
	H.eq("advisor: low ilvl note", #normal.notes > 0, true)

	local unique = Advisor.analyze(Parser.parse(UNIQUE), league)
	H.eq("advisor: unique -> rule", unique.ruleId, "unique")

	-- Prefix/suffix awareness, available only thanks to Data/mods.lua.
	H.eq("advisor: classified prefixes", open.prefixCount, 1)
	H.eq("advisor: classified suffixes", open.suffixCount, 2)
	H.eq("advisor: open prefixes", open.openPrefixes, 2)
	H.eq("advisor: open suffixes", open.openSuffixes, 1)
	H.contains("advisor: state shows affix split",
		table.concat(Advisor.stateFor(open, "en"), " | "), "Affixes: 1P / 2S")
	H.contains("advisor: state shows modifier tier",
		table.concat(Advisor.stateFor(open, "en"), " | "), "T5 +120 to maximum Life")
	H.eq("advisor: roll ceiling stats present",
		open.rollStats ~= nil and open.rollStats.allGroups > 700 and open.rollStats.groups > 0, true)

	local prefixesFull = Advisor.analyze(Parser.parse(PREFIXES_FULL), league)
	H.eq("advisor: three prefixes -> rule", prefixesFull.ruleId, "rare_prefixes_full")
	H.eq("advisor: three prefixes -> open prefixes", prefixesFull.openPrefixes, 0)
	H.eq("advisor: three prefixes -> open suffixes", prefixesFull.openSuffixes, 1)
	-- Two modifier steps, the value reroll, quality, and now the Vaal Orb at the end.
	H.eq("advisor: three prefixes -> max plan still fills suffixes", #prefixesFull.plans[2].steps, 5)
	H.eq("advisor: three prefixes -> and the plan ends with Vaal",
		prefixesFull.plans[2].steps[5].id, "vaal")
	H.contains("advisor: three prefixes -> explains suffixes only",
		table.concat(Advisor.notesFor(prefixesFull, "en"), " | "), "suffix")

	local suffixesFull = Advisor.analyze(Parser.parse(SUFFIXES_FULL), league)
	H.eq("advisor: three suffixes -> rule", suffixesFull.ruleId, "rare_suffixes_full")
	H.eq("advisor: three suffixes -> open suffixes", suffixesFull.openSuffixes, 0)
	H.eq("advisor: three suffixes -> open prefixes", suffixesFull.openPrefixes, 1)

	-- Roll odds attached to steps (surfaced in the panel as percentages). The quality step sits first,
	-- so the rule's own step is the second one; naming the step by its id keeps the check honest rather
	-- than counting positions.
	local function stepById(advice, planIndex, id)
		for _, step in ipairs(advice.plans[planIndex].steps) do
			if step.id == id then
				return step
			end
		end
		return nil
	end
	local minStep = stepById(open, 1, "exalted")
	H.check("advisor: the rule's add step is in the plan", minStep ~= nil)
	H.eq("advisor: add step carries a roll pool", minStep.pool ~= nil and #minStep.pool.groups > 0, true)
	H.eq("advisor: both sides open means an unrestricted pool", minStep.pool.side, nil)
	local greaterStep = stepById(open, 2, "greater_exalted")
	H.eq("advisor: greater variant sets a mod-level floor", greaterStep.minModLevel, 35)
	H.eq("advisor: greater variant pool is not larger",
		greaterStep.pool.tierCount <= minStep.pool.tierCount, true)

	local chaosStep = stepById(full, 1, "chaos")
	H.eq("advisor: removal step carries removal odds", chaosStep.removal ~= nil, true)
	H.eq("advisor: removal chance is per modifier",
		math.abs(chaosStep.removal.perModChance - 100 / 6) < 0.01, true)

	-- Side-locked pool when only one side has room.
	local sideStep = stepById(prefixesFull, 1, "exalted")
	H.eq("advisor: side-locked pool follows the open side", sideStep.pool.side, "suffix")

	-- Synthetic ruleset: proves the unverified-warning path and rule isolation.
	local synthetic = {
		league = "test-league",
		currencies = {
			mystery = { en = "Mystery Orb", effectEn = "does nothing", cost = "low", status = "unverified" },
		},
		rules = {
			{ id = "always", when = { rarity = "RARE" }, min = { "mystery" }, max = { "mystery" }, why = { min = "тест", max = "тест" } },
		},
		glossary = { },
		warnings = { unverified = "WARN" },
	}
	local synth = Advisor.analyze(Parser.parse(RARE_OPEN), synthetic)
	H.eq("advisor: synthetic rule wins", synth.ruleId, "always")
	H.eq("advisor: unverified step flagged", synth.plans[1].steps[1].warning, "WARN")

	-- Console/file dump is Russian; the panel variant is covered by the ASCII check below.
	local text = Advisor.toText(open)
	H.contains("advisor: text rendering (min plan)", text, "МИН")
	H.contains("advisor: text rendering (max plan)", text, "МАКС")
	H.contains("advisor: text rendering (currency)", text, "Exalted Orb")

	-- Bilingual rendering: the panel needs ASCII (host fonts have no Cyrillic),
	-- while file/console output stays Russian.
	local i18n = require("Core.i18n")
	H.eq("i18n: state renders in english", Advisor.stateFor(open, "en")[1], "Rarity: RARE")
	H.eq("i18n: state renders in english", Advisor.stateFor(open, "en")[1], "Rarity: RARE")
	H.eq("i18n: notes localised (ru)", type(Advisor.notesFor(normal, "ru")[1]), "string")

	local enNotes = Advisor.notesFor(normal, "en")
	H.eq("i18n: notes localised (en)", #enNotes > 0, true)
	H.contains("i18n: english note text", enNotes[1] or "", "item level")

	local offenders = { }
	local function checkAscii(label, s)
		if s and not i18n.isAscii(s) then
			offenders[#offenders + 1] = label .. "=" .. tostring(s)
		end
	end
	for _, advice in ipairs({ open, full, corrupted, normal, unique, prefixesFull, suffixesFull }) do
		checkAscii("blockerEn", advice.blockerEn)
		for _, plan in ipairs(advice.plans) do
			checkAscii("titleEn", plan.titleEn)
			checkAscii("reasonEn", plan.reasonEn)
			for _, step in ipairs(plan.steps) do
				checkAscii("step.en", step.en)
				checkAscii("effectEn", step.effectEn)
				checkAscii("hintEn", step.hintEn)
				checkAscii("warningEn", step.warningEn)
			end
		end
	end
	H.check("panel strings are ASCII (fonts have no Cyrillic)", #offenders == 0,
		table.concat(offenders, " | "))
end
