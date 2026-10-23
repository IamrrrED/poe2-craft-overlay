-- PoE2 Craft Overlay : Item/Ocr.lua
-- Turn text read from a picture of an item tooltip into the format the item parser
-- expects.
--
-- OCR does not reproduce the copied-item format: the `--------` separators are dropped
-- (they are long runs of punctuation that no OCR engine reports), spacing drifts, and a
-- percent sign can be lost. The parser is strict about sections, so this module rebuilds
-- them: every punctuation-only line becomes a separator again, and text without any
-- separators at all is split into the game's own blocks (header, properties, modifiers,
-- trailing fields) by keyword.
--
-- Nothing here invents content: unrecognised lines are kept verbatim, because a modifier
-- the parser cannot match is reported as unknown rather than silently dropped.

local Ocr = { }

-- Lines the game uses as section separators, once OCR has had its way with them.
local SEPARATOR = "^[%-_=~%.%*%s]+$"

-- Fields that belong to the item itself rather than to a modifier.
local PROPERTY_PREFIX = {
	"quality", "evasion rating", "armour", "armor", "energy shield", "sockets",
	"requirements", "level", "str", "dex", "int", "critical strike chance",
	"physical damage", "elemental damage", "attacks per second", "weapon range",
	"stack size", "experience", "quality:", "radius", "limited to", "requires",
	"item class:", "rarity:", "item level:", "note:",
}

local function trim(text)
	return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isProperty(line)
	local lowered = line:lower()
	for _, prefix in ipairs(PROPERTY_PREFIX) do
		if lowered:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- The first lines of a tooltip name the item: its class, its rarity, then the item name and
-- the base type. They look like properties, but they belong to the header block, and the
-- name and base lines that follow them are not properties at all.
local HEADER_PREFIX = { "item class:", "rarity:" }

local function isHeaderField(line)
	local lowered = line:lower()
	for _, prefix in ipairs(HEADER_PREFIX) do
		if lowered:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- A modifier line: the game writes them as "+37% to Cold Resistance", "Adds 3 to 8 ...",
-- "12% increased ...". Anything already starting with a sign or a percentage is one.
local function isModifier(line)
	if line:match("^[%+%-]") then
		return true
	end
	if line:find("%%", 1, true) then
		return true
	end
	local lowered = line:lower()
	return lowered:match("^%d+%.?%d*%%") ~= nil
		or lowered:match("^adds ") ~= nil
		or lowered:match("^%d+ to %d+") ~= nil
end

--- Normalise OCR text so the item parser can read it.
-- @param raw text as returned by the OCR script
-- @return text in the copied-item layout, plus a table describing what was reconstructed
function Ocr.toItemText(raw)
	local kept, hadSeparator = { }, false
	for line in tostring(raw or ""):gmatch("[^\r\n]+") do
		local trimmed = trim(line)
		if trimmed ~= "" then
			if trimmed:match(SEPARATOR) then
				hadSeparator = true
				kept[#kept + 1] = "--------"
			else
				kept[#kept + 1] = trimmed
			end
		end
	end

	if hadSeparator then
		return table.concat(kept, "\n"), { rebuilt = false, lines = #kept }
	end

	-- No separators anywhere: rebuild the blocks. The header is everything up to the
	-- first property or modifier line, which is how the game orders a tooltip too.
	local header, properties, modifiers, trailing = { }, { }, { }, { }
	local phase = "header"
	for _, line in ipairs(kept) do
		local lowered = line:lower()
		if lowered:sub(1, #"item level") == "item level" then
			trailing[#trailing + 1] = line
			phase = "trailing"
		elseif phase == "header" and isHeaderField(line) then
			-- "Item Class: ..." and "Rarity: ..." stay in the header: they are part of the same
			-- block as the name and the base type that follow them. Treating them as
			-- properties pushed the name and the base into the modifier block, and the item
			-- then had a property line as its base type.
			header[#header + 1] = line
		elseif isProperty(line) then
			properties[#properties + 1] = line
			phase = "properties"
		elseif isModifier(line) then
			modifiers[#modifiers + 1] = line
			phase = "modifiers"
		elseif phase == "header" then
			header[#header + 1] = line
		else
			-- An unclassified line after the header is far more likely to be a modifier
			-- than a field, so it stays with the modifiers where the parser can judge it.
			modifiers[#modifiers + 1] = line
		end
	end

	local out = { }
	local function block(list)
		if #list > 0 then
			out[#out + 1] = table.concat(list, "\n")
		end
	end
	block(header)
	block(properties)
	block(modifiers)
	block(trailing)
	return table.concat(out, "\n--------\n"), {
		rebuilt = true,
		lines = #kept,
		header = #header,
		properties = #properties,
		modifiers = #modifiers,
		trailing = #trailing,
	}
end

--- Statistics for the diagnostics log.
function Ocr.stats()
	return { separatorPattern = SEPARATOR, propertyPrefixes = #PROPERTY_PREFIX }
end

return Ocr
