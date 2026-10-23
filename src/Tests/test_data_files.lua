-- PoE2 Craft Overlay : Tests/test_data_files.lua
-- Every data file the engine loads must actually load, and lose nothing on the way.
--
-- Why this exists: one of the localised modifier dictionaries carried a real newline inside a Lua string
-- literal, so the file was a syntax error. Every reader uses pcall(), so the failure was silent - the
-- dictionary came up with 3 of 10 parts and 806 of 3084 entries, and from the player's side it looked
-- like "the engine does not recognise Russian modifiers". A card with half-translated lines was the only
-- visible sign, and it took a live screenshot to notice.
--
-- So the parts are loaded here for their own sake: each one must compile, each one must contain the number
-- of entries its own header declares, and the total must be the sum of those numbers. Silent data loss is
-- what this file is for.

local H = require("Tests.harness")

--- Load every part named by an index file, returning the parts and the names that failed.
local function loadParts(indexName)
	local okIndex, index = pcall(require, indexName)
	if not okIndex or type(index) ~= "table" or type(index.parts) ~= "table" then
		return nil, { indexName .. ": " .. tostring(index) }
	end
	local parts, failures = { }, { }
	for _, partName in ipairs(index.parts) do
		local ok, part = pcall(require, "Data." .. tostring(partName))
		if ok and type(part) == "table" then
			parts[#parts + 1] = { name = tostring(partName), data = part }
		else
			failures[#failures + 1] = tostring(partName) .. ": " .. tostring(part)
		end
	end
	return parts, failures
end

--- Count the entries of one table field inside a part.
local function countEntries(part, field)
	local counted = 0
	for _ in pairs(part[field] or { }) do
		counted = counted + 1
	end
	return counted
end

-- Every data module the engine loads, by name. One unloadable file used to mean silently missing
-- modifiers; this list makes the same accident loud for the rest of the data as well.
local DATA_MODULES = {
	"Data.config", "Data.bases", "Data.mods", "Data.categories", "Data.essences", "Data.runes",
	"Data.runeforging", "Data.augments", "Data.desecrated", "Data.desecration_pool", "Data.prices",
	"Data.leagues", "Data.crafting_guide", "Data.rules_ru", "Data.display_ru", "Data.league_0_5_5",
	"Data.coe_bases", "Data.coe_mods", "Data.coe_text_map", "Data.coe_weights", "Data.icon_index",
	"Data.currency_icons", "Data.fonts", "Data.ru_bases", "Data.ru_stats",
}

return function(h)
	-- A data file that does not compile is a feature that quietly does not work.
	local broken = { }
	for _, name in ipairs(DATA_MODULES) do
		local ok, loaded = pcall(require, name)
		if not ok or type(loaded) ~= "table" then
			broken[#broken + 1] = name .. ": " .. tostring(loaded):gsub("%s+", " ")
		end
	end
	h.check("data: every data module loads (" .. #DATA_MODULES .. " modules)", #broken == 0,
		table.concat(broken, " | "))

	-- The modifier dictionary the parser matches Russian lines against.
	local statParts, statFailures = loadParts("Data.ru_stats")
	h.check("data: the modifier dictionary index loads", statParts ~= nil,
		table.concat(statFailures or { }, " | "))
	if statParts then
		h.check("data: every modifier part loads (" .. #statParts .. " parts)", #statFailures == 0,
			table.concat(statFailures, " | "))
		local declared, merged, declaredParts = 0, 0, 0
		for _, part in ipairs(statParts) do
			local entries = countEntries(part.data, "stats")
			merged = merged + entries
			if type(part.data.count) == "number" then
				declared = declared + part.data.count
				declaredParts = declaredParts + 1
				h.eq("data: part " .. part.name .. " holds what it declares", entries, part.data.count)
			end
		end
		h.check("data: the modifier dictionary is whole (declared " .. declared .. ", loaded " .. merged .. ")",
			merged == declared and merged > 3000, tostring(merged))
	end

	-- The base/currency names, which the parser and the display both use.
	local okBases, bases = pcall(require, "Data.ru_bases")
	local baseCount = 0
	if okBases and type(bases) == "table" then
		for _ in pairs(bases.bases or { }) do
			baseCount = baseCount + 1
		end
	end
	h.eq("data: the base name dictionary loads", okBases and type(bases) == "table", true)
	h.check("data: and holds every name it declares",
		baseCount == (tonumber(bases and bases.count) or -1), tostring(baseCount))

	-- The reverse (display) dictionary, which the Russian panel reads names from.
	local displayParts, displayFailures = loadParts("Data.display_names_ru")
	h.check("data: the display dictionary index loads", displayParts ~= nil,
		table.concat(displayFailures or { }, " | "))
	if displayParts then
		h.check("data: every display part loads (" .. #displayParts .. " parts)", #displayFailures == 0,
			table.concat(displayFailures, " | "))
		local names = 0
		for _, part in ipairs(displayParts) do
			names = names + countEntries(part.data, "map")
		end
		local okIndex, index = pcall(require, "Data.display_names_ru")
		h.check("data: the display dictionary holds every name it declares",
			okIndex and type(index) == "table" and names == (tonumber(index.nameCount) or -1),
			tostring(names) .. " of " .. tostring(okIndex and index and index.nameCount))
	end
end
