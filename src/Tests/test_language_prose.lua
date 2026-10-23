-- PoE2 Craft Overlay : Tests/test_language_prose.lua
-- No ordinary English word left inside our Russian prose.
--
-- The panel speaks two languages, and the Russian side was checked for readability by eye only. This is
-- the machine check: every string literal that contains Cyrillic is scanned for English words that have a
-- Russian equivalent and therefore must not appear mid-sentence - "Magic", "Rare", "ilvl", "Quality".
--
-- Two things are deliberately allowed:
--   * a game object's name in Latin letters ("Exalted Orb", "Omen of Whittling", "Breach Ring"): the
--     trade site and the Russian client print the same names, and Data/display_names_ru.lua translates
--     them wherever they appear as a value;
--   * anything inside « » - a quotation of somebody else's text (a video title, a poe2db sentence, a
--     property name printed by the game). Translating a quotation would make the reference unfindable.
--
-- The same audit exists as a tool for people: tools/audit_russian_prose.py (it prints the sentences and
-- the words, which is what makes the fix easy). This test is the guard that keeps them out.

local H = require("Tests.harness")

-- The prose modules: what a player reads on the card, in the picker or in the reference.
local FILES = {
	"Craft/Advisor.lua",
	"Craft/Coach.lua",
	"Craft/Lesson.lua",
	"Craft/Techniques.lua",
	"Craft/Curriculum.lua",
	"Craft/Claims.lua",
	"Craft/CraftOrBuy.lua",
	"Craft/GenesisTree.lua",
	"Craft/Stage.lua",
	"Data/crafting_guide.lua",
	"Data/league_0_5_5.lua",
	"Mcp/api.lua",
}

-- Ordinary English words that have a Russian word. A name is not listed here on purpose.
local FORBIDDEN = {
	magic = true, rare = true, normal = true, unique = true, quality = true, ilvl = true,
	item = true, level = true, tier = true, chance = true, better = true, first = true,
	second = true, third = true, slot = true, slots = true, mod = true, mods = true,
	prefix = true, prefixes = true, suffix = true, suffixes = true, affix = true, affixes = true,
	craft = true, crafting = true,
}

local CYRILLIC = "[\208-\209]"

--- Every double-quoted string literal on one line, with escapes handled (a literal may contain \").
local function literalsOf(line)
	local out = { }
	local index = 1
	while true do
		local start = line:find('"', index, true)
		if not start then
			return out
		end
		local position = start + 1
		local text = { }
		while position <= #line do
			local character = line:sub(position, position)
			if character == "\\" then
				text[#text + 1] = line:sub(position, position + 1)
				position = position + 2
			elseif character == '"' then
				break
			else
				text[#text + 1] = character
				position = position + 1
			end
		end
		out[#out + 1] = table.concat(text)
		index = position + 1
	end
end

--- Drop quotations, which are somebody else's words.
local function withoutQuotations(text)
	local out = { }
	local index = 1
	while true do
		local open = text:find("«", index, true)
		if not open then
			out[#out + 1] = text:sub(index)
			return table.concat(out)
		end
		out[#out + 1] = text:sub(index, open - 1)
		local close = text:find("»", open + 1, true)
		if not close then
			out[#out + 1] = text:sub(open)
			return table.concat(out)
		end
		index = close + 1
	end
end

--- Latin words of a text, lower-cased, with the surrounding characters kept for a word boundary check.
local function latinWords(text)
	local out = { }
	local index = 1
	while index <= #text do
		local start, finish = text:find("[%a][%a'%-]+", index)
		if not start then
			return out
		end
		local before = text:sub(start - 1, start - 1)
		local after = text:sub(finish + 1, finish + 1)
		-- A digit or an underscore glues a token together: "magic_two_mods" is a rule id and
		-- "poe2craft" is a program name, not the English word inside them.
		local bounded = (before == "" or not before:match("[%a%-%d_]"))
			and (after == "" or not after:match("[%a%-%d_]"))
		if bounded then
			out[#out + 1] = text:sub(start, finish):lower():gsub("['’%-]+$", "")
		end
		index = finish + 1
	end
	return out
end

return function(h)
	local findings = { }
	local checked = 0
	for _, name in ipairs(FILES) do
		local file = io.open(name, "rb")
		if file then
			local number = 0
			for line in file:lines() do
				number = number + 1
				for _, literal in ipairs(literalsOf(line)) do
					if literal:find(CYRILLIC) then
						checked = checked + 1
						-- Domains and file names (poe2craft.com, ru_bases.lua) are addresses, not words.
						local prose = withoutQuotations(literal):gsub("%S+%.%a+", " ")
						for _, word in ipairs(latinWords(prose)) do
							if FORBIDDEN[word] then
								findings[#findings + 1] = string.format("%s:%d [%s] %s",
									name, number, word, prose:sub(1, 90))
							end
						end
					end
				end
			end
			file:close()
		end
	end

	h.check("prose: the Russian strings were found", checked > 200, tostring(checked))
	local head = { }
	for index = 1, math.min(#findings, 5) do
		head[#head + 1] = findings[index]
	end
	h.check("prose: no ordinary English word is left in the Russian text (" .. #findings .. " left)",
		#findings == 0, table.concat(head, " | "))
end
