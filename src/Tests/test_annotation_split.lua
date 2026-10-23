-- The prefix/suffix split must follow the annotation the game prints, not our modifier tables.
--
-- Found on the customer's helmet: "19% increased Rarity of Items found" is a SUFFIX in Path of Building's
-- tables, but a helmet carries it as a PREFIX ("Exotic") and the game writes that in the line above it.
-- Trusting the table's type counted the prefix as a suffix, so the item came out as 2 prefixes and 4
-- suffixes - a shape no rare can have. Slot advice is withheld for an impossible split, so the panel
-- quietly stopped giving it, and the payload crashed outright on a nil open-slot count.
return function()
	local H = require("Tests.harness")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Api = require("Mcp.api")

	-- Three prefixes and three suffixes. The first prefix carries two stat lines, which must count as one
	-- affix: counting lines produced seven affixes and seven tier verdicts for a six-affix item.
	local HELMET = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Symbolic Bastion", "Sorcerous Tiara", "--------",
		"Energy Shield: 218 (augmented)", "--------",
		"Requirements: Level 70, 84 (augmented) Int", "--------", "Item Level: 79", "--------",
		'{ Prefix Modifier "Charged" (Tier: 2) - Mana, Energy Shield }',
		"37(33-38)% increased Energy Shield",
		"+32(27-32) to maximum Mana",
		'{ Prefix Modifier "Unfaltering" (Tier: 2) - Energy Shield }',
		"88(80-91)% increased Energy Shield",
		'{ Prefix Modifier "Exotic" (Tier: 1) - Rarity }',
		"19(16-19)% increased Rarity of Items found",
		'{ Suffix Modifier "of the Exile" (Tier: 3) - Chaos, Resistance }',
		"+18(16-19)% to Chaos Resistance",
		'{ Suffix Modifier "of Archaeology" (Tier: 1) - Rarity }',
		"16(15-18)% increased Rarity of Items found",
		'{ Suffix Modifier "of Aptitude" (Tier: 5) }',
		"15% reduced Attribute Requirements",
	}, "\n")
	local item = Parser.parse(HELMET)
	Mods.annotate(item)
	H.eq("annotation: three prefixes", item.prefixCount, 3)
	H.eq("annotation: three suffixes", item.suffixCount, 3)
	H.eq("annotation: the split is complete", item.affixSplitComplete, true)
	H.eq("annotation: and arithmetically possible", item.affixSplitConsistent, true)
	H.eq("annotation: no unclassified lines", item.unclassifiedMods, 0)
	H.eq("annotation: the annotation decided every side", item.sideFromAnnotation, 6)
	H.eq("annotation: nothing is open", (item.openPrefixes or 0) + (item.openSuffixes or 0), 0)
	H.eq("annotation: every affix has a tier verdict",
		(item.tiersExact or 0) + (item.tiersEstimated or 0), 6)

	-- The Russian client writes "{ Префикс ... }" instead of "{ Prefix Modifier ... }", and the dictionary
	-- translates modifier wording only partly, so the annotation is what keeps the split readable there.
	local RUSSIAN = table.concat({
		"Класс предмета: Шлемы", "Редкость: Редкий", "Символический бастион", "Чародейская тиара",
		"--------", "Энергетический щит: 218 (augmented)", "--------",
		"Требуется: Уровень 70, 84 (augmented) Инт", "--------", "Уровень предмета: 79", "--------",
		'{ Префикс "Заоблачный" (Уровень: 2) — Мана, Энергетический щит }',
		"37(33-38)% увеличение энергетического щита",
		"+32(27-32) к максимуму маны",
		'{ Префикс "Неукротимый" (Уровень: 2) — Энергетический щит }',
		"88(80-91)% увеличение энергетического щита",
		'{ Префикс "Диковинный" (Уровень: 1) — Выпадение }',
		"19(16-19)% повышение редкости найденных предметов",
		'{ Суффикс "ссыльного" (Уровень: 3) — Хаос, Сопротивление }',
		"+18(16-19)% к сопротивлению хаосу",
		'{ Суффикс "археологии" (Уровень: 1) — Выпадение }',
		"16(15-18)% повышение редкости найденных предметов",
		'{ Суффикс "уместности" (Уровень: 5) }',
		"15% снижение требований к характеристикам",
	}, "\n")
	-- lang = "en": this block compares the SPLIT itself, and the English spelling is what it was written
	-- against. The Russian spelling of the same numbers is covered by Tests.test_language_corpus.
	local russian = assert(Api.call("analyze_item", { item_text = RUSSIAN, lang = "en" }))
	H.eq("annotation: the Russian client reads the same split",
		russian.item.affixes, "3P/3S open 0P/0S")
	H.eq("annotation: and the same rule", russian.ruleId, "rare_full")

	-- "Дарует умение: ..." / "Grants Skill: ..." is the sceptre's own line, not a modifier. Left out of the
	-- property list it became one unclassified line, and one unclassified line is enough for the advisor to
	-- refuse a rule: the payload came back with no rule and no plan, so the panel answered from its
	-- previous screen and offered a Divine reroll for an item the engine had not parsed at all.
	local SCEPTRE = table.concat({
		"Класс предмета: Скипетры", "Редкость: Редкий", "Ужасный нарост", "Гремящий скипетр",
		"--------", "Дух: 114 (augmented)", "--------", "Требуется: Уровень 44", "--------",
		"Уровень предмета: 78", "--------",
		"Дарует умение: Приспешник скелет-воин 18 уровня", "--------",
		'{ Префикс "Бирюзовый" (Уровень: 8) — Мана }', "+35(35-54) к максимуму маны",
		'{ Префикс "Советнический" (Уровень: 7) }', "14(10-14)% увеличение духа",
		"+17(17-20) к максимуму маны",
		'{ Префикс "Принуждающий" (Уровень: 8) — Урон }',
		"Союзники в вашем присутствии наносят увеличенный на 31(25-34)% урон",
		'{ Суффикс "смотрителя" (Уровень: 2) — Приспешник, Камень }',
		"+3 к уровню всех камней умений приспешников",
	}, "\n")
	local sceptreItem = Parser.parse(require("Item.Ru").toEnglish(SCEPTRE))
	Mods.annotate(sceptreItem)
	H.eq("annotation: the skill line is a property, not a modifier",
		sceptreItem.unclassifiedMods, 0)
	H.check("annotation: and it is recorded as a property",
		sceptreItem.properties["Дарует умение"] ~= nil or sceptreItem.properties["Grants Skill"] ~= nil,
		table.concat((function()
			local keys = { }
			for key in pairs(sceptreItem.properties or { }) do keys[#keys + 1] = tostring(key) end
			return keys
		end)(), ", "))
	-- lang = "en": the steps are compared by their English currency names, which are the canonical ones.
	local sceptre = assert(Api.call("analyze_item", { item_text = SCEPTRE, lang = "en" }))
	H.eq("annotation: the sceptre gets a rule", sceptre.ruleId, "rare_prefixes_full")
	local sceptreSteps = { }
	for _, step in ipairs((sceptre.plans[1] or { }).steps or { }) do
		sceptreSteps[#sceptreSteps + 1] = tostring(step.name)
	end
	H.eq("annotation: and it is told to fill the empty slot, not to reroll",
		(sceptreSteps[1] or ""), "Exalted Orb")

	-- The panel saves the last captured item here, which is how this bug was diagnosed. The file changes
	-- with every capture, so only the thing that must always hold is asserted: the payload answers and
	-- carries an item. affixes is nil by design when the split is unknown, and asserting otherwise made
	-- this check fail on a legitimate item.
	local file = io.open("last_item.txt", "rb")
	if file then
		local text = file:read("*a")
		file:close()
		local ok, saved = pcall(Api.call, "analyze_item", { item_text = text })
		H.check("annotation: the last captured item still analyses", ok and type(saved) == "table",
			tostring(saved))
		if ok and type(saved) == "table" then
			H.check("annotation: and its payload carries an item",
				type(saved.item) == "table" and type(saved.item.affixes) ~= "boolean",
				tostring(saved.item and saved.item.affixes))
		end
	end
end
