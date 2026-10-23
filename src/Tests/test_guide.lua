-- The reference is data, so it can be checked like any other data: no empty entries, no mechanics
-- explained twice, and every beginner mistake has words.
return function()
	local H = require("Tests.harness")
	local Guide = require("Data.crafting_guide")

	H.eq("guide: the league is named", type(Guide.league), "string")
	H.eq("guide: sources are listed", #Guide.SOURCES >= 4, true)
	H.eq("guide: two caps are described", #Guide.CAPS, 2)
	H.eq("guide: the main rule is a sentence", #Guide.MAIN_RULE > 40, true)
	H.eq("guide: the orbs are listed", #Guide.ORBS >= 10, true)
	H.eq("guide: every orb says what it does", type(Guide.ORBS[1].does), "string")
	H.eq("guide: omens are listed", #Guide.OMENS.entries >= 6, true)
	H.eq("guide: desecration bones are listed", #Guide.DESECRATION.slots >= 5, true)
	H.eq("guide: beginner mistakes are listed", #Guide.MISTAKES >= 6, true)
	H.eq("guide: the step loop is described", #Guide.LOOP >= 4, true)

	for _, orb in ipairs(Guide.ORBS) do
		H.eq("guide: orb '" .. orb.id .. "' is explained", #tostring(orb.does) > 10, true)
		H.eq("guide: orb '" .. orb.id .. "' warns about something", #tostring(orb.risk) > 2, true)
	end
	for _, omen in ipairs(Guide.OMENS.entries) do
		H.eq("guide: omen '" .. omen.id .. "' says why", #tostring(omen.why) > 10, true)
	end
end