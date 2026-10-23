-- The step ORDER, on the customer's own items: modifiers first, then quality, then the finishing step.
return function()
	local H = require("Tests.harness")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Advisor = require("Craft.Advisor")
	local Coach = require("Craft.Coach")
	local league = require("Data.league_0_5_5")

	local HELMET = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Symbolic Bastion", "Charming Tiara",
		"--------", "Energy Shield: 218 (augmented)", "--------",
		"Requirements: Level 70, 99 Int", "--------", "Item Level: 80", "--------",
		'{ Prefix Modifier "Charming" (Tier: 2) }', "37% increased Energy Shield",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }', "+18% to Chaos Resistance",
		'{ Suffix Modifier "of the Wind" (Tier: 1) }', "19% increased Rarity of Items found",
		'{ Suffix Modifier "of the Sky" (Tier: 1) }', "16% increased Rarity of Items found",
	}, "\n")

	local item = Parser.parse(HELMET)
	Mods.annotate(item)
	local advice = Advisor.analyze(item, league)
	local order = { }
	for position, step in ipairs(advice.plans[1].steps) do
		order[#order + 1] = position .. ":" .. tostring(step.id)
	end
	H.check("order: the helmet's min plan starts with a modifier step",
		(advice.plans[1].steps[1] or { }).id == "exalted", table.concat(order, " "))
	-- The minimal plan closes with quality. Vaal is one-way, so it belongs to the maximum plan, where it is
	-- the last step and quality sits directly in front of it.
	local minQualityAt = nil
	for position, step in ipairs(advice.plans[1].steps) do
		if step.id == "scrap" then minQualityAt = position end
	end
	H.eq("order: the minimal plan closes with quality", minQualityAt, #advice.plans[1].steps)
	local maxSteps = advice.plans[2].steps
	H.eq("order: the maximum plan ends with Vaal", (maxSteps[#maxSteps] or { }).id, "vaal")
	-- Quality comes AFTER the value reroll, by the customer's rule: it multiplies the item's numbers, so it
	-- is worth most once those numbers are final.
	H.eq("order: with the value reroll before quality", (maxSteps[#maxSteps - 2] or { }).id, "divine")
	H.eq("order: and quality right after it", (maxSteps[#maxSteps - 1] or { }).id, "scrap")
	-- The Vaal step must carry its own warning to the card: it is one-way and can destroy the craft.
	local vaalStep = maxSteps[#maxSteps]
	H.check("order: the Vaal step states its risk",
		type(vaalStep.warning) == "string" and #vaalStep.warning > 20, tostring(vaalStep.warning))
	H.check("order: and the English wording as well",
		type(vaalStep.warningEn) == "string" and #vaalStep.warningEn > 20, tostring(vaalStep.warningEn))
	H.check("order: the card offers the modifier step first",
		Coach.step(item, advice, Coach.state(item, HELMET), nil).currency ~= "Armourer's Scrap",
		table.concat(order, " "))

	-- An item with nothing left to add fixes its values before raising quality. That order is checked on
	-- the full-rare fixture in test_advisor, where the slots really are full; a helmet with a suffix
	-- removed is NOT such an item, which is what an earlier version of this check got wrong.

	-- A Magic flask with both mods and no quality: quality is still the step, because nothing else works.
	local FLASK = table.concat({
		"Item Class: Life Flasks", "Rarity: Magic",
		"Abundant Transcendent Life Flask of the Surgeon", "--------",
		"Recovers 1327 Life over 4 Seconds", "Consumes 10 of 75 Charges on use", "--------",
		"Item Level: 54", "--------",
		'{ Prefix Modifier "Abundant" (Tier: 5) }', "58% increased Recovery Amount",
		'{ Suffix Modifier "of the Surgeon" (Tier: 1) }', "31% Chance to gain a Charge when you Kill an Enemy",
	}, "\n")
	local flask = Parser.parse(FLASK)
	Mods.annotate(flask)
	local flaskAdvice = Advisor.analyze(flask, league)
	H.eq("order: a full Magic flask upgrades to Rare before anything else",
		Coach.step(flask, flaskAdvice, Coach.state(flask, FLASK), nil).currency, "Regal Orb")
end
