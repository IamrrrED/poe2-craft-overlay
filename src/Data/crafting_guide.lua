--- The crafting reference, as data rather than prose.
--
-- Every entry was taken from the open 0.5 / 0.5.5 sources (see SOURCES below) and written for a
-- beginner: what it does, when to use it, what it costs you, and what goes wrong. The overlay and
-- the panel both show these words, so the app never explains a mechanic differently in two places.
--
-- Language: the Russian text is the field itself and the English twin carries the "En" suffix
-- ("title" / "titleEn"). Mcp/api.lua picks one and drops the other, so the panel never sees a
-- half-translated card. A field without a twin is a failing assertion in Tests.test_language.
local Guide = { }

Guide.league = "0.5.5 Forbidden Rites"
Guide.SOURCES = {
	{ title = "PoE2 Crafting Guide 0.5 (currency, essences, omens)", url = "https://timesaver.gg/blog/poe2-0-5-crafting-guide" },
	{ title = "PoE2 Crafting Cost 0.5.4 (why it feels expensive)", url = "https://timesaver.gg/blog/poe2-crafting-cost-guide" },
	{ title = "PoE2 Crafting Codex (modifier groups, desecration, runeforging)", url = "https://domistae.github.io/poe2-leveling/poe2_crafting_codex.html" },
	{ title = "PoE2 0.5 Currency & Crafting Guide (omens, mistakes)", url = "https://gamemarket.gg/news/path-of-exile-2/poe-2-0-5-currency-crafting-guide-orbs-essences-omens-endgame" },
	{ title = "Runecrafting Guide (Runes of Aldur)", url = "https://pathofexile2.wiki.fextralife.com/Runecrafting_Guide" },
}

--- The two rules that decide everything in 0.5: they are the first thing a beginner must learn.
Guide.CAPS = {
	{
		id = "crafted",
		title = "Один созданный мод на предмет",
		titleEn = "One crafted modifier per item",
		text = "Эссенция, Perfect-эссенция и сплавы пишут в ОДИН общий слот. Две гарантированные "
			.. "эссенции на предмет поставить нельзя — старая техника с цепочкой эссенций больше не работает.",
		textEn = "An essence, a Perfect essence and an alloy all write into ONE shared slot. Two "
			.. "guaranteed essences cannot go on one item, so the old essence-chain technique no "
			.. "longer works.",
	},
	{
		id = "desecrated",
		title = "Один осквернённый мод на предмет",
		titleEn = "One desecrated modifier per item",
		text = "Осквернение занимает отдельный слот. Значит на предмете может быть два "
			.. "почти-гарантированных мода: один созданный и один осквернённый. Остальные аффиксы добираются риском.",
		textEn = "Desecration takes its own slot. So an item can carry two almost-guaranteed "
			.. "modifiers: one crafted and one desecrated. Every other affix has to be gambled for.",
	},
}

--- The whole craft in one sentence: the plan every beginner should follow.
Guide.MAIN_RULE = "Зафиксируй два мода, которые обязан иметь (эссенция + осквернение), "
	.. "потом дёшево добирай остальные аффиксы Exalted'ами под омэнами."
Guide.MAIN_RULE_EN = "Lock in the two modifiers the item must have (an essence plus a desecration), "
	.. "then fill the remaining affixes cheaply with Exalted Orbs under omens."

Guide.ORBS = {
	{ id = "transmutation", name = "Transmutation",
		does = "Обычный предмет → магический, добавляет 1 мод.",
		doesEn = "Normal item → magic, adds 1 modifier.",
		when = "Самый первый шаг на белой базе.",
		whenEn = "The very first step on a white base.",
		risk = "Нет.",
		riskEn = "None." },
	{ id = "augmentation", name = "Augmentation",
		does = "Добавляет второй мод магическому предмету.",
		doesEn = "Adds a second modifier to a magic item.",
		when = "Пока предмет магический — это самые дешёвые попытки.",
		whenEn = "While the item is magic, these are the cheapest attempts.",
		risk = "Нет.",
		riskEn = "None." },
	{ id = "regal", name = "Regal",
		does = "Магический → редкий, добавляет третий мод.",
		doesEn = "Magic → rare, adds a third modifier.",
		when = "Когда на магическом уже есть нужное.",
		whenEn = "When the magic item already has what you want.",
		risk = "Направление мода случайно.",
		riskEn = "The side of the modifier is random." },
	{ id = "alchemy", name = "Alchemy",
		does = "Обычный → редкий сразу с четырьмя модами.",
		doesEn = "Normal → rare straight away, with four modifiers.",
		when = "Редко: прыжок через магическую стадию теряет дешёвый отбор.",
		whenEn = "Rarely: skipping the magic stage loses the cheap sifting.",
		risk = "Четыре случайных мода сразу.",
		riskEn = "Four random modifiers at once." },
	{ id = "exalted", name = "Exalted",
		does = "Добавляет новый мод в СВОБОДНЫЙ слот редкого предмета.",
		doesEn = "Adds a new modifier into a FREE slot of a rare item.",
		when = "Основная рабочая валюта, когда якоря уже стоят.",
		whenEn = "The main working currency once the anchors are in place.",
		risk = "Может попасть не в ту сторону — нужен омэн.",
		riskEn = "It can land on the wrong side, so use an omen." },
	{ id = "chaos", name = "Chaos",
		does = "Убирает ОДИН случайный мод и добавляет новый (не полный переролл).",
		doesEn = "Removes ONE random modifier and adds a new one (not a full reroll).",
		when = "Чтобы заменить явно плохой мод.",
		whenEn = "To replace a clearly bad modifier.",
		risk = "Снимет хороший — нужен Omen of Whittling.",
		riskEn = "It may remove a good one, so use Omen of Whittling." },
	{ id = "annulment", name = "Annulment",
		does = "Убирает один случайный мод.",
		doesEn = "Removes one random modifier.",
		when = "Чтобы освободить место под нужный мод.",
		whenEn = "To free a slot for the modifier you want.",
		risk = "Снимет не тот — с Omen of Light снимает только осквернённый.",
		riskEn = "It may remove the wrong one; with Omen of Light it removes only the desecrated one." },
	{ id = "divine", name = "Divine",
		does = "Перебрасывает ЧИСЛА существующих модов в их диапазонах.",
		doesEn = "Rerolls the NUMBERS of the existing modifiers inside their ranges.",
		when = "Только когда список модов уже финальный.",
		whenEn = "Only once the modifier list is final.",
		risk = "Потратить на предмет, где список модов ещё не тот.",
		riskEn = "Spending it on an item whose modifier list is not the one you want yet." },
	{ id = "vaal", name = "Vaal",
		does = "Оскверняет предмет — сильно, случайно и НЕОБРАТИМО.",
		doesEn = "Corrupts the item: powerful, random and IRREVERSIBLE.",
		when = "Последним шагом и только если не боитесь потерять предмет.",
		whenEn = "As the last step, and only if losing the item does not frighten you.",
		risk = "Портит предмет навсегда.",
		riskEn = "It can ruin the item for good." },
	{ id = "chance", name = "Chance",
		does = "Обычный предмет → случайный уникальный, при неудаче база уничтожается.",
		doesEn = "Normal item → a random unique; on failure the base is destroyed.",
		when = "Охота за конкретным уникальным.",
		whenEn = "Hunting one specific unique.",
		risk = "Потеря базы.",
		riskEn = "Loss of the base." },
}

Guide.TIERS = {
	title = "Тиры валют: Lesser / Greater / Perfect",
	titleEn = "Currency tiers: Lesser / Greater / Perfect",
	text = "Transmutation, Augmentation, Regal, Exalted и Chaos бывают трёх тиров. "
		.. "Greater требует более высокий минимальный уровень мода, Perfect — ещё выше. "
		.. "На базе с низким уровнем предмета Perfect не даст топовый тир — это просто выброшенная валюта.",
	textEn = "Transmutation, Augmentation, Regal, Exalted and Chaos come in three tiers. Greater "
		.. "demands a higher minimum modifier level, Perfect a higher one still. On a low item level "
		.. "base Perfect cannot reach the top tier: that is currency thrown away.",
}

Guide.ESSENCE = {
	title = "Эссенции: единственный гарантированный мод",
	titleEn = "Essences: the one guaranteed modifier",
	text = "Эссенция навязывает конкретный мод. Тиры: Lesser → Greater → Grand → Perfect. "
		.. "Тратить её нужно на тот мод, без которого предмет бессмыслен. "
		.. "Важно: мод эссенции ограничен уровнем предмета — на низком уровне топовое число не выпадет.",
	textEn = "An essence forces one specific modifier. Tiers: Lesser → Greater → Grand → Perfect. "
		.. "Spend it on the modifier the item is pointless without. Note: the essence modifier is "
		.. "capped by item level, so a low level base cannot roll the top number.",
}

Guide.GROUPS = {
	title = "Группы модов: почему эссенция «не срабатывает»",
	titleEn = "Modifier groups: why an essence does nothing",
	text = "На предмете не может быть двух модов одной группы. Если эссенция даёт мод группы, "
		.. "которая уже занята, она не применится и НИЧЕГО не потратит — игра сообщит, "
		.. "что такой мод уже есть. Это не неудача, а правило.",
	textEn = "An item cannot carry two modifiers of one group. If the essence grants a modifier of a "
		.. "group that is already taken, it does not apply and spends NOTHING: the game says that "
		.. "modifier is already present. That is a rule, not a failure.",
}

Guide.DESECRATION = {
	title = "Осквернение: второй якорь",
	titleEn = "Desecration: the second anchor",
	text = "Abyssal Bone добавляет скрытый осквернённый мод, у Колодца Душ открываются ТРИ варианта, "
		.. "выбранный становится постоянным. Кости: Gnawed (только до 64-го уровня предмета), Preserved (любой), "
		.. "Ancient (любой, минимальный уровень мода ~40 — сразу отсекает мусорные тиры).",
	textEn = "Abyssal Bone adds a hidden desecrated modifier, the Well of Souls offers THREE options "
		.. "and the chosen one becomes permanent. Bones: Gnawed (item level 64 or lower only), "
		.. "Preserved (any), Ancient (any, minimum modifier level about 40, which skips the junk "
		.. "tiers at once).",
	slots = {
		{ id = "jawbone", name = "Jawbone", for_what = "оружие и колчаны", for_whatEn = "weapons and quivers" },
		{ id = "rib", name = "Rib", for_what = "броня", for_whatEn = "armour" },
		{ id = "collarbone", name = "Collarbone", for_what = "украшения", for_whatEn = "jewellery" },
		{ id = "cranium", name = "Cranium", for_what = "шлемы", for_whatEn = "helmets" },
		{ id = "vertebrae", name = "Vertebrae", for_what = "нательная броня", for_whatEn = "body armour" },
	},
}

Guide.OMENS = {
	title = "Омэны: то, что отличает крафт от рулетки",
	titleEn = "Omens: what separates crafting from roulette",
	entries = {
		{ id = "exaltation", name = "Sinistral / Dextral Exaltation",
			does = "Exalted добавит мод только в префикс или только в суффикс.",
			doesEn = "Exalted adds a modifier only to the prefix or only to the suffix side.",
			why = "Не даёт промахнуться в уже заполненную сторону.",
			whyEn = "Stops it landing on a side that is already full." },
		{ id = "necromancy", name = "Sinistral / Dextral Necromancy",
			does = "Осквернение покажет варианты только нужной стороны.",
			doesEn = "Desecration offers options from the wanted side only.",
			why = "Направляет второй якорь туда, где он нужен.",
			whyEn = "Points the second anchor where it is needed." },
		{ id = "light", name = "Omen of Light",
			does = "Annulment снимает только осквернённый мод.",
			doesEn = "Annulment removes only the desecrated modifier.",
			why = "Главный инструмент «повторить осквернение», не разрушая остальное.",
			whyEn = "The main tool for redoing a desecration without destroying the rest." },
		{ id = "echoes", name = "Omen of Abyssal Echoes",
			does = "Перебрасывает три варианта осквернения.",
			doesEn = "Rerolls the three desecration options.",
			why = "Ещё один шанс выбрать лучший из трёх.",
			whyEn = "One more chance to pick the best of three." },
		{ id = "whittling", name = "Omen of Whittling",
			does = "Chaos снимает мод с САМЫМ НИЗКИМ требованием к уровню.",
			doesEn = "Chaos removes the modifier with the LOWEST level requirement.",
			why = "Убирает худший мод, а не случайный.",
			whyEn = "Removes the worst modifier instead of a random one." },
		{ id = "sanctification", name = "Omen of Sanctification",
			does = "Vaal не может дать отрицательный результат.",
			doesEn = "Vaal cannot produce a negative outcome.",
			why = "Только для очень дорогих попыток.",
			whyEn = "For very expensive attempts only." },
	},
}

Guide.ALLOYS = {
	title = "Сплавы и рунная ковка",
	titleEn = "Alloys and runeforging",
	text = "13 сплавов (Imbued, Expansive, Mystic, Swift, Runic и другие) дают тематические созданные моды, "
		.. "но занимают ТОТ ЖЕ слот, что эссенция: это альтернатива якорю, а не дополнительный мод. "
		.. "Рунная ковка тратит Verisium и умеет поднимать базу низкоуровневых уникальных предметов до эндгеймовой "
		.. "и добавлять Runic Ward.",
	textEn = "The 13 alloys (Imbued, Expansive, Mystic, Swift, Runic and others) grant thematic crafted "
		.. "modifiers but take the SAME slot as an essence: they are an alternative anchor, not an extra "
		.. "modifier. Runeforging spends Verisium and can raise the base of a low level unique to an "
		.. "endgame one and add Runic Ward.",
}

--- The beginner mistakes worth catching before they cost currency.
Guide.MISTAKES = {
	{ id = "essence_used_group",
		text = "Эссенция в уже занятую группу модов: не сработает и потратит эссенцию зря (если игра не вернула её).",
		textEn = "An essence aimed at a modifier group that is already taken: it does nothing and wastes "
			.. "the essence (unless the game hands it back)." },
	{ id = "essence_wrong_stat",
		text = "Потратить единственный созданный слот на мод, который и так катится обычной валютой.",
		textEn = "Spending the single crafted slot on a modifier that ordinary currency rolls anyway." },
	{ id = "exalt_no_omen",
		text = "Бросать Exalted без омэна на предмет, где сторона уже заполнена: промах впустую.",
		textEn = "Throwing Exalted Orbs without an omen at an item whose side is already full: a miss for nothing." },
	{ id = "perfect_low_ilvl",
		text = "Тратить Perfect-валюту на базу с низким уровнем предмета: топовый тир там невозможен.",
		textEn = "Spending Perfect currency on a low item level base: the top tier is impossible there." },
	{ id = "divine_too_early",
		text = "Divine до того, как список модов финальный: перебрасываются только числа.",
		textEn = "Divine before the modifier list is final: only the numbers are rerolled." },
	{ id = "vaal_early",
		text = "Vaal до завершения крафта: осквернение необратимо.",
		textEn = "Vaal before the craft is finished: corruption is irreversible." },
	{ id = "desecrate_no_omen",
		text = "Осквернять без омэна нужной стороны: варианты придут не в тот префикс или суффикс.",
		textEn = "Desecrating without the omen for the wanted side: the options land on the wrong prefix or suffix." },
	{ id = "low_ilvl_base",
		text = "Крафтить на базе с низким уровнем предмета: потолок модов ниже, деньги уходят впустую.",
		textEn = "Crafting on a low item level base: the modifier ceiling is lower and the money is wasted." },
}

--- The loop the assistant follows: one step, then look at the item again.
Guide.LOOP = {
	"1. Скопируйте предмет в игре (Ctrl+C) и нажмите Ctrl+Q — помощник посмотрит на предмет.",
	"2. Сделайте ОДИН шаг, который он предложил, прямо в игре.",
	"3. Скопируйте предмет снова и нажмите Ctrl+Q — помощник увидит результат шага.",
	"4. Повторяйте: следующий шаг зависит от того, что выпало, а не от плана, составленного заранее.",
}
Guide.LOOP_EN = {
	"1. Copy the item in game (Ctrl+C) and press Ctrl+Q: the helper takes a look at it.",
	"2. Take the ONE step it suggested, right there in the game.",
	"3. Copy the item again and press Ctrl+Q: the helper sees the result of the step.",
	"4. Repeat: the next step depends on what rolled, not on a plan made in advance.",
}

return Guide
