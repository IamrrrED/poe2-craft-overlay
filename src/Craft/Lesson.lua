-- PoE2 Craft Overlay : Craft/Lesson.lua
-- The rule behind a step, in the words an experienced player would use to a beginner.
--
-- Why this is not part of the step's "why". The why answers "why THIS action on THIS item". A lesson answers
-- "what is the principle", so that the player stops needing the tool for the next item. Every guide in
-- docs/mentor-research.md teaches by stating the principle once and then showing it in action; the overlay
-- used to show only the action, which teaches nothing after the item is sold.
--
-- The lessons are written from the rules the engine itself enforces, so a lesson cannot claim something the
-- data does not do: nothing here is copied from a guide without being true of our own tables.
local Lesson = { }

-- Per currency in the ruleset. Keys match the ids in Data/league_0_5_5.lua.
Lesson.BY_CURRENCY = {
	transmutation = {
		title = "Первая валюта: предмет становится волшебным",
		titleEn = "The first currency: the item becomes Magic",
		text = "Transmutation даёт один случайный мод. Это самая дешёвая точка входа, поэтому на этом шаге "
			.. "надо быть придирчивым: плохой старт выбрасывают, а не спасают.",
		textEn = "Transmutation grants one random modifier. It is the cheapest entry point, so this step "
			.. "demands being picky: a bad start is thrown away, not rescued.",
	},
	augmentation = {
		title = "Второй мод — пока ещё дёшево",
		titleEn = "The second modifier - still cheap",
		text = "Augmentation добавляет второй мод волшебному предмету. Здесь заканчивается бесплатный перекат: "
			.. "после Regal предмет станет редким, и отбросить старт уже не выйдет.",
		textEn = "Augmentation adds a second modifier to a Magic item. The free reroll ends here: after "
			.. "Regal the item becomes Rare, and the start can no longer be thrown away.",
	},
	regal = {
		title = "Regal закрепляет то, что уже хорошо",
		titleEn = "Regal locks in what is already good",
		text = "Regal поднимает волшебный предмет до редкого и добавляет третий мод, сохраняя два прежних. Поэтому его "
			.. "применяют только когда ОБА мода волшебного предмета годятся: он фиксирует их, но третий придёт случайным.",
		textEn = "Regal raises Magic to Rare and adds a third modifier, keeping the two existing ones. So it "
			.. "is used only when BOTH Magic modifiers are good: it locks them in, but the third comes in random.",
	},
	alchemy = {
		title = "Alchemy — быстро, но без выбора",
		titleEn = "Alchemy - fast, but with no choice",
		text = "Alchemy сразу делает предмет редким с несколькими модами. Это быстрее, чем Transmute → Augment → Regal, "
			.. "но вы не выбираете, что получится: на предмет, который надо довести до лучшего, это плохой путь.",
		textEn = "Alchemy makes a Rare with several modifiers at once. That is faster than Transmute → Augment → Regal, "
			.. "but the player does not choose the outcome: on an item that must reach its best, this is a bad path.",
	},
	exalted = {
		title = "Exalted занимает пустой слот, ничего не ломая",
		titleEn = "Exalted fills an empty slot without breaking anything",
		text = "Если сторона не занята, Exalted только добавляет мод: существующие он не трогает. Поэтому "
			.. "это самый безопасный способ улучшить предмет — но добавляет он случайный мод, так что "
			.. "каждая сфера — отдельная ставка.",
		textEn = "If the side is open, Exalted only adds a modifier: it does not touch the existing ones. So "
			.. "it is the safest way to improve an item - but the modifier it adds is random, so "
			.. "every orb is a separate bet.",
	},
	greater_exalted = {
		title = "Greater — тот же эффект, выше минимальный тир",
		titleEn = "Greater - same effect, higher minimum tier",
		text = "Greater Exalted не даёт другого эффекта: он добавляет мод, но минимальный тир выше. Отсюда "
			.. "правило выбора: обычный орб — на эксперименты, Greater — на предмет, который вы точно оставите.",
		textEn = "Greater Exalted has no different effect: it adds a modifier, but the minimum tier is higher. Hence "
			.. "the choice rule: a plain orb for experiments, Greater for an item the player will certainly keep.",
	},
	perfect_exalted = {
		title = "Perfect — для предмета, который вы не замените",
		titleEn = "Perfect - for an item the player will not replace",
		text = "Perfect Exalted отсекает низкие тиры полностью. Это дорого, и это имеет смысл только на "
			.. "предмете, который останется у вас надолго; на промежуточном это переплата.",
		textEn = "Perfect Exalted cuts low tiers out entirely. It is expensive, and it makes sense only on "
			.. "an item that will stay with the player for long; on an intermediate one it is an overpay.",
	},
	chaos = {
		title = "Chaos убирает один мод и даёт другой",
		titleEn = "Chaos removes one modifier and gives another",
		text = "В PoE 2 Chaos не перекатывает весь предмет: он снимает ОДИН случайный мод и добавляет новый. "
			.. "Значит он может снять и хороший мод тоже — это шаг на предмете, который стоит спасать, а не "
			.. "на черновике.",
		textEn = "In PoE 2 Chaos does not reroll the whole item: it removes ONE random modifier and adds a new one. "
			.. "So it can remove a good modifier too - this is a step for an item worth saving, not "
			.. "for a draft.",
	},
	greater_chaos = {
		title = "Greater Chaos — то же, но новый мод выше тиром",
		titleEn = "Greater Chaos - the same, but the new modifier is a higher tier",
		text = "Он снимает один случайный мод, как обычный Chaos, но добавленный будет не ниже заданного тира. "
			.. "Оправдан там, где низкий тир обесценил бы предмет.",
		textEn = "It removes one random modifier, like a plain Chaos, but the added one is no lower than a set tier. "
			.. "Justified where a low tier would devalue the item.",
	},
	perfect_chaos = {
		title = "Perfect Chaos — замена без низких тиров",
		titleEn = "Perfect Chaos - a replacement with no low tiers",
		text = "Самый дорогой вариант замены: снимает один мод и даёт новый максимального тира. Это "
			.. "инструмент последней правки, а не способ искать нужный мод с нуля.",
		textEn = "The most expensive replacement: it removes one modifier and adds a new one at the maximum tier. It is "
			.. "a last-edit tool, not a way to hunt the needed modifier from scratch.",
	},
	annulment = {
		title = "Annulment снимает, но не выбирает",
		titleEn = "Annulment removes, but does not choose",
		text = "Annulment удаляет один случайный мод — с любой стороны. Сам по себе это лотерея: он может "
			.. "снять и то, что вы хотите сохранить. Точность даёт омен, а не орб.",
		textEn = "Annulment deletes one random modifier - on either side. On its own it is a lottery: it can "
			.. "remove what the player wants to keep. Precision comes from an omen, not from the orb.",
	},
	divine = {
		title = "Divine меняет числа, а не набор",
		titleEn = "Divine changes the numbers, not the set",
		text = "Divine перебрасывает значения модов, а набор остаётся тем же. Значит его место — когда моды "
			.. "уже нужные, а числа низкие; до этого он только тратит валюту.",
		textEn = "Divine rerolls the modifier values and the set stays the same. So its place is when the modifiers "
			.. "are already the right ones and the numbers are low; before that it only spends currency.",
	},
	vaal = {
		title = "Vaal — последним и один раз",
		titleEn = "Vaal - last, and only once",
		text = "Осквернение может дать мощный имплицит, а может испортить предмет, и после него крафт "
			.. "невозможен. Поэтому это делают последним шагом, когда результат уже устраивает.",
		textEn = "Desecration can grant a powerful implicit or ruin the item, and after it crafting is "
			.. "impossible. So it is done as the last step, when the result already satisfies the player.",
	},
	quality = {
		title = "Качество множит то, что уже есть",
		titleEn = "Quality multiplies what is already there",
		text = "Качество — отдельное число предмета: оно не занимает слот и умножает собственные "
			.. "характеристики. Поднимать его имеет смысл, когда моды уже стоят: оно умножает итог.",
		textEn = "Quality is a separate number on the item: it takes no slot and multiplies the item's own "
			.. "stats. Raising it makes sense once the modifiers are in place: it multiplies the result.",
	},
	whetstone = {
		title = "Качество оружия — это урон",
		titleEn = "Weapon quality is damage",
		text = "Blacksmith's Whetstone поднимает качество оружия, а качество множит физический урон базы. "
			.. "Это бесплатно по слотам и не может провалиться — поэтому такие вещи делают до дорогих орбов.",
		textEn = "Blacksmith's Whetstone raises weapon quality, and quality multiplies the base's physical damage. "
			.. "It costs no slots and cannot fail - so this is done before the expensive orbs.",
	},
	scrap = {
		title = "Качество брони — это защиты",
		titleEn = "Armour quality is defences",
		text = "Armourer's Scrap поднимает качество брони, а качество множит броню, уклонение и энергетический "
			.. "щит. Один процент качества — один процент защит, и это не занимает слот.",
		textEn = "Armourer's Scrap raises armour quality, and quality multiplies armour, evasion and energy "
			.. "shield. One percent of quality is one percent of defences, and it takes no slot.",
	},
	etcher = {
		title = "Etcher — качество посохов и жезлов",
		titleEn = "Etcher - quality for staves and wands",
		text = "Arcanist's Etcher поднимает качество кастерского оружия. Правило то же: качество не занимает "
			.. "слот и множит то, что уже есть, поэтому его добирают, а не откладывают.",
		textEn = "Arcanist's Etcher raises the quality of caster weapons. The rule is the same: quality takes no "
			.. "slot and multiplies what is already there, so it is topped up rather than postponed.",
	},
	bauble = {
		title = "Bauble — качество флакона",
		titleEn = "Bauble - flask quality",
		text = "Glassblower's Bauble поднимает качество флакона, а качество увеличивает объём восстановления. "
			.. "На флаконе качество часто важнее лишнего мода.",
		textEn = "Glassblower's Bauble raises flask quality, and quality increases the amount restored. "
			.. "On a flask quality is often more important than an extra modifier.",
	},
	prism = {
		title = "Prism — качество камня",
		titleEn = "Prism - gem quality",
		text = "Gemcutter's Prism поднимает качество камня умения. Это меняет сам камень, а не предмет, "
			.. "поэтому к крафту снаряжения это не относится.",
		textEn = "Gemcutter's Prism raises the quality of a skill gem. It changes the gem itself, not the item, "
			.. "so it does not belong to gear crafting.",
	},
	hinekora = {
		title = "Hinekora's Lock — посмотреть, прежде чем платить",
		titleEn = "Hinekora's Lock - look before paying",
		text = "Hinekora's Lock показывает, что сделает следующая валюта, и НЕ применяет её. Любое другое "
			.. "изменение предмета снимает эту возможность, поэтому лок ставят прямо перед дорогим сливом. "
			.. "Это единственный способ узнать результат заранее — и именно то, чего не хватает совету "
			.. "«просто попробуй».",
		textEn = "Hinekora's Lock shows what the next currency will do and does NOT apply it. Any other "
			.. "change to the item removes that possibility, so the lock goes in right before an expensive spend. "
			.. "It is the only way to learn the result in advance - and exactly what the advice "
			.. "\"just try it\" lacks.",
	},
}

-- Principles that are not about one currency, chosen by what the step is doing.
Lesson.BY_KIND = {
	add = {
		title = "Что делает добавление мода",
		titleEn = "What adding a modifier does",
		text = "Если сторона свободна, добавление только ставит новый мод и ничего не снимает. Проверять надо "
			.. "одно: сколько слотов открыто и с какой стороны.",
		textEn = "If the side is open, adding only places a new modifier and removes nothing. One thing has to be "
			.. "checked: how many slots are open and on which side.",
	},
	replace = {
		title = "Что делает замена",
		titleEn = "What a replacement does",
		text = "Замена снимает один мод и ставит другой. Она не выбирает, какой снять, если нет омена — "
			.. "поэтому на предмете с хорошими модами сначала считают риск, а потом платят.",
		textEn = "A replacement removes one modifier and places another. Without an omen it does not choose "
			.. "which one to remove - so on an item with good modifiers the risk is counted first and paid after.",
	},
	improve = {
		title = "Что делает улучшение",
		titleEn = "What an improvement does",
		text = "Улучшение не меняет набор модов: качество множит характеристики, Divine перебрасывает числа. "
			.. "Оно не может испортить предмет, поэтому его делают, когда набор уже собран.",
		textEn = "An improvement does not change the set of modifiers: quality multiplies the stats, Divine "
			.. "rerolls the numbers. It cannot ruin the item, so it is done once the set is already complete.",
	},
	free = {
		title = "Как освободить слот",
		titleEn = "How to free a slot",
		text = "Освободить сторону можно только тем, что снимает мод. Омен сужает выбор (конкретная сторона "
			.. "или самый слабый мод), но сам по себе ничего не снимает — он меняет следующую валюту.",
		textEn = "A side can only be freed by something that removes a modifier. An omen narrows the choice "
			.. "(a specific side or the weakest modifier), but removes nothing on its own - it changes the "
			.. "next currency.",
	},
	risky = {
		title = "Необратимые шаги",
		titleEn = "Irreversible steps",
		text = "Необратимый шаг — тот, после которого предмет больше нельзя менять. Их делают последними и "
			.. "только на предмете, который вы готовы потерять.",
		textEn = "An irreversible step is one after which the item can no longer be changed. Such steps are done last and "
			.. "only on an item the player is ready to lose.",
	},
}

-- English currency name -> id, so a step that only carries the display name ("Exalted Orb") can still find its
-- lesson. The step card is built from a resolved step in one branch and from a plain currency name in others,
-- and a lesson attached only in the first branch silently disappeared for the rest: the plan-completion and
-- quality paths showed an instruction with no principle behind it.
Lesson.NAME_TO_ID = {
	["Orb of Transmutation"] = "transmutation",
	["Orb of Augmentation"] = "augmentation",
	["Regal Orb"] = "regal",
	["Orb of Alchemy"] = "alchemy",
	["Exalted Orb"] = "exalted",
	["Greater Exalted Orb"] = "greater_exalted",
	["Perfect Exalted Orb"] = "perfect_exalted",
	["Chaos Orb"] = "chaos",
	["Greater Chaos Orb"] = "greater_chaos",
	["Perfect Chaos Orb"] = "perfect_chaos",
	["Orb of Annulment"] = "annulment",
	["Divine Orb"] = "divine",
	["Vaal Orb"] = "vaal",
	["Hinekora's Lock"] = "hinekora",
	-- The ruleset's own catch-all for quality; the specific items below each have their own lesson.
	["Quality currency"] = "quality",
	["Blacksmith's Whetstone"] = "whetstone",
	["Armourer's Scrap"] = "scrap",
	["Arcanist's Etcher"] = "etcher",
	["Glassblower's Bauble"] = "bauble",
	["Gemcutter's Prism"] = "prism",
}

--- The lesson for a currency, by its english display name.
-- @param name e.g. "Exalted Orb"
-- @param kind optional step kind, used as the fallback
-- @return { title, text } or nil
function Lesson.forName(name, kind)
	local id = Lesson.NAME_TO_ID[tostring(name or "")]
	local lesson = id and Lesson.BY_CURRENCY[id] or nil
	if lesson then
		return lesson
	end
	return Lesson.BY_KIND[tostring(kind or "")]
end

--- The lesson for a step, or nil when there is nothing to teach for it.
-- @param step resolved step table (has id, en, kind)
-- @return { title, text } or nil
function Lesson.reasonFor(step)
	if type(step) ~= "table" then
		return nil
	end
	local byCurrency = Lesson.BY_CURRENCY[tostring(step.id or "")]
	if byCurrency then
		return byCurrency
	end
	-- A step resolved from the ruleset carries the display name rather than the id in some branches.
	local byName = Lesson.forName(step.en or step.currency)
	if byName then
		return byName
	end
	local byKind = Lesson.BY_KIND[tostring(step.kind or "")]
	if byKind then
		return byKind
	end
	return nil
end

--- How many lessons exist, for the diagnostics line.
function Lesson.count()
	local total = 0
	for _ in pairs(Lesson.BY_CURRENCY) do total = total + 1 end
	for _ in pairs(Lesson.BY_KIND) do total = total + 1 end
	return total
end

return Lesson
