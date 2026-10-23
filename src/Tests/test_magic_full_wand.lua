-- A full Magic caster weapon: the item that showed the rule was wrong.
--
-- The wand carries two excellent modifiers - 46% increased Spell Damage and +3 to Level of all Chaos Spell
-- Skill Gems - on a Magic base. The advisor answered "nothing can be added, raise the quality", because the
-- `magic_full` rule claimed a Regal Orb "finds no room". That is false: Regal raises the rarity to Rare and
-- adds a third modifier, and the cap rises with the rarity. The same capture also reported the slot split as
-- unknown, because Coach.state read its counters from a field the parser does not always fill and subtracted
-- from a hardcoded three instead of the item's own cap of one and one.
return function()
	local H = require("Tests.harness")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Advisor = require("Craft.Advisor")
	local Coach = require("Craft.Coach")
	local league = require("Data.league_0_5_5")

	local WAND = table.concat({
		"Item Class: Wands",
		"Rarity: Magic",
		"Siphoning Wand",
		"--------",
		"Requires: Level 28, 23 Int",
		"--------",
		"Item Level: 79",
		"--------",
		"Grants Skill: Level 17 Energy Drain",
		"--------",
		'{ Prefix Modifier "Chanting" (Tier: 1) }',
		"46% increased Spell Damage",
		'{ Suffix Modifier "of the Void" (Tier: 1) }',
		"+3 to Level of all Chaos Spell Skill Gems",
	}, "\n")

	local item = Parser.parse(WAND)
	Mods.annotate(item)

	-- The slot split has to be known, or nothing downstream can reason about room.
	H.eq("wand: one prefix is counted", item.prefixCount, 1)
	H.eq("wand: one suffix is counted", item.suffixCount, 1)
	H.eq("wand: the split is complete", item.affixSplitComplete, true)
	-- A Magic item's cap is one and one, which is exactly why this item is full.
	H.eq("wand: the cap is one and one", item.affixCaps and item.affixCaps.prefixes, 1)

	local state = Coach.state(item, WAND)
	H.eq("wand: the coach trusts the split", state.splitKnown, true)
	H.eq("wand: no prefix slot is open", state.openPrefixes, 0)
	H.eq("wand: no suffix slot is open", state.openSuffixes, 0)

	local advice = Advisor.analyze(item, league)
	H.eq("wand: a full Magic item gets its own rule", advice.ruleId, "magic_full")

	-- Regal must be there: it is the only move that changes the item rather than its numbers.
	local offered = false
	for _, plan in ipairs(advice.plans or { }) do
		for _, step in ipairs(plan.steps or { }) do
			if step.id == "regal" then offered = true end
		end
	end
	H.eq("wand: the rarity upgrade is offered", offered, true)
	H.eq("wand: and it is the first step",
		(advice.plans[1].steps[1] or { }).id, "regal")

	local report = Coach.report(item, advice, WAND)
	H.check("wand: the card names the step", report and report.step ~= nil)
	if report and report.step then
		H.eq("wand: and the step is the Regal Orb", report.step.currency, "Regal Orb")
		-- The explanation must not claim the impossible. The old text said no currency adds anything.
		local why = tostring(report.step.why or "")
		H.check("wand: the explanation says the rarity is raised", why:find("Regal", 1, true) ~= nil
			or why:find("Rare", 1, true) ~= nil, why)
		H.check("wand: and does not claim nothing can be added",
			why:find("no currency adds another modifier", 1, true) == nil, why)
	end
end
