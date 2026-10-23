-- The Genesis Tree advisor: plans with steps and expected births, not a description.
--
-- The tree answers a question a beginner actually asks - "how do I get the catalyst I need" - and since 0.5.0
-- it is the ONLY way to get one, so the mentor has to be able to answer it. Every number below is a published
-- chance, and the attempts are 1/chance worked out from those chances.
return function()
	local H = require("Tests.harness")
	local GenesisTree = require("Craft.GenesisTree")
	local league = require("Data.league_0_5_5")
	local Api = require("Mcp.api")

	-- Every goal is complete: it names the Wombgift, the womb, and why it is worth doing.
	H.check("tree: there are goals", #GenesisTree.GOALS >= 6, tostring(#GenesisTree.GOALS))
	local ids = { }
	for _, goal in ipairs(GenesisTree.GOALS) do
		H.eq("tree: the id is unique (" .. tostring(goal.id) .. ")", ids[goal.id], nil)
		ids[goal.id] = true
		H.check("tree: a goal has a title (" .. goal.id .. ")",
			type(goal.title) == "string" and #goal.title > 6, tostring(goal.title))
		H.check("tree: it names a Wombgift (" .. goal.id .. ")",
			type(goal.wombgift) == "string" and goal.wombgift:find("Wombgift", 1, true) ~= nil,
			tostring(goal.wombgift))
		H.check("tree: and a womb (" .. goal.id .. ")",
			type(goal.womb) == "string" and goal.womb ~= "", tostring(goal.womb))
		H.check("tree: it explains why (" .. goal.id .. ")",
			type(goal.why) == "string" and #goal.why > 60, tostring(#(goal.why or "")))
		-- A goal with no published chance must not pretend to have one.
		local chance = GenesisTree.chanceOf(goal, league)
		H.check("tree: the chance is a probability (" .. goal.id .. ")",
			type(chance) == "number" and chance >= 0 and chance <= 1, tostring(chance))
	end

	-- The Wombgift names must be the ones the data records, or the plan would tell a player to look for a
	-- thing that does not exist.
	local known = { }
	for _, gift in ipairs((league.genesisTree or { }).wombgifts or { }) do
		known[gift.en] = true
	end
	for _, goal in ipairs(GenesisTree.GOALS) do
		H.eq("tree: the Wombgift exists in the data (" .. goal.id .. ")", known[goal.wombgift], true)
	end

	-- The arithmetic. 15% catalysts means about 6.7 births; 4% refined means about 25.
	local any = GenesisTree.plan("catalyst_any", league)
	H.check("tree: the catalyst plan exists", any ~= nil)
	if any then
		H.eq("tree: its chance is fifteen percent", any.chance, 0.15)
		H.eq("tree: so about 6.7 births", any.expectedBirths, 6.67)
		H.check("tree: it has steps", #any.steps >= 3, tostring(#any.steps))
	end
	local refined = GenesisTree.plan("catalyst_refined", league)
	if refined then
		H.eq("tree: a refined catalyst is four percent", refined.chance, 0.04)
		H.eq("tree: so about twenty-five births", refined.expectedBirths, 25)
		H.check("tree: and it is rarer than the plain one", refined.chance < any.chance)
	end
	-- The Refined Breach Ring is two rolls multiplied, and the plan must say so rather than guess.
	local rbr = GenesisTree.plan("refined_breach_ring", league)
	if rbr then
		H.check("tree: the refined Breach Ring is a product of two rolls",
			math.abs(rbr.chance - (0.10 * 0.05)) < 1e-9, tostring(rbr.chance))
		H.eq("tree: which is about two hundred births", rbr.expectedBirths, 200)
		local mentionsTwo = false
		for _, step in ipairs(rbr.steps) do
			if tostring(step.risk):find("два броска", 1, true) then mentionsTwo = true end
		end
		H.eq("tree: and the plan says two rolls", mentionsTwo, true)
	end

	-- A certain outcome reports no attempt count: "1 birth" is noise, and inventing a number would be wrong.
	local ring = GenesisTree.plan("ring", league)
	H.check("tree: the ring plan exists", ring ~= nil)
	if ring then
		H.eq("tree: a ring is certain", ring.chance, 1)
		H.eq("tree: so one birth", ring.expectedBirths, 1)
		-- With nothing to repeat, the fourth step must not appear.
		H.check("tree: no repeat step for a certain outcome", #ring.steps, 3)
	end

	-- An unknown goal is refused, not guessed.
	H.eq("tree: an unknown goal has no plan", GenesisTree.plan("nope", league), nil)
	H.eq("tree: no goal has no plan", GenesisTree.plan(nil, league), nil)

	-- The reference payload carries the plans, so the panel can show them.
	local guide = assert(Api.call("crafting_guide", { }))
	H.check("tree: the guide carries the tree", type(guide.genesisTree) == "table")
	H.check("tree: with its location", type(guide.genesisTree.location) == "string"
		and #guide.genesisTree.location > 10, tostring(guide.genesisTree.location))
	H.check("tree: with the goals and their numbers",
		type(guide.genesisTree.goals) == "table" and #guide.genesisTree.goals >= 6,
		tostring(guide.genesisTree.goals and #guide.genesisTree.goals))
	for _, goal in ipairs(guide.genesisTree.goals or { }) do
		H.check("tree: a goal in the payload has an expected count (" .. tostring(goal.id) .. ")",
			type(goal.expectedBirths) == "number", tostring(goal.expectedBirths))
	end
end
