-- PoE2 Craft Overlay : Tests/test_parser.lua
-- Fixtures follow the in-game clipboard layout (sections separated by "--------").

local Parser = require("Item.Parser")

-- Rare gloves, tagged implicits (advanced copy), corrupted.
local RARE_TAGGED = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Quality: +20% (augmented)
Armour: 320 (augmented)
--------
Requirements:
Level: 78
Str: 100
--------
Sockets: S S
--------
Item Level: 82
--------
+30 to Strength (implicit)
--------
+120 to maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
--------
Corrupted
]]

-- Magic item: single name line holding prefix + base + suffix.
local MAGIC = [[
Item Class: Boots
Rarity: Magic
Runed Slippers of the Whelpling
--------
Quality: +12% (augmented)
Evasion Rating: 210 (augmented)
--------
Item Level: 65
--------
+25% to Movement Speed
+35 to maximum Life
]]

-- Normal base with no explicit modifiers at all.
local NORMAL = [[
Item Class: Bows
Rarity: Normal
Composite Bow
--------
Physical Damage: 20-38
Critical Hit Chance: 5.00%
Attacks per Second: 1.20
--------
Item Level: 62
]]

-- Advanced copy: modifier roll ranges must be stripped from the text and kept.
local RANGED = [[
Item Class: Rings
Rarity: Rare
Rune Knot
Gold Ring
--------
Item Level: 75
--------
+(30-40) to Strength
+(50-70) to maximum Life
--------
Corrupted
Twice Corrupted
]]

-- Plain Ctrl+C: no tags, so the first block is only *suspected* to be implicit.
local UNTAGGED = [[
Item Class: Helmets
Rarity: Rare
Gloom Visage
Expert Plated Helm
--------
Item Level: 80
--------
+25 to Strength
--------
+90 to maximum Life
+40% to Fire Resistance
]]

return function(H)
	local item = Parser.parse(RARE_TAGGED)
	H.eq("parser: item class", item.itemClass, "Gloves")
	H.eq("parser: rarity", item.rarity, "RARE")
	H.eq("parser: name", item.name, "Doom Grip")
	H.eq("parser: base type", item.baseType, "Expert Vaal Gauntlets")
	H.eq("parser: item level", item.itemLevel, 82)
	H.eq("parser: quality", item.quality, 20)
	H.eq("parser: implicit mods", #item.implicitMods, 1)
	H.eq("parser: explicit mods", #item.explicitMods, 3)
	H.eq("parser: sockets", #item.sockets, 2)
	H.eq("parser: requirements level", item.requirements["Level"], "78")
	H.eq("parser: corrupted flag", item.flags.corrupted, true)
	H.eq("parser: not modifiable", item.isModifiable, false)
	H.eq("parser: armour property", item.properties["Armour"].value, "320")
	H.eq("parser: armour augmented", item.properties["Armour"].augmented, true)
	H.eq("parser: valid", item.valid, true)

	local magic = Parser.parse(MAGIC)
	H.eq("parser: magic rarity", magic.rarity, "MAGIC")
	H.eq("parser: magic base is the name line", magic.baseType, magic.name)
	H.eq("parser: magic explicit mods", #magic.explicitMods, 2)

	local normal = Parser.parse(NORMAL)
	H.eq("parser: normal rarity", normal.rarity, "NORMAL")
	H.eq("parser: normal base", normal.baseType, "Composite Bow")
	H.eq("parser: normal has no mods", #normal.explicitMods, 0)
	H.eq("parser: normal modifiable", normal.isModifiable, true)

	local ranged = Parser.parse(RANGED)
	H.eq("parser: range stripped from mod text", ranged.explicitMods[1].text, "+ to Strength")
	H.eq("parser: range min captured", ranged.explicitMods[1].ranges[1].min, 30)
	H.eq("parser: range max captured", ranged.explicitMods[1].ranges[1].max, 40)
	H.eq("parser: twice corrupted flag", ranged.flags.doubleCorrupted, true)

	local untagged = Parser.parse(UNTAGGED)
	H.eq("parser: untagged explicit count", #untagged.explicitMods, 3)
	H.eq("parser: untagged suspected implicit count", #untagged.suspectedImplicitMods, 1)
	H.eq("parser: untagged implicit list stays empty", #untagged.implicitMods, 0)
	H.eq("parser: untagged note code", untagged.notes[1] and untagged.notes[1].code, "suspected_implicit")
	H.eq("parser: untagged note param", untagged.notes[1] and untagged.notes[1].params[1], 1)

	local empty = Parser.parse("   \n  ")
	H.eq("parser: empty input invalid", empty.valid, false)
	H.eq("parser: empty input note code", empty.notes[1] and empty.notes[1].code, "empty_input")
end
