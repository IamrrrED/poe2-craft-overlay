-- PoE2 Craft Overlay : Item/Bases.lua
-- Base type lookup: which spawn tags a base has, and finding the base inside a decorated name.
--
-- Why a module of its own: both the parser and the modifier classifier need it. A Magic item is named
-- "<prefix> <base> <suffix>", so the parser's base type can be the whole name - "Abundant Transcendent
-- Life Flask of the Surgeon" instead of "Transcendent Life Flask". Every modifier lookup starts from
-- the base ("is this tier allowed on these tags?"), so a decorated base type resolved nothing at all.
-- The parser therefore normalises the base as soon as it has read the name, and the classifier
-- resolves the tags from it.

local Bases = { }

local loaded = nil

local function data()
	if loaded == nil then
		local ok, table_ = pcall(require, "Data.bases")
		if ok and type(table_) == "table" and type(table_.tags) == "table" then
			loaded = table_
		else
			loaded = { tags = { } }
		end
		-- Base names, longest first, for finding a base inside a decorated name. Built once: the
		-- search runs for every modifier.
		local names = { }
		for name in pairs(loaded.tags) do
			names[#names + 1] = name
		end
		table.sort(names, function(left, right)
			if #left ~= #right then
				return #left > #right
			end
			return left < right
		end)
		loaded.namesLongestFirst = names
	end
	return loaded
end

--- The raw spawn-tag string of a base type, or nil.
function Bases.tags(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return data().tags[name]
end

--- The known base type contained in a name, longest match first.
-- "Abundant Transcendent Life Flask of the Surgeon" -> "Transcendent Life Flask"; a shorter base name
-- can never win over a longer one that contains it.
function Bases.find(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	for _, candidate in ipairs(data().namesLongestFirst) do
		if name:find(candidate, 1, true) then
			return candidate
		end
	end
	return nil
end

return Bases
