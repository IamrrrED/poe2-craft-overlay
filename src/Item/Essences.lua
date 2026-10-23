-- PoE2 Craft Overlay : Item/Essences.lua
-- Essences are the game's *guaranteed* craft: an essence always applies one specific
-- modifier, and which modifier that is depends on the item class. PoB carries that
-- table (Data/essences.lua, generated from Essence.lua), so the overlay can show
-- exactly what an essence would give instead of a generic description.
--
-- Odds are 100% by definition - the interesting part is which modifier, at which
-- tier, and whether the craft is blocked because the item already has that mod group.

local Mods = require("Item.Mods")

local Essences = { }

-- Cost tier per essence tier, so the advisor can offer the cheap option first.
local TIER_COST = {
	[""] = "medium",
	Lesser = "low",
	Greater = "high",
	Perfect = "veryhigh",
}

local COST_RANK = { low = 1, medium = 2, high = 3, veryhigh = 4, ["?"] = 5 }

local cached = nil

local function list()
	if cached == nil then
		local ok, loaded = pcall(require, "Data.essences")
		cached = (ok and type(loaded) == "table" and loaded.list) or { }
	end
	return cached
end

--- Display name of an essence: the English name from the game data.
function Essences.label(name)
	return tostring(name)
end


--- Data provenance for the UI/tests.
function Essences.stats()
	local ok, loaded = pcall(require, "Data.essences")
	if ok and type(loaded) == "table" and loaded.stats then
		return loaded.stats
	end
	return { essences = 0 }
end

--- Essences usable on this item, best first.
-- @param item parsed + annotated item
-- @param opts { excludeGroups = table|nil, limit = number|nil }
-- @return list of {
--   name, label, type, tier, level, mod = { groupKey, text, tier, lvl },
--   chance = 100, blocked = bool (group already on the item), needsLevel = bool,
-- }
function Essences.optionsFor(item, opts)
	opts = opts or { }
	local class = item and item.itemClass
	if not class then
		return { }
	end
	-- Groups already on the item are blocked by the "one modifier per group" rule; if
	-- the caller did not supply them, derive them from the item itself.
	local excludeGroups = opts.excludeGroups
	if not excludeGroups then
		excludeGroups = { }
		for _, mod in ipairs(item.explicitMods or { }) do
			if mod.mod then
				excludeGroups[mod.mod.groupKey] = true
			end
		end
	end

	local options = { }
	for _, essence in ipairs(list()) do
		-- The game writes class names in the plural ("Item Class: Helmets") while the data
		-- tables are keyed by the singular ("Helmet"). Looking up only the exact name silently
		-- lost every essence for armour, so both forms are tried.
		local mods = essence.mods
		local modKey = mods and (mods[class] or mods[(class:gsub("s$", ""))])
		if modKey then
			local info = Mods.byKey(modKey)
			if info then
				options[#options + 1] = {
					name = essence.name,
					label = Essences.label(essence.name),
					type = essence.type,
					tier = essence.tier,
					level = essence.level,
					mod = {
						groupKey = info.groupKey,
						text = info.text,
						tier = info.tier,
						lvl = info.lvl,
					},
					chance = 100,
					cost = TIER_COST[essence.tier or ""] or "medium",
					blocked = excludeGroups[info.groupKey] == true,
					needsLevel = (item.itemLevel or 0) < info.lvl,
				}
			end
		end
	end

	table.sort(options, function(a, b)
		if a.blocked ~= b.blocked then
			return not a.blocked
		end
		-- Cheapest usable essence first (the MIN route), then the better modifier tier.
		local rankA = COST_RANK[a.cost] or 5
		local rankB = COST_RANK[b.cost] or 5
		if rankA ~= rankB then
			return rankA < rankB
		end
		if a.mod.tier ~= b.mod.tier then
			return a.mod.tier < b.mod.tier
		end
		return a.name < b.name
	end)

	if opts.limit and #options > opts.limit then
		local trimmed = { }
		for index = 1, opts.limit do
			trimmed[index] = options[index]
		end
		return trimmed
	end
	return options
end

return Essences
