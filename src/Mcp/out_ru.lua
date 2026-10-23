-- PoE2 Craft Overlay : Mcp/out_ru.lua
-- Russian output for the engine's own texts.
--
-- so a Russian client sees a Russian page whose analysis text is English. This module
-- translates that text on the way out, without touching the calculations: it walks the
-- result and replaces whole strings and known fragments.
--
-- Deliberately conservative: an unknown string is left in English rather than being
-- mangled, and only complete phrases from the tables below are replaced. Technical
-- references (file names, urls) are not translated at all.

local OutRu = { }

-- Whole strings, translated exactly.
local EXACT = {
	["MIN - lowest budget"] = "MIN — минимальные затраты",
	["MAX - best result"] = "MAX — лучший результат",
	["A slot is open - one Exalted Orb adds a mod without risking the existing ones."] =
		"Есть свободный слот — одна Exalted Orb добавит мод, не трогая существующие.",
	["Greater/Perfect Exalted raise the minimum mod level, then Divine tunes the values."] =
		"Greater/Perfect Exalted поднимают минимальный уровень мода, затем Divine правит значения.",
	["An Omen restricts which modifier is removed, then Chaos - this targets the junk affix."] =
		"Знамение ограничивает, какой мод будет удалён, затем Chaos — так цель выбирается точнее.",
	["No free slots: a Chaos Orb swaps a random modifier for a new one."] =
		"Свободных слотов нет: Chaos Orb заменит случайный мод на новый.",
	["Adds one random modifier to a Rare item (max 3 prefixes + 3 suffixes)."] =
		"Добавляет один случайный мод на редкий предмет (до 3 префиксов и 3 суффиксов).",
	["As Exalted, with a minimum modifier level of 35 - cuts the junk tiers."] =
		"Как Exalted, но минимальный уровень мода 35 — отсекает мусорные тиры.",
	["Rerolls the numeric values of existing modifiers; the modifier set is unchanged."] =
		"Перебрасывает числовые значения существующих модов; набор модов не меняется.",
	["Removes one random modifier and adds a new one (Rare items)."] =
		"Удаляет один случайный мод и добавляет новый (для редких предметов).",
	["Rewrites the rules of the next matching currency (eg. adds only a suffix)."] =
		"Меняет правила следующей подходящей валюты (например, добавит только суффикс).",
	-- Notes the advisor adds.
	["all 6 affix slots are taken: free a slot first (Chaos/Annulment), then add"] =
		"все 6 слотов аффиксов заняты: сначала освободите слот (Chaos/Annulment), потом добавляйте",
	-- Source labels. These are the labels the site shows above each reference; the file
	-- names and urls under them stay as they are.
	["Modifier weights"] = "Веса модификаторов",
	["League 0.5.5 Forbidden Rites"] = "Лига 0.5.5 Forbidden Rites",
	["Essences"] = "Эссенции",
	["Runes and soul cores"] = "Руны и soul cores",
	["Runeforging"] = "Руносборка",
	["Desecration"] = "Очернение",
	["alloy modifiers carry zero spawn weight in PoB, so no odds are reported for them"] =
		"у модов сплавов нулевой вес выпадения в PoB, поэтому шансы для них не приводятся",
	["Crafting codex (community)"] = "Кодекс крафта (сообщество)",
	["Omen list (community)"] = "Список знамений (сообщество)",
}

-- Fragments that appear inside longer sentences, with their translations.
local FRAGMENTS = {
	-- Generated sentences: the values inside them (mod text, percentages, counts) are kept,
	-- the frame around them is translated. Longest frames first, because each entry replaces
	-- the first occurrence it finds.
	{ "The Chaos Orb will remove ", "Chaos Orb удалит " },
	{ " (mod level ", " (уровень мода " },
	{ ") - the weakest modifier, not a random one.", ") — самый слабый мод, а не случайный." },
	{ "The Chaos Orb removes only a suffix: ", "Chaos Orb удаляет только суффикс: " },
	{ "The Chaos Orb removes only a prefix: ", "Chaos Orb удаляет только префикс: " },
	{ " modifiers on that side).", " мода с этой стороны)." },
	{ " chance to hit ", " шанс задеть " },
	{ "Socketing the rune grants exactly this modifier - ", "Руна в гнезде даёт ровно этот мод — " },
	{ "Socketing the rune grants exactly this modifier", "Руна в гнезде даёт ровно этот мод" },
	{ "modifier pool", "пул модификаторов" },
	{ "works only on ", "работает только с предметами редкости " },
	{ " items, and this one is ", ", а этот — " },
	-- The same effect is worded in the singular in the league data; without this entry the
	-- step stayed English on the page.
	{ "Rewrite the rules of the next matching currency", "Меняет правила следующей подходящей валюты" },
	{ "Rewrites the rules of the next matching currency", "Меняет правила следующей подходящей валюты" },
	{ "(eg. adds only a suffix)", "(например, добавит только суффикс)" },
	{ "(eg. adds only a prefix)", "(например, добавит только префикс)" },
	-- The league data writes "e.g." with the dots; both spellings are handled.
	{ "(e.g. adds only a suffix)", "(например, добавит только суффикс)" },
	{ "(e.g. adds only a prefix)", "(например, добавит только префикс)" },
	{ "A slot is open", "Есть свободный слот" },
	{ "untagged mod(s)", "моды без тега" },
	{ "free a slot first", "сначала освободите слот" },
	{ "modifier(s) unrecognised", "не распознано модов" },
	{ "may be implicits - use the advanced copy for certainty",
		"могут быть имплиситами — для точности используйте расширенное копирование" },
	{ "prefix/suffix split unknown, slot-based rules are skipped",
		"разделение префикс/суффикс неизвестно, правила по слотам пропущены" },
	{ "tier estimated from item level", "тир оценён по уровню предмета" },
	{ "value matched no range", "значение не совпало с диапазоном" },
	{ "chance of the best reachable tier", "шанс лучшего достижимого тира" },
	{ "guaranteed modifier", "гарантированный мод" },
	{ "no randomness", "без случайности" },
	{ "limit", "лимит" },
	{ "per item", "на предмет" },
	{ "odds not computed", "шансы не рассчитаны" },
	{ "not computable from the available data", "не вычисляется по доступным данным" },
	{ "alloys", "сплавы" },
	{ "Omens", "Знамения" },
	{ "Runes", "Руны" },
	{ "Desecration uses its own slot", "Очернение занимает отдельный слот" },
	{ "Sockets the rune grants exactly this modifier", "Руна даёт ровно этот мод" },
	{ "Guaranteed modifier", "Гарантированный мод" },
}

local function translateString(text)
	local exact = EXACT[text]
	if exact then
		return exact
	end
	-- Fragments are applied longest first, so a short one cannot cut a longer sentence.
	local result = text
	for _, pair in ipairs(FRAGMENTS) do
		if result:find(pair[1], 1, true) then
			result = result:gsub(pair[1]:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"),
				function() return pair[2] end)
		end
	end
	return result
end

--- Translate every string inside a value (tables and arrays included).
-- Technical fields are skipped: urls and file references are not language.
function OutRu.translate(value, key)
	if key == "url" or key == "source" or key == "detail" or key == "model" or key == "id" then
		return value
	end
	local kind = type(value)
	if kind == "string" then
		return translateString(value)
	elseif kind == "table" then
		local out = { }
		for innerKey, innerValue in pairs(value) do
			out[innerKey] = OutRu.translate(innerValue, tostring(innerKey))
		end
		return out
	end
	return value
end

--- Statistics for the diagnostics log.
function OutRu.stats()
	return { exact = (function()
		local count = 0
		for _ in pairs(EXACT) do count = count + 1 end
		return count
	end)(), fragments = #FRAGMENTS }
end

-- План крафта: подписи цены и вида шага, чтобы панель показывала их по-русски.
OutRu.planCost = {
	veryhigh = "очень дорого", high = "дорого", medium = "средне", low = "дёшево",
}
OutRu.planKind = {
	omen = "омен", bone = "десакрация (кость)", essence = "эссенция", rune = "руна",
	alloy = "сплав", desecration = "десакрация",
}

--- Whether a reply should be translated for the player.
-- The assistant speaks the language of the game client, and in serving mode there is no clipboard
-- capture to learn it from: the item text in the request is the only evidence, and it is exactly
-- what the parser's own detection uses.
function OutRu.wantsRussian(args)
	local text = type(args) == "table" and args.item_text or nil
	if type(text) ~= "string" or text == "" then
		return false
	end
	local ok, Ru = pcall(require, "Item.Ru")
	return ok and Ru and Ru.looksRussian and Ru.looksRussian(text) == true
end

return OutRu
