-- PoE2 Craft Overlay : Tests/test_language_corpus.lua
-- Every item class the tests know about, through every tool the panel actually calls, in both languages.
--
-- Why: two hand-written samples prove the mechanism works, but not that it works on every CLASS of item and
-- in every ANSWER. Waystones, tablets, relics, jewels, flasks, charms, uniques and weapons each take their own
-- branch, and each panel tab is a different tool: analyze_item (the card), item_lines (the client's own
-- lines), craft_step (the coach), crafting_guide (the reference tab), prices (the league snapshot) and
-- check_claim (a question typed by the player). A branch nobody exercises is where a Russian-only string
-- survives - which is how the panel stayed "partly Russian" for a while.
--
-- The corpus is generated from the item fixtures the tests already use (tools/build_item_corpus.py).
--
-- What counts as a violation:
--   * English answer: Cyrillic anywhere in our payload, except the client's own text (item_lines, and any
--     line that appears in the copied item), the coverage report, the matcher's needles, and "{...}"
--     annotations the game prints.
--   * Russian answer: an ASCII-only sentence of TWO or more words that is not capitalised like a name and is
--     not an address - i.e. our own prose left in English.
--   * Either answer: the two languages must return the SAME SHAPE. A key that exists in one language and not
--     the other means a twin was lost, and a page that reads it will show nothing.

local H = require("Tests.harness")
local Api = require("Mcp.api")
local Corpus = require("Tests.item_corpus")

local ALLOWED_PATHS = {
	"^ruCoverage",
	"%.matches%.",
	-- The item's own name: the game prints prefix + base + suffix in one line, and only the base has an
	-- official translation. The name is shown as the client wrote it (with the base translated), and
	-- there is no affix-name table to finish the job.
	"^item%.name$",
	-- Machine ids ("essence:Lesser Essence of the Infinite"): the page uses them to remember the selected
	-- method. They are not shown.
	"%.id$",
	-- Affix names the client prints ("of the Walrus"): the game's own words.
	"^item%.affixes%.",
	-- The modifier pool prints the game's stat lines ("Equipment and Skill Gems have ... reduced Attribute
	-- Requirements"). Same kind of text as the affix names above: translated where the dictionary knows the
	-- sentence, verbatim where it does not, and never our prose.
	"^modPool%.",
}

-- The client's own text: item_lines ANSWERS with it, and nothing in it is ours to translate.
local CLIENT_PAYLOAD = "item_lines"

-- How many English strings of ours are still expected in a Russian reply. This number may only go DOWN:
-- the check fails when it grows, so a new untranslated sentence cannot slip in unnoticed.
local KNOWN_ENGLISH_LEFT = 0

local function pathAllowed(path)
	for _, pattern in ipairs(ALLOWED_PATHS) do
		if path:find(pattern) then
			return true
		end
	end
	return false
end

local function hasCyrillic(text)
	return text:find("[\208-\209][\128-\191]") ~= nil
end

--- Every string of a payload with its path.
local function strings(value, path, out)
	out = out or { }
	if type(value) == "string" then
		out[#out + 1] = { path = path, text = value }
	elseif type(value) == "table" then
		for key, item in pairs(value) do
			strings(item, path == "" and tostring(key) or (path .. "." .. tostring(key)), out)
		end
	end
	return out
end

--- Every key path of a payload, sorted. Used to compare the shape of the two languages' answers.
local function keyPaths(value, path, out)
	out = out or { }
	for key, item in pairs(value) do
		local full = path == "" and tostring(key) or (path .. "." .. tostring(key))
		if type(item) == "table" then
			keyPaths(item, full, out)
		else
			out[#out + 1] = full
		end
	end
	table.sort(out)
	return out
end

--- The lines of the item as the client printed them.
local function clientLines(itemText)
	local set = { }
	for line in tostring(itemText):gmatch("[^\r\n]+") do
		local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
		if trimmed ~= "" then
			set[trimmed] = true
		end
	end
	return set
end

--- Does this string look like an English sentence of ours rather than a name?
local function looksLikeEnglishProse(text)
	if hasCyrillic(text) or #text < 4 then
		return false
	end
	if text:find("://", 1, true) or text:find("_", 1, true) then
		return false
	end
	local words, capitalised = { }, 0
	for word in text:gmatch("[%a][%a'’%-]*") do
		words[#words + 1] = word
		local first = word:sub(1, 1)
		if first:match("%u") or word == "of" or word == "the" or word == "and" or word == "in" then
			capitalised = capitalised + 1
		end
	end
	if #words < 2 or capitalised == #words then
		return false
	end
	for _, word in ipairs(words) do
		local lowered = word:lower()
		if lowered == "the" or lowered == "and" or lowered == "with" or lowered == "your"
			or lowered == "this" or lowered == "from" or lowered == "have" or lowered == "will" then
			return true
		end
	end
	return false
end

return function(h)
	local count = 0
	for _ in pairs(Corpus) do
		count = count + 1
	end
	h.check("corpus: the item corpus loads (" .. count .. " items)", count >= 30, tostring(count))

	local englishProblems, russianProblems, shapeProblems = { }, { }, { }
	local checkedItems, checkedStrings, checkedShapes = 0, 0, 0

	--- Read one answer in one language.
	local function scan(payload, lang, tool, index, lines)
		if type(payload) ~= "table" then
			return
		end
		checkedItems = checkedItems + 1
		local clientText = tool == CLIENT_PAYLOAD
		for _, entry in ipairs(strings(payload, "", { })) do
			checkedStrings = checkedStrings + 1
			if clientText or pathAllowed(entry.path) or lines[entry.text] then
				-- the game's own words
			elseif lang == "en" and entry.text:sub(1, 1) == "{" then
				-- the game's annotation of a modifier
			elseif lang == "en" and hasCyrillic(entry.text) then
				englishProblems[#englishProblems + 1] = string.format(
					"item %d %s :: %s :: %s", index, tool, entry.path, entry.text)
			elseif lang == "ru" and looksLikeEnglishProse(entry.text) then
				russianProblems[#russianProblems + 1] = string.format(
					"item %d %s :: %s :: %s", index, tool, entry.path, entry.text)
			end
		end
	end

	-- craft_step reads the craft memory, and that memory holds whatever was captured last - in whichever
	-- language it was captured. So its SHAPE legitimately depends on history (the first call after a fresh
	-- workspace has no "before" block at all), and comparing the two languages there would report state as a
	-- language bug. Its TEXT is still scanned in both languages above.
	local STATELESS = {
		analyze_item = true, item_lines = true, crafting_guide = true, prices = true, check_claim = true,
	}

	--- Compare the two languages' answer shapes.
	local function compareShape(english, russian, tool, index, lines)
		if not STATELESS[tool] then
			return
		end
		if type(english) ~= "table" or type(russian) ~= "table" then
			return
		end
		checkedShapes = checkedShapes + 1
		local left, right = keyPaths(english, "", { }), keyPaths(russian, "", { })
		local leftSet, rightSet = { }, { }
		for _, path in ipairs(left) do
			leftSet[path] = true
		end
		for _, path in ipairs(right) do
			rightSet[path] = true
		end
		for _, path in ipairs(left) do
			if not rightSet[path] then
				shapeProblems[#shapeProblems + 1] = string.format(
					"item %d %s :: %s exists in English, not in Russian", index, tool, path)
			end
		end
		for _, path in ipairs(right) do
			if not leftSet[path] then
				shapeProblems[#shapeProblems + 1] = string.format(
					"item %d %s :: %s exists in Russian, not in English", index, tool, path)
			end
		end
	end

	for index = 1, count do
		local itemText = Corpus[index]
		local lines = clientLines(itemText)
		for _, tool in ipairs({ "analyze_item", "craft_step", "item_lines" }) do
			local english = Api.call(tool, { item_text = itemText, lang = "en" })
			local russian = Api.call(tool, { item_text = itemText, lang = "ru" })
			scan(english, "en", tool, index, lines)
			scan(russian, "ru", tool, index, lines)
			compareShape(english, russian, tool, index, lines)
		end
	end

	-- The reference tab and the league snapshot do not depend on the item: once per language is enough.
	for _, lang in ipairs({ "en", "ru" }) do
		local guide = Api.call("crafting_guide", { lang = lang })
		scan(guide, lang, "crafting_guide", 0, { })
		local prices = Api.call("prices", { lang = lang })
		scan(prices, lang, "prices", 0, { })
	end
	compareShape(Api.call("crafting_guide", { lang = "en" }), Api.call("crafting_guide", { lang = "ru" }),
		"crafting_guide", 0, { })
	compareShape(Api.call("prices", { lang = "en" }), Api.call("prices", { lang = "ru" }), "prices", 0, { })

	-- A question typed by the player, in both languages.
	local questions = { "занимает ли качество слот", "does quality take a slot" }
	for _, question in ipairs(questions) do
		local english = Api.call("check_claim", { text = question, lang = "en" })
		local russian = Api.call("check_claim", { text = question, lang = "ru" })
		scan(english, "en", "check_claim", 0, { })
		scan(russian, "ru", "check_claim", 0, { })
		compareShape(english, russian, "check_claim", 0, { })
	end

	h.check("corpus: every answer was read in both languages", checkedItems >= 200, tostring(checkedItems))
	h.check("corpus: the payloads were actually read", checkedStrings > 20000, tostring(checkedStrings))
	h.check("corpus: the two languages were compared", checkedShapes >= 80, tostring(checkedShapes))

	-- The whole list, grouped by field, so a fix can be made once instead of once per item.
	local byField = { }
	local function note(list)
		local counts = { }
		for _, line in ipairs(list) do
			local field = line:gsub("^item %d+ [%a_]+ :: ", "")
			field = field:gsub("%.%d+%.", ".N.")
			field = field:gsub(" :: .*$", "")
			counts[field] = (counts[field] or 0) + 1
		end
		local fields = { }
		for field, count in pairs(counts) do
			fields[#fields + 1] = { field, count }
		end
		table.sort(fields, function(a, b) return a[2] > b[2] end)
		for _, entry in ipairs(fields) do
			byField[#byField + 1] = string.format("%5d  %s", entry[2], entry[1])
		end
	end
	note(englishProblems)
	note(russianProblems)
	note(shapeProblems)
	local report = io.open("language_corpus_report.txt", "w")
	if report then
		report:write("English reply problems: ", tostring(#englishProblems), "\n")
		report:write("Russian reply problems: ", tostring(#russianProblems), "\n")
		report:write("Answer shape problems: ", tostring(#shapeProblems), "\n\n")
		for _, line in ipairs(byField) do
			report:write(line, "\n")
		end
		local function dump(title, list)
			report:write("\n--- ", title, " ---\n")
			for index = 1, math.min(#list, 60) do
				report:write(list[index], "\n")
			end
		end
		dump("English samples", englishProblems)
		dump("Russian samples", russianProblems)
		dump("Shape samples", shapeProblems)
		report:close()
	end

	local function head(list, limit)
		local out = { }
		for i = 1, math.min(#list, limit) do
			out[#out + 1] = list[i]
		end
		return table.concat(out, " | ")
	end
	h.check("corpus: no Russian of ours in an English reply over the whole corpus ("
		.. #englishProblems .. " left)", #englishProblems == 0, head(englishProblems, 4))
	h.check("corpus: no English prose of ours in a Russian reply ("
		.. #russianProblems .. " of " .. KNOWN_ENGLISH_LEFT .. ")", #russianProblems <= KNOWN_ENGLISH_LEFT,
		head(russianProblems, 4))
	h.check("corpus: both languages answer with the same shape ("
		.. #shapeProblems .. " differences)", #shapeProblems == 0, head(shapeProblems, 4))
end
