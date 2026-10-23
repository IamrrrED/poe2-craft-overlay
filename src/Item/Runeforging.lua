-- PoE2 Craft Overlay : Item/Runeforging.lua
-- Runeforging / runemastering turns a base type into an upgraded one ("Runeforged ...",
-- "Runemastered ..."). Which bases can be transformed comes from PoB's
-- VerisiumCrafts.lua, extracted into Data/runeforging.lua.

local Runeforging = { }

local cached = nil

local function table_()
	if cached == nil then
		local ok, loaded = pcall(require, "Data.runeforging")
		cached = (ok and type(loaded) == "table" and loaded.byBase) or { }
	end
	return cached
end

function Runeforging.stats()
	local ok, loaded = pcall(require, "Data.runeforging")
	if ok and type(loaded) == "table" and loaded.stats then
		return loaded.stats
	end
	return { bases = 0 }
end

--- Transformed base names for a base type, or nil when it cannot be runeforged.
function Runeforging.forBase(baseName)
	if not baseName or baseName == "" then
		return nil
	end
	return table_()[baseName]
end

--- Convenience: does this item's base have a runeforging route?
function Runeforging.forItem(item)
	return Runeforging.forBase(item and item.baseType)
end

return Runeforging
