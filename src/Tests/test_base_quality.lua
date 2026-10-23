-- Choosing the base for its quality ceiling - a decision made before the item exists.
--
-- qualityCapFor answers "what can THIS item reach", which only helps once the base is already bought. The
-- decision that costs money is the one before: a Breach Ring reaches 40% and a Refined one 45%, so if the plan
-- is to run catalysts to a high quality, the base is part of the plan.
return function()
	local H = require("Tests.harness")
	local Advisor = require("Craft.Advisor")
	local league = require("Data.league_0_5_5")

	-- Known bases, by the name a player would search for.
	H.eq("base cap: a Breach Ring reaches forty",
		Advisor.qualityCapForBase("Breach Ring", league), 40)
	H.eq("base cap: a Refined Breach Ring reaches forty-five",
		Advisor.qualityCapForBase("Refined Breach Ring", league), 45)
	-- Anything else is the ordinary ceiling, and must not be inflated by a partial name match.
	H.eq("base cap: a Gold Ring stays at twenty",
		Advisor.qualityCapForBase("Gold Ring", league), 20)
	H.eq("base cap: an unknown base stays at twenty",
		Advisor.qualityCapForBase("Nonsense Base", league), 20)
	H.eq("base cap: and no name at all stays at twenty",
		Advisor.qualityCapForBase(nil, league), 20)

	-- The longer name must win: a Refined Breach Ring contains "Breach Ring", and containment matching in
	-- the wrong order would report 40 for an item that reaches 45.
	H.eq("base cap: the longer base name wins",
		Advisor.qualityCapForBase("Refined Breach Ring of Something", league), 45)
	-- A decorated rare name still resolves through the containment fallback.
	H.eq("base cap: a decorated name still resolves",
		Advisor.qualityCapForBase("Rare Breach Ring", league), 40)

	-- The data and the reader must agree, or the helper would answer from a table the ruleset never had.
	local caps = (league.quality or { }).baseCaps or { }
	H.check("base cap: the ruleset records the bases", next(caps) ~= nil)
	for name, cap in pairs(caps) do
		H.eq("base cap: " .. name .. " reads back as recorded",
			Advisor.qualityCapForBase(name, league), cap)
		-- Nothing may claim a ceiling above the documented maximum of 45.
		H.check("base cap: " .. name .. " does not exceed 45", cap <= 45, tostring(cap))
	end
end
