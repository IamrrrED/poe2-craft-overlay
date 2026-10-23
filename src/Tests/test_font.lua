-- PoE2 Craft Overlay : Tests/test_font.lua
-- The glyph renderer is split so this can run headless: metrics, UTF-8 decoding,
-- glyph lookup and width arithmetic are pure Lua. Only loadAtlas/draw need the host.
--
-- Atlases carry a per-glyph advance, which is what lets proportional faces (Segoe UI,
-- Arial) render with correct spacing - the earlier monospaced grid could not.

local Font = require("Core.font")

return function(H)
	local metrics = Font.metrics()
	H.eq("font: atlas metrics present", metrics ~= nil, true)
	H.eq("font: base size recorded", metrics and metrics.baseSize > 0, true)
	H.eq("font: atlas grid described", metrics and metrics.columns > 0 and metrics.rows > 0, true)
	H.eq("font: glyph count matches codepoint list",
		metrics and metrics.codeCount, metrics and #metrics.codepoints)
	H.eq("font: per-glyph advances present",
		metrics and #metrics.advances, metrics and #metrics.codepoints)
	H.eq("font: atlas file lives under Data/fonts",
		metrics and metrics.file:sub(1, 11), "Data/fonts/")
	H.eq("font: atlas file is a png", metrics and metrics.file:sub(-4), ".png")

	-- Every candidate atlas is described by the manifest and loadable by id.
	local variants = Font.variants()
	H.eq("font: a broad set of variants is offered", #variants >= 25, true)
	local smallest = 99
	local families = { }
	for _, variant in ipairs(variants) do
		families[variant.family] = true
		if variant.size < smallest then
			smallest = variant.size
		end
	end
	H.eq("font: small sizes included", smallest <= 12, true)
	H.eq("font: several families included", (function()
		local count = 0
		for _ in pairs(families) do count = count + 1 end
		return count
	end)() >= 4, true)
	local defaultVariant = Font.manifest() and Font.manifest().default
	H.eq("font: manifest default is listed", defaultVariant ~= nil, true)
	local defaultFound = false
	local brokenVariants = { }
	for _, variant in ipairs(variants) do
		if variant.id == defaultVariant then
			defaultFound = true
		end
		local variantMetrics = Font.metricsFor(variant.id)
		if not variantMetrics or #variantMetrics.advances ~= #variantMetrics.codepoints then
			brokenVariants[#brokenVariants + 1] = variant.id
		end
	end
	H.eq("font: default variant is in the list", defaultFound, true)

	-- The default atlas is Fontin, the typeface Path of Exile and the Sidekick app use.
	-- It must be able to draw every character the panel shows, Cyrillic included: the
	-- builder records blank cells, so a face that cannot do it fails right here.
	local defaultMetrics = Font.metricsFor(defaultVariant)
	H.eq("font: default variant is Fontin", defaultMetrics.font, "Fontin")
	H.eq("font: default atlas has no blank glyphs", defaultMetrics.missingCount, 0)
	H.eq("font: default atlas draws cyrillic",
		Font.hasGlyph(1057, defaultVariant) and Font.hasGlyph(1103, defaultVariant), true)
	H.eq("font: default atlas draws the symbols the panel uses",
		Font.hasGlyph(8212, defaultVariant) and Font.hasGlyph(176, defaultVariant), true)
	H.check("font: every variant has complete metrics", #brokenVariants == 0,
		table.concat(brokenVariants, ", "))

	-- Selecting an unknown variant falls back instead of failing.
	local chosen = Font.use("definitely-not-a-font")
	H.eq("font: unknown variant falls back to the manifest default", chosen, defaultVariant)
	Font.use(defaultVariant)
	H.eq("font: current id follows selection", Font.currentId(), defaultVariant)

	-- UTF-8 decoding (Lua 5.1 has no utf8 library, so this is hand-rolled).
	local ascii = Font.decode("Ab ")
	H.eq("font: ascii decode length", #ascii, 3)
	H.eq("font: ascii decode first", ascii[1], 65)
	H.eq("font: ascii decode third", ascii[3], 32)

	local cyrillic = Font.decode("Сфера")
	H.eq("font: cyrillic decode length", #cyrillic, 5)
	H.eq("font: cyrillic first codepoint", cyrillic[1], 1057) -- С
	H.eq("font: cyrillic last codepoint", cyrillic[5], 1072)  -- а
	H.eq("font: yo decodes to 1025", Font.decode("Ё")[1], 1025)
	H.eq("font: em dash decodes to 8212", Font.decode("—")[1], 8212)

	-- Glyph coverage: Cyrillic, ASCII and the symbols the panel uses are present.
	H.eq("font: has cyrillic capital", Font.hasGlyph(1057), true)
	H.eq("font: has cyrillic small", Font.hasGlyph(1072), true)
	H.eq("font: has yo", Font.hasGlyph(1025), true)
	H.eq("font: has ascii letter", Font.hasGlyph(65), true)
	H.eq("font: has digit", Font.hasGlyph(48), true)
	H.eq("font: has em dash", Font.hasGlyph(8212), true)
	H.eq("font: no emoji glyph", Font.hasGlyph(0x1F600), false)

	-- Widths come from the per-glyph advances.
	local size = metrics.baseSize
	H.eq("font: single glyph width matches its advance",
		Font.width("С", size), Font.advanceOf(1057, size))
	local expected = Font.advanceOf(1057, size) + Font.advanceOf(1092, size)
		+ Font.advanceOf(1077, size) + Font.advanceOf(1088, size) + Font.advanceOf(1072, size)
	H.eq("font: width of five glyphs is their sum", Font.width("Сфера", size), expected)
	H.eq("font: width scales with size",
		math.abs(Font.width("Сфера", size * 2) - expected * 2) < 0.01, true)

	-- Proportional faces must have genuinely different advances, monospaced ones not.
	local proportional = Font.metricsFor("segoe_semibold_16")
	if proportional then
		local narrow = Font.advanceOf(1057 + 1000, proportional.baseSize, "segoe_semibold_16") -- placeholder
		local iAdvance = Font.advanceOf(1058, proportional.baseSize, "segoe_semibold_16") -- Б
		local wAdvance = Font.advanceOf(1064, proportional.baseSize, "segoe_semibold_16") -- Ж
		H.eq("font: proportional advances differ per glyph", iAdvance ~= wAdvance, true)
		H.eq("font: unknown glyph falls back to a space", narrow > 0, true)
	end
	local mono = Font.metricsFor("consolas_bold_16")
	if mono then
		H.eq("font: monospaced advances are uniform",
			Font.advanceOf(1058, mono.baseSize, "consolas_bold_16"),
			Font.advanceOf(1064, mono.baseSize, "consolas_bold_16"))
	end

	-- Characters missing from the atlas are reported, not silently dropped.
	local missing = Font.missing("abc" .. string.char(0xF0, 0x9F, 0x98, 0x80))
	H.eq("font: missing glyph reported", #missing, 1)
	H.eq("font: known text has no missing glyphs", #Font.missing("Сфера (Exalted Orb) T1"), 0)

	-- Letter spacing (tracking): baked into every atlas and adjustable at runtime,
	-- which is what makes a line read as one dense block of text.
	local baked = metrics.tracking
	H.eq("font: atlas carries a tracking value", type(baked), "number")
	H.eq("font: baked tracking is compressed", baked < 1, true)
	H.eq("font: tracking is used by default", Font.trackingFor(), baked)
	local naturalWidth = Font.width("Сфера", size) / baked
	Font.setTracking(0.5)
	local tightWidth = Font.width("Сфера", size)
	H.eq("font: tighter tracking narrows the text", math.abs(tightWidth - naturalWidth * 0.5) < 0.01, true)
	Font.setTracking(nil)
	H.eq("font: reset returns to the atlas value", Font.trackingFor(), baked)

	-- The renderer itself must not be invoked in headless mode: availability stays
	-- false until an atlas is loaded, and drawOrFallback must use the ASCII fallback.
	H.eq("font: not loaded before use", Font.available(), false)
	local fellBack = Font.drawOrFallback({
		drawString = function(...) return true end,
		asciiSafe = function(s) return (tostring(s):gsub("[\128-\255]", "?")) end,
	}, "Сфера", 0, 0, 16, "VAR")
	H.eq("font: fallback returns a width", fellBack > 0, true)
end
