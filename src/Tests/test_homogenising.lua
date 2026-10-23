-- The Homogenising omen: it exists in the game, but NOT in a 0.5 league - and therefore must never be offered.
--
-- History worth keeping: the ruleset first said "not obtainable in league" because 0.4.0 disabled its DROP, then
-- that was "corrected" to "still obtainable through the currency exchange". The customer's live exchange in
-- Forbidden Rites shows the truth: the omen is simply absent (disabled from dropping AND restricted to Standard
-- on the exchange). So the technique cannot be performed in a league at all, and an adviser that offers it is
-- telling the player to buy something that does not exist.
--
-- The data stays (it exists in Standard, and the reference should not pretend otherwise), but with
-- status = "removed", and the adviser skips anything marked that way.
return function()
	local H = require("Tests.harness")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Advisor = require("Craft.Advisor")
	local league = require("Data.league_0_5_5")

	local omen = (league.omens or { }).homogenising_exaltation
	H.check("homogenising: the omen is still in the data for reference", omen ~= nil)
	if omen then
		H.eq("homogenising: but it is marked as removed from the league", omen.status, "removed")
		H.check("homogenising: and its text says it cannot be got in a league",
			tostring(omen.effectEn):lower():find("standard", 1, true) ~= nil
				or tostring(omen.effectEn):lower():find("no longer drops", 1, true) ~= nil,
			tostring(omen.effectEn))
	end
	local coronation = (league.omens or { }).homogenising_coronation
	H.check("homogenising: the Regal twin is the same case",
		coronation ~= nil and coronation.status == "removed", tostring(coronation and coronation.status))

	-- A free prefix slot is exactly the case the old test expected an offer for. It must now get NONE.
	local GLOVES = table.concat({
		"Item Class: Gloves", "Rarity: Rare", "Test Gloves", "Expert Vaal Gauntlets", "--------",
		"Item Level: 82", "--------",
		'{ Prefix Modifier "Ruin" (Tier: 3) }', "+85 to maximum Energy Shield",
	}, "\n")
	local item = Parser.parse(GLOVES)
	Mods.annotate(item)
	local advice = Advisor.analyze(item, league)
	local offered = 0
	for _, option in ipairs(advice.omenOptions or { }) do
		if tostring(option.omenId or "") == "homogenising_exaltation" then
			offered = offered + 1
		end
	end
	H.eq("homogenising: the method is not offered even with a free slot", offered, 0)

	-- And the reference tab must not present it as a usable method either.
	local Techniques = require("Craft.Techniques")
	local mentions = 0
	for _, technique in ipairs(Techniques.list and Techniques.list() or { }) do
		if tostring(technique.text or ""):lower():find("homogenis", 1, true)
			or tostring(technique.text or ""):find("единого возвышения", 1, true) then
			mentions = mentions + 1
		end
	end
	H.check("homogenising: no technique teaches the method as available", mentions == 0, tostring(mentions))
end
