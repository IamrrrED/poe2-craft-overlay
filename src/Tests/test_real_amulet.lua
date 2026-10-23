-- The customer's own amulet: a full rare on a Russian client.
--
-- Three things were wrong with it, and all three came from the same place - the parser treated the IMPLICIT
-- block as an unclassified modifier. That switched `affixSplitComplete` off, so the panel could not tell the
-- item was full and offered a currency to add a modifier to a 3/3 amulet. The same run also showed a modifier
-- carrying the wrong side, because the side came from Path of Building's table instead of the game's own
-- annotation.
--
-- The text below is reproduced verbatim from src/last_item.txt as the client wrote it.
return function()
	local H = require("Tests.harness")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Ru = require("Item.Ru")
	local Api = require("Mcp.api")

	local CAPTURED = table.concat({
		"Класс предмета: Амулеты",
		"Редкость: Редкий",
		"Вихревой медальон",
		"Лазурный амулет",
		"--------",
		"Требуется: Уровень 64",
		"--------",
		"Уровень предмета: 83",
		"--------",
		"{ Собственное свойство — Мана }",
		"23(20-30)% повышение скорости регенерации маны",
		"--------",
		'{ Префикс "Выносливый" (Уровень: 1) — Здоровье }',
		"+123(120-149) к максимуму здоровья",
		'{ Префикс "Маревый" (Уровень: 3) — Уклонение }',
		"37(33-38)% увеличение уклонения",
		'{ Префикс "Неприступный" (Уровень: 1) — Энергетический щит }',
		"47(45-50)% увеличение максимума энергетического щита",
		'{ Суффикс "стежков" (Уровень: 3) — Здоровье }',
		"16(16-18)% полученного урона восполняется в виде здоровья",
		'{ Суффикс "таланта" (Уровень: 3) — Чародейский, Скорость }',
		"19(19-21)% повышение скорости сотворения чар",
		'{ Суффикс "переливов" (Уровень: 1) — Стихийный, Огонь, Холод, Молния, Сопротивление }',
		"+17(17-18)% к сопротивлению всем стихиям",
	}, "\n")

	H.eq("amulet: the client's Russian is detected", Ru.looksRussian(CAPTURED), true)
	local item = Parser.parse(Ru.toEnglish(CAPTURED) or CAPTURED)
	Mods.annotate(item)

	-- The split has to be complete: every modifier was recognised, and it is 3 prefixes and 3 suffixes.
	H.eq("amulet: three prefixes are counted", item.prefixCount, 3)
	H.eq("amulet: three suffixes are counted", item.suffixCount, 3)
	H.eq("amulet: the split is complete despite the implicit", item.affixSplitComplete, true)
	H.eq("amulet: and arithmetically possible", item.affixSplitConsistent, true)
	H.eq("amulet: caps are the ordinary three and three", item.affixCaps and item.affixCaps.prefixes, 3)

	-- The item is FULL. This is the fact the panel used to miss, and it is what turned "nothing to add" into
	-- "add an Exalted Orb for 0.03 chaos".
	H.eq("amulet: no prefix slot is open", item.openPrefixes, 0)
	H.eq("amulet: no suffix slot is open", item.openSuffixes, 0)

	-- The implicit is not an affix and must not be counted as unclassified.
	H.eq("amulet: nothing is left unclassified", item.unclassifiedMods or 0, 0)

	-- Side comes from the game's annotation, not from the builder's table: "+maximum Life" is a PREFIX here
	-- while Path of Building tables it as a suffix.
	local lifeMod = nil
	for _, mod in ipairs(item.explicitMods or { }) do
		if tostring(mod.text):find("to maximum Life", 1, true) then lifeMod = mod end
	end
	H.check("amulet: the life modifier is found", lifeMod ~= nil)
	if lifeMod then
		H.eq("amulet: and its side is the game's, not the table's", lifeMod.side, "prefix")
	end

	-- The block the panel builds from it must say "nothing to add", not quote a price for adding.
	local payload = assert(Api.call("craft_step", { item_text = CAPTURED }))
	local block = payload.craftOrBuy
	H.check("amulet: the step card carries the craft-or-buy block", block ~= nil)
	if block then
		H.eq("amulet: it does not price a modifier that cannot be added", block.hasCost, false)
		H.eq("amulet: it knows the item is full", block.fullItem, true)
		H.check("amulet: and says what is left instead",
			type(block.fullNote) == "string" and block.fullNote:find("некуда", 1, true) ~= nil,
			tostring(block.fullNote))
	end
end
