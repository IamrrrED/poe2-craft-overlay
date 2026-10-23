-- PoE2 Craft Overlay : Data/ru_stats.lua
-- GENERATED FILE - do not edit by hand (tools/fetch_ru_map.py).
--
-- Index of the Russian modifier dictionaries. Each group lives in its own file
-- (ru_stats_<kind>.lua) because the host reads a small data file reliably and a large
-- one not at all; the engine loads them on first use and merges them.
return {
	source = 'pathofexile.com/api/trade2/data/stats (en + ru, paired by id)',
	count = 3084,
	parts = {
		"ru_stats_enchant_1",
		"ru_stats_explicit_1",
		"ru_stats_explicit_2",
		"ru_stats_explicit_3",
		"ru_stats_explicit_4",
		"ru_stats_explicit_5",
		"ru_stats_explicit_6",
		"ru_stats_explicit_7",
		"ru_stats_explicit_8",
		"ru_stats_implicit_1",
	},
	counts = {
		["enchant"] = 6,
		["explicit"] = 3021,
		["implicit"] = 57,
	},
}
