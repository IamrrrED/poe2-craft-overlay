-- PoE2 Craft Overlay : Core/prefs.lua
-- Tiny persistent preferences store (font variant, and whatever else the user picks
-- at runtime). Kept out of Data/config.lua on purpose: the config is a curated file
-- with comments, this one is written by the overlay itself.

local util = require("Core.util")

local Prefs = { }

Prefs.PATH = "prefs.lua"

local cached = nil

local function readFromDisk()
	local text = util.readFile(Prefs.PATH)
	if not text or util.trim(text) == "" then
		return { }
	end
	-- The file is written by this module, so loading it as Lua is safe and keeps the
	-- format human-readable.
	local chunk = loadstring and loadstring(text) or nil
	if not chunk then
		return { }
	end
	local ok, data = pcall(chunk)
	if ok and type(data) == "table" then
		return data
	end
	return { }
end

local function serialize(data)
	local parts = { }
	for _, key in ipairs(util.sortedKeys(data)) do
		local value = data[key]
		if type(value) == "string" then
			parts[#parts + 1] = string.format("\t%s = %q,", key, value)
		elseif type(value) == "number" or type(value) == "boolean" then
			parts[#parts + 1] = string.format("\t%s = %s,", key, tostring(value))
		end
	end
	return "return {\n" .. table.concat(parts, "\n") .. "\n}\n"
end

local function store()
	if cached == nil then
		cached = readFromDisk()
	end
	return cached
end

function Prefs.get(key)
	return store()[key]
end

--- Set a key and persist immediately; returns true when the file was written.
function Prefs.set(key, value)
	local data = store()
	data[key] = value
	return util.writeFile(Prefs.PATH, serialize(data))
end

function Prefs.all()
	local copy = { }
	for key, value in pairs(store()) do
		copy[key] = value
	end
	return copy
end

--- Drop the in-memory cache (used by tests to re-read from disk).
function Prefs.reset()
	cached = nil
end

return Prefs
