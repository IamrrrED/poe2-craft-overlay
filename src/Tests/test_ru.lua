-- PoE2 Craft Overlay : Tests/test_ru.lua
-- Russian input: a Russian client copies Russian text, and the engine works on English
-- Path of Building data, so this layer decides whether the tool works at all for such a
-- player. The sample below is a real capture from the game, not a made-up one.

local Ru = require("Item.Ru")
local Parser = require("Item.Parser")

local RUSSIAN = [[
Класс предмета: Амулеты
Редкость: Волшебный
Маркизский Алый амулет дракона
--------
Требуется: Уровень 36
--------
Уровень предмета: 79
--------
{ Собственное свойство — Здоровье }
Регенерация 3(2-4) здоровья в секунду
--------
{ Префикс "Маркизский" (Уровень: 2) }
+18(15-20) к ловкости
--------
{ Суффикс "дракона" (Уровень: 3) }
+24(20-30)% к сопротивлению огню
]]

local ENGLISH = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+118 to maximum Life
]]

return function(H)
	H.eq("ru: russian text is detected", Ru.looksRussian(RUSSIAN), true)
	H.eq("ru: english text is not touched", Ru.looksRussian(ENGLISH), false)

	local translated, report = Ru.toEnglish(RUSSIAN)
	H.eq("ru: translation reports what it did", report.translated, true)
	H.contains("ru: class label", translated, "Item Class:")
	H.contains("ru: class value", translated, "Amulets")
	H.contains("ru: rarity label", translated, "Rarity:")
	H.contains("ru: rarity value", translated, "Magic")
	H.contains("ru: item level label", translated, "Item Level:")
	H.contains("ru: prefix annotation", translated, "Prefix Modifier")
	H.contains("ru: suffix annotation", translated, "Suffix Modifier")
	H.contains("ru: tier inside an annotation", translated, "(Tier: 2)")
	H.contains("ru: fire resistance phrase", translated, "to Fire Resistance")
	H.eq("ru: numbers are left alone", translated:find("18(15-20)", 1, true) ~= nil, true)
	H.eq("ru: separators survive", translated:find("--------", 1, true) ~= nil, true)
	H.eq("ru: leftover lines are counted", report.leftover >= 1, true)

	-- An official stat line with a roll RANGE must be recognised: the client writes
	-- "имеют 33(30-34)% увеличение ...", and the dictionary key is "#% увеличение ...". Before the
	-- range was dropped from the key, and before the Cyrillic-aware lowercase existed, this line came
	-- out half translated (see Tests.test_data_files for the loading half of that story).
	local allies = Ru.toEnglish("Союзники в вашем присутствии имеют 33(30-34)% увеличение шанса критического удара")
	H.check("ru: a ranged official line becomes English",
		tostring(allies):find("Critical Hit Chance", 1, true) ~= nil, tostring(allies))
	H.check("ru: and the sign belongs only to a leading number",
		tostring(allies):sub(1, 1) ~= "+", tostring(allies))

-- The point of the whole exercise: the engine can read the item afterwards.
	local item = Parser.parse(translated)
	H.eq("ru: parser accepts the translated item", item ~= nil, true)
	H.eq("ru: class read", item.itemClass, "Amulets")
	H.eq("ru: rarity read", tostring(item.rarity):lower(), "magic")
	H.eq("ru: item level read", item.itemLevel, 79)
	H.eq("ru: the item is considered valid", item.valid ~= false, true)

	-- Base type names come from the official localised data as well.
	local baseTest = Ru.toEnglish("Маркизский Алый амулет дракона")
	H.contains("ru: base type translated", baseTest, "Amulet")
	H.eq("ru: base dictionary loaded", Ru.stats().bases > 100, true)

	-- The dictionary must not cut fragments out of longer Russian words.
	local mangled = Ru.toEnglish("15% повышение редкости найденных предметов")
	H.eq("ru: no mangled russian words", mangled:find("Rake", 1, true), nil)

	-- Property values use the same words as the labels.
	local properties = Ru.toEnglish("Требуется: Уровень 36")
	H.contains("ru: property value translated", properties, "Level")

	local stats = Ru.stats()
	H.eq("ru: dictionary is present", stats.phrases > 20, true)
	H.eq("ru: classes are present", stats.classes > 10, true)
end
