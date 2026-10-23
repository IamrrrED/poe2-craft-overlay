-- PoE2 Craft Overlay : Tests/test_categories.lua
-- The official category of a base type: a second opinion on the class the parser read.

local Categories = require("Item.Categories")

return function(H)
	H.eq("categories: amulet is an accessory", Categories.of("Crimson Amulet"), "accessory")
	H.eq("categories: body armour is armour", Categories.of("Leather Vest"), "armour")
	H.eq("categories: dagger is a weapon", Categories.of("Glass Shank"), "weapon")
	H.eq("categories: jewel stays a jewel", Categories.of("Emerald"), "jewel")
	H.eq("categories: unknown base gives nothing", Categories.of("Not A Real Base"), nil)
	H.eq("categories: empty input is handled", Categories.of(""), nil)
	H.eq("categories: nil input is handled", Categories.of(nil), nil)

	H.eq("categories: gear is recognised", Categories.isGear("armour"), true)
	H.eq("categories: currency is not gear", Categories.isGear("currency"), false)

	local stats = Categories.stats()
	H.eq("categories: the table is loaded", stats.bases > 1000, true)
	H.eq("categories: the source is recorded", stats.source ~= nil, true)
end
