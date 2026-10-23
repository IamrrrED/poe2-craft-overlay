-- "Craft or buy": what the craft costs, and how to compare it with the market honestly.
--
-- Every guide in docs/mentor-research.md says to answer this BEFORE spending, and every one of them does it
-- with a number. We can only produce one side of that comparison - the craft cost - because the price
-- snapshot has never carried rare items and no public feed prices "a rare with these three modifiers". The
-- module therefore reports the cost exactly, refuses to rank routes whose price has a missing component, and
-- hands the player the search recipe plus the decision rule. Inventing a buy price would be the worst thing
-- a mentor could do, and these checks pin that down.
return function()
	local H = require("Tests.harness")
	local CraftOrBuy = require("Craft.CraftOrBuy")
	local Api = require("Mcp.api")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Advisor = require("Craft.Advisor")
	local league = require("Data.league_0_5_5")

	local HELMET = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Symbolic Bastion", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }', "+18% to Chaos Resistance",
	}, "\n")
	local item = Parser.parse(HELMET)
	Mods.annotate(item)
	-- The cost model rides with the API's analysis (the dispatcher attaches craftSummary), so the test takes
	-- the same route the panel does rather than calling the advisor directly and seeing no costs at all.
	-- lang = "en" throughout: the routes are identified by their English labels, which are the ones
	-- the engine uses internally. The Russian labels are covered by Tests.test_language.
	local advice = assert(Api.call("analyze_item", { item_text = HELMET, lang = "en" }))
	H.check("craft-or-buy: the analysis carries the priced summary", advice.craftSummary ~= nil)

	-- The search recipe lists the item's REAL modifiers, never our annotation lines. An early version put
	-- "{ Prefix Modifier ... }" into the list, and a trade filter for that line returns nothing.
	local recipe = CraftOrBuy.searchRecipe(item)
	H.check("craft-or-buy: the recipe names the class", tostring(recipe.class):find("Helmet") ~= nil,
		tostring(recipe.class))
	H.eq("craft-or-buy: the recipe carries the item level", recipe.itemLevel, 80)
	H.eq("craft-or-buy: and the rarity", tostring(recipe.rarity):upper(), "RARE")
	H.check("craft-or-buy: the recipe has stat filters", #recipe.stats >= 2, tostring(#recipe.stats))
	for _, stat in ipairs(recipe.stats) do
		H.check("craft-or-buy: no annotation line becomes a filter (" .. tostring(stat.text) .. ")",
			not tostring(stat.text):find("Modifier", 1, true),
			tostring(stat.text))
	end

	-- The cheapest route is a FULLY priced one. Desecration is the case that exposed the bug: we priced the
	-- omen but not the bone, so it came out at 0.02 chaos and ranked first on every item.
	local cheapest = CraftOrBuy.cheapest(advice)
	H.check("craft-or-buy: there is a priced route", cheapest ~= nil)
	if cheapest then
		H.check("craft-or-buy: it is not the desecration route (whose bone has no price)",
			tostring(cheapest.method) ~= "Desecration", tostring(cheapest.method))
		H.check("craft-or-buy: it carries an expected cost", cheapest.expectedCost ~= nil
			and type(cheapest.expectedCost.chaos) == "number")
		H.check("craft-or-buy: and an attempt count", type(cheapest.expectedAttempts) == "number")
	end

	-- A route with an unpriced component is reported as unknown, not as cheap.
	local unpriced = CraftOrBuy.unpricedRoutes(advice)
	local sawDesecration = false
	for _, route in ipairs(unpriced) do
		if tostring(route.method) == "Desecration" then
			sawDesecration = true
			H.check("craft-or-buy: the missing component is named",
				#(route.missing or { }) > 0, tostring(#(route.missing or { })))
		end
	end
	H.eq("craft-or-buy: desecration is listed as unpriced, not as cheapest", sawDesecration, true)

	-- The summary marks the lower bound, so anything comparing costs can skip it.
	local marked = false
	for _, entry in ipairs((advice.craftSummary and advice.craftSummary.entries) or { }) do
		if tostring(entry.label) == "Desecration" then
			H.eq("craft-or-buy: the desecration entry is flagged incomplete", entry.costIncomplete, true)
			H.check("craft-or-buy: and names what is missing", entry.unpriced ~= nil)
			marked = true
		end
	end
	H.eq("craft-or-buy: the flag is present on the entry", marked, true)

	-- The block itself: the rule is always stated, the price age travels with the numbers, and the block
	-- never claims to know a finished-item price.
	local block = CraftOrBuy.forItem(item, advice)
	H.check("craft-or-buy: there is a block", block ~= nil)
	H.check("craft-or-buy: the rule is stated in full", type(block.rule) == "string" and #block.rule > 80,
		tostring(block.rule and #block.rule))
	H.check("craft-or-buy: the price age is carried", type(block.pricesAsOf) == "string"
		and #block.pricesAsOf > 0, tostring(block.pricesAsOf))
	-- The currency-snapshot note was removed on request: it explained our bookkeeping, not the item.
	H.check("craft-or-buy: no snapshot bookkeeping note on the card", block.priceNote == nil,
		tostring(block.priceNote))
	H.check("craft-or-buy: no invented buy price is present",
		block.buyPrice == nil and block.finishedPrice == nil)
	-- An item without an item gives no block rather than a wrong one.
	H.eq("craft-or-buy: no item, no block", CraftOrBuy.forItem(nil, advice), nil)

	-- And it reaches the step card, which is where the player spends.
	-- lang = "en": the unpriced route is identified by its English label ("Desecration Bone"). The
	-- Russian label is covered by Tests.test_language.
	local report = assert(Api.call("craft_step", { item_text = HELMET, lang = "en" }))
	H.check("craft-or-buy: the step card carries the block", report.craftOrBuy ~= nil)
	H.check("craft-or-buy: with its recipe", report.craftOrBuy.recipe ~= nil)
end
