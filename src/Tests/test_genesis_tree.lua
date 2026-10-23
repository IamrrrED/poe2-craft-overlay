-- The Genesis Tree, and the essence count that turned out to be documented all along.
--
-- The Genesis Tree is a whole crafting line 0.5.0 introduced and the ruleset had nothing about: since that
-- patch catalysts no longer drop from monsters, so it is the only source of the quality jewellery and jewels
-- need. The second check here settles a question this audit got wrong twice.
return function()
	local H = require("Tests.harness")
	local league = require("Data.league_0_5_5")
	local Claims = require("Craft.Claims")

	-- 1. The Genesis Tree is described, not just named.
	local tree = league.genesisTree
	H.check("tree: the block exists", type(tree) == "table")
	H.check("tree: it says where it is", type(tree.location) == "string" and #tree.location > 10)
	H.eq("tree: it consumes two things", #(tree.consumes or { }), 2)
	local wombgifts = tree.wombgifts or { }
	H.eq("tree: there are five Wombgift types", #wombgifts, 5)
	local byOutput = { }
	for _, gift in ipairs(wombgifts) do
		byOutput[gift.produces] = gift
		H.check("tree: a Wombgift names its output (" .. tostring(gift.en) .. ")",
			type(gift.en) == "string" and gift.en ~= "" and type(gift.produces) == "string")
		H.check("tree: and the output has a Russian name (" .. tostring(gift.en) .. ")",
			type(gift.producesRu) == "string" and gift.producesRu ~= "")
	end
	-- The five outputs are the ones the official description lists.
	for _, output in ipairs({ "currency", "ring", "amulet", "belt", "breachstone" }) do
		H.check("tree: a " .. output .. " can be birthed", byOutput[output] ~= nil)
	end
	-- The odds that decide whether a catalyst can be targeted at all.
	H.eq("tree: the catalyst chance is fifteen percent", tree.catalystChance, 0.15)
	H.eq("tree: the refined catalyst chance is four percent", tree.refinedCatalystChance, 0.04)
	H.check("tree: refined is rarer than plain because it needs a second roll",
		tree.refinedCatalystChance < tree.catalystChance)
	H.eq("tree: a birthed item is a Breach Ring ten percent of the time", tree.breachRingChance, 0.10)
	H.eq("tree: and Refined five percent of that", tree.refinedBreachRingChance, 0.05)
	H.check("tree: the notes state the drop change", #(tree.notes or { }) >= 4, tostring(#(tree.notes or { })))
	local notesText = table.concat(tree.notes or { }, " ")
	H.check("tree: including that catalysts no longer drop from monsters",
		notesText:find("НЕ падают с монстров", 1, true) ~= nil, notesText:sub(1, 80))

	-- 2. The claim that catches the outdated habit, because "farm Breach for catalysts" was good advice once.
	local claim = Claims.answer("Катализаторы падают с монстров?")
	H.eq("tree: the catalyst-source claim is recognised", claim.id, "catalysts_drop_from_monsters")
	H.eq("tree: and marked false", claim.verdict, "false")
	H.check("tree: with the Genesis Tree named as the only source",
		tostring(claim.why):find("Genesis Tree", 1, true) ~= nil, tostring(claim.why))

	-- 3. The essence count. 81 from Path of Building plus the one documented gap equals poe2db's 82 - so the
	-- shortfall was never a mystery, it was already written down in our own data.
	local missing = league.missingEssences or { }
	H.eq("essences: exactly one essence is known to be missing", #missing, 1)
	H.eq("essences: and it is Essence of the Abyss", missing[1] and missing[1].en, "Essence of the Abyss")
	H.check("essences: with its effect recorded, not just its name",
		type(missing[1] and missing[1].text) == "string" and #missing[1].text > 60,
		tostring(missing[1] and missing[1].text))
	local ok, essences = pcall(require, "Data.essences")
	if ok then
		H.eq("essences: the generated table holds the other eighty-one", #(essences.list or { }), 81)
		-- And the missing one is genuinely absent from the generated list rather than duplicated.
		local seen = false
		for _, entry in ipairs(essences.list or { }) do
			if tostring(entry.en or entry.name) == "Essence of the Abyss" then seen = true end
		end
		H.eq("essences: Essence of the Abyss is not in the generated table", seen, false)
	end
end
