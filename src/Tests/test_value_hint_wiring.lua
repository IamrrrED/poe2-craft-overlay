-- PoE2 Craft Overlay : Tests/test_value_hint_wiring.lua
-- The card may only speak about chasing a modifier when a modifier can still be added. That is what this checks: on an
-- item that is corrupted, the step must carry no hints at all and must explain why, in both languages. The positive
-- case (which modifiers count as valuable, and in what order) is pinned in test_value_hint.lua, where no item text is
-- involved - an item that cannot be crafted is exactly where a wrong "chase this" hint would do damage.
return function()
	local H = require("Tests.harness")
	local Api = require("Mcp.api")

	local CORRUPTED = table.concat({
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

	local answer, errorText = Api.call("craft_step", { item_text = CORRUPTED, lang = "ru", goal = "life" })
	H.check("gate: craft_step answered", answer ~= nil, tostring(errorText))
	if not answer then
		return
	end
	H.eq("gate: a corrupted item carries no hints", answer.valueHints, nil)
	H.eq("gate: and no summary sentence", answer.valueHintText, nil)
	H.check("gate: it explains the silence", type(answer.valueHintsBlocked) == "string"
		and #answer.valueHintsBlocked > 10, tostring(answer.valueHintsBlocked))
	local english = Api.call("craft_step", { item_text = CORRUPTED, lang = "en", goal = "life" })
	H.check("gate: the explanation follows the reply language", english ~= nil
		and type(english.valueHintsBlocked) == "string" and english.valueHintsBlocked:find("item", 1, true) ~= nil,
		english and tostring(english.valueHintsBlocked))
	H.check("gate: the reason names the item, not a modifier", answer.valueHintsBlocked:find("предмет", 1, true) ~= nil,
		tostring(answer.valueHintsBlocked))
end