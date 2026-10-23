-- PoE2 Craft Overlay : Tests/test_ocr.lua
-- Text read from a picture of a tooltip: OCR drops the "--------" separators and drifts in
-- spacing, so the blocks have to be rebuilt. The sample is the exact text that
-- tools/test_ocr.ps1 produces from its rendered tooltip.

local Ocr = require("Item.Ocr")
local Parser = require("Item.Parser")

local READ_FROM_IMAGE = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
Quality: +20% (augmented)
Evasion Rating: 296 (augmented)
+118 to maximum Life
+44% to Fire Resistance
+37% to Cold Resistance
Item Level: 82
]]

return function(H)
	local text, report = Ocr.toItemText(READ_FROM_IMAGE)
	H.eq("ocr: blocks are rebuilt", report.rebuilt, true)
	H.eq("ocr: the header keeps four lines", report.header, 4)
	H.eq("ocr: properties are separated", report.properties, 2)
	H.eq("ocr: modifiers are separated", report.modifiers, 3)
	H.eq("ocr: the item level is trailing", report.trailing, 1)

	local item = Parser.parse(text)
	H.eq("ocr: the parser accepts the rebuilt text", item ~= nil, true)
	-- The bug this test exists for: the class and rarity lines used to be taken as properties,
	-- which pushed the name and the base type into the modifier block and left a property line
	-- as the base type.
	H.eq("ocr: base type is the base line", item.baseType, "Blacksteel Gauntlets")
	H.eq("ocr: class is read", item.itemClass, "Gloves")
	H.eq("ocr: rarity is read", tostring(item.rarity):lower(), "rare")
	H.eq("ocr: item level is read", item.itemLevel, 82)

	-- Separators that did survive OCR must be kept as they are.
	local withSeparators, kept = Ocr.toItemText("Item Class: Gloves\n--------\nQuality: +20%")
	H.eq("ocr: surviving separators stop the rebuild", kept.rebuilt, false)
	H.eq("ocr: separators are normalised", withSeparators:find("--------", 1, true) ~= nil, true)
end
