-- PoE2 Craft Overlay : Core/font.lua
-- The overlay's own text renderer, with selectable glyph atlases.
--
-- Why it exists: the host draws text with PoB's bitmap fonts, and none of the three
-- accepted font names ("VAR", "VAR BOLD", "FIXED") contains Cyrillic glyphs - the
-- engine renders them as "[u0431][u0432]..." placeholders, and other names are
-- rejected outright. So Cyrillic is drawn glyph by glyph from our own atlas
-- (tools/build_fonts.ps1) using DrawImage's texture-coordinate variant.
--
-- Atlases keep a uniform grid of cells but carry a PER-GLYPH advance, so proportional
-- faces (Segoe UI, Arial) render correctly. Several variants are built and can be
-- compared side by side (font_compare.flag) or selected via config.ui.fontVariant.
--
-- Split for testability: metrics, UTF-8 decoding, indexing and width arithmetic are
-- pure Lua (headless tests); only loadAtlas/draw touch the renderer.

local Font = { }

local metricsCache = { }
local handleCache = { }
local atlasState = { } -- variant id -> "ready" | "failed"
local currentId = nil
local manifest = nil
local trackingOverride = nil

--- Manifest of the available atlases (Data/fonts.lua).
function Font.manifest()
	if manifest == nil then
		local ok, loaded = pcall(require, "Data.fonts")
		manifest = (ok and type(loaded) == "table") and loaded or false
	end
	return manifest or nil
end

function Font.variants()
	local data = Font.manifest()
	return (data and data.variants) or { }
end

--- Id of the variant currently in use.
function Font.currentId()
	if currentId then
		return currentId
	end
	local data = Font.manifest()
	currentId = (data and data.default) or "segoe_semibold_16"
	return currentId
end

--- Select the atlas to use. Unknown ids fall back to the manifest default.
-- @return the id actually selected
function Font.use(id)
	local wanted = id
	if wanted then
		local known = false
		for _, variant in ipairs(Font.variants()) do
			if variant.id == wanted then
				known = true
				break
			end
		end
		if not known then
			wanted = nil
		end
	end
	currentId = wanted or (Font.manifest() and Font.manifest().default) or "segoe_semibold_16"
	return currentId
end

--- Atlas metrics for a variant (default: the current one).
function Font.metricsFor(id)
	local variantId = id or Font.currentId()
	if metricsCache[variantId] == nil then
		local ok, loaded = pcall(require, "Data.fonts." .. variantId)
		metricsCache[variantId] = (ok and type(loaded) == "table" and loaded.codepoints) and loaded or false
	end
	return metricsCache[variantId] or nil
end

--- Metrics of the current variant.
function Font.metrics()
	return Font.metricsFor(Font.currentId())
end

local function indexFor(variantId)
	local metrics = Font.metricsFor(variantId)
	if not metrics then
		return nil
	end
	if not metrics._index then
		local index = { }
		for position, code in ipairs(metrics.codepoints or { }) do
			index[code] = position
		end
		metrics._index = index
	end
	return metrics._index
end

--- Decode a UTF-8 string into a list of codepoints (Lua 5.1 has no utf8 library).
function Font.decode(text)
	local codes = { }
	local s = tostring(text)
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		if c < 0x80 then
			codes[#codes + 1] = c
			i = i + 1
		elseif c < 0xE0 then
			local c2 = s:byte(i + 1) or 0
			codes[#codes + 1] = (c - 0xC0) * 64 + (c2 - 0x80)
			i = i + 2
		elseif c < 0xF0 then
			local c2 = s:byte(i + 1) or 0
			local c3 = s:byte(i + 2) or 0
			codes[#codes + 1] = (c - 0xE0) * 4096 + (c2 - 0x80) * 64 + (c3 - 0x80)
			i = i + 3
		else
			local c2 = s:byte(i + 1) or 0
			local c3 = s:byte(i + 2) or 0
			local c4 = s:byte(i + 3) or 0
			codes[#codes + 1] = (c - 0xF0) * 262144 + (c2 - 0x80) * 4096 + (c3 - 0x80) * 64 + (c4 - 0x80)
			i = i + 4
		end
	end
	return codes
end

--- Is a codepoint present in the atlas?
function Font.hasGlyph(code, id)
	local index = indexFor(id or Font.currentId())
	return index ~= nil and index[code] ~= nil
end

--- Letter spacing (tracking) of an atlas: 1.0 = the font's natural advance, values
-- below 1 squeeze the gap between letters. Baked into each atlas, overridable at
-- runtime so the user can tighten or loosen the panel text.
function Font.trackingFor(id)
	if trackingOverride then
		return trackingOverride
	end
	local metrics = Font.metricsFor(id or Font.currentId())
	return (metrics and metrics.tracking) or 1
end

--- Override the tracking; pass nil to fall back to the atlas default.
function Font.setTracking(value)
	trackingOverride = tonumber(value)
	return Font.trackingFor(Font.currentId())
end

--- Advance of one character at the given pixel size (per-glyph, so proportional
-- faces keep correct spacing; scaled by the tracking).
function Font.advanceOf(code, size, id)
	local metrics = Font.metricsFor(id or Font.currentId())
	if not metrics then
		return (size or 16) * 0.5
	end
	local index = indexFor(id or Font.currentId())
	local position = index and index[code]
	local advance
	if position and metrics.advances then
		advance = metrics.advances[position]
	end
	if not advance then
		-- Unknown glyph: fall back to a space so the cursor still moves.
		local spacePosition = index and index[32]
		advance = (spacePosition and metrics.advances and metrics.advances[spacePosition])
			or metrics.cellWidth or (size or 16) * 0.5
	end
	local scale = ((size or metrics.baseSize) / metrics.baseSize) * Font.trackingFor(id)
	return advance * scale
end

--- Width of a single line of text at the given pixel size.
function Font.width(text, size, id)
	local total = 0
	for _, code in ipairs(Font.decode(text)) do
		total = total + Font.advanceOf(code, size, id)
	end
	return total
end

--- Characters in `text` the current atlas cannot draw.
function Font.missing(text, id)
	local missing = { }
	for _, code in ipairs(Font.decode(text)) do
		if not Font.hasGlyph(code, id) then
			missing[#missing + 1] = code
		end
	end
	return missing
end

--- Load an atlas image. Renderer-dependent, so never called from tests.
-- @return handle|nil, reason
function Font.loadAtlas(id)
	local variantId = id or Font.currentId()
	if atlasState[variantId] == "ready" then
		return handleCache[variantId]
	end
	if atlasState[variantId] == "failed" then
		return nil, "atlas load previously failed"
	end

	local metrics = Font.metricsFor(variantId)
	if not metrics then
		atlasState[variantId] = "failed"
		return nil, "no metrics for " .. variantId
	end
	if type(NewImageHandle) ~= "function" then
		atlasState[variantId] = "failed"
		return nil, "host has no image API"
	end

	local ok, img = pcall(NewImageHandle)
	if not ok or not img then
		atlasState[variantId] = "failed"
		return nil, "NewImageHandle failed"
	end
	local loaded, err = pcall(function() img:Load(metrics.file, "CLAMP") end)
	if not loaded then
		atlasState[variantId] = "failed"
		return nil, "atlas load failed: " .. tostring(err)
	end
	handleCache[variantId] = img
	atlasState[variantId] = "ready"
	return img
end

function Font.available(id)
	return atlasState[id or Font.currentId()] == "ready"
end

--- Draw one line with a specific atlas.
-- The caller sets the draw colour; images are tinted by it, like DrawString.
-- @return number width drawn in pixels
function Font.drawVariant(id, text, x, y, size)
	local metrics = Font.metricsFor(id)
	local img = Font.loadAtlas(id)
	if not metrics or not img then
		return 0
	end

	local scale = (size or metrics.baseSize) / metrics.baseSize
	local cellW = metrics.cellWidth * scale
	local cellH = metrics.cellHeight * scale
	local atlasW = metrics.columns * metrics.cellWidth
	local atlasH = metrics.rows * metrics.cellHeight
	local index = indexFor(id)

	local cursor = x
	for _, code in ipairs(Font.decode(text)) do
		local position = index and index[code]
		if position then
			local cell = position - 1
			local col = cell % metrics.columns
			local row = math.floor(cell / metrics.columns)
			local u0 = (col * metrics.cellWidth) / atlasW
			local v0 = (row * metrics.cellHeight) / atlasH
			local u1 = ((col + 1) * metrics.cellWidth) / atlasW
			local v1 = ((row + 1) * metrics.cellHeight) / atlasH
			DrawImage(img, cursor, y, cellW, cellH, u0, v0, u1, v1)
		end
		cursor = cursor + Font.advanceOf(code, size, id)
	end
	return cursor - x
end

--- Draw with the selected atlas.
function Font.draw(text, x, y, size)
	return Font.drawVariant(Font.currentId(), text, x, y, size)
end

--- Draw text, falling back to the host's DrawString when no atlas is available.
-- @param api table { drawString = fn, asciiSafe = fn }
function Font.drawOrFallback(api, text, x, y, size, fontName)
	if Font.available() or Font.loadAtlas() then
		return Font.draw(text, x, y, size)
	end
	local safe = api.asciiSafe and api.asciiSafe(text) or text
	api.drawString(x, y, "LEFT", size, fontName, safe)
	return Font.width(safe, size)
end

return Font
