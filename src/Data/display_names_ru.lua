-- PoE2 Craft Overlay : Data/display_names_ru.lua
-- GENERATED FILE - do not edit by hand (tools/build_display_names.py).
--
-- English name -> Russian name, and English modifier template -> Russian modifier template.
-- Built by inverting the pairs the parser already uses (Item/Ru.lua, Data/ru_bases.lua,
-- Data/ru_stats_*.lua), so the parsing direction and the display direction cannot drift apart.
--
-- The pairs live in parts (display_names_ru_1.lua ...) for the same measured reason the modifier
-- dictionary does: the host reads a small data file reliably and a large one not at all.
-- Modifier keys are lower-cased templates with the numbers blanked to '#', exactly the form
-- Item/Ru.lua compares against; the numbers are put back by Ru.toRussian.
return {
	source = 'Item/Ru.lua + Data/ru_bases.lua + Data/ru_stats_*.lua (inverted)',
	generatedAt = "2026-10-20 18:08",
	nameCount = 3140,
	statCount = 3075,
	parts = {
		"display_names_ru_1",
		"display_names_ru_2",
		"display_names_ru_3",
		"display_names_ru_4",
		"display_names_ru_5",
		"display_names_ru_6",
		"display_names_ru_7",
		"display_names_ru_8",
		"display_names_ru_9",
		"display_names_ru_10",
		"display_names_ru_11",
	},
}
