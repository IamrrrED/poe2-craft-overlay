-- PoE2 Craft Overlay : Data/fonts/franklin_13.lua
-- GENERATED FILE - do not edit by hand (tools/build_fonts.ps1).
--
-- Glyph atlas metrics. The host's bitmap fonts have no Cyrillic glyphs, so the panel
-- draws every character as one cell of this atlas. dvances holds a per-glyph
-- advance in atlas pixels, which is what lets proportional faces (Segoe UI, Arial)
-- render correctly instead of being forced onto a monospaced grid.
return {
	generated = '2026-10-06 07:54',
	id = 'franklin_13',
	label = 'Franklin Gothic Medium 13 (proportional)',
	font = 'Franklin Gothic Medium',
	kind = 'prop',
	style = 'Regular',
	baseSize = 13,
	isDefault = false,
	file = 'Data/fonts/franklin_13.png',
	columns = 32,
	rows = 6,
	cellWidth = 21,
	cellHeight = 15,
	lineHeight = 15,
	codeCount = 171,
	codepoints = { 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 1025, 1105, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068, 1069, 1070, 1071, 1072, 1073, 1074, 1075, 1076, 1077, 1078, 1079, 1080, 1081, 1082, 1083, 1084, 1085, 1086, 1087, 1088, 1089, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1101, 1102, 1103, 8470, 8212, 183, 8594, 176, 215, 8804, 8805, 10003, 9888 },
	advances = { 5, 9, 10, 13, 13, 15, 14, 8, 9, 9, 13, 13, 8, 8, 8, 11, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 8, 8, 13, 13, 13, 12, 14, 13, 13, 13, 14, 12, 12, 13, 13, 8, 10, 13, 12, 16, 14, 13, 13, 13, 13, 12, 11, 13, 12, 17, 12, 12, 12, 9, 11, 9, 12, 12, 12, 12, 12, 11, 12, 12, 9, 12, 12, 8, 8, 12, 8, 16, 12, 12, 12, 12, 9, 11, 9, 12, 11, 14, 11, 11, 10, 9, 12, 9, 13, 12, 12, 13, 13, 13, 11, 13, 12, 16, 12, 14, 14, 13, 12, 16, 13, 13, 13, 13, 13, 11, 12, 15, 12, 13, 13, 17, 17, 13, 16, 13, 13, 17, 13, 12, 12, 12, 10, 11, 12, 14, 11, 12, 12, 12, 11, 14, 12, 12, 12, 12, 11, 10, 11, 14, 11, 12, 12, 15, 16, 12, 15, 11, 11, 15, 12, 18, 14, 6, 18, 13, 13, 13, 13, 20, 18 },
	tracking = 0.94,
	-- Blank cells in the atlas: codepoints this face cannot draw. A non-empty list that
	-- includes Cyrillic means the panel must not be shown in Russian with this atlas.
	missingGlyphs = {  },
	missingCount = 0,
}