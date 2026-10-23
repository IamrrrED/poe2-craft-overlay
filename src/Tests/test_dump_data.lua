-- Dumps the crafting data to JSON for the Electron overlay.
--
-- The JavaScript side needs the same numbers the engine uses (mods and their spawn weights, essences,
-- alloys, omens, runes, desecration, prices). Retyping them by hand would be a source of silent
-- mismatches, so the engine exports its own tables instead: whatever the Lua side computes is exactly
-- what the card will show.
--
-- It runs as a test because the test harness is the simplest way to execute Lua inside the engine.

local json = require("Mcp.json")

-- The engine's working directory is not guaranteed, so every likely place is tried and the one that
-- works is reported. Guessing a single path is what made this fail silently the first time.
local CANDIDATES = { "app/data/", "../app/data/", "../../app/data/", "data/" }

local function openOut(name)
	for _, prefix in ipairs(CANDIDATES) do
		local file = io.open(prefix .. name .. ".json", "w")
		if file then
			return file, prefix
		end
	end
	return nil, nil
end

local function tryWrite(name, loader)
	local ok, value = pcall(loader)
	if not ok or value == nil then
		return name .. ": skipped"
	end
	local file, prefix = openOut(name)
	if not file then
		return name .. ": cannot write"
	end
	file:write(json.encode(value))
	file:close()
	return name .. ": written to " .. prefix
end

return function()
	local results = {}
	results[#results + 1] = tryWrite("crafting_guide", function() return require("Data.crafting_guide") end)
	results[#results + 1] = tryWrite("prices", function() return require("Data.prices") end)
	results[#results + 1] = tryWrite("essences", function() return require("Data.essences") end)
	results[#results + 1] = tryWrite("runes", function() return require("Data.runes") end)
	results[#results + 1] = tryWrite("leagues", function() return require("Data.leagues") end)
	results[#results + 1] = tryWrite("augments", function() return require("Data.augments") end)
	results[#results + 1] = tryWrite("desecrated", function() return require("Data.desecrated") end)
	-- The mods and their spawn weights: this is what the odds are computed from.
	results[#results + 1] = tryWrite("mods", function() return require("Data.mods") end)
	results[#results + 1] = tryWrite("bases", function() return require("Data.bases") end)
	-- The Russian base names, needed to match a captured item against the English keys the essence
	-- and augment tables use.
	results[#results + 1] = tryWrite("ru_bases", function() return require("Data.ru_bases") end)
	-- The official stat texts (Russian and English). Modifier keys such as ColdResist6 are recorded as
	-- templates ("+#% to Cold Resistance"), and those texts live here rather than in the modifier table.
	for i = 1, 8 do
		local name = "ru_stats_explicit_" .. i
		results[#results + 1] = tryWrite(name, function() return require("Data." .. name) end)
	end
	results[#results + 1] = tryWrite("ru_stats_implicit_1", function() return require("Data.ru_stats_implicit_1") end)
	results[#results + 1] = tryWrite("ru_stats", function() return require("Data.ru_stats") end)
	results[#results + 1] = tryWrite("runeforging", function() return require("Data.runeforging") end)

	local summary = table.concat(results, " | ")
	for _, prefix in ipairs(CANDIDATES) do
		local log = io.open(prefix .. "dump-report.txt", "w")
		if log then
			log:write(summary .. "\n")
			log:close()
			break
		end
	end
	print("dump: " .. summary)
	return true
end
