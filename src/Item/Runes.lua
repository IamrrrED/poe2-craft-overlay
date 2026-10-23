-- PoE2 Craft Overlay : Item/Runes.lua
-- Runes, soul cores, idols and abyssal eyes. Unlike a currency roll, socketing a rune
-- applies ONE specific modifier to a specific item slot, so the chance is 100% by
-- definition - the interesting part is which rune fits which slot and how many the
-- item accepts (limit).
--
-- Data: Data/runes.lua, generated from PoB's ModRunes.lua by tools/extract_mods.py.

local Mods = require("Item.Mods")

local Runes = { }

-- Rune slot key -> list of tag groups. A slot matches when ANY group matches, and a
-- group matches when ALL of its tags are present on the item's base.
-- Tags come from Data/bases.lua (e.g. "body_armour", "one_hand_weapon").
-- Weapon and armour are families: a wand carries "wand" but not "weapon", so both the
-- generic tag and every specific weapon tag are accepted.
local WEAPON_GROUPS = {
	{ "weapon" }, { "one_hand_weapon" }, { "two_hand_weapon" },
	{ "wand" }, { "staff" }, { "sceptre" }, { "bow" }, { "crossbow" },
	{ "quarterstaff" }, { "spear" }, { "mace" }, { "dagger" }, { "flail" },
	{ "sword" }, { "axe" }, { "claw" }, { "talisman" },
}

local ARMOUR_GROUPS = {
	{ "armour" }, { "body_armour" }, { "helmet" }, { "gloves" }, { "boots" },
	{ "shield" }, { "buckler" }, { "focus" },
}

local SLOT_REQUIREMENTS = {
	["weapon"] = WEAPON_GROUPS,
	["armour"] = ARMOUR_GROUPS,
	["helmet"] = { { "helmet" } },
	["gloves"] = { { "gloves" } },
	["boots"] = { { "boots" } },
	["body armour"] = { { "body_armour" } },
	["shield"] = { { "shield" } },
	["buckler"] = { { "buckler" } },
	["focus"] = { { "focus" } },
	["wand"] = { { "wand" } },
	["staff"] = { { "staff" } },
	["sceptre"] = { { "sceptre" } },
	["bow"] = { { "bow" } },
	["crossbow"] = { { "crossbow" } },
	["quarterstaff"] = { { "quarterstaff" } },
	["spear"] = { { "spear" } },
	["talisman"] = { { "talisman" } },
	["one hand mace"] = { { "mace", "one_hand_weapon" } },
	["two hand mace"] = { { "mace", "two_hand_weapon" } },
	["caster"] = { { "wand" }, { "staff" }, { "sceptre" }, { "focus" } },
	["martial weapon wand or staff"] = { { "weapon" }, { "wand" }, { "staff" } },
}

local cached = nil

local function table_()
	if cached == nil then
		local ok, loaded = pcall(require, "Data.runes")
		cached = (ok and type(loaded) == "table" and loaded.bySlot) or { }
	end
	return cached
end

--- Split a slot key like "martial weapon wand or staff" into alternatives.
local function splitOr(text)
	local parts = { }
	local start = 1
	while true do
		local from, to = text:find(" or ", start, true)
		if not from then
			parts[#parts + 1] = text:sub(start)
			break
		end
		parts[#parts + 1] = text:sub(start, from - 1)
		start = to + 1
	end
	return parts
end

--- Does a rune slot key apply to an item with these base tags?
function Runes.slotMatches(slotKey, tagSet)
	local key = tostring(slotKey):lower()
	for _, part in ipairs(splitOr(key)) do
		-- A part can itself contain several words ("martial weapon wand"), so the whole
		-- part is tried first and then each of its tokens.
		local candidates = { part }
		if not SLOT_REQUIREMENTS[part] then
			for token in part:gmatch("[^ ]+") do
				candidates[#candidates + 1] = token
			end
		end
		local groups = nil
		for _, candidate in ipairs(candidates) do
			if SLOT_REQUIREMENTS[candidate] then
				groups = SLOT_REQUIREMENTS[candidate]
				break
			end
		end
		if groups then
			for _, group in ipairs(groups) do
				local all = true
				for _, tag in ipairs(group) do
					if not tagSet[tag] then
						all = false
						break
					end
				end
				if all then
					return true
				end
			end
		end
	end
	return false
end

--- Base tags of the item as a set, plus the class name as a fallback tag.
function Runes.tagsOf(item)
	local tagSet = { }
	local hints = Mods.hintsFor(item)
	for _, tag in ipairs(hints or { }) do
		tagSet[tostring(tag):lower()] = true
	end
	local class = tostring(item and item.itemClass or ""):lower()
	if class ~= "" then
		tagSet[class] = true
		tagSet[class:gsub("%s+", "_")] = true
	end
	return tagSet
end

function Runes.stats()
	local ok, loaded = pcall(require, "Data.runes")
	if ok and type(loaded) == "table" and loaded.stats then
		return loaded.stats
	end
	return { runes = 0, slots = 0, entries = 0 }
end

--- How many augment sockets this item has, and how many are still free.
--
-- The item text prints the empty ones as letters ("Sockets: S S"), so when the game gives us that, it is
-- the truth and the capacity table is only a fallback for text that omits it. What is already socketed
-- arrives as "Rune: ..." lines. A socketed augment cannot be removed, only overwritten, so "free" means
-- "you can still add", not "you can rearrange".
-- @param item parsed item
-- @param ruleset ruleset carrying the sockets spec
-- @return table { capacity, free, used, runes, note }
function Runes.socketsFor(item, ruleset)
	local spec = (ruleset or { }).sockets or { }
	local runes = item and item.runes or { }
	local used = #runes
	-- How many sockets the BASE has. The printed letters only say how many are still empty, so they can
	-- raise the floor but must never be added to the used count on their own.
	local capacity = nil
	local tagSet = Runes.tagsOf(item or { })
	local table_ = spec.capacity or { }
	local class = tostring(item and item.itemClass or ""):lower()
	if class:find("body armour", 1, true) or tagSet["body_armour"] then
		capacity = table_["body armour"]
	elseif tagSet["two_hand_weapon"] then
		capacity = table_["two hand weapon"]
	elseif tagSet["one_hand_weapon"] or tagSet["weapon"] then
		capacity = table_["one hand weapon"]
	elseif tagSet["helmet"] then
		capacity = table_["helmet"]
	elseif tagSet["gloves"] then
		capacity = table_["gloves"]
	elseif tagSet["boots"] then
		capacity = table_["boots"]
	elseif tagSet["shield"] then
		capacity = table_["shield"]
	elseif tagSet["buckler"] then
		capacity = table_["buckler"]
	elseif tagSet["focus"] then
		capacity = table_["focus"]
	end

	-- The game printed the empty sockets, so the item has at least (empty + used) of them: that catches a
	-- base whose table entry is missing, and an item the game gave an extra socket to.
	local printed = item and item.sockets or nil
	local fromPrint = (printed and #printed or 0) + used
	if fromPrint > 0 and (not capacity or fromPrint > capacity) then
		capacity = fromPrint
	end

	if not capacity then
		return nil
	end
	return {
		capacity = capacity,
		used = used,
		free = math.max(0, capacity - used),
		runes = runes,
		note = spec.note,
		-- An item that is already full can still take one more by corrupting it, which is a real but
		-- one-way move.
		vaalCanExceed = spec.vaalOrbCanExceed,
	}
end

--- Can this rune still be put into this item?
-- Two things stop it: no free socket, and the rune's own per-item limit already being reached (a rune
-- with limit 1 cannot be socketed twice even with sockets to spare).
-- @param item parsed item
-- @param option entry from Runes.optionsFor
-- @param sockets table from Runes.socketsFor
-- @return allowed boolean, reason string|nil
function Runes.canSocket(item, option, sockets)
	if not option then
		return false, "no rune"
	end
	local info = sockets or Runes.socketsFor(item, nil)
	if info and info.free <= 0 then
		return false, "no free socket"
	end
	local limit = tonumber(option.limit) or 1
	local already = 0
	for _, name in ipairs((info and info.runes) or { }) do
		if name == option.name then
			already = already + 1
		end
	end
	if already >= limit then
		return false, "limit reached"
	end
	return true, nil
end

--- Runes that fit this item, most accessible first.
-- @param item parsed item
-- @param opts { limit = number|nil }
-- @return list of { name, type, text, limit, levelReq, slot, chance = 100, unique }
function Runes.optionsFor(item, opts)
	opts = opts or { }
	if not item then
		return { }
	end
	local tagSet = Runes.tagsOf(item)
	local options = { }
	for slot, entries in pairs(table_()) do
		if Runes.slotMatches(slot, tagSet) then
			for _, entry in ipairs(entries) do
				options[#options + 1] = {
					name = entry.name,
					type = entry.type,
					text = entry.texts and entry.texts[1] or "",
					extraTexts = entry.texts,
					limit = entry.limit or 1,
					levelReq = entry.levelReq or 0,
					unique = entry.unique == true,
					localMod = entry.isLocal == true,
					slot = slot,
					chance = 100,
				}
			end
		end
	end

	table.sort(options, function(a, b)
		-- Cheapest to use first: lower level requirement, then plain runes before
		-- unique-only items (idols, abyssal eyes).
		if a.levelReq ~= b.levelReq then
			return a.levelReq < b.levelReq
		end
		if a.unique ~= b.unique then
			return not a.unique
		end
		if a.type ~= b.type then
			return a.type < b.type
		end
		return a.name < b.name
	end)

	-- The same rune can fit several slots of one item; keep one row per rune.
	local seen, unique = { }, { }
	for _, option in ipairs(options) do
		local key = option.name .. "|" .. option.text
		if not seen[key] then
			seen[key] = true
			unique[#unique + 1] = option
		end
	end

	if opts.limit and #unique > opts.limit then
		local trimmed = { }
		for index = 1, opts.limit do
			trimmed[index] = unique[index]
		end
		return trimmed
	end
	return unique
end

--- How many runes fit the item in total (used for the panel summary).
function Runes.countFor(item)
	return #Runes.optionsFor(item)
end

return Runes
