-- PoE2 Craft Overlay : Tests/test_language.lua
-- The parity gate between the panel's two languages.
--
-- The engine's own prose is Russian, and the English twin sits next to it in "<field>En" (game data the
-- engine keeps in English carries "<field>Ru" instead). Mcp/api.lua chooses one of the two at a single
-- point, so this file has two jobs:
--
--   1. prove that choice works: a called tool answers in ONE language, with no twins left in the
--      payload for the panel to trip over;
--   2. keep the translation honest by listing every string that is still Russian in an English reply.
--      That list is the work order - it is written to src/language_report.txt and printed, so the next
--      session starts from "these N strings", not from "somewhere in the panel".
--
-- The strict assertion (no Russian at all in an English reply) is off until the translation is done:
-- turning it on is the last step of that work, and then this file fails if anything is left.

local H = require("Tests.harness")
local Api = require("Mcp.api")
local Ru = require("Item.Ru")

-- Set to true when no Russian is expected in an English reply any more.
local REQUIRE_EN_COMPLETE = true

local EN_ITEM = table.concat({
	"Item Class: Gloves",
	"Rarity: Rare",
	"Doom Grip",
	"Blacksteel Gauntlets",
	"--------",
	"Quality: +20% (augmented)",
	"Armour: 412 (augmented)",
	"--------",
	"Requirements:",
	"Level: 78",
	"Str: 100",
	"--------",
	"Item Level: 82",
	"--------",
	"+30 to Strength (implicit)",
	"--------",
	"+118 to maximum Life",
	"+44% to Fire Resistance",
	"--------",
}, "\n")

local RU_ITEM = table.concat({
	"Класс предмета: Шлемы",
	"Редкость: Волшебный",
	"Маска парии моржа",
	"--------",
	"Уклонение: 137",
	"Энергетический щит: 43",
	"--------",
	"Требуется: Уровень 54, 42 Ловк, 42 Инт",
	"--------",
	"Уровень предмета: 65",
	"--------",
	"{ Суффикс \"моржа\" (Уровень: 4) — Стихийный, Холод, Сопротивление }",
	"+30(26-30)% к сопротивлению холоду",
}, "\n")

--- Collect every string in a value with the path it sits on.
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

--- Every key in a value that still carries a translation suffix.
local function twinsLeft(value, path, out)
	out = out or { }
	if type(value) ~= "table" then
		return out
	end
	for key, item in pairs(value) do
		if type(key) == "string" and #key > 3 then
			local tail = key:sub(-2)
			if tail == "En" or tail == "Ru" then
				out[#out + 1] = (path == "" and "" or (path .. ".")) .. key
			end
		end
		if type(item) == "table" then
			twinsLeft(item, path == "" and tostring(key) or (path .. "." .. tostring(key)), out)
		end
	end
	return out
end

local function hasCyrillic(text)
	return text:find("[\208-\209]") ~= nil and text:find("[\128-\191]") ~= nil
end

--- Lines that are the game's own text, not ours.
-- An annotation line ("{ Suffix Modifier "моржа" (Tier: 4) ... }") carries the affix name exactly as the
-- client printed it. There is no official Russian affix-name table (affix names live in the game, and the
-- trade site's localised data does not carry them), so translating them would mean inventing names. They
-- are shown as the game wrote them, which is also what the item view does with the whole tooltip.
local function gameOwnText(text)
	return text:match("^%s*{") ~= nil
end

--- Paths that are Russian on purpose in an English reply.
--  * ruCoverage is a report about what the Russian->English translation did to the copied text: it
--    quotes the game's own Russian, and it exists so a translation gap can be read, not displayed.
--  * claims.*.matches are the matcher's needles: they are compared against what the player typed in
--    Russian, and they are never shown.
local function skipPath(path)
	return path:find("^ruCoverage") ~= nil or path:find("%.matches%.") ~= nil
end

return function(h)
	-- ---- the gate itself ----------------------------------------------------------------------
	local sample = { title = "Следующий шаг", titleEn = "Next step", count = 2 }
	local english = Api.localise(sample, "en")
	local russian = Api.localise(sample, "ru")
	h.eq("language: an English reply takes the twin", english.title, "Next step")
	h.eq("language: a Russian reply keeps the original", russian.title, "Следующий шаг")
	h.eq("language: the twin is not repeated in the payload", english.titleEn, nil)
	h.eq("language: numbers pass through", english.count, 2)
	h.eq("language: the twin of a table is taken", (Api.localise(
		{ steps = { { name = "Эссенция", nameEn = "Essence" } } }, "en")).steps[1].name, "Essence")
	h.eq("language: a missing argument means Russian", Api.languageOf({ }), "ru")
	h.eq("language: an explicit request wins", Api.languageOf({ lang = "en" }), "en")
	h.eq("language: the site's spelling of the argument works too",
		Api.languageOf({ language = "en" }), "en")
	h.eq("language: anything else falls back to Russian", Api.languageOf({ lang = "de" }), "ru")

	-- ---- the replies the panel actually receives ----------------------------------------------
	local CALLS = {
		{ name = "analyze_item", args = { item_text = EN_ITEM } },
		{ name = "craft_step", args = { item_text = EN_ITEM } },
		{ name = "crafting_guide", args = { } },
		{ name = "sources", args = { } },
		{ name = "methods", args = { item_text = EN_ITEM } },
		{ name = "check_claim", args = { text = "Regal Orb is useless on a full Magic item" } },
		{ name = "craft_or_buy", args = { item_text = EN_ITEM, buy_price = 40 } },
	}

	local report = { }
	local leftRussian = { }
	local answered = 0
	for _, call in ipairs(CALLS) do
		for _, lang in ipairs({ "ru", "en" }) do
			local args = { }
			for key, value in pairs(call.args) do
				args[key] = value
			end
			args.lang = lang
			local payload = Api.call(call.name, args)
			if type(payload) ~= "table" then
				h.check("language: " .. call.name .. " answered (" .. lang .. ")", false, "no payload")
			else
				answered = answered + 1
				local twins = twinsLeft(payload, "", { })
				h.check("language: " .. call.name .. " (" .. lang .. ") carries no translation twins",
					#twins == 0, table.concat(twins, ", ", 1, math.min(#twins, 8)))
				if lang == "en" then
					local strings = strings(payload, "", { })
					local cyrillic = 0
					for _, entry in ipairs(strings) do
						if not skipPath(entry.path) and not gameOwnText(entry.text) and hasCyrillic(entry.text) then
							cyrillic = cyrillic + 1
							leftRussian[#leftRussian + 1] = call.name .. " :: " .. entry.path
								.. " :: " .. entry.text
						end
					end
					report[#report + 1] = string.format("%-16s %5d strings, %4d still Russian",
						call.name, #strings, cyrillic)
				end
			end
		end
	end
	h.eq("language: every call answered in both languages", answered, #CALLS * 2)

	-- The Russian item goes through the same gate: its prose must be English in an English reply even
	-- though the game's own text in it is Russian (that text is the client's, not ours).
	local russianItem = Api.call("craft_step", { item_text = RU_ITEM, lang = "en" })
	h.check("language: a Russian item still gets an English card", type(russianItem) == "table")
	if type(russianItem) == "table" then
		local strings = strings(russianItem, "", { })
		local cyrillic = 0
		for _, entry in ipairs(strings) do
			if not skipPath(entry.path) and not gameOwnText(entry.text) and hasCyrillic(entry.text) then
				cyrillic = cyrillic + 1
				leftRussian[#leftRussian + 1] = "craft_step(ru item) :: " .. entry.path
					.. " :: " .. entry.text
			end
		end
		report[#report + 1] = string.format("%-16s %5d strings, %4d still Russian", "craft_step(ru)", #strings, cyrillic)
	end

	local index = require("Data.display_names_ru")
	h.check("language: the reverse dictionary is split into parts", #index.parts > 1, tostring(#index.parts))
	local failures, loadedNames = { }, 0
	for _, partName in ipairs(index.parts) do
		local okPart, part = pcall(require, "Data." .. partName)
		if not okPart then
			failures[#failures + 1] = partName .. ": " .. tostring(part)
		else
			for _ in pairs((part or { }).map or { }) do loadedNames = loadedNames + 1 end
		end
	end
	h.check("language: every part of the reverse dictionary loads", #failures == 0, table.concat(failures, " | "))
	h.eq("language: the reverse dictionary holds every name", loadedNames, index.nameCount)
	h.eq("language: the reverse dictionary translates a class name", tostring(Ru.toRussian("Helmets")), "Шлемы")
	h.eq("language: and a modifier text", tostring(Ru.toRussian("+30% to Cold Resistance")), "+30% к сопротивлению холоду")

	-- ---- the game's own object names, in Russian -------------------------------------------------
	-- A Russian reply is not only our prose in Russian: the item's base, its class and its modifier
	-- texts are the game's objects, and the panel has to show them the way the Russian client does.
	-- The spellings come from the official localised pairs inverted by tools/build_display_names.py,
	-- so nothing here is invented by us.
	local function anyString(value, needle)
		if type(value) == "string" then
			return value:find(needle, 1, true) ~= nil
		end
		if type(value) ~= "table" then
			return false
		end
		for _, item in pairs(value) do
			if anyString(item, needle) then
				return true
			end
		end
		return false
	end

	local russianNames = Api.call("analyze_item", { item_text = RU_ITEM, lang = "ru" })
	local russianCard = Api.call("craft_step", { item_text = RU_ITEM, lang = "ru" })
	h.check("language: a Russian reply names the base in Russian",
		anyString(russianNames, "Маска парии") or anyString(russianCard, "Маска парии"))
	h.check("language: a Russian reply names the class in Russian",
		anyString(russianNames, "Шлемы") or anyString(russianCard, "Шлемы"),
		"class in the reply: " .. tostring(((russianCard.craftOrBuy or { }).recipe or { }).class))
	h.check("language: a Russian reply spells the modifier in Russian",
		anyString(russianNames, "к сопротивлению холоду") or anyString(russianCard, "к сопротивлению холоду"),
		"no Russian modifier text anywhere in the reply")

	-- The English direction is untouched by that pass, and it is the canonical spelling the trade site
	-- and Path of Building use.
	local englishNames = Api.call("analyze_item", { item_text = RU_ITEM, lang = "en" })
	local englishCard = Api.call("craft_step", { item_text = RU_ITEM, lang = "en" })
	h.check("language: an English reply keeps the canonical Latin names",
		anyString(englishNames, "Pariah Mask"), "Pariah Mask missing")
	h.check("language: and no Russian name leaked into it",
		not anyString(englishCard, "Маска парии"))

	-- A machine value that happens to look like a game name must NOT be translated: the engine compares
	-- it against the ruleset ("Regal Orb" is a currency name used as an identifier), and translating it
	-- would look right on screen and break the advice.
	local russianStep = russianCard.step or { }
	h.check("language: an identifier that looks like a name is left alone",
		russianStep.currency == nil or type(russianStep.currency) ~= "string"
			or russianStep.currency:find("[A-Za-z]") ~= nil, tostring(russianStep.currency))

	-- The work order: written where the next session can read it, and printed in the test log.
	local file = io.open("language_report.txt", "w")
	if file then
		file:write("Strings still Russian in an English reply: ", tostring(#leftRussian), "\n\n")
		for _, line in ipairs(report) do
			file:write(line, "\n")
		end
		file:write("\n")
		for _, line in ipairs(leftRussian) do
			file:write(line, "\n")
		end
		file:close()
	end
	if REQUIRE_EN_COMPLETE then
		-- The guarantee, as an assertion with a number: an English reply contains no Russian of ours.
		-- What the game itself wrote stays as it is (see gameOwnText above), and the matcher needles are
		-- not shown to anyone, so they are not part of the count.
		local head = { }
		for index = 1, math.min(#leftRussian, 5) do
			head[#head + 1] = leftRussian[index]
		end
		h.check("language: an English reply carries no Russian of ours (" .. #leftRussian .. " left)",
			#leftRussian == 0, table.concat(head, " | "))
	elseif #leftRussian > 0 then
		local head = { }
		for index = 1, math.min(#leftRussian, 5) do
			head[#head + 1] = leftRussian[index]
		end
		h.check("language: English replies still carry " .. #leftRussian .. " Russian strings (see language_report.txt)",
			false, table.concat(head, " | "))
	end
	h.check("language: the report lists what is left", file ~= nil)
end
