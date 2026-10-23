-- Quality above 20%: which routes exist, and what each one costs.
--
-- Every guide that pushes quality past the ordinary ceiling treats it as a detail and moves on, but the routes
-- differ in price and in one case in permanence: a Vaal Infuser can corrupt the item, and Essence of the Breach
-- spends the item's only created modifier slot. The helper used to hardcode 20 as "the cap", so a 35% Breach
-- Ring was told its quality was already maximal.
--
-- Sources: poe2wiki (Vaal Infuser, Breach Ring, Quality), basicknowledge.xyz/poe2/craft/quality and
-- /craft/breach. The one claim NOT repeated here is a 50% ceiling: nothing trustworthy states it, and the
-- highest documented base (Refined Breach Ring) reaches 45.
return function()
	local H = require("Tests.harness")
	local Advisor = require("Craft.Advisor")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local league = require("Data.league_0_5_5")

	local function capOf(text)
		local item = Parser.parse(text)
		Mods.annotate(item)
		return Advisor.qualityCapFor(item), item
	end

	-- The default, and the ordinary currency ceiling, are both 20.
	H.eq("quality: the default ceiling is twenty", Advisor.DEFAULT_MAX_QUALITY, 20)
	local plain = capOf(table.concat({
		"Item Class: Helmets", "Rarity: Rare", "T", "Charming Tiara", "--------",
		"Quality: +20%", "--------", "Item Level: 80",
	}, "\n"))
	H.eq("quality: a plain item caps at twenty", plain, 20)

	-- A base whose own implicit raises the ceiling: the item states it, so the helper reads it.
	local breach = capOf(table.concat({
		"Item Class: Rings", "Rarity: Rare", "T", "Breach Ring", "--------",
		"Quality: +35%", "--------", "Item Level: 80", "--------",
		"{ Implicit Modifier }", "Maximum Quality is 40%",
	}, "\n"))
	H.eq("quality: a Breach Ring reaches forty", breach, 40)

	local refined = capOf(table.concat({
		"Item Class: Rings", "Rarity: Rare", "T", "Refined Breach Ring", "--------",
		"Quality: +40%", "--------", "Item Level: 80", "--------",
		"{ Implicit Modifier }", "Maximum Quality is 45%",
	}, "\n"))
	H.eq("quality: a Refined Breach Ring reaches forty-five", refined, 45)

	-- Essence of the Breach states the raise as a delta rather than an absolute.
	local essence = capOf(table.concat({
		"Item Class: Rings", "Rarity: Rare", "T", "Gold Ring", "--------",
		"Quality: +20%", "--------", "Item Level: 80", "--------",
		'{ Suffix Modifier "of the Breach" (Tier: 1) }', "+20% to Maximum Quality",
	}, "\n"))
	H.eq("quality: the Breach essence lifts a plain ring to forty", essence, 40)

	-- The data records every route, so the panel can name the price instead of only the number.
	local quality = league.quality
	H.check("quality: the ruleset describes the routes", type(quality) == "table")
	H.eq("quality: the ordinary currency cannot pass twenty", quality.ordinaryCurrencyCap, 20)
	H.eq("quality: a Vaal Infuser stops at thirty", quality.infuserMax, 30)
	local byId = { }
	for _, route in ipairs(quality.routes or { }) do byId[route.id] = route end
	H.check("quality: the infuser route is recorded", byId.vaal_infuser ~= nil)
	H.eq("quality: and it stops at thirty", byId.vaal_infuser.to, 30)
	H.check("quality: the infuser's risk is stated",
		tostring(byId.vaal_infuser.cost):find("оскверн", 1, true) ~= nil,
		tostring(byId.vaal_infuser.cost))
	H.eq("quality: the Breach Ring route reaches forty", byId.breach_ring.to, 40)
	H.eq("quality: the Refined one reaches forty-five", byId.refined_breach_ring.to, 45)
	H.eq("quality: the essence route reaches forty on jewellery", byId.essence_of_the_breach.to, 40)
	H.check("quality: and its cost is the created slot",
		tostring(byId.essence_of_the_breach.cost):find("созданный", 1, true) ~= nil,
		tostring(byId.essence_of_the_breach.cost))
	-- No route claims a ceiling above 45: nothing trustworthy documents one.
	for _, route in ipairs(quality.routes or { }) do
		H.check("quality: no route invents a higher ceiling than 45 (" .. tostring(route.id) .. ")",
			(tonumber(route.to) or 0) <= 45, tostring(route.to))
	end

	-- The four infusers are still listed with what they do.
	local infusers = league.vaalInfusers or { }
	H.eq("quality: there are four Vaal infusers", #infusers, 4)
	for _, infuser in ipairs(infusers) do
		H.eq("quality: each raises to thirty (" .. tostring(infuser.en) .. ")", infuser.raisesTo, 30)
		H.eq("quality: and carries a corruption risk (" .. tostring(infuser.en) .. ")",
			infuser.corruptRisk, true)
	end
end
