-- PoE2 Craft Overlay : Item/Categories.lua
-- The category the game itself puts a base type in.
--
-- The parser's item class comes from Path of Building data, which is a Path of Exile 1
-- heritage: it names some PoE2 things differently and cannot know about things PoE2 added.
-- The trade site's own data groups every base type into the categories the game uses
-- (accessory, armour, weapon, jewel, flask, gem, currency, map, sanctum, wombgift), so a
-- disagreement is worth reporting and a missing class can be filled in.

local Categories = { }

local dataCache = nil
local function data()
	if dataCache == nil then
		local ok, loaded = pcall(require, "Data.categories")
		dataCache = (ok and type(loaded) == "table" and type(loaded.byBase) == "table")
			and loaded or false
	end
	return dataCache or nil
end

--- The official category of a base type, or nil when the base is not in the game's list.
function Categories.of(baseType)
	local store = data()
	if not store or type(baseType) ~= "string" or baseType == "" then
		return nil
	end
	local found = store.byBase[baseType]
	if found then
		return found
	end
	-- Stored names come without the game's leading annotations, so try the plain form too.
	local plain = baseType:gsub("%s*%b()", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return store.byBase[plain]
end

--- Does this category look like armour or a weapon (things with defence or damage)?
function Categories.isGear(category)
	return category == "armour" or category == "weapon" or category == "accessory"
		or category == "jewel" or category == "flask"
end

--- Statistics for the diagnostics log.
function Categories.stats()
	local store = data()
	local count = 0
	if store then
		for _ in pairs(store.byBase) do
			count = count + 1
		end
	end
	return { bases = count, source = store and store.source or nil }
end

return Categories
