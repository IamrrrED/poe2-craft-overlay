-- What the coach sees for the customer's helmet, and whether a quality change is visible to the memory.
--
-- The card said "nothing changed" about a step that WAS applied: quality is not part of any modifier
-- line, so the memory comparison could not see it move. That is what makes the card repeat the same
-- step forever, which is what the customer ran into.
return function()
	local H = require("Tests.harness")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Advisor = require("Craft.Advisor")
	local Coach = require("Craft.Coach")
	local Memory = require("Craft.Memory")
	local league = require("Data.league_0_5_5")

	local HELMET = table.concat({
		"Item Class: Helmets",
		"Rarity: Rare",
		"Symbolic Bastion",
		"Charming Tiara",
		"--------",
		"Energy Shield: 218 (augmented)",
		"--------",
		"Requirements: Level 70, 99 Int",
		"--------",
		"Item Level: 80",
		"--------",
		'{ Prefix Modifier "Charming" (Tier: 2) }',
		"37% increased Energy Shield",
		'{ Prefix Modifier "of the Charming" (Tier: 2) }',
		"+32 to maximum Mana",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }',
		"+18% to Chaos Resistance",
		'{ Suffix Modifier "of the Wind" (Tier: 1) }',
		"19% increased Rarity of Items found",
		'{ Suffix Modifier "of the Sky" (Tier: 1) }',
		"16% increased Rarity of Items found",
	}, "\n")

	local item = Parser.parse(HELMET)
	Mods.annotate(item)
	local advice = Advisor.analyze(item, league)
	H.eq("helmet: the rule found", advice.ruleId ~= nil, true)
	H.eq("helmet: the quality step is offered", (advice.qualityStep or { }).en, "Armourer's Scrap")
	H.eq("helmet: quality with no quality line is zero", tostring(item.quality), "nil")
	H.check("helmet: a slot is open", (item.openPrefixes or 0) + (item.openSuffixes or 0) > 0,
		tostring(item.openPrefixes) .. "/" .. tostring(item.openSuffixes))

	-- The memory question: does a quality change look like a change?
	Memory.clear()
	local before = Parser.parse(HELMET)
	local AFTER = (HELMET:gsub("Energy Shield: 218 %(augmented%)", "Quality: +20% (augmented)\nEnergy Shield: 240 (augmented)"))
	local after = Parser.parse(AFTER)
	H.eq("memory: the same item is recognised after a quality change",
		Memory.fingerprint(before), Memory.fingerprint(after))
	-- One thing changed: the quality. The comparison must report exactly that, and it must be a quality
	-- line rather than a modifier, because quality is not part of any modifier line.
	local changes = Memory.compare(Memory.mods(before), Memory.mods(after))
	H.eq("memory: the quality change is the only change", #changes.added, 1)
	H.eq("memory: and nothing is reported as removed", #changes.removed, 0)
	H.check("memory: the added value is the new quality",
		tostring(changes.added[1] or ""):find("20", 1, true) ~= nil, tostring(changes.added[1]))

	-- And the card must move on instead of repeating the quality step.
	local state = Coach.state(after, AFTER)
	local step = Coach.step(after, Advisor.analyze(after, league), state, {
		sameItem = true,
		previousStepIndex = 1,
		verdict = "progress",
	})
	H.check("coach: after quality the card moves on", step ~= nil and step.currency ~= "Armourer's Scrap",
		tostring(step and (step.currency or step.title)))
end

