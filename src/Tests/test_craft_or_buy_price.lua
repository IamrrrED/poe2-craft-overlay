-- "Cheaper to craft or to buy?" - answered with two real numbers, one of them supplied by the player.
--
-- No feed prices an individual rare, so the market side of this comparison can only come from the person
-- looking at the trade site. The engine supplies the craft side exactly and does the arithmetic; the panel
-- never guesses a price. The margin matters too: our cost is an average, so a 5% difference is noise.
return function()
	local H = require("Tests.harness")
	local Api = require("Mcp.api")
	local CraftOrBuy = require("Craft.CraftOrBuy")

	local ITEM = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Test", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }', "+18% to Chaos Resistance",
	}, "\n")
	local advice = assert(Api.call("analyze_item", { item_text = ITEM }))
	local cheapest = CraftOrBuy.cheapest(advice)
	H.check("buy: the item has a computed craft cost", cheapest ~= nil
		and cheapest.expectedCost ~= nil)
	local cost = cheapest and cheapest.expectedCost and cheapest.expectedCost.chaos
	H.check("buy: which is a positive number", type(cost) == "number" and cost > 0, tostring(cost))

	-- A market price far below the craft cost: buy.
	local cheap = CraftOrBuy.compare(cost * 0.2, advice)
	H.check("buy: a much cheaper market yields a verdict", cheap ~= nil)
	if cheap then
		H.eq("buy: and the verdict is to buy", cheap.verdict, "buy")
		H.check("buy: with the saving stated in the text",
			tostring(cheap.text):find("Покупайте", 1, true) ~= nil, tostring(cheap.text))
		H.check("buy: and the difference is positive", cheap.difference > 0, tostring(cheap.difference))
	end

	-- A market price far above: craft.
	local dear = CraftOrBuy.compare(cost * 10, advice)
	H.check("buy: an expensive market yields a verdict", dear ~= nil)
	if dear then
		H.eq("buy: and the verdict is to craft", dear.verdict, "craft")
		H.check("buy: with the premium stated",
			tostring(dear.text):find("Крафтите", 1, true) ~= nil, tostring(dear.text))
	end

	-- Within the noise band: neither, because our number is an average rather than a promise.
	local same = CraftOrBuy.compare(cost, advice)
	H.check("buy: an equal price yields a verdict", same ~= nil)
	if same then
		H.eq("buy: and it refuses to call a coin flip", same.verdict, "either")
	end
	-- Just inside the band on either side is still "either".
	local nearCheap = CraftOrBuy.compare(cost * 0.9, advice)
	local nearDear = CraftOrBuy.compare(cost * 1.1, advice)
	if nearCheap then H.eq("buy: ten percent cheaper is still noise", nearCheap.verdict, "either") end
	if nearDear then H.eq("buy: ten percent dearer is still noise", nearDear.verdict, "either") end

	-- The honesty clause travels with every verdict.
	if cheap then
		H.check("buy: the note says the craft cost is an average",
			tostring(cheap.note):find("СРЕДНЕЕ", 1, true) ~= nil, tostring(cheap.note))
		H.check("buy: and that the price was the player's own",
			tostring(cheap.note):find("сами", 1, true) ~= nil, tostring(cheap.note))
	end

	-- Refusals: a bad price is not a comparison, and neither is a missing craft cost.
	H.eq("buy: a negative price is refused", CraftOrBuy.compare(-1, advice), nil)
	H.eq("buy: a non-numeric price is refused", CraftOrBuy.compare(nil, advice), nil)
	H.eq("buy: advice without a cost is refused", CraftOrBuy.compare(1, { }), nil)

	-- Prices are printed at the scale they live on. A craft may cost 0.11 chaos while a cheap rare sells for
	-- 0.0142; two fixed decimals would print "0.01" and could flip the verdict the whole comparison exists for.
	local CraftOrBuy = require("Craft.CraftOrBuy")
	H.eq("buy: a fraction of a chaos keeps four places", CraftOrBuy.money(0.0142), "0.0142")
	H.eq("buy: padding zeros are trimmed", CraftOrBuy.money(0.11), "0.11")
	H.eq("buy: one to ten keeps two places", CraftOrBuy.money(1.5), "1.5")
	H.eq("buy: ten and above keeps one", CraftOrBuy.money(12.34), "12.3")
	H.eq("buy: zero prints as zero", CraftOrBuy.money(0), "0")
	H.eq("buy: nothing prints as zero", CraftOrBuy.money(nil), "0")
	-- And the ready-to-show line uses it rather than its own formatting: verdictFor is what the host calls.
	local shown = CraftOrBuy.verdictFor(cost * 0.2, advice)
	H.check("buy: verdictFor builds a line", shown ~= nil and type(shown.line) == "string",
		tostring(shown and shown.line))
	if shown then
		-- The exact figure the player typed must survive into the sentence, not be rounded to two places.
		local precise = string.format("%.4f", shown.buyPrice):gsub("0+$", ""):gsub("%.$", "")
		H.check("buy: the line shows the price as precisely as it is known",
			tostring(shown.line):find(precise, 1, true) ~= nil,
			tostring(shown.line) .. " (looking for " .. precise .. ")")
	end

	-- Through the API, the way the host calls it.
	local viaApi = assert(Api.call("craft_or_buy", { item_text = ITEM, buy_price = cost * 0.2 }))
	H.eq("buy: the API answers", viaApi.verdict, "buy")
	H.check("buy: and returns a ready sentence", type(viaApi.line) == "string"
		and viaApi.line:find("хаоса", 1, true) ~= nil, tostring(viaApi.line))
	local noPrice, err = Api.call("craft_or_buy", { item_text = ITEM })
	H.eq("buy: a missing price is an error", noPrice, nil)
	H.check("buy: with a message", type(err) == "string" and #err > 10, tostring(err))
	local noItem = Api.call("craft_or_buy", { buy_price = 5 })
	H.eq("buy: a missing item is an error", noItem, nil)
end
