-- PoE2 Craft Overlay : Item/Ru.lua
-- Russian input support: a Russian item copied from the game is turned into the English
-- shape the rest of the engine works with.
--
-- Why this layer exists: every number in the overlay comes from Path of Building's English
-- data (base types, modifier groups, spawn weights). A Russian client copies Russian text,
-- so without a translation step the parser recognises nothing at all. Translating on the
-- way in keeps the whole calculation path untouched and single-language.
--
-- What is translated, and what is not:
--   * structure and labels (Класс предмета, Редкость, Уровень предмета, Требуется, ...),
--     so the item's class, rarity, item level and affix split are always known;
--   * the game's own modifier annotations ({ Префикс "..." (Уровень: N) } -> PoB's
--     "{ Prefix Modifier ... (Tier: N) }"), so tiers survive;
--   * common modifier phrases from the dictionary below.
--
-- A modifier line that still contains Cyrillic after this is reported as unrecognised by
-- the analysis (the panel and the site label such lines) rather than being guessed at.
-- Full coverage of Russian modifier names needs GGG's own name table; the dictionary here
-- is deliberately small and honest.

local Ru = { }

-- Labels and section words. Longest first: "Класс предмета" must win over "Класс".
local LABELS = {
	{ "Класс предмета:", "Item Class:" },
	{ "Уровень предмета:", "Item Level:" },
	{ "Собственное свойство", "Implicit Modifier" },
	{ "Дополнительное свойство", "Explicit Modifier" },
	{ "Редкость:", "Rarity:" },
	{ "Требуется:", "Requirements:" },
	{ "Качество:", "Quality:" },
	-- The game writes "Гнёзда:" with a diaeresis in some clients and "Гнезда:" without it in
	-- others. Both spellings must be here: when the label is missed the socket line is read as a
	-- modifier, the socket count is lost, and - worse - that stray "modifier" makes the affix split
	-- look incomplete, which switches off every slot-based recommendation.
	{ "Гнёзда:", "Sockets:" },
	{ "Гнезда:", "Sockets:" },
	{ "Связано:", "Links:" },
	{ "Уровень:", "Level:" },
	{ "Сила:", "Str:" },
	{ "Ловкость:", "Dex:" },
	{ "Интеллект:", "Int:" },
	{ "Броня:", "Armour:" },
	{ "Уклонение:", "Evasion Rating:" },
	{ "Энергетический щит:", "Energy Shield:" },
	{ "Физический урон:", "Physical Damage:" },
	{ "Элементальный урон:", "Elemental Damage:" },
	{ "Шанс критического удара:", "Critical Strike Chance:" },
	{ "Атак в секунду:", "Attacks per Second:" },
	{ "Радиус:", "Radius:" },
	{ "Опыт:", "Experience:" },
	{ "Стек:", "Stack Size:" },
	{ "Примечание:", "Note:" },
	-- The game's modifier annotations.
	{ "Префикс", "Prefix Modifier" },
	{ "Суффикс", "Suffix Modifier" },
	{ "Уровень:", "Tier:" },
	{ "Свойство", "Modifier" },
}

local RARITY = {
	["Обычный"] = "Normal",
	["Волшебный"] = "Magic",
	["Редкий"] = "Rare",
	["Уникальный"] = "Unique",
	["Валюта"] = "Currency",
	["Самоцвет"] = "Gem",
	["Наследие"] = "Unique",
	["Реликвия"] = "Relic",
	["Задание"] = "Quest",
	["Божественный"] = "Divination",
	["Пробный"] = "Sanctum",
}

-- Item classes and slot words: the engine picks its modifier pools by class, so this is
-- worth translating even though base type names (thousands of them) are not covered here.
local CLASSES = {
	["Амулеты"] = "Amulets",
	["Кольца"] = "Rings",
	["Пояса"] = "Belts",
	["Перчатки"] = "Gloves",
	["Сапоги"] = "Boots",
	["Шлемы"] = "Helmets",
	["Нагрудники"] = "Body Armours",
	["Щиты"] = "Shields",
	["Кинжалы"] = "Daggers",
	["Когти"] = "Claws",
	["Одноручные мечи"] = "One Hand Swords",
	["Одноручные топоры"] = "One Hand Axes",
	["Одноручные булавы"] = "One Hand Maces",
	["Двуручные мечи"] = "Two Hand Swords",
	["Двуручные топоры"] = "Two Hand Axes",
	["Двуручные булавы"] = "Two Hand Maces",
	["Луки"] = "Bows",
	["Арбалеты"] = "Crossbows",
	["Жезлы"] = "Wands",
	["Посохи"] = "Staves",
	["Копья"] = "Spears",
	["Флаконы жизни"] = "Life Flasks",
	["Флаконы маны"] = "Mana Flasks",
	["Камни умений"] = "Skill Gems",
	["Камни поддержки"] = "Support Gems",
	["Самоцветы"] = "Jewels",
	["Карты"] = "Maps",
	["Навершия"] = "Sceptres",
	-- The game writes sceptres as "Скипетры" on a real captured item, while the trade data spells them
	-- "Навершия". Only the second was mapped, so the class stayed Russian, the quality currency for a
	-- caster weapon could not be found, and the sceptre was offered no quality step at all.
	["Скипетры"] = "Sceptres",
	["Фокусы"] = "Foci",
	["Колчаны"] = "Quivers",
}

-- Common modifier phrases. Keys are lowercase fragments; the replacement keeps the numbers
-- and the rest of the line, which is what the English matcher needs.
local PHRASES = {
	-- Wording taken from a real captured Russian item (see the coverage report in
	-- analyze_item): these are the phrases the official trade vocabulary does not have,
	-- because trade filters ask for flat values rather than percentages.
	{ "увеличение энергетического щита", "increased Energy Shield" },
	{ "повышение редкости найденных предметов", "increased Rarity of Items found" },
	{ "понижение редкости найденных предметов", "reduced Rarity of Items found" },
	{ "к максимуму mana", "to maximum Mana" },
	{ "к максимуму маны", "to maximum Mana" },
	{ "к максимуму здоровья", "to maximum Life" },
	{ "энергетического щита", "Energy Shield" },
	{ "редкости найденных предметов", "Rarity of Items found" },
	{ "к максимуму", "to maximum" },
	{ "регенерация здоровья", "Life Regeneration" },
	{ "регенерация маны", "Mana Regeneration" },
	{ "к максимальному здоровью", "to maximum Life" },
	{ "к максимальному запасу здоровья", "to maximum Life" },
	{ "к максимальной мане", "to maximum Mana" },
	{ "к максимальному запасу маны", "to maximum Mana" },
	{ "к сопротивлению огню", "to Fire Resistance" },
	{ "к сопротивлению холоду", "to Cold Resistance" },
	{ "к сопротивлению молнии", "to Lightning Resistance" },
	{ "к сопротивлению хаосу", "to Chaos Resistance" },
	{ "ко всем элементальным сопротивлениям", "to all Elemental Resistances" },
	{ "к сопротивлению всем стихиям", "to all Elemental Resistances" },
	{ "ко всем характеристикам", "to all Attributes" },
	{ "к силе", "to Strength" },
	{ "к ловкости", "to Dexterity" },
	{ "к интеллекту", "to Intelligence" },
	{ "к броне", "to Armour" },
	{ "к уклонению", "to Evasion Rating" },
	{ "к энергетическому щиту", "to maximum Energy Shield" },
	{ "к максимальному энергетическому щиту", "to maximum Energy Shield" },
	{ "к точности", "to Accuracy Rating" },
	{ "к здоровью", "to maximum Life" },
	{ "регенерация здоровья", "Life Regeneration" },
	{ "регенерации здоровья", "Life Regeneration" },
	{ "скорость атаки", "Attack Speed" },
	{ "скорость чтения заклинаний", "Cast Speed" },
	{ "скорость передвижения", "Movement Speed" },
	{ "скорость сотворения", "Cast Speed" },
	{ "увеличение физического урона", "increased Physical Damage" },
	{ "повышение физического урона", "increased Physical Damage" },
	{ "к редкости предметов", "to Rarity of Items found" },
	{ "к количеству находимых предметов", "to Quantity of Items found" },
	{ "к уровню всех камней умений", "to Level of all Skill Gems" },
	{ "к уровню всех камней", "to Level of all Skill Gems" },
	{ "к радиусу действия", "to Area of Effect" },
	{ "площадь действия", "Area of Effect" },
	{ "к урону", "to Damage" },
	{ "в секунду", "per second" },
	{ "повышает", "increased" },
	{ "понижает", "reduced" },
	{ "добавляет", "Adds" },
	{ "урона от огня", "Fire Damage" },
	{ "урона от холода", "Cold Damage" },
	{ "урона от молнии", "Lightning Damage" },
	{ "физического урона", "Physical Damage" },
	{ "урона хаосом", "Chaos Damage" },
	{ "здоровья", "Life" },
	{ "маны", "Mana" },
	{ "брони", "Armour" },
	{ "уклонения", "Evasion" },
	{ "оглушению", "Stun" },
	{ "оглушения", "Stun" },
	{ "критического удара", "Critical Strike" },
	{ "критический удар", "Critical Strike" },
	{ "яда", "Poison" },
	{ "кровотечения", "Bleeding" },
	{ "ожога", "Ignite" },
	{ "замораживания", "Freeze" },
}

local CYRILLIC = "[\208-\209][\128-\191]" -- UTF-8 range for Cyrillic letters

--- Lowercase that also folds Cyrillic.
--
-- string.lower() follows the C locale, and on this host it folds ASCII only: "Союзники" kept its capital,
-- so a line that starts with one never matched the dictionary key written in lower case ("союзники ..."),
-- and the official modifier table silently missed every line with a capitalised first word. The same call
-- is used by the label and phrase passes, which had the same blind spot.
local function lower(text)
	local value = tostring(text or ""):lower()
	if not value:find(CYRILLIC) then
		return value
	end
	local out = { }
	local index = 1
	while index <= #value do
		local first = value:byte(index)
		local second = value:byte(index + 1)
		if first == 0xD0 and second then
			if second >= 0x90 and second <= 0x9F then
				-- А..П: the second byte moves into the lowercase half of the same block.
				out[#out + 1] = string.char(0xD0, second + 0x20)
			elseif second >= 0xA0 and second <= 0xAF then
				-- Р..Я: their lowercase forms live in the next block (0xD1 0x80..0x8F).
				out[#out + 1] = string.char(0xD1, second - 0x20)
			elseif second == 0x81 then
				-- Ё
				out[#out + 1] = string.char(0xD1, 0x91)
			elseif second == 0x80 then
				-- Ѐ
				out[#out + 1] = string.char(0xD1, 0x90)
			else
				out[#out + 1] = string.char(first, second)
			end
			index = index + 2
		else
			out[#out + 1] = string.char(first)
			index = index + 1
		end
	end
	return table.concat(out)
end

Ru.lower = lower

-- Values that appear after a label (requirements, attributes) - the same words the labels
-- use, but here they stand alone inside the line.
local VALUES = {
	-- Full words only: a plain search is used (see below), so short fragments like "инт" or
	-- "стр" are left out - they would match inside other Russian words.
	--
	-- Both spellings are listed because Lua's string.lower folds ASCII only: Cyrillic keeps
	-- its case, so a line starting a sentence ("Уровень 70") never matched a lowercase entry
	-- and the value stayed Russian.
	{ "уровень", "Level" },
	{ "Уровень", "Level" },
	{ "требуется", "Requirements" },
	{ "Требуется", "Requirements" },
	{ "интеллект", "Int" },
	{ "Интеллект", "Int" },
	{ "ловкость", "Dex" },
	{ "Ловкость", "Dex" },
	{ "сила", "Str" },
	{ "Сила", "Str" },
	{ "энергетический щит", "Energy Shield" },
	{ "Энергетический щит", "Energy Shield" },
	{ "броня", "Armour" },
	{ "Броня", "Armour" },
	{ "уклонение", "Evasion Rating" },
	{ "Уклонение", "Evasion Rating" },
	-- Tags the game prints inside its { ... } annotations.
	{ "мана", "Mana" },
	{ "Мана", "Mana" },
	{ "здоровье", "Life" },
	{ "Здоровье", "Life" },
	{ "стихийный", "Elemental" },
	{ "Стихийный", "Elemental" },
	{ "огонь", "Fire" },
	{ "Огонь", "Fire" },
	{ "холод", "Cold" },
	{ "Холод", "Cold" },
	{ "молния", "Lightning" },
	{ "Молния", "Lightning" },
	{ "сопротивление", "Resistance" },
	{ "Сопротивление", "Resistance" },
	{ "физический", "Physical" },
	{ "Физический", "Physical" },
	{ "хаос", "Chaos" },
	{ "Хаос", "Chaos" },
	{ "атрибут", "Attribute" },
	{ "Атрибут", "Attribute" },
	-- Last on purpose: a short form must not shadow a longer word ("Инт" vs "Интеллект").
	{ "Инт", "Int" },
	{ "инт", "Int" },
}

--- Is this byte part of a word? Cyrillic is multi-byte, so anything with the high bit set
-- counts, as does an ASCII letter.
local function isWordByte(char)
	if char == "" or char == nil then
		return false
	end
	return char:match("[%a]") ~= nil or char:byte() >= 128
end

--- Find a phrase only where it stands as a whole phrase.
--
-- A plain substring search replaced fragments inside Russian words - "повышение" came out
-- as "Rakeение" once - because e.g. "ожога" sat inside a longer word. Requiring a non-word
-- character on both sides fixes that.
local function findWhole(lowered, phrase)
	local from = 1
	while true do
		local startIndex, endIndex = lowered:find(phrase, from, true)
		if not startIndex then
			return nil
		end
		local beforeOk = not isWordByte(lowered:sub(startIndex - 1, startIndex - 1))
		local afterOk = not isWordByte(lowered:sub(endIndex + 1, endIndex + 1))
		if beforeOk and afterOk then
			return startIndex
		end
		from = startIndex + 1
	end
end

--- The official Russian -> English modifier table (Data/ru_stats.lua, built by
-- tools/fetch_ru_map.py from the localised trade site). Both sides are stored with the
-- numbers replaced by '#', so any roll finds its template.
local statsCache = nil
local function statMap()
	if statsCache == nil then
		-- The dictionaries are split by stat group (Data/ru_stats_<kind>.lua) and indexed by
		-- Data/ru_stats.lua: one big file was not read by the host at all, small ones are.
		local okIndex, index = pcall(require, "Data.ru_stats")
		if not okIndex or type(index) ~= "table" or type(index.parts) ~= "table" then
			statsCache = false
		else
			local merged = { }
			for _, partName in ipairs(index.parts) do
				local ok, part = pcall(require, "Data." .. tostring(partName))
				if ok and type(part) == "table" and type(part.stats) == "table" then
					for template, english in pairs(part.stats) do
						merged[template] = english
					end
				end
			end
			statsCache = next(merged) and merged or false
		end
	end
	return statsCache or nil
end

--- Reduce a line to a comparable template: ranges and numbers become '#'.
local function templateOf(text)
	local value = tostring(text)
	-- The (26-30) in "+30(26-30)% to Cold Resistance" is the roll RANGE, not a second value, and
	-- numbersIn drops it for the same reason. Keeping it as "#" made the template "##%" while the
	-- dictionary key is "#%", so nothing matched and a Russian client's line came out half translated
	-- ("+30% к сопротивлению Coldу") - which then reached the panel and the trade recipe.
	value = value:gsub("%(%s*[-+]?%d+%.?%d*%s*%-%s*[-+]?%d+%.?%d*%s*%)", "")
	value = value:gsub("[-+]?%d+%.?%d*", "#")
	value = value:gsub("%+", "")
	value = value:gsub("#%s+#", "#")
	value = value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return lower(value)
end

--- The numbers of a line, in order, as strings.
local function numbersIn(text)
	local out = { }
	local value = tostring(text)
	-- Drop the tier range first: "(2-4)" describes the roll, not the modifier's value.
	value = value:gsub("%(%s*[-+]?%d+%.?%d*%s*%-%s*[-+]?%d+%.?%d*%s*%)", "")
	local sign = ""
	for number in value:gmatch("([-+]?%d+%.?%d*)") do
		out[#out + 1] = number
	end
	return out
end

--- Put the original numbers back into the English template.
local function fillTemplate(template, numbers)
	local index = 0
	local filled = tostring(template):gsub("#", function()
		index = index + 1
		return numbers[index] or "#"
	end)
	return filled
end

--- Base type names, also from the official localised data (paired by position inside each
-- category, and only for categories whose counts match in both languages).
local basesCache = nil
local function baseMap()
	if basesCache == nil then
		-- A separate, smaller data file: the combined one was not read reliably by the host.
		local ok, data = pcall(require, "Data.ru_bases")
		basesCache = (ok and type(data) == "table" and type(data.bases) == "table") and data.bases or false
	end
	return basesCache or nil
end

local function escapePattern(text)
	return (tostring(text):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

--- Replace a Russian base type name with its English one.
local function translateBase(line)
	local map = baseMap()
	if not map or not line:find(CYRILLIC) then
		return line
	end
	-- The longest match wins, so a short name cannot cut a longer one in half, and the match
	-- must be a whole word: replacing a base name inside a longer Russian word produced
	-- "Rakeение" out of "Выпадение" in a real annotation.
	local best, target = nil, nil
	for russian, english in pairs(map) do
		local from = line:find(russian, 1, true)
		if from and (best == nil or #russian > #best) then
			local beforeOk = not isWordByte(line:sub(from - 1, from - 1))
			local afterOk = not isWordByte(line:sub(from + #russian, from + #russian))
			if beforeOk and afterOk then
				best, target = russian, english
			end
		end
	end
	if best then
		return (line:gsub(escapePattern(best), function() return target end, 1))
	end
	return line
end

--- Translate one line through the official table. Returns nil when it is not there.
local function translateWithTable(line)
	local map = statMap()
	if not map then
		return nil
	end
	local english = map[templateOf(line)]
	if not english then
		return nil
	end
	local numbers = numbersIn(line)
	local filled = fillTemplate(english, numbers)
	-- The roll range the advanced copy prints ("+18(15-20)%") is not part of the trade vocabulary, so no
	-- dictionary key can carry it: it is put back after the value instead of being dropped. Dropping it
	-- lost information the player needs (the same test asserts it survives), while keeping it in the key
	-- meant the line did not match at all and reached the panel half translated.
	local range = line:match("%(%s*[-+]?%d+%.?%d*%s*[%-–—]%s*[-+]?%d+%.?%d*%s*%)")
	if range then
		filled = filled:gsub("([%+%-]?%d+%.?%d*)", "%1" .. range:gsub("%%", "%%%%"), 1)
	end
	-- The game writes "+118 to maximum Life" while the trade vocabulary writes
	-- "# to maximum Life": keep the game's sign, the matcher normalises it anyway.
	-- The plus sign belongs to a number that LEADS the line ("+18 to Strength"), not to a sentence that
	-- happens to contain one: the official table turned a modifier into "Allies in your Presence have
	-- +33% increased Critical Hit Chance", which reads like a mistake.
	if english:sub(1, 1) == "#" and tonumber(numbers[1] or "") and tonumber(numbers[1]) > 0
		and filled:sub(1, 1) ~= "+" then
		filled = "+" .. filled
	end
	return filled
end

--- Does this text look like it came from a Russian client?
function Ru.looksRussian(text)
	if type(text) ~= "string" then
		return false
	end
	return text:find(CYRILLIC) ~= nil
end

--- Does a line still contain Cyrillic after translation?
local function hasCyrillic(text)
	return text:find(CYRILLIC) ~= nil
end

--- Translate a Russian item text into the English layout the parser expects.
-- @param text copied item text (Russian client)
-- @return translated text, plus a report { translated, leftover }
function Ru.toEnglish(text)
	local out = { }
	local leftover = 0
	local officialCount = 0
	local dictionaryCount = 0
	local untranslated = { }
	local traces = { }
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local converted = line
		local trace = { original = line }

		-- 1. The official table first: it knows the exact wording the game uses, so a line
		--    it knows becomes the English modifier the engine matches against.
		local official = translateWithTable(converted)
		if official then
			converted = official
			officialCount = officialCount + 1
		end

		-- 2. The game writes a modifier's tier as "(Уровень: N)" inside its { ... } annotations, while a
		--    plain "Уровень:" label means the required character level. The annotation form is handled
		--    first, or the generic label would swallow it.
		converted = converted:gsub("%(Уровень: (%d+)%)", "(Tier: %1)")

		-- A modifier line the official table did NOT recognise must be left exactly as the client wrote
		-- it. The word-level passes below exist for labels, property lines and annotations; applied to a
		-- modifier they translate a word or two and leave the rest Russian, and that hybrid is worse than
		-- no translation at all - a live item showed "Союзники в вашем присутствии имеют 33% увеличение
		-- шанса Critical Strike". A stat line is recognisable without guessing: it carries numbers, has no
		-- label colon, and is not an annotation.
		local isModifier = official == nil
			and converted:find("%d") ~= nil
			and converted:find(":", 1, true) == nil
			and converted:sub(1, 1) ~= "{"
		if not isModifier then

		-- Item classes and slots FIRST, before the short label words.
		--
		-- Order matters and the old order was wrong: the label pass replaces the bare word
		-- "Свойство" with "Modifier", which sits INSIDE the class name "Самоцветы" - the class
		-- became "GemС‹", no class the engine knows, and every class-driven decision (quality
		-- currency, modifier pool) silently lost its item class. Longest match first is the rule
		-- the tables already state; this is that rule applied between passes rather than inside one.
		for russian, english in pairs(CLASSES) do
			converted = converted:gsub(russian, english)
		end

		-- Labels first, then property values. The other order broke the label "Уровень
		-- предмета" (its first word was replaced before the label could be recognised), and
		-- with the capitalised spellings in VALUES the values still match afterwards.
		local lowered = lower(converted)
		for _, pair in ipairs(LABELS) do
			if converted:find(pair[1], 1, true) then
				converted = converted:gsub(pair[1], pair[2], 1)
			end
		end

		lowered = lower(converted)
		for _, pair in ipairs(VALUES) do
			-- Plain search, exactly like the label pass above. The boundary helper was tried
			-- here and refused matches it should have taken, and the table holds whole words
			-- (in both spellings), so a plain search is both simpler and correct.
			local from = lowered:find(pair[1], 1, true)
			if from then
				converted = converted:sub(1, from - 1) .. pair[2] .. converted:sub(from + #pair[1])
				lowered = lower(converted)
			end
		end
		trace.afterValues = converted

		trace.afterLabels = converted
		-- Rarity words appear as a value after "Rarity:".
		for russian, english in pairs(RARITY) do
			converted = converted:gsub(russian, english)
		end

		-- Modifier phrases: only the matched fragments are replaced, so numbers and the
		-- structure of the line stay exactly as the game wrote them.
		local before = converted
		lowered = lower(converted)
		for _, pair in ipairs(PHRASES) do
			-- Plain search on purpose: the game inflects these phrases ("к сопротивлению
			-- огню и холоду"), so requiring a whole phrase would miss real lines. The short
			-- entries that could sit inside a word are spelled out in full in the table
			-- instead of relying on boundaries here.
			local from = lowered:find(pair[1], 1, true)
			if from then
				converted = converted:sub(1, from - 1) .. pair[2] .. converted:sub(from + #pair[1])
				lowered = lower(converted)
			end
		end
		if converted ~= before then
			dictionaryCount = dictionaryCount + 1
		end

		end   -- not a modifier line: the word-level passes only run there

		-- Base type names come from the same official source, so the item's name line turns into the
		-- English base type the engine knows. On a Magic item this line IS the base line (the game writes
		-- prefix + base + suffix in one line), so it cannot be skipped; the affix words around the base
		-- stay Russian because there is no official table of affix names to translate them from.
		converted = translateBase(converted)
		if hasCyrillic(converted) then
			leftover = leftover + 1
			if #untranslated < 12 then
				untranslated[#untranslated + 1] = converted
			end
			if #traces < 4 then
				trace.final = converted
				traces[#traces + 1] = trace
			end
		end
		out[#out + 1] = converted
	end

	local result = table.concat(out, "\n")
	return result, {
		translated = true,
		lines = #out,
		leftover = leftover,
		official = officialCount,
		dictionary = dictionaryCount,
		untranslated = untranslated,
		traces = traces,
		phraseCount = #PHRASES,
	}
end

--- Statistics for the diagnostics log.
function Ru.stats()
	return { labels = #LABELS, phrases = #PHRASES, bases = (function()
		local count = 0
		for _ in pairs(baseMap() or { }) do count = count + 1 end
		return count
	end)(), classes = (function()
		local count = 0
		for _ in pairs(CLASSES) do count = count + 1 end
		return count
	end)(), rarities = (function()
		local count = 0
		for _ in pairs(RARITY) do count = count + 1 end
		return count
	end)() }
end

--- The reverse direction: English names and modifier texts back into Russian.
--
-- Why it exists: the engine works in English, and a Russian panel that shows "Orb of Augmentation" or
-- "+30% to Cold Resistance" looks half translated. The pairs are not written by hand - the official
-- localised data is inverted by tools/build_display_names.py, so the parsing direction and the display
-- direction can never drift apart.
--
-- Split into parts for the same measured reason the modifier dictionary is (see statMap above).
local displayCache = nil
local function displayMaps()
	if displayCache == nil then
		local okIndex, index = pcall(require, "Data.display_names_ru")
		if not okIndex or type(index) ~= "table" or type(index.parts) ~= "table" then
			displayCache = false
		else
			local names, stats = { }, { }
			for _, partName in ipairs(index.parts) do
				local ok, part = pcall(require, "Data." .. tostring(partName))
				if ok and type(part) == "table" then
					for english, russian in pairs(part.map or { }) do
						if names[english] == nil then
							names[english] = russian
						end
					end
					for template, russian in pairs(part.stats or { }) do
						if stats[template] == nil then
							stats[template] = russian
						end
					end
				end
			end
			displayCache = (next(names) or next(stats)) and { names = names, stats = stats } or false
		end
	end
	return displayCache or nil
end

--- Template for the DISPLAY direction (English -> Russian).
--
-- The difference from templateOf: a roll range counts as a VALUE here. Path of Building writes
-- "(14-20)% increased Armour and Evasion" where the game writes "18% increased ...", so dropping the range
-- produced a template with no placeholder at all and nothing matched.
local function displayTemplate(text)
	local value = tostring(text)
	value = value:gsub("%(%s*[-+]?%d+%.?%d*%s*%-%s*[-+]?%d+%.?%d*%s*%)", "#")
	value = value:gsub("[-+]?%d+%.?%d*", "#")
	value = value:gsub("%+", "")
	value = value:gsub("#%s*#", "#")
	value = value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return value:lower()
end

--- The numbers and roll ranges of a line, in the order they appear.
local function displayPieces(text)
	local out = { }
	local value = tostring(text)
	local position = 1
	while position <= #value do
		local rangeStart, rangeEnd, rangeText = value:find(
			"(%(%s*[-+]?%d+%.?%d*%s*%-%s*[-+]?%d+%.?%d*%s*%))", position)
		local numberStart, numberEnd, numberText = value:find("([-+]?%d+%.?%d*)", position)
		if rangeStart and (not numberStart or rangeStart < numberStart) then
			out[#out + 1] = rangeText
			position = rangeEnd + 1
		elseif numberStart then
			out[#out + 1] = numberText
			position = numberEnd + 1
		else
			break
		end
	end
	return out
end

--- Fill a template's placeholders with those pieces, in order.
local function displayFill(template, pieces)
	local index = 0
	return (tostring(template):gsub("#", function()
		index = index + 1
		return pieces[index] or "#"
	end))
end
--- English name or modifier text in Russian.
-- @param text English name ("Pariah Mask") or modifier text ("+30% to Cold Resistance")
-- @return Russian text, or nil when nothing is known - the caller keeps English rather than inventing
function Ru.toRussian(text)
	local maps = displayMaps()
	if not maps then
		return nil
	end
	local value = tostring(text or "")
	if value == "" then
		return nil
	end
	local name = maps.names[value]
	if name then
		return name
	end
	-- A modifier. Path of Building prints a tier's ROLL RANGE where the game prints the rolled number
	-- ("(14-20)% increased Armour and Evasion"), so in this direction a range IS the value: it becomes a
	-- placeholder for the template lookup and is put back verbatim afterwards. Blanking only the digits
	-- (the parsing direction) left the template as "% increased Armour and Evasion", which is not a key
	-- any dictionary holds - that is why 642 modifier lines stayed English in the Russian panel.
	local english = displayTemplate(value)
	local template = maps.stats[english]
	if not template then
		return nil
	end
	local filled = displayFill(template, displayPieces(value))
	-- The plus sign belongs to a number that LEADS the line ("+18 to Strength"), not to a sentence that
	-- happens to contain one: the official table turned a modifier into "Allies in your Presence have
	-- +33% increased Critical Hit Chance", which reads like a mistake.
	local first = tostring(displayPieces(value)[1] or "")
	if english:sub(1, 1) == "#" and tonumber(first) and tonumber(first) > 0 and filled:sub(1, 1) ~= "+" then
		filled = "+" .. filled
	end
	return filled
end

--- Whether this exact text is a name the display dictionary knows.
function Ru.knownName(text)
	local maps = displayMaps()
	return (maps and maps.names[tostring(text or "")]) or nil
end

return Ru
