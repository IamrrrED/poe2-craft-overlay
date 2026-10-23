-- Cost and chance come from the engine's snapshot, so the step can be judged before it is paid for.
return function()
	local H = require("Tests.harness")
	local Coach = require("Craft.Coach")
	local Parser = require("Item.Parser")

	local ITEM = table.concat({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		"+118 to maximum Life",
	}, "\n")

	local advice = {
		prices = { fetchedAt = "2026-10-06 23:17" },
		craftSummary = {
			total = 29, applicable = 11,
			entries = {
				{ label = "Exalted Orb", chancePerAttempt = 0.0738, attemptsFor90 = 31 },
				{ label = "Chaos Orb", chancePerAttempt = 0.0769, attemptsFor90 = 29 },
			},
		},
		plans = {
			{ id = "min", reason = "Один свободный слот.", steps = {
				{ en = "Exalted Orb", count = 2, effect = "Добавляет один мод" },
			} },
		},
	}

	local report = Coach.report(Parser.parse(ITEM), advice, ITEM)
	H.eq("coach: the step currency is kept", report.step.currency, "Exalted Orb")
	H.eq("coach: the chance is taken from the engine", report.step.chancePerAttempt, 0.0738)
	H.eq("coach: attempts to 90 % are taken too", report.step.attemptsFor90, 31)
	H.eq("coach: a cost line is built", type(report.step.costLine), "string")
	H.eq("coach: the cost line mentions the chance", report.step.costLine:find("шанс", 1, true) ~= nil, true)
	H.eq("coach: the count multiplies the unit price", report.step.cost ~= nil, true)
	H.eq("coach: nothing is invented without a snapshot", (function()
		local bare = Coach.report(Parser.parse(ITEM), { plans = advice.plans }, ITEM)
		return bare.step.cost == nil and bare.step.costLine:find("не удалось", 1, true) ~= nil
	end)(), true)
end