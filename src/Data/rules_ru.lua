-- PoE2 Craft Overlay : Data/rules_ru.lua
-- Russian text for the ruleset's own English descriptions.
--
-- The league ruleset (Data/league_0_5_5.lua) carries its descriptions in English (`effectEn`,
-- `warningEn`), because those are the strings that go to the site and to anyone reading the data. The
-- panel answers in the language the player picked, so the Russian side needs the same sentences - and
-- hand-translating 105 entries inside the ruleset would put the two languages far apart and make the next
-- rule easy to add in English only.
--
-- So the Russian text lives here, keyed by the English sentence it translates. Lookup is exact; a sentence
-- without an entry simply stays English, which is the honest degradation (an unknown rule is better read
-- in the language it was written than mangled).
--
-- Terms that have no settled Russian name in the community (Foulborn, Graft Implants, Kurgal, Amanamu,
-- Ulaman, Logbook, Biome) stay as the game writes them.
local RulesRu = { }

RulesRu.effects = {
	["Turns a Normal item Magic with one modifier."] =
		"Превращает обычный предмет в волшебный с одним модом.",
	["As Transmutation, with a minimum modifier level of 44."] =
		"Как Transmutation, но минимальный уровень мода 44.",
	["As Transmutation, with a minimum modifier level of 70."] =
		"Как Transmutation, но минимальный уровень мода 70.",
	["Adds one modifier to a Magic item (Magic caps at one prefix and one suffix)."] =
		"Добавляет один мод волшебному предмету (у волшебного максимум один префикс и один суффикс).",
	["As Augmentation, with a minimum modifier level of 44."] =
		"Как Augmentation, но минимальный уровень мода 44.",
	["As Augmentation, with a minimum modifier level of 70."] =
		"Как Augmentation, но минимальный уровень мода 70.",
	["Upgrades a Magic item to Rare and adds one modifier."] =
		"Поднимает волшебный предмет до редкого и добавляет один мод.",
	["As Regal, with a minimum modifier level of 35."] =
		"Как Regal, но минимальный уровень мода 35.",
	["As Regal, with a minimum modifier level of 50."] =
		"Как Regal, но минимальный уровень мода 50.",
	["Adds one random modifier to a Rare item (max 3 prefixes + 3 suffixes)."] =
		"Добавляет один случайный мод редкому предмету (максимум 3 префикса и 3 суффикса).",
	["As Exalted, with a minimum modifier level of 35 - cuts the junk tiers."] =
		"Как Exalted, но минимальный уровень мода 35 — отсекает мусорные тиры.",
	["As Exalted, with a minimum modifier level of 50 - the final slam."] =
		"Как Exalted, но минимальный уровень мода 50 — финальная попытка.",
	["Lets an item foresee the result of the next Currency item used on it. Modifying the item in any way removes the ability to foresee."] =
		"Позволяет предмету увидеть заранее результат следующей валюты, применённой к нему. Любое изменение предмета снимает эту возможность.",
	["Removes one random modifier and adds a new one (Rare items)."] =
		"Убирает один случайный мод и добавляет новый (для редких предметов).",
	["As Chaos, with a minimum modifier level of 35."] =
		"Как Chaos, но минимальный уровень мода 35.",
	["As Chaos, with a minimum modifier level of 50."] =
		"Как Chaos, но минимальный уровень мода 50.",
	["Rerolls the numeric values of existing modifiers; the modifier set is unchanged."] =
		"Перебрасывает числа существующих модов; набор модов не меняется.",
	["Removes one random modifier. Risky: it can strip the modifier you need."] =
		"Убирает один случайный мод. Рискованно: может снять нужный вам мод.",
	["Locks one random modifier in place; it can no longer be modified."] =
		"Закрепляет один случайный мод; изменить его больше нельзя.",
	["Corrupts the item: adds a corrupted implicit, an extra socket or another effect (possibly bricking it). No further changes."] =
		"Оскверняет предмет: добавляет осквернённый имплисит, лишний сокет или другой эффект (возможна порча предмета). Дальше менять его нельзя.",
	["Upgrades a Normal item straight to Rare with several modifiers (typically 4)."] =
		"Поднимает обычный предмет сразу до редкого с несколькими модами (обычно четырьмя).",
	["Upgrades a Normal item into a random Unique of the same class - or destroys it."] =
		"Превращает обычный предмет в случайный уникальный того же класса — или уничтожает его.",
	["Raises item quality (scales base stats). Do this BEFORE expensive modifiers."] =
		"Поднимает качество предмета (оно множит характеристики базы). Делать это нужно ДО дорогих модов.",
	["Raises the quality of martial weapons: 1% more local physical damage per 1% quality."] =
		"Поднимает качество боевого оружия: +1% к локальному физическому урону за каждый 1% качества.",
	["Raises the quality of armour: 1% more defences (armour, evasion, energy shield) per 1%."] =
		"Поднимает качество брони: +1% к защитам (броня, уклонение, энергетический щит) за каждый 1%.",
	["Raises the quality of wands, staves and sceptres: 1% quality per 1%, which improves the socketed skill."] =
		"Поднимает качество жезлов, посохов и скипетров: 1% качества за 1%, что усиливает вложенное умение.",
	["Raises the quality of a flask: 1% more recovery per 1% quality."] =
		"Поднимает качество флакона: +1% к восстановлению за каждый 1% качества.",
	["Raises the quality of a skill or support gem; always exactly 5%."] =
		"Поднимает качество камня умения или поддержки; всегда ровно 5%.",
	["Guarantees one specific modifier. Occupies the item's single crafted-modifier slot."] =
		"Гарантирует один конкретный мод. Занимает единственный слот созданного мода на предмете.",
	["Guarantees the modifier at the highest available mod level. Also uses the crafted-mod slot."] =
		"Гарантирует мод с максимально доступным уровнем мода. Тоже занимает слот созданного мода.",
	["Rewrites the rules of the next matching currency (e.g. adds only a suffix)."] =
		"Меняет правила следующей подходящей валюты (например, добавит только суффикс).",
	["Adds a hidden desecrated modifier; you pick one of three at the Well of Souls."] =
		"Добавляет скрытый осквернённый мод; у Колодца Душ вы выбираете один из трёх.",
	["Removes a random modifier and adds one exclusive to that alloy. Uses the crafted-mod slot."] =
		"Убирает случайный мод и добавляет мод, доступный только этому сплаву. Занимает слот созданного мода.",
	["A rune goes into a socket for a fixed modifier; meta-runes unlock new mod pools for normal crafting."] =
		"Руна вставляется в сокет и даёт фиксированный мод; мета-руны открывают новые пулы модов для обычного крафта.",
	["The next Chaos Orb removes the lowest-level modifier instead of a random one."] =
		"Следующий Chaos Orb снимает мод с самым низким уровнем вместо случайного.",
	["The next Chaos Orb removes only a prefix."] =
		"Следующий Chaos Orb снимает только префикс.",
	["The next Chaos Orb removes only a suffix."] =
		"Следующий Chaos Orb снимает только суффикс.",
	["The next Exalted Orb adds two modifiers instead of one."] =
		"Следующий Exalted Orb добавляет два мода вместо одного.",
	["The next Exalted Orb adds only a prefix."] =
		"Следующий Exalted Orb добавляет только префикс.",
	["The next Exalted Orb adds only a suffix."] =
		"Следующий Exalted Orb добавляет только суффикс.",
	["The next Exalted Orb adds a modifier sharing a TAG with one already on the item. No longer drops (0.4): obtainable through the currency exchange, still functional."] =
		"Следующий Exalted Orb добавляет мод с тем же тегом, что у одного из уже имеющихся. Больше не выпадает (0.4): добывается через обмен валют, но работает.",
	["The next Exalted Orb biases the added modifier toward the catalyst's tag (exact bias undocumented)."] =
		"Следующий Exalted Orb смещает добавленный мод к тегу катализатора (точное смещение не документировано).",
	["The next Orb of Annulment removes two modifiers."] =
		"Следующий Orb of Annulment снимает два мода.",
	["The next Orb of Annulment removes only a prefix."] =
		"Следующий Orb of Annulment снимает только префикс.",
	["The next Orb of Annulment removes only a suffix."] =
		"Следующий Orb of Annulment снимает только суффикс.",
	["The next Regal Orb adds only a prefix."] =
		"Следующий Regal Orb добавляет только префикс.",
	["The next Regal Orb adds only a suffix."] =
		"Следующий Regal Orb добавляет только суффикс.",
	["The next Orb of Chance will not destroy the item."] =
		"Следующий Orb of Chance не уничтожит предмет.",
	["The next Orb of Chance is guaranteed to upgrade the item to a random Unique of the same class."] =
		"Следующий Orb of Chance гарантированно поднимет предмет до случайного уникального того же класса.",
	["The next Divine Orb rerolls implicit modifiers only."] =
		"Следующий Divine Orb перебрасывает только имплиситы.",
	["The desecration affects the prefix side."] =
		"Очернение затрагивает сторону префиксов.",
	["The desecration affects the suffix side."] =
		"Очернение затрагивает сторону суффиксов.",
	["The next Orb of Annulment removes only a desecrated modifier - the way to take back a bad desecration without losing the rest."] =
		"Следующий Orb of Annulment снимает только осквернённый мод — так отменяют неудачное очернение, не теряя остальное.",
	["The next Logbook adds special modifiers to revealed Grand Expedition areas."] =
		"Следующий Logbook добавляет особые моды в раскрытые области Grand Expedition.",
	["The next Logbook guarantees a Medved encounter in the revealed Biome."] =
		"Следующий Logbook гарантирует встречу с Medved в раскрытом Biome.",
	["The next Logbook guarantees a Vorana encounter in the revealed Biome."] =
		"Следующий Logbook гарантирует встречу с Vorana в раскрытом Biome.",
	["The next Logbook guarantees an Uhtred encounter in the revealed Biome."] =
		"Следующий Logbook гарантирует встречу с Uhtred в раскрытом Biome.",
	["The next Logbook guarantees an Olroth encounter in the revealed Biome."] =
		"Следующий Logbook гарантирует встречу с Olroth в раскрытом Biome.",
	["The next Divine Orb used on a Rare item sanctifies it: every modifier value is multiplied once by 0.78-1.22. The item cannot be crafted further."] =
		"Следующий Divine Orb на редком предмете освящает его: каждое значение мода один раз умножается на 0.78–1.22. Дальше предмет крафтить нельзя.",
	["The next Orb of Alchemy rolls the maximum number of prefixes."] =
		"Следующий Orb of Alchemy выдаёт максимальное число префиксов.",
	["The next Orb of Alchemy rolls the maximum number of suffixes."] =
		"Следующий Orb of Alchemy выдаёт максимальное число суффиксов.",
	["The next Perfect or Corrupted Essence removes only a prefix before applying its guaranteed modifier."] =
		"Следующая Perfect или Corrupted эссенция снимает только префикс, прежде чем поставить свой гарантированный мод.",
	["The next Perfect or Corrupted Essence removes only a suffix before applying its guaranteed modifier."] =
		"Следующая Perfect или Corrupted эссенция снимает только суффикс, прежде чем поставить свой гарантированный мод.",
	["The next Regal Orb adds a modifier sharing a TAG with one already on the item. No longer drops (0.5.0): obtainable through the currency exchange, still functional."] =
		"Следующий Regal Orb добавляет мод с тем же тегом, что у одного из уже имеющихся. Больше не выпадает (0.5.0): добывается через обмен валют, но работает.",
	["One reroll of the three modifiers offered when a desecrated modifier is revealed at the Well of Souls."] =
		"Один переброс трёх модов, которые предлагаются при раскрытии осквернённого мода у Колодца Душ.",
	["The next desecration of a weapon or jewellery guarantees a random Kurgal modifier."] =
		"Следующее очернение оружия или украшения гарантирует случайный мод Kurgal.",
	["The next desecration of a weapon or jewellery guarantees a random Amanamu modifier."] =
		"Следующее очернение оружия или украшения гарантирует случайный мод Amanamu.",
	["The next desecration of a weapon or jewellery guarantees a random Ulaman modifier."] =
		"Следующее очернение оружия или украшения гарантирует случайный мод Ulaman.",
	["Prevents 75% of the experience lost on death."] =
		"Сохраняет 75% опыта, который теряется при смерти.",
	["The next Shrine grants an additional effect."] =
		"Следующий Shrine даёт дополнительный эффект.",
	["The next item sold to a vendor is mispriced in your favour."] =
		"Следующий предмет, проданный торговцу, оценивается в вашу пользу.",
	["The next gamble has a 50% chance to cost no gold and not consume the omen."] =
		"У следующей азартной ставки 50% шанс не стоить золота и не потратить знамение.",
	["Refills flask and charm charges when you reach Low Life."] =
		"Восполняет заряды флаконов и оберегов, когда у вас Low Life.",
	["Restores life, mana and energy shield when you reach Low Life."] =
		"Восстанавливает здоровье, ману и энергетический щит, когда у вас Low Life.",
	["The next Rogue Exile is joined by an ally."] =
		"К следующему Rogue Exile присоединяется союзник.",
	["The next Strongbox can be opened a second time."] =
		"Следующий Strongbox можно открыть второй раз.",
	["The next Possessed monster releases its Azmeri Spirit. 0.5.5 reworded the description without changing the effect."] =
		"Следующий Possessed монстр выпускает свой Azmeri Spirit. В 0.5.5 описание переписали, эффект не изменился.",
	["The next Chaos Orb on a Waystone rolls modifiers that do not grant Monster Effectiveness."] =
		"Следующий Chaos Orb на Waystone выдаёт моды, не дающие Monster Effectiveness.",
	["The next Chaos Orb on a Waystone rolls modifiers that do not grant Monster Rarity."] =
		"Следующий Chaos Orb на Waystone выдаёт моды, не дающие Monster Rarity.",
	["The next Chaos Orb on a Waystone rolls modifiers that do not grant Pack Size."] =
		"Следующий Chaos Orb на Waystone выдаёт моды, не дающие Pack Size.",
	["The next Chaos Orb on a Waystone rolls modifiers that do not grant Item Rarity."] =
		"Следующий Chaos Orb на Waystone выдаёт моды, не дающие Item Rarity.",
	["The next desecration replaces every modifier on the item, creating up to six unrevealed modifiers and corrupting it. An explicit exception to the one-desecrated-modifier limit."] =
		"Следующее очернение заменяет все моды на предмете, создавая до шести нераскрытых, и оскверняет его. Явное исключение из правила «один осквернённый мод».",
	["Not obtainable since 0.5.0: the Recombinator was removed and existing copies were deleted. Kept here so the name is not mistaken for a live method."] =
		"Недоступно с 0.5.0: Recombinator убрали, существующие копии удалили. Оставлено здесь, чтобы название не приняли за рабочий способ.",
	["Vaal Orb always produces a change (no 'nothing happens' outcome). Removed from league drops; Standard-only copies remain."] =
		"Vaal Orb всегда даёт изменение (исхода «ничего не произошло» нет). Убран из дропа лиги; копии остались только в Standard.",
	["+20 to Modifier Tier Rating"] =
		"+20 к рейтингу тира модов",
	["Values of random modifiers are rolled an additional time, keeping the best"] =
		"Числа случайных модов перебрасываются ещё раз, берётся лучшее",
	["33% chance to be Fractured"] =
		"33 % шанс, что предмет выйдет расколотым",
	["The lowest level Modifier is removed"] =
		"Снимается мод с наименьшим уровнем",
	["Sockets and Links rolled +50 times, keeping the best"] =
		"Сокеты и связи перебрасываются +50 раз, берётся лучшее",
	["Parent of the three 'reduced <type> modifier chance' passives"] =
		"Родитель трёх пассивок «меньше модов <типа>»",
	["Parent of the 'increased <type> modifier chance' passives"] =
		"Родитель пассивок «больше модов <типа>»",
	["300% increased chance for Resistance Modifiers"] =
		"300 % к шансу модов сопротивления",
	["300% increased chance for Life Modifiers"] =
		"300 % к шансу модов здоровья",
	["25% chance to birth 3 extra currency, 3% for 10"] =
		"25 % шанс родить 3 дополнительные валюты, 3 % — десять",
	["Currency is rolled an additional time, keeping the rarest outcome"] =
		"Валюта перебрасывается ещё раз, берётся самый редкий исход",
	["2% chance for birthed currency to drop as a full stack"] =
		"2 % шанс, что рождённая валюта выпадет полным стеком",
	["25% extra currency; 100% increased chance for Graft Implants and Foulborn"] =
		"25 % дополнительной валюты; 100 % к шансу Graft Implants и Foulborn",
	["Uniques are rolled an additional time, keeping the rarest outcome - biases to T3/T4"] =
		"Уникальные предметы перебрасываются ещё раз, берётся самый редкий исход — со смещением к T3/T4",
	["Birthed uniques have 100% reduced chance to be Foulborn"] =
		"У рождённых уникальных предметов на 100 % меньше шанс быть Foulborn",
	["30% chance for an extra item; +30% chance to be Foulborn"] =
		"30 % шанс на дополнительный предмет; +30 % к шансу Foulborn",
	["Creates a copy of an item."] =
		"Создаёт копию предмета.",
	["Identifies an item."] =
		"Опознаёт предмет.",
	["Sets a Skill Gem to have 3 Support Gem Sockets."] =
		"Задаёт камню умения 3 сокета поддержки.",
	["Sets a Skill Gem to have 4 Support Gem Sockets."] =
		"Задаёт камню умения 4 сокета поддержки.",
	["Sets a Skill Gem to have 5 Support Gem Sockets."] =
		"Задаёт камню умения 5 сокетов поддержки.",
}

RulesRu.warnings = {
	["One-way. Equipment has FOUR equal outcomes, 25% each: a corruption implicit (it REPLACES the existing implicit), a socket turning non-white, the item becoming rare with SIX random affixes (the craft is gone), or no change. One attempt in four destroys the result."] =
		"Необратимо. У снаряжения ЧЕТЫРЕ равных исхода по 25 %: осквернённый имплисит (он ЗАМЕНЯЕТ существующий), сокет теряет белый цвет, предмет становится редким с ШЕСТЬЮ случайными аффиксами (крафт уничтожен) или ничего не меняется. Одна попытка из четырёх губит результат.",
}

--- The Russian text of an English ruleset sentence, or nil when it is not translated.
function RulesRu.text(english)
	if type(english) ~= "string" then
		return nil
	end
	return RulesRu.effects[english] or RulesRu.warnings[english]
end

return RulesRu
