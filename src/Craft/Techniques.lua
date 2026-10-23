-- PoE2 Craft Overlay : Craft/Techniques.lua
-- The advanced, state-dependent methods that an experienced crafter knows and a rule table cannot derive.
--
-- Where a Lesson states a principle and a rule decides what applies, a Technique is a SEQUENCE with a
-- precondition: "when the item looks like this, do these steps in this order, and here is why each one is
-- safe". They come from reading the guides themselves (docs/mentor-research.md): the Homogenising tag hunt,
-- the jewel suffix trick, the desecration reroll wash.
--
-- Two rules for this file, both learned the hard way:
--   1. A technique is only offered when its precondition is verifiably true of the item. Offering it in the
--      wrong state is worse than not offering it, because the player spends currency following it.
--   2. Every step says what it does to the item and what can go wrong. A sequence without that is trivia.
local Techniques = { }

--- The list. `when` is checked against the parsed item; `steps` are shown in order.
--
-- Every technique carries a `leagueNote`: which patch it came from, what was checked, and where it stands in
-- 0.5.5. A guide is not a licence to assume its answer is current - the two guides these come from are from
-- different eras (one from 2025, one from 0.5.1/0.5.2), and a beginner cannot tell that from the video. The
-- note is shown with the technique so the player sees the age of the claim, not just the claim.
Techniques.LIST = {
	{
		id = "jewel_suffix_cap",
		title = "Ювелирка: переполненный суффикс делает префикс безопасным",
		titleEn = "Jewels: an overfull suffix side makes the prefix safe",
		-- Precondition, stated in the item's own terms. A Rare jewel holds 2/2; Potent Liquid of Contempt adds
		-- one slot to a random side and the item then reads "+1 Suffix Modifier allowed". That modifier is
		-- ITSELF one of the suffix affixes - it is what makes the side five affixes instead of four - so the
		-- side is full when the real suffixes plus that bought slot reach the raised cap. While it is full,
		-- rebuilding a prefix cannot destroy the suffixes, which is the whole technique.
		when = function(item)
			if tostring(item.itemClass or ""):lower() ~= "jewels" then
				return false
			end
			if tostring(item.rarity or ""):upper() ~= "RARE" then
				return false
			end
			local caps = item.affixCaps
			if type(caps) ~= "table" or type(caps.base) ~= "table" then
				return false
			end
			local bought = (tonumber(caps.suffixes) or 0) - (tonumber(caps.base.suffixes) or 0)
			if bought <= 0 then
				-- Without the bought slot a third suffix cannot exist at all, so this is not the trick state.
				return false
			end
			local suffixes = tonumber(item.suffixCount) or 0
			return (suffixes + bought) >= (tonumber(caps.suffixes) or 0)
		end,
		why = "Обычный редкий ювелир держит 2 префикса и 2 суффикса. Третий суффикс появляется только после "
			.. "Potent Liquid of Contempt (50/50, какая сторона получит слот) — и тогда суффиксов 3 при "
			.. "лимите 3. Сторона заполнена, поэтому Chaos не может тронуть суффиксы и уходит в префикс: "
			.. "префиксы можно перебирать, не рискуя собранным.",
		whyEn = "A normal rare jewel holds 2 prefixes and 2 suffixes. The third suffix appears only after "
			.. "Potent Liquid of Contempt (50/50 which side gets the slot) - and then there are 3 suffixes "
			.. "against a limit of 3. The side is full, so Chaos cannot touch the suffixes and goes into the "
			.. "prefix: the prefixes can be rerolled without risking what is already built.",
		steps = {
			{ action = "Potent Liquid of Contempt", what = "даёт +1 слот случайной стороне",
				whatEn = "grants +1 slot to a random side",
				risk = "если слот уйдёт в префикс — трюк не соберётся, ювелир придётся перекатывать",
				riskEn = "if the slot lands on the prefix, the trick does not assemble and the jewel has to "
					.. "be rerolled" },
			{ action = "Заполнить три суффикса", actionEn = "Fill all three suffixes",
				what = "нужные моды на стороне суффиксов",
				whatEn = "the wanted modifiers on the suffix side",
				risk = "пока суффиксов меньше трёх, Chaos ещё может попасть в них",
				riskEn = "while there are fewer than three suffixes, Chaos can still land on them" },
			{ action = "Exalted Orb", what = "заполняет свободный префикс",
				whatEn = "fills the open prefix",
				risk = "случайный префикс",
				riskEn = "a random prefix" },
			{ action = "Chaos Orb (повторять)", actionEn = "Chaos Orb (repeat)",
				what = "перебирает ТОЛЬКО префиксы",
				whatEn = "rerolls ONLY the prefixes",
				risk = "не снимайте «+1 допустимый суффикс»: без него суффиксы снова станут уязвимы",
				riskEn = "do not remove +1 Suffix allowed: without it the suffixes become vulnerable again" },
		},
		source = "Fubgun, «How to Craft The Best Jewels (5 mods)», 221 тыс. просмотров — расшифровка; "
			.. "лимиты ювелирки сверены с источниками 0.5.x",
		sourceEn = "Fubgun, 'How to Craft The Best Jewels (5 mods)', 221k views - transcript; "
			.. "the jewel caps were checked against 0.5.x sources",
		leagueNote = "Видео от 2026-06-13, эпоха 0.5.1–0.5.2. Механика появилась в 0.5.0 и не менялась "
			.. "патчами 0.5.3–0.5.5 (в заметках 0.5.5 нет изменений ювелирки). Лимиты 2/2 и «+1 слот» "
			.. "сверены отдельно по источникам 0.5.x.",
		leagueNoteEn = "Video from 2026-06-13, the 0.5.1-0.5.2 era. The mechanic appeared in 0.5.0 and was "
			.. "not changed by patches 0.5.3-0.5.5 (the 0.5.5 notes contain no jewel changes). The 2/2 "
			.. "limits and the '+1 slot' were checked separately against 0.5.x sources.",
	},
	{
		id = "jewel_slot_upgrade",
		title = "Ювелирка: сначала +1 слот, потом остальное",
		titleEn = "Jewels: the +1 slot first, the rest after",
		when = function(item)
			return tostring(item.itemClass or ""):lower() == "jewels"
		end,
		why = "Potent Liquid of Contempt даёт +1 слот случайной стороны — это 50/50. Если попадёт в сторону, "
			.. "которая не нужна, вся дальнейшая работа теряет смысл, поэтому слот добавляют РАНЬШЕ, чем "
			.. "доводят остальное: иначе удачный префикс может быть вытеснен.",
		whyEn = "Potent Liquid of Contempt grants +1 slot on a random side - that is 50/50. If it lands on a "
			.. "side that is not wanted, all the further work loses its point, so the slot is added BEFORE "
			.. "the rest is finished: otherwise a good prefix can be pushed out.",
		steps = {
			{ action = "Fracturing Orb", what = "закрепляет ключевой мод (например, крит-урон 20 %)",
				whatEn = "locks the key modifier (for example 20% crit damage)",
				risk = "1 из 4 на нужный мод; зафракченный мод уже не убрать",
				riskEn = "1 in 4 for the wanted modifier; a fractured modifier can no longer be removed" },
			{ action = "Chaos Orb", what = "добрать второй суффикс",
				whatEn = "add the second suffix",
				risk = "зафракченный мод под замену не попадает",
				riskEn = "the fractured modifier cannot be the one replaced" },
			{ action = "Exalted Orb ×2", what = "заполнить префиксы",
				whatEn = "fill the prefixes",
				risk = "содержимое префиксов пока не важно",
				riskEn = "what the prefixes hold does not matter yet" },
			{ action = "Potent Liquid of Contempt", what = "+1 слот случайной стороны",
				whatEn = "+1 slot on a random side",
				risk = "попадёт не туда — перекатывать Chaos заново",
				riskEn = "if it lands on the wrong side, the Chaos rolls start over" },
		},
		source = "Fubgun, «How to Craft The Best Jewels (5 mods)» — расшифровка",
		sourceEn = "Fubgun, 'How to Craft The Best Jewels (5 mods)' - transcript",
		leagueNote = "Видео от 2026-06-13 (0.5.1–0.5.2). Fracturing Orb и Liquid Emotions есть в своде "
			.. "0.5.5; порядок «слот раньше остального» — это совет автора, а не правило игры.",
		leagueNoteEn = "Video from 2026-06-13 (0.5.1-0.5.2). Fracturing Orb and Liquid Emotions are in the "
			.. "0.5.5 ruleset; the order 'slot before the rest' is the author's advice, not a rule of the game.",
	},
	{
		id = "preview_before_slam",
		title = "Проверить слив заранее: Hinekora's Lock",
		titleEn = "Check the slam in advance: Hinekora's Lock",
		when = function(item)
			-- Any Rare that still has room can be previewed before the next currency is spent.
			if tostring(item.rarity or ""):upper() ~= "RARE" then
				return false
			end
			if item.flags and (item.flags.corrupted or item.flags.sanctified) then
				return false
			end
			-- Room is judged against the item's own caps, not against a fixed 3/3: bases such as the Absent
			-- Amulet cap lower, and a full item has nothing left to preview.
			local caps = item.affixCaps
			local prefixes = tonumber(item.prefixCount) or 0
			local suffixes = tonumber(item.suffixCount) or 0
			if type(caps) == "table" then
				return prefixes < (tonumber(caps.prefixes) or 3)
					or suffixes < (tonumber(caps.suffixes) or 3)
			end
			return (tonumber(item.openPrefixes) or 0) + (tonumber(item.openSuffixes) or 0) > 0
		end,
		why = "Hinekora's Lock показывает, что сделает следующая валюта, и не применяет её. Любое другое "
			.. "изменение предмета снимает возможность, поэтому лок ставят прямо перед дорогим шагом. Это "
			.. "единственный способ не платить за провал вслепую — остальные советы «просто попробуй» "
			.. "проверить результат заранее не дают.",
		whyEn = "Hinekora's Lock shows what the next currency will do and does not apply it. Any other change "
			.. "to the item removes the ability, so the lock is used right before an expensive step. It is "
			.. "the only way not to pay for a blind failure - the other 'just try it' advice gives no way to "
			.. "check the result in advance.",
		steps = {
			{ action = "Hinekora's Lock", what = "включает предпросмотр следующей валюты",
				whatEn = "enables a preview of the next currency",
				risk = "стоит дорого; любое другое изменение предмета отменяет предпросмотр",
				riskEn = "expensive; any other change to the item cancels the preview" },
			{ action = "Применить валюту", actionEn = "Apply the currency",
				what = "результат уже известен до применения",
				whatEn = "the result is known before it is applied",
				risk = "отменить сам бросок нельзя — только решить, тратить ли",
				riskEn = "the roll itself cannot be cancelled - only the decision whether to spend" },
		},
		source = "poe2db, страница Currency (0.5.5): «foresee the result of the next Currency item»",
		sourceEn = "poe2db, the Currency page (0.5.5): 'foresee the result of the next Currency item'",
		leagueNote = "Валюта есть в списке валютной вкладки poe2db для 0.5.5. В наших данных её не было — "
			.. "добавлена этим аудитом вместе с уроком.",
		leagueNoteEn = "The currency is in the list on the poe2db currency tab for 0.5.5. It was missing from "
			.. "our data - added by this audit together with the lesson.",
	},
	{
		id = "homogenising_tag_hunt",
		title = "Охота на тег: омен Homogenising + Exalted",
		titleEn = "Tag hunt: the Homogenising omen + Exalted",
		-- Precondition: a RARE with an open side and exactly one modifier family on it.
		when = function(item, families)
			if tostring(item.rarity or ""):upper() ~= "RARE" then
				return false
			end
			return (tonumber(item.openPrefixes) or 0) > 0 or (tonumber(item.openSuffixes) or 0) > 0
		end,
		why = "Омен Homogenising заставляет Exalted добавить мод той же группы, что уже есть. Пока на "
			.. "выбранной стороне достижима одна группа, это фактически гарантированный мод. Важно: бонус "
			.. "учитывает группы ОБЕИХ сторон, поэтому сначала доводят одну сторону.",
		whyEn = "The Homogenising omen forces Exalted to add a modifier of the same group as one already on "
			.. "the item. While only one group is reachable on the chosen side, that is effectively a "
			.. "guaranteed modifier. Note: the bonus counts the groups of BOTH sides, so one side is finished "
			.. "first.",
		steps = {
			{ action = "Довести первую сторону", actionEn = "Finish the first side",
				what = "суффиксы или префиксы — но целиком",
				whatEn = "suffixes or prefixes - but in full",
				risk = "недоделанная сторона добавит свои теги в пул",
				riskEn = "an unfinished side adds its tags to the pool" },
			{ action = "Omen of Homogenising Exaltation + Exalted", what = "мод нужной группы",
				whatEn = "a modifier of the wanted group",
				risk = "если группа не одна — не гарантия",
				riskEn = "if the group is not the only one, it is not guaranteed" },
			{ action = "Повторять по слотам", actionEn = "Repeat per slot",
				what = "второй и третий мод той же группы",
				whatEn = "the second and the third modifier of the same group",
				risk = "чем больше групп на предмете, тем шире пул",
				riskEn = "the more groups on the item, the wider the pool" },
		},
		source = "GhazzyTV, «How to GUARANTEE Modifiers», 87 тыс. просмотров — расшифровка",
		sourceEn = "GhazzyTV, 'How to GUARANTEE Modifiers', 87k views - transcript",
		-- This one is the oldest and needed the most caution: the guide is a year older than the league.
		leagueNote = "Видео от 2025-09-02, то есть эпоха 0.2/0.3 — заметно старше лиги 0.5.5. Что проверено: "
			.. "сам омен в 0.5.5 есть и работает (с 0.4.0 у него отключён ДРОП, копии действуют; продаётся "
			.. "на Currency Exchange). Чего в видео НЕТ: с 0.4 омен нельзя нафармить, поэтому его цена в "
			.. "свежей лиге другая, а конкретные уровни предмета и эссенции из ролика — того патча. Механику стоит "
			.. "считать рабочей, экономику — устаревшей.",
		leagueNoteEn = "Video from 2025-09-02, that is the 0.2/0.3 era - noticeably older than league 0.5.5. "
			.. "What was checked: the omen itself exists and works in 0.5.5 (its DROP has been disabled since "
			.. "0.4.0, copies still work; it is sold on the Currency Exchange). What the video does NOT have: "
			.. "since 0.4 the omen cannot be farmed, so its price in a fresh league is different, and the "
			.. "specific ilvl and essences from the clip belong to that patch. Treat the mechanic as working, "
			.. "the economy as outdated.",
	},
	{
		id = "desecration_wash",
		title = "Очернение по фрактуре: одна сторона ровно из двух модов",
		titleEn = "Desecration over a fracture: one side of exactly two modifiers",
		when = function(item)
			if tostring(item.rarity or ""):upper() ~= "RARE" then
				return false
			end
			-- The loop needs a fractured modifier: it holds one slot so the other can be overwritten forever.
			-- The flag is taken from the copied text, because the game announces it in the annotation line
			-- above the modifier ("{ Fractured Prefix Modifier ... }" / "Расколотое") and the parser does not
			-- carry it as a field yet.
			local raw = tostring(item.raw or ""):lower()
			local fractured = raw:find("fractured", 1, true) ~= nil
				or raw:find("расколото", 1, true) ~= nil
			if not fractured then
				return false
			end
			-- And the technique only makes sense while a side is short enough to be rewritten.
			local prefixes = tonumber(item.prefixCount) or 0
			local suffixes = tonumber(item.suffixCount) or 0
			return math.min(prefixes, suffixes) >= 1
		end,
		why = "Если на одной стороне ровно два мода и один из них зафракчен, очернение снова и снова "
			.. "переписывает второй слот, а зафракченный не трогает. Это и есть способ «перебирать» "
			.. "очернённый мод без Omen of Light на каждую попытку: как только модов на стороне три, "
			.. "очернение может задеть уже собранное.",
		whyEn = "If one side holds exactly two modifiers and one of them is fractured, desecration rewrites "
			.. "the second slot again and again and does not touch the fractured one. That is the way to "
			.. "reroll a desecrated modifier without Omen of Light on every attempt: as soon as the side "
			.. "holds three modifiers, desecration can hit what is already built.",
		steps = {
			{ action = "Держать сторону ровно в два мода",
				actionEn = "Keep the side at exactly two modifiers",
				what = "зафракченный + один перезаписываемый",
				whatEn = "the fractured one + one that can be overwritten",
				risk = "третий мод на стороне — и очернение начнёт задевать готовое",
				riskEn = "a third modifier on the side - and desecration starts hitting the finished part" },
			{ action = "Кость + Well of Souls", actionEn = "Bone + Well of Souls",
				what = "очернить открытую сторону и раскрыть мод",
				whatEn = "desecrate the open side and reveal the modifier",
				risk = "слот очернения только один",
				riskEn = "there is only one desecration slot" },
			{ action = "Omen of Abyssal Echoes", what = "перекатить предложенную тройку, если промах",
				whatEn = "reroll the three offered options on a miss",
				risk = "тратит ещё одну кость",
				riskEn = "spends one more bone" },
			{ action = "Повторять очернение", actionEn = "Repeat the desecration",
				what = "мод перебирается без снятия предыдущего",
				whatEn = "the modifier is rerolled without removing the previous one",
				risk = "не снимайте фрактуру: без неё слот снова станет случайным",
				riskEn = "do not remove the fracture: without it the slot becomes random again" },
		},
		source = "гайды по очернению 0.5.x (ezg, poe2craft.com) и практика 0.5.5; модель раскрытия «3 из пула» "
			.. "уже в движке",
		sourceEn = "0.5.x desecration guides (ezg, poe2craft.com) and 0.5.5 practice; the '3 out of the pool' "
			.. "reveal model is already in the engine",
		leagueNote = "Актуально для 0.5.5: очернение и все его омены в своде есть. Отличие от старых роликов: "
			.. "они снимали очернение через Omen of Light каждый раз, что дорого — при фрактуре это не нужно.",
		leagueNoteEn = "Current for 0.5.5: desecration and all its omens are in the ruleset. The difference "
			.. "from the old videos: they removed the desecration with Omen of Light every time, which is "
			.. "expensive - with a fracture that is not needed.",
	},
}

--- Techniques that apply to this item.
-- @param item parsed item
-- @return list of { id, title, why, steps, source }
function Techniques.forItem(item)
	local out = { }
	for _, technique in ipairs(Techniques.LIST) do
		local ok, applies = pcall(technique.when, item)
		if ok and applies then
			out[#out + 1] = {
				id = technique.id,
				title = technique.title,
				titleEn = technique.titleEn,
				why = technique.why,
				whyEn = technique.whyEn,
				steps = technique.steps,
				source = technique.source,
				sourceEn = technique.sourceEn,
				-- The age of the claim travels with it: a beginner cannot tell from a video which patch it is.
				leagueNote = technique.leagueNote,
				leagueNoteEn = technique.leagueNoteEn,
			}
		end
	end
	return out
end

--- One technique by id, for the reference list and tests.
function Techniques.byId(id)
	for _, technique in ipairs(Techniques.LIST) do
		if technique.id == id then
			return technique
		end
	end
	return nil
end

return Techniques
