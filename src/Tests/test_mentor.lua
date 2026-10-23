-- The mentor, end to end: every part reaches the payloads the panel reads.
--
-- The individual modules have their own tests. This one exists for the claim the objective actually makes -
-- that the overlay contains a beginner mentor, not six unrelated features - so it checks the three payloads
-- the panel requests on a capture (craft_step, analyze_item, crafting_guide) and fails if any part of the
-- mentor stops travelling with them.
return function()
	local H = require("Tests.harness")
	local Api = require("Mcp.api")

	local ITEM = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Symbolic Bastion", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }', "+18% to Chaos Resistance",
	}, "\n")

	-- 1. The step card: what to do, why, the principle, and whether to craft at all.
	local step = assert(Api.call("craft_step", { item_text = ITEM }))
	H.check("mentor: the step card names the next action",
		type(step.step) == "table" and type(step.step.currency) == "string" and step.step.currency ~= "",
		tostring(step.step and step.step.currency))
	H.check("mentor: it explains the action",
		type(step.step.why) == "string" and #step.step.why > 20, tostring(#(step.step.why or "")))
	H.check("mentor: it teaches the principle behind it",
		type(step.step.lesson) == "string" and #step.step.lesson > 80,
		tostring(#(step.step.lesson or "")))
	H.check("mentor: and it answers whether to craft at all",
		type(step.craftOrBuy) == "table" and type(step.craftOrBuy.rule) == "string",
		tostring(step.craftOrBuy ~= nil))

	-- 2. The analysis: budget tier, advanced techniques, and the course.
	local analysis = assert(Api.call("analyze_item", { item_text = ITEM }))
	local methods = analysis.methods
	H.check("mentor: the analysis carries the methods payload", type(methods) == "table")
	H.check("mentor: it knows which budget stage the item is at",
		type(methods.stage) == "table" and type(methods.stage.id) == "string",
		tostring(methods.stage and methods.stage.id))
	H.eq("mentor: a level-80 item is endgame", methods.stage.id, "endgame")
	H.check("mentor: it explains the stage in words",
		type(methods.stage.description) == "string" and #methods.stage.description > 30)
	H.check("mentor: the advanced techniques travel with it",
		type(methods.techniques) == "table")
	H.check("mentor: and the course travels with it",
		type(methods.curriculum) == "table" and #methods.curriculum >= 4,
		tostring(methods.curriculum and #methods.curriculum))

	-- Every method is either allowed or marked to save, so a beginner is never left guessing.
	local refused, total = 0, 0
	for _, group in ipairs(methods.groups or { }) do
		for _, row in ipairs(group.methods or { }) do
			total = total + 1
			H.check("mentor: every method carries a stage verdict (" .. tostring(row.title) .. ")",
				type(row.allowedAtStage) == "boolean", tostring(row.allowedAtStage))
			if row.allowedAtStage == false then
				refused = refused + 1
				H.check("mentor: a refused method says why (" .. tostring(row.title) .. ")",
					type(row.stageNote) == "string" and #row.stageNote > 20)
			end
		end
	end
	H.check("mentor: the picker has methods", total > 0, tostring(total))
	H.eq("mentor: an endgame item refuses nothing", refused, 0)

	-- 3. The reference: the traps, and how many of them the data settles.
	local guide = assert(Api.call("crafting_guide", { }))
	H.check("mentor: the reference lists the known traps",
		type(guide.claims) == "table" and #guide.claims >= 8, tostring(guide.claims and #guide.claims))
	H.check("mentor: and reports how many the engine verifies",
		type(guide.claimsChecked) == "table" and guide.claimsChecked.checked >= 8,
		tostring(guide.claimsChecked and guide.claimsChecked.checked))
	H.eq("mentor: with none contradicting the data", guide.claimsChecked.failed, 0)

	-- 4. The claim checker answers through the same engine, so the page cannot hold a second opinion.
	local answer = assert(Api.call("check_claim", { text = "Chaos перекатывает весь предмет" }))
	H.eq("mentor: the claim checker recognises a trap", answer.id, "chaos_rerolls_all")
	H.eq("mentor: and marks it false", answer.verdict, "false")
	H.eq("mentor: and says the data settles it", answer.verified, true)

	-- 5. A low-level item proves the budget tier is real, not a field that always says endgame.
	local LOW = table.concat({
		"Item Class: Boots", "Rarity: Rare", "Campaign Boots", "Rawhide Boots", "--------",
		"Item Level: 40", "--------",
		'{ Prefix Modifier "Runner" (Tier: 2) }', "20% increased Movement Speed",
	}, "\n")
	local low = assert(Api.call("analyze_item", { item_text = LOW }))
	H.eq("mentor: a level-40 item is the campaign tier", low.methods.stage.id, "campaign")
	local lowRefused = 0
	for _, group in ipairs(low.methods.groups or { }) do
		for _, row in ipairs(group.methods or { }) do
			if row.allowedAtStage == false then lowRefused = lowRefused + 1 end
		end
	end
	H.check("mentor: and the campaign refuses the expensive orbs", lowRefused > 0, tostring(lowRefused))

	-- 6. The player's situation changes the answer, the way a person's advice changes when they hear "I am in
	-- SSF and I only have half a chaos".
	local first = require("Tests.item_corpus")[1]
	local rich = (Api.call("craft_step", { item_text = first, lang = "ru", mode = "trade", goal = "sell",
		budget_chaos = 0.5 }) or { }).step or { }
	H.check("mentor: a budget turns into attempts and a chance",
		tonumber(rich.affordableAttempts) ~= nil and tonumber(rich.affordableChance) ~= nil,
		tostring(rich.affordableAttempts))
	if tonumber(rich.cost) then
		H.eq("mentor: the affordable attempts are budget divided by the attempt price",
			tonumber(rich.affordableAttempts), math.floor(0.5 / tonumber(rich.cost)))
	end
	H.check("mentor: and the reply talks about attempts", (rich.budgetReply or ""):find("попыт", 1, true) ~= nil,
		tostring(rich.budgetReply))

	-- SSF: there is nowhere to buy the finished item, so quoting a trade threshold would be a lie.
	local ssf = (Api.call("craft_step", { item_text = first, lang = "ru", mode = "ssf", goal = "wear" }) or { })
		.step or { }
	H.check("mentor: SSF drops the trade stop rule", ssf.stopRule == nil, tostring(ssf.stopRule))
	H.check("mentor: and says why instead", (ssf.modeNote or ""):find("SSF", 1, true) ~= nil, tostring(ssf.modeNote))
	H.check("mentor: wearing the item is answered differently", (ssf.goalNote or "") ~= "", tostring(ssf.goalNote))
	-- The twins are dropped by the language gate, so the English side is checked in its own answer.
	local ssfEn = (Api.call("craft_step", { item_text = first, lang = "en", mode = "ssf", goal = "wear" }) or { })
		.step or { }
	H.check("mentor: the English SSF answer carries its own lines",
		(ssfEn.modeNote or "") ~= "" and (ssfEn.goalNote or "") ~= "", tostring(ssfEn.modeNote))
	H.check("mentor: with no Russian in them",
		not (ssfEn.modeNote or ""):find("[\208-\209][\128-\191]"), tostring(ssfEn.modeNote))
	H.check("mentor: and no trade stop rule there either", ssfEn.stopRule == nil, tostring(ssfEn.stopRule))

	-- 7. The two lines that make the step sound like a person: what the whole attempt costs and where to
	-- stop. Both are derived from numbers the step already carries, so they must agree with them - a stop rule
	-- quoting a different figure than the budget would be worse than no rule at all.
	local priced = nil
	for index = 1, 12 do
		local candidate = require("Tests.item_corpus")[index]
		local card = Api.call("craft_step", { item_text = candidate, lang = "ru" })
		local step = card and card.step
		if step and step.cost and step.attemptsFor90 then
			priced = { step = step, item = candidate }
			break
		end
	end
	H.check("mentor: a step with a price and odds exists in the corpus", priced ~= nil, "none found")
	if priced then
		local step = priced.step
		local expected = tonumber(step.cost) * tonumber(step.attemptsFor90)
		H.check("mentor: the budget is cost per attempt times attempts",
			tonumber(step.budget90) ~= nil and math.abs(tonumber(step.budget90) - expected) < 1e-9,
			tostring(step.budget90) .. " vs " .. tostring(expected))
		local budgetText = string.format("%.4f", expected):gsub("0+$", ""):gsub("%.$", "")
		H.check("mentor: the stop rule quotes the budget, not another number",
			(step.stopRule or ""):find(budgetText, 1, true) ~= nil, tostring(step.stopRule))
		H.check("mentor: and says what to do with it",
			(step.stopRule or ""):find("покупайте", 1, true) ~= nil
				or (step.stopRule or ""):find("бросайте", 1, true) ~= nil, tostring(step.stopRule))
		H.check("mentor: the budget names the currency",
			(step.budgetLine or ""):find(tostring(step.costUnit or "?"), 1, true) ~= nil, tostring(step.budgetLine))
		local english = (Api.call("craft_step", { item_text = priced.item, lang = "en" }) or { }).step or { }
		H.check("mentor: the English step carries its own two lines",
			(english.stopRule or "") ~= "" and (english.budgetLine or "") ~= "", tostring(english.stopRule))
		H.check("mentor: with no Russian in them",
			not (english.stopRule or ""):find("[\208-\209][\128-\191]"), tostring(english.stopRule))
	end
end
