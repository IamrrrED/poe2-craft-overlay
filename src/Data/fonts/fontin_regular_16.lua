-- PoE2 Craft Overlay : Data/fonts/fontin_regular_16.lua
-- GENERATED FILE - do not edit by hand (tools/build_fonts.ps1).
--
-- Glyph atlas metrics. The host's bitmap fonts have no Cyrillic glyphs, so the panel
-- draws every character as one cell of this atlas. dvances holds a per-glyph
-- advance in atlas pixels, which is what lets proportional faces (Segoe UI, Arial)
-- render correctly instead of being forced onto a monospaced grid.
return {
	generated = '2026-10-06 07:54',
	id = 'fontin_regular_16',
	label = 'Fontin Regular 16 (as in Sidekick)',
	font = 'Fontin',
	kind = 'prop',
	style = 'Regular',
	baseSize = 16,
	isDefault = false,
	file = 'Data/fonts/fontin_regular_16.png',
	columns = 32,
	rows = 6,
	cellWidth = 25,
	cellHeight = 20,
	lineHeight = 20,
	codeCount = 171,
	codepoints = { 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 1025, 1105, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103, 8470, 8212, 183, 8594, 176, 215, 8804, 8805, 10003, 9888 },
	advances = { 6, 10, 12, 17, 13, 19, 18, 10, 11, 11, 12, 14, 9, 11, 9, 11, 15, 11, 13, 13, 14, 13, 15, 13, 14, 15, 10, 10, 12, 14, 12, 13, 21, 16, 15, 16, 17, 14, 14, 16, 18, 11, 11, 15, 14, 21, 18, 17, 15, 17, 16, 14, 15, 17, 16, 21, 15, 14, 15, 10, 12, 10, 16, 13, 11, 14, 15, 14, 15, 14, 11, 14, 15, 10, 10, 15, 10, 20, 16, 15, 15, 15, 13, 13, 12, 16, 14, 20, 14, 14, 14, 11, 7, 11, 15, 17, 15, 17, 17, 17, 15, 19, 17, 21, 17, 18, 18, 17, 18, 20, 18, 19, 18, 17, 18, 16, 17, 20, 17, 18, 17, 20, 21, 19, 21, 17, 18, 23, 18, 15, 15, 15, 12, 16, 15, 18, 14, 15, 15, 14, 15, 18, 15, 15, 15, 15, 14, 14, 14, 20, 14, 16, 15, 19, 20, 16, 18, 15, 14, 18, 15, 23, 17, 10, 23, 12, 16, 16, 16, 24, 22 },
	tracking = 0.94,
	-- Blank cells in the atlas: codepoints this face cannot draw. A non-empty list that
	-- includes Cyrillic means the panel must not be shown in Russian with this atlas.
	missingGlyphs = {  },
	missingCount = 0,
}