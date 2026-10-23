-- What the second-source pass changed.
--
-- Two numbers and one claim went out on a single source and were checked against others:
--   * the Genesis Tree catalyst chance, now confirmed by three;
--   * desecration's availability in 0.5.x, which an earlier audit had flagged as unconfirmed;
-- and two of our own statements turned out to be false and are corrected here.
return function()
	local H = require("Tests.harness")
	local league = require("Data.league_0_5_5")
	local GenesisTree = require("Craft.GenesisTree")

	-- 1. Omen of Putrefaction was recorded as contradicting the one-desecrated-modifier limit and as
	-- unconfirmed. It is neither: it is the documented exception, and it is confirmed.
	local putrefaction = (league.omens or { }).putrefaction
	H.check("second source: Putrefaction exists", putrefaction ~= nil)
	if putrefaction then
		H.eq("second source: it is confirmed, not unverified", putrefaction.status, "league")
		H.eq("second source: it replaces every modifier", putrefaction.replacesAll, true)
		H.eq("second source: and corrupts the item", putrefaction.corrupts, true)
		H.check("second source: its text no longer calls itself contradictory",
			not tostring(putrefaction.effectEn):find("conflicts", 1, true),
			tostring(putrefaction.effectEn))
		H.check("second source: and names it as the exception",
			tostring(putrefaction.effectEn):find("exception", 1, true) ~= nil)
	end

	-- 2. The second catalyst node, which we did not have.
	H.eq("second source: the duplicate catalyst node is recorded",
		(league.genesisTree or { }).duplicateCatalystChance, 0.30)
	H.eq("second source: and the main catalyst chance is unchanged",
		(league.genesisTree or { }).catalystChance, 0.15)

	-- 3. Desecration's own facts, which only the omen records implied before.
	local desecration = league.desecration
	H.check("second source: the desecration block exists", type(desecration) == "table")
	H.eq("second source: three options are offered", desecration.choices, 3)
	H.eq("second source: an off-pool modifier appears from item level sixty-five",
		desecration.offPoolFromItemLevel, 65)
	H.eq("second source: one desecrated modifier per item", desecration.maxDesecrated, 1)
	H.eq("second source: abyss omens stop dropping below sixty-five", desecration.omenDropLevel, 65)
	H.check("second source: the reveal location is named",
		tostring(desecration.revealedAt):find("Well of Souls", 1, true) ~= nil,
		tostring(desecration.revealedAt))

	-- 4. Our own two false statements.
	-- The tree's passives are freely refundable, so the plan must not tell a beginner the setup is irreversible.
	local plan = GenesisTree.plan("catalyst_any", league)
	H.check("second source: the catalyst plan exists", plan ~= nil)
	if plan then
		local nodeStep = nil
		for _, step in ipairs(plan.steps) do
			if tostring(step.action):find("ноды", 1, true) then nodeStep = step end
		end
		H.check("second source: the node step exists", nodeStep ~= nil)
		if nodeStep then
			H.check("second source: it says the nodes can be reallocated for free",
				tostring(nodeStep.risk):find("бесплатно", 1, true) ~= nil, tostring(nodeStep.risk))
			H.check("second source: not that they are irreversible",
				not tostring(nodeStep.risk):find("необратим", 1, true), tostring(nodeStep.risk))
		end
		-- And the plan mentions the duplicate node without pretending it changes the type odds.
		H.check("second source: the plan mentions the duplicate node",
			tostring(plan.why):find("30%", 1, true) ~= nil, tostring(plan.why))
	end
end
