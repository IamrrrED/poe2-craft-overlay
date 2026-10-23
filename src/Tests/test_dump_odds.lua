-- Exports the engine's own odds, so the JavaScript side can be checked against them line by line.
--
-- The overlay now computes chances from the exported weights. That port is only trustworthy if the
-- numbers match what the engine produces for the same context, so this writes the engine's answer to
-- app/data/odds.json and the comparison happens outside.

local json = require("Mcp.json")

local CANDIDATES = { "app/data/", "../app/data/", "../../app/data/" }

local function writeOut(name, value)
	for _, prefix in ipairs(CANDIDATES) do
		local file = io.open(prefix .. name .. ".json", "w")
		if file then
			file:write(json.encode(value))
			file:close()
			return true
		end
	end
	return false
end

local function loadMods()
	for _, name in ipairs({ "Craft.Mods", "Item.Mods", "Mods", "Craft.ModsIndex", "Data.Mods" }) do
		local ok, mod = pcall(require, name)
		if ok and type(mod) == "table" and mod.rollPool then
			return mod, name
		end
	end
	return nil, nil
end

return function()
	local Mods, moduleName = loadMods()
	if not Mods then
		local report = "odds: the Mods module with rollPool was not found"
		writeOut("odds-report", report)
		print(report)
		return true
	end

	local result = { module = moduleName, samples = {} }
	local cases = {
		{ name = "prefixes ilvl 82", ilvl = 82, hints = { type = "Prefix" } },
		{ name = "suffixes ilvl 82", ilvl = 82, hints = { type = "Suffix" } },
		{ name = "any ilvl 82", ilvl = 82, hints = {} },
		{ name = "any ilvl 1", ilvl = 1, hints = {} },
	}

	for _, case in ipairs(cases) do
		local ok, pool = pcall(Mods.rollPool, case.ilvl, case.hints, {})
		if ok and type(pool) == "table" then
			local entries = {}
			for _, entry in ipairs(pool.entries or pool) do
				entries[#entries + 1] = {
					key = entry.key or entry.id or entry.group,
					weight = entry.weight,
					chance = entry.chance,
					type = entry.type,
				}
			end
			result.samples[#result.samples + 1] = {
				name = case.name,
				ilvl = case.ilvl,
				total = pool.total,
				count = #entries,
				entries = entries,
			}
		else
			result.samples[#result.samples + 1] = { name = case.name, error = tostring(pool) }
		end
	end

	writeOut("odds", result)
	writeOut("odds-report", "odds: exported " .. #result.samples .. " sample(s) from " .. moduleName)
	print("odds: " .. #result.samples .. " sample(s) exported from " .. moduleName)
	return true
end
