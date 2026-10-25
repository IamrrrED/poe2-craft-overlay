-- PoE2 Craft Overlay : Tests/test_value_hint_wiring.lua
-- The card gets its highlight from craft_step, so this checks the answer itself rather than the module in isolation:
-- the step must carry valueHints, the summary must be a sentence, and the mods it highlights must be the ones the
-- engine's own pool ranked - no second ranking invented on the way to the card.
return function()
	local H = require("Tests.harness")
	local Api = require("Mcp.api")

	local GLOVES = table.concat({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"Quality: +20% (augmented)",
		"Evasion Rating: 296 (augmented)",
		"+118 to maximum Life (implicit)",
		"+44% to Fire Resistance",
		"+37% to Cold Resistance",
		"+31% to Lightning Resistance",
		"--------",
		"Corrupted",
	}, "\n")

	local answer, errorText = Api.call("craft_step", { item_text = GLOVES, lang = "ru", goal = "life" })
	H.check("wiring: craft_step answered", answer ~= nil, tostring(errorText))
	if not answer then
		return
	end

	H.check("wiring: the step carries valueHints", type(answer.valueHints) == "table", type(answer.valueHints))
	H.check("wiring: it has a valuable list", type(answer.valueHints.valuable) == "table",
		type(answer.valueHints and answer.valueHints.valuable))
	H.check("wiring: it has an others list", type(answer.valueHints.others) == "table",
		type(answer.valueHints and answer.valueHints.others))

	-- The summary is what the card prints, so it must exist when something is worth chasing and stay empty otherwise.
	local valuable = answer.valueHints.valuable or { }
	if #valuable > 0 then
		H.check("wiring: a valuable mod produces a sentence", type(answer.valueHintText) == "string"
			and #answer.valueHintText > 10, tostring(answer.valueHintText))
		local first = valuable[1]
		H.check("wiring: the first valuable mod names a family", tostring(first.family or "") ~= "",
			tostring(first.family))
		H.check("wiring: it carries a chance from the pool", tonumber(first.chance) ~= nil,
			tostring(first.chance))
	else
		H.eq("wiring: nothing valuable means no sentence", answer.valueHintText, nil)
	end

	-- Whatever is highlighted must also appear in the pool the answer carries: one ranking, not two.
	local pool = answer.modPool or { }
	local poolWanted = pool.wanted or { }
	if #poolWanted > 0 and #valuable > 0 then
		local families = { }
		for _, entry in ipairs(poolWanted) do
			families[tostring(entry.family)] = true
		end
		H.check("wiring: the highlighted family comes from the pool", families[tostring(valuable[1].family)] == true,
			tostring(valuable[1].family))
	end

	-- A higher bar must not increase the number of highlighted mods.
	local strict = Api.call("craft_step", { item_text = GLOVES, lang = "ru", value_boost = 2.5 })
	if strict and strict.valueHints then
		H.check("wiring: a strict threshold does not highlight more",
			#(strict.valueHints.valuable or { }) <= #valuable,
			tostring(#(strict.valueHints.valuable or { })) .. " > " .. tostring(#valuable))
	end
end
