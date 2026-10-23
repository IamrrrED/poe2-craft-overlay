-- PoE2 Craft Overlay : Tests/test_out_ru.lua
-- The engine's own explanations in Russian: a Russian client must not see a Russian page
-- with English analysis text. Numbers and technical references stay untouched.

local OutRu = require("Mcp.out_ru")

return function(H)
	local plan = OutRu.translate({ id = "min", title = "MIN - lowest budget",
		reason = "A slot is open - one Exalted Orb adds a mod without risking the existing ones.",
		steps = { { name = "Exalted Orb", cost = "medium",
			effect = "Adds one random modifier to a Rare item (max 3 prefixes + 3 suffixes)." } } })

	H.contains("out: plan heading translated", plan.title, "минимальные затраты")
	H.contains("out: plan reason translated", plan.reason, "свободный слот")
	H.contains("out: step effect translated", plan.steps[1].effect, "Добавляет один случайный мод")
	H.eq("out: currency names are kept", plan.steps[1].name, "Exalted Orb")
	H.eq("out: cost tiers are kept", plan.steps[1].cost, "medium")

	local notes = OutRu.translate({ notes = { "8 modifier(s) unrecognised: prefix/suffix split unknown, slot-based rules are skipped" } })
	H.contains("out: notes translated", notes.notes[1], "не распознано")

	-- Technical references must survive verbatim.
	local sources = OutRu.translate({ sources = { { label = "Modifier weights", url = "https://example.org/x",
		detail = "Path of Building PoE2: Data/ModItem.lua" } } })
	H.eq("out: source label translated", sources.sources[1].label, "Веса модификаторов")
	H.eq("out: url untouched", sources.sources[1].url, "https://example.org/x")
	H.eq("out: file reference untouched", sources.sources[1].detail, "Path of Building PoE2: Data/ModItem.lua")

	H.eq("out: dictionaries present", OutRu.stats().exact > 10 and OutRu.stats().fragments > 10, true)

	-- The assistant speaks the language of the game client. In serving mode there is no clipboard
	-- capture to learn that language from, so the item text in the request is the evidence - the
	-- same evidence the parser itself uses.
	H.eq("lang: russian item is translated", OutRu.wantsRussian({ item_text = "Редкость: редкий" }), true)
	H.eq("lang: english item is left alone", OutRu.wantsRussian({ item_text = "Rarity: Rare" }), false)
	H.eq("lang: no item text means no translation", OutRu.wantsRussian({ }), false)
end