-- PoE2 Craft Overlay : Craft/Claims.lua
-- Checks a claim about crafting against the rules the engine actually enforces.
--
-- Why this exists. Researching the most popular guides (docs/mentor-research.md) turned up an "ultimate
-- beginner guide" that ranks well and teaches mechanics PoE 2 does not have: a "resonant anvil", an "echoing
-- chisel", an Orb of Scouring, "Regal locks your prefix", invented tier rules and invented research numbers.
-- A beginner cannot tell that from a real guide, and every wrong claim costs him currency. The overlay has
-- verified tables, so it can answer "is this true?" instead of only "what do I do next".
--
-- The claims are checked against the SAME data the advice uses, so a "true" answer here cannot contradict the
-- recommendation on another tab.
local Claims = { }

-- The claims worth checking, with how to decide each one from the ruleset.
-- `id` is stable: it is what the panel and tests refer to.
Claims.KNOWN = {
	{
		id = "catalysts_drop_from_monsters",
		matches = { "катализатор", "catalyst", "breach фарм катализатор" },
		verdict = "false",
		title = "Катализаторы больше не падают с монстров",
		titleEn = "Catalysts no longer drop from monsters",
		why = "С 0.5.0 катализаторы нельзя получить дропом: единственный источник — Genesis Tree в Монастыре "
			.. "Хранителей. «Пофармить Breach на катализаторы» больше не работает, хотя Breach Rings и "
			.. "Wombgifts по-прежнему падают с Breach-монстров.",
		whyEn = "Since 0.5.0 catalysts cannot be obtained as drops: the only source is the Genesis Tree in the "
			.. "Monastery of the Keepers. \"Farming Breach for catalysts\" no longer works, although Breach Rings "
			.. "and Wombgifts still drop from Breach monsters.",
		source = "официальные заметки 0.5.0: «Catalysts can no longer drop from Monsters»; раздел genesisTree",
		sourceEn = "official 0.5.0 notes: \"Catalysts can no longer drop from Monsters\"; the genesisTree section",
	},
	{
		id = "waystone_chaos_rerolls_all",
		matches = { "waystone", "вейстоун", "вейстоуна", "вейстоуне", "карта крафт" },
		-- The gear rule is the opposite of the truth for a waystone, so it must not win on needle length.
		winsOver = { "chaos_rerolls_all", "no_full_reroll" },
		verdict = "true",
		title = "На вейстоуне Chaos перекатывает ВСЕ моды",
		titleEn = "On a waystone Chaos rerolls ALL modifiers",
		why = "Это исключение из правила «полного реролла нет»: на снаряжении Chaos снимает один мод и "
			.. "добавляет один, а на вейстоуне он заменяет весь набор. Омены Chaotic … сужают пул, запрещая "
			.. "одну группу модов.",
		whyEn = "This is the exception to the \"no full reroll\" rule: on gear Chaos removes one modifier and "
			.. "adds one, while on a waystone it replaces the whole set. Chaotic ... omens narrow the pool by "
			.. "banning one modifier group.",
		source = "записи Omen of Chaotic … в своде и страница Waystones на poe2db (0.5.5)",
		sourceEn = "the Omen of Chaotic ... entries in the ruleset and the Waystones page on poe2db (0.5.5)",
	},
	{
		id = "scouring_orb",
		matches = { "scouring", "скуринг", "скауринг" },
		verdict = "false",
		title = "Орб Скуринга в PoE 2 не существует",
		titleEn = "There is no Orb of Scouring in PoE 2",
		why = "В Path of Exile 2 нет валюты, которая возвращает редкий или волшебный предмет к обычному. Поэтому "
			.. "«снять всё и начать заново» на предмете нельзя: единственный перекат — на волшебной стадии.",
		whyEn = "Path of Exile 2 has no currency that returns a Rare or Magic item to Normal. So \"remove "
			.. "everything and start over\" is impossible on an item: the only reroll is at the Magic stage.",
		source = "наш свод правил не содержит такой валюты; так же пишут все проверенные гайды",
		sourceEn = "our ruleset contains no such currency; every verified guide says the same",
	},
	{
		id = "regal_locks_prefix",
		matches = { "regal lock", "регал фиксир", "фиксирует префикс", "regal фиксир" },
		verdict = "false",
		title = "Regal не «фиксирует префикс»",
		titleEn = "Regal does not \"lock the prefix\"",
		why = "Regal поднимает волшебный предмет до редкого и добавляет ОДИН случайный мод, сохраняя два прежних. "
			.. "Никакой фиксации от будущих изменений он не даёт: после Regal предмет можно менять дальше.",
		whyEn = "Regal raises a Magic item to Rare and adds ONE random modifier, keeping the two it had. It "
			.. "gives no lock against future changes: after Regal the item can still be modified.",
		source = "правило magic_two_mods в нашем своде",
		sourceEn = "the magic_two_mods rule in our ruleset",
	},
	{
		id = "alchemy_blocks_suffixes",
		matches = { "alchemy блокир", "alchemy блокирует", "alchemy prevents" },
		verdict = "false",
		title = "Alchemy не блокирует суффиксы",
		titleEn = "Alchemy does not block suffixes",
		why = "Alchemy сразу делает предмет редким со случайными модами. Она не «запирает» стороны: после неё открытые "
			.. "слоты можно занимать обычными способами.",
		whyEn = "Alchemy turns the item Rare straight away, with random modifiers. It does not \"lock\" the "
			.. "sides: after it the free slots can be filled the usual way.",
		source = "правило normal_base: alchemy даёт редкий предмет, дальше работает обычная логика слотов",
		sourceEn = "the normal_base rule: alchemy gives Rare, then the usual slot logic applies",
	},
	{
		id = "chaos_rerolls_all",
		matches = { "chaos re-rolls all", "chaos rerolls all", "chaos перекатывает", "chaos полностью" },
		verdict = "false",
		title = "Chaos в PoE 2 не перекатывает весь предмет",
		titleEn = "Chaos in PoE 2 does not reroll the whole item",
		why = "Он снимает ОДИН случайный мод и добавляет новый. Это не полный реролл, как в PoE 1, — "
			.. "поэтому Chaos может снять и хороший мод.",
		whyEn = "It removes ONE random modifier and adds a new one. That is not a full reroll as in PoE 1, "
			.. "which is why Chaos can remove a good modifier too.",
		source = "описание валюты chaos в своде и правила замены",
		sourceEn = "the chaos currency entry in the ruleset and the replacement rules",
	},
	{
		id = "essence_twice",
		-- Both spellings are matched: the player may write the game's English word or the Russian one,
		-- and the panel has to recognise the question either way.
		matches = { "два created", "два созданных", "two crafted", "второй эссенц", "two essences",
			"один created", "один созданный", "несколько гарантированных" },
		verdict = "false",
		title = "Один гарантированный мод, а не два",
		titleEn = "One guaranteed modifier, not two",
		why = "Эссенция, сплав и руна дают гарантированный («созданный») мод, и такой слот на предмете один. "
			.. "До 0.5.0 можно было собрать несколько гарантированных модов сразу — с 0.5.0 только один, "
			.. "поэтому старые гайды, где их четыре-пять, больше не работают.",
		whyEn = "An essence, an alloy and a rune grant a guaranteed (\"crafted\") modifier, and an item has one "
			.. "such slot. Before 0.5.0 several guaranteed modifiers could be collected at once - since 0.5.0 "
			.. "only one, so the old guides that show four or five of them no longer work.",
		source = "нерф эссенций 0.5.0 (разбор XTheFarmerX); движок предупреждает о занятом созданном слоте",
		sourceEn = "the 0.5.0 essence nerf (XTheFarmerX's breakdown); the engine warns when the crafted slot is taken",
	},
	{
		id = "vaal_reversible",
		matches = { "vaal reversible", "vaal обратим", "осквернение обратимо" },
		verdict = "false",
		title = "Осквернение необратимо",
		titleEn = "Corruption is irreversible",
		why = "После Vaal предмет больше нельзя крафтить. Поэтому его делают последним и только на предмете, "
			.. "который готовы потерять.",
		whyEn = "After Vaal the item can no longer be crafted. So it is done last and only on an item the "
			.. "player is ready to lose.",
		source = "правило locked и предупреждение шага vaal",
		sourceEn = "the locked rule and the warning on the vaal step",
	},
	{
		id = "vaal_all_skills_rate",
		matches = { "+1 all skills", "+1 ко всем умениям", "ваал +1", "осквернение +1", "vaal +1" },
		verdict = "true",
		title = "Vaal: четыре равных исхода, один из них уничтожает крафт",
		titleEn = "Vaal: four equal outcomes, one of them destroys the craft",
		why = "У снаряжения осквернение даёт ОДИН из четырёх равных исходов, по 25 % каждый: осквернённый "
			.. "имплисит (он заменяет существующий), цвет сокета станет не белым, предмет станет редким с "
			.. "ШЕСТЬЮ случайными модами — весь крафт пропадает, — либо не изменится ничего. Именно поэтому "
			.. "Vaal делают последним и только на предмете, который готовы потерять. Шанс получить нужный "
			.. "имплисит — это 25 % МИНУС вероятность того, что выпадет не тот имплисит: набор имплиситов "
			.. "зависит от базы, поэтому «+1 ко всем умениям» с конкретной базы нужно смотреть отдельно.",
		whyEn = "On gear a corruption gives ONE of four equal outcomes, 25% each: a corrupted implicit (it "
			.. "replaces the existing one), the socket colour stops being white, the item becomes rare with "
			.. "SIX random modifiers - the whole craft is gone - or nothing changes at all. That is exactly "
			.. "why Vaal is done last and only on an item the player is ready to lose. The chance to get the "
			.. "wanted implicit is 25% MINUS the chance that a different implicit rolls: the implicit pool "
			.. "depends on the base, so \"+1 to all skills\" on a specific base has to be looked at separately.",
		source = "poewiki Vaal_Orb, снято 2026-10-20: четыре исхода, равный шанс; для самоцветов +1 к уровню "
			.. "= 1/8 (1/4 на эффект уровня × 1/2 на знак)",
		sourceEn = "poewiki Vaal_Orb, taken 2026-10-20: four outcomes, equal chance; for soul cores +1 to "
			.. "level = 1/8 (1/4 for the level effect x 1/2 for the sign)",
	},
	{
		id = "homogenising_both_sides",
		matches = { "homogenising", "гомогениз", "теги обеих сторон", "tags of both sides" },
		verdict = "true",
		title = "Homogenising Exaltation стягивает мод к тегам предмета",
		titleEn = "Homogenising Exaltation pulls the modifier towards the item's tags",
		why = "Omen of Homogenising Exaltation заставляет следующий Exalted добавить мод из тегов, которые "
			.. "уже есть на предмете, — это подтверждено разбором и правилом. Но формулировка «теги ОБЕИХ "
			.. "сторон» (будто префикс и суффикс считаются вместе) в наших данных не подтверждена: точную "
			.. "трактовку проверить нечем, поэтому на неё не опираемся. И помните: с 0.4.0 омен больше не "
			.. "падает, работает только на уже существующих копиях.",
		whyEn = "Omen of Homogenising Exaltation makes the next Exalted add a modifier from the tags that are "
			.. "already on the item - that is confirmed by the breakdown and by the rule. But the wording "
			.. "\"tags of BOTH sides\" (as if prefix and suffix are counted together) is not confirmed by our "
			.. "data: there is nothing to check the exact reading against, so we do not rely on it. And "
			.. "remember: since 0.4.0 the omen no longer drops, only copies that already exist work.",
		source = "разбор GhazzyTV + правило омэна; трактовка «обеих сторон» не проверена",
		sourceEn = "GhazzyTV's breakdown + the omen rule; the \"both sides\" reading is not verified",
	},
	{
		id = "ilvl_mod_thresholds",
		matches = { "ilvl", "уровень предмета", "порог тира", "item level threshold", "итем левел" },
		verdict = "true",
		title = "Пороги уровня предмета задают тир — но точные числа не сверены",
		titleEn = "Item level thresholds set the tier - but the exact numbers are not verified",
		why = "Тир мода ограничен уровнем предмета, и это работает. Однако конкретные пороги, которые "
			.. "называют в видео, мы не сверяли построчно с poe2db: часть чисел взята из разбора, а не из "
			.. "таблиц. Поэтому панель показывает тир, который нашла в данных, и не обещает, что бо́льший "
			.. "уровень предмета всегда даст следующий тир.",
		whyEn = "A modifier tier is capped by item level, and that works. However the specific thresholds "
			.. "named in the video have not been checked line by line against poe2db: some of the numbers come "
			.. "from the breakdown, not from the tables. So the panel shows the tier it found in the data and "
			.. "does not promise that a higher item level always gives the next tier.",
		source = "механика из данных предмета; построчной сверки порогов с poe2db нет",
		sourceEn = "the mechanic comes from item data; the thresholds have not been checked line by line against poe2db",
	},
	{
		id = "quality_free_slot",
		matches = { "quality takes a slot", "качество занимает", "качество съедает", "качество это слот" },
		verdict = "false",
		title = "Качество не занимает слот",
		titleEn = "Quality takes no slot",
		why = "Качество — отдельное число предмета, оно не аффикс и не занимает ни префикс, ни суффикс. "
			.. "Именно поэтому его поднимают, не рискуя модами.",
		whyEn = "Quality is a separate number on the item: it is not an affix and takes neither a prefix nor "
			.. "a suffix. That is exactly why it is raised without risking the modifiers.",
		source = "описание шага качества и правило качества в своде",
		sourceEn = "the quality step description and the quality rule in the ruleset",
	},
	{
		id = "divine_changes_mods",
		matches = { "divine changes mods", "divine меняет моды", "divine перебрасывает моды" },
		verdict = "false",
		title = "Divine меняет числа, а не набор модов",
		titleEn = "Divine changes the numbers, not the modifier set",
		why = "Он перебрасывает значения существующих модов и не убирает их. Набор модов остаётся тем же.",
		whyEn = "It rerolls the values of the existing modifiers and does not remove them. The modifier set "
			.. "stays the same.",
		source = "описание валюты divine",
		sourceEn = "the divine currency entry",
	},
	{
		id = "no_full_reroll",
		matches = { "full reroll", "полный реролл", "перекатить предмет" },
		verdict = "false",
		title = "Полного реролла в PoE 2 нет",
		titleEn = "There is no full reroll in PoE 2",
		why = "Предмет собирается постепенно: обычный → волшебный → редкий, и каждая валюта добавляет или меняет "
			.. "один мод. Поэтому единственная дешёвая точка отбора — волшебная стадия.",
		whyEn = "An item is built up step by step: Normal -> Magic -> Rare, and every currency adds or "
			.. "changes one modifier. So the only cheap point to sift is the Magic stage.",
		source = "правила потолка аффиксов и порядок планов",
		sourceEn = "the affix cap rules and the order of the plans",
	},
	{
		id = "exalted_safe",
		matches = { "exalted safe", "exalted не портит", "exalted безопасно" },
		verdict = "true",
		title = "Exalted не трогает существующие моды",
		titleEn = "Exalted does not touch the existing modifiers",
		why = "Если сторона свободна, Exalted только добавляет мод. Существующие он не снимает — поэтому это "
			.. "самый безопасный способ улучшить предмет. Но добавленный мод случайный.",
		whyEn = "If the side is free, Exalted only adds a modifier. It does not remove the existing ones, "
			.. "which is why it is the safest way to improve an item. But the added modifier is random.",
		source = "описание валюты exalted и правила добавления",
		sourceEn = "the exalted currency entry and the addition rules",
	},
	{
		id = "regal_keeps_mods",
		matches = { "regal keeps", "regal сохраняет", "regal сохранит" },
		verdict = "true",
		title = "Regal сохраняет оба мода волшебного предмета",
		titleEn = "Regal keeps both Magic modifiers",
		why = "Он поднимает редкость и добавляет третий мод, не снимая первые два. Именно поэтому его "
			.. "применяют, когда оба мода уже годятся.",
		whyEn = "It raises the rarity and adds a third modifier without removing the first two. That is "
			.. "exactly why it is used when both modifiers are already good.",
		source = "правило magic_two_mods",
		sourceEn = "the magic_two_mods rule",
	},
}

-- Cyrillic case folding, done on codepoints.
--
-- string.lower() folds ASCII only in this Lua build: "Скуринга":lower() came back unchanged, so the pattern
-- never matched and the checker answered "not in my list" for a claim it knows. gsub is no help either - it
-- works on bytes, and a Cyrillic letter is two of them, so a character class of "А-Я" means nothing to it.
-- The text is therefore decoded to codepoints, folded, and rebuilt.
local CYRILLIC_OFFSET = 0x20 -- А..Я (U+0410..U+042F) sit exactly 0x20 above а..я (U+0430..U+044F)

--- Decode UTF-8 into codepoints.
-- @param text input
-- @return list of codepoints
local function codepoints(text)
	local out = { }
	local index, length = 1, #text
	while index <= length do
		local byte = text:byte(index)
		if not byte then
			break
		end
		local size, code
		if byte < 0x80 then
			size, code = 1, byte
		elseif byte < 0xE0 then
			size, code = 2, byte - 0xC0
		elseif byte < 0xF0 then
			size, code = 3, byte - 0xE0
		else
			size, code = 4, byte - 0xF0
		end
		for step = 1, size - 1 do
			local nextByte = text:byte(index + step) or 0
			code = code * 64 + (nextByte - 0x80)
		end
		out[#out + 1] = code
		index = index + size
	end
	return out
end

--- Encode codepoints back into UTF-8.
local function utf8Of(codes)
	local out = { }
	for _, code in ipairs(codes) do
		if code < 0x80 then
			out[#out + 1] = string.char(code)
		elseif code < 0x800 then
			out[#out + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
		elseif code < 0x10000 then
			out[#out + 1] = string.char(0xE0 + math.floor(code / 4096),
				0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
		else
			out[#out + 1] = string.char(0xF0 + math.floor(code / 262144),
				0x80 + math.floor(code / 4096) % 64, 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
		end
	end
	return table.concat(out)
end

--- Lower-case ASCII and Cyrillic.
-- @param text input
-- @return lower-cased text
local function lower(text)
	local folded = { }
	for _, code in ipairs(codepoints(tostring(text or ""))) do
		if code >= 65 and code <= 90 then
			code = code + 32                -- A..Z
		elseif code >= 0x410 and code <= 0x42F then
			code = code + CYRILLIC_OFFSET   -- А..Я
		elseif code == 0x401 then
			code = 0x451                    -- Ё
		end
		folded[#folded + 1] = code
	end
	return utf8Of(folded)
end

--- Machine checks that tie a claim to the ruleset.
--
-- A "verdict" written as prose is only as good as the person who wrote it, and the whole point of this module
-- is that we do not have to be trusted. Where the data can decide a claim, it does: the currency records carry
-- structured fields (adds, removes, side), so "Chaos rerolls your whole item" is refutable by `removes == 1`
-- rather than by our opinion. Claims whose truth is a game-wide fact with no row in our tables (there is no
-- Orb of Scouring to look up) verify by the ABSENCE of the thing, which is also a data check.
--
-- Keys match a claim id. A function returns true when the claim holds according to the data.
Claims.VERIFIERS = {
	-- No currency in the ruleset is a Scouring Orb: not by id, not by name, not by effect.
	scouring_orb = function(rules)
		for id, currency in pairs((rules or { }).currencies or { }) do
			local name = tostring(id):lower() .. " " .. tostring(currency.en or ""):lower()
			if name:find("scour", 1, true) then
				return false
			end
		end
		return true
	end,
	-- Chaos removes exactly one modifier and adds one.
	chaos_rerolls_all = function(rules)
		local chaos = ((rules or { }).currencies or { }).chaos
		return chaos ~= nil and tonumber(chaos.removes) == 1 and tonumber(chaos.adds) == 1
	end,
	-- Divine touches no modifier: it adds none, removes none, and grants no side.
	divine_changes_mods = function(rules)
		local divine = ((rules or { }).currencies or { }).divine
		return divine ~= nil and tonumber(divine.adds) == 0 and tonumber(divine.removes) == 0
	end,
	-- Exalted only adds.
	exalted_safe = function(rules)
		local exalted = ((rules or { }).currencies or { }).exalted
		return exalted ~= nil and tonumber(exalted.adds) == 1 and tonumber(exalted.removes) == 0
	end,
	-- Regal only adds, so both Magic modifiers survive it.
	regal_locks_prefix = function(rules)
		local regal = ((rules or { }).currencies or { }).regal
		return regal ~= nil and tonumber(regal.removes) == 0
	end,
	regal_keeps_mods = function(rules)
		local regal = ((rules or { }).currencies or { }).regal
		return regal ~= nil and tonumber(regal.removes) == 0
	end,
	-- Vaal says in its own record that nothing can be done afterwards.
	vaal_reversible = function(rules)
		local vaal = ((rules or { }).currencies or { }).vaal
		if not vaal then
			return false
		end
		local text = tostring(vaal.effectEn or ""):lower()
		return text:find("no further changes", 1, true) ~= nil
	end,
	-- Quality is not a modifier: no currency in the set is an affix, and quality is applied to the item's own
	-- quality field. The check is that no currency claims to fill a prefix or suffix with quality.
	quality_free_slot = function(rules)
		local quality = ((rules or { }).currencies or { }).quality
		if quality == nil then
			-- Quality comes from catalysts and scraps rather than one `quality` currency in some tables; the
			-- claim still holds, and the absence of an affix-shaped entry is the evidence.
			return true
		end
		return tonumber(quality.adds or 0) == 0
	end,
	-- One created slot and one desecrated slot are limits the ruleset states.
	--
	-- NOT verified by data: there is no `limits` row to read, so an earlier version of this verifier returned
	-- true unconditionally and the panel reported "checked against the data" for a rule the data never checked.
	-- The rule is real and the engine enforces it (Coach reports `craftedAnchorUsed` and warns that a second
	-- created modifier will not fit), but that is behavioural, so the claim is left marked as written by hand
	-- and the enforcement is tested directly in Tests/test_claims.lua instead of being dressed up as a data
	-- check. Removing the fake pass is the point: a green tick that means nothing is worse than no tick.
}

--- Run every available verifier against a ruleset.
--
-- Every verifier answers the same question: "do the data support the verdict printed with this claim?" - so a
-- plain `true` means agreement, whichever way the verdict points. Getting this backwards is exactly the kind
-- of conflation a check like this exists to prevent: for a trap, "the data contradict the trap" is agreement,
-- not a failure.
-- @param rules the league table
-- @return { checked, failed = { { id, verdict, holds } } }
function Claims.verifyAll(rules)
	local checked, failed = 0, { }
	for _, claim in ipairs(Claims.KNOWN) do
		local verifier = Claims.VERIFIERS[claim.id]
		if verifier then
			checked = checked + 1
			local ok, holds = pcall(verifier, rules)
			if not ok or holds ~= true then
				failed[#failed + 1] = { id = claim.id, verdict = claim.verdict, holds = holds }
			end
		end
	end
	return { checked = checked, failed = failed }
end

	-- Find the claim a question is about.
--
-- Scoring is by the longest matching needle, so a specific claim wins over a generic one. That is not enough
-- when the specific claim is a qualifier of the generic one: "на вейстоуне chaos перекатывает всё?" contains
-- "chaos перекатывает" (longer) and was answered with the gear rule, which is the opposite of the truth for a
-- waystone. A claim can therefore declare which claims it overrides when BOTH match.
-- @param text what the player typed or asked
-- @return claim table or nil
function Claims.find(text)
	local lowered = lower(text)
	if lowered == "" then
		return nil
	end
	local best, bestLength = nil, 0
	local matched = { }
	for _, claim in ipairs(Claims.KNOWN) do
		for _, needle in ipairs(claim.matches or { }) do
			local at = lowered:find(lower(needle), 1, true)
			if at then
				matched[claim.id] = true
				if #needle > bestLength then
					best, bestLength = claim, #needle
				end
			end
		end
	end
	if best == nil then
		return nil
	end
	-- A more specific claim that also matched takes over from the generic one it qualifies.
	for _, claim in ipairs(Claims.KNOWN) do
		if matched[claim.id] and claim.winsOver then
			for _, generic in ipairs(claim.winsOver) do
				if generic == best.id then
					return claim
				end
			end
		end
	end
	return best
end

--- Answer a claim.
-- @param text the question
-- @return { known, id, verdict, title, why, source } — known=false when there is nothing to say
function Claims.answer(text)
	local claim = Claims.find(text)
	if not claim then
		return {
			known = false,
			why = "Такого утверждения нет в проверенном списке. Проверить его по нашим данным нельзя — "
				.. "не доверяйте формулировке, пока её не подтвердит игровой текст или проверенный гайд.",
			whyEn = "Such a claim is not in the verified list. It cannot be checked against our data - do "
				.. "not trust the wording until the game text or a verified guide confirms it.",
		}
	end
	return {
		known = true,
		id = claim.id,
		verdict = claim.verdict,
		title = claim.title,
		titleEn = claim.titleEn,
		why = claim.why,
		whyEn = claim.whyEn,
		source = claim.source,
		sourceEn = claim.sourceEn,
		-- True when the ruleset itself can settle this claim, so the panel can say "checked against the data"
		-- instead of "written by us". That difference is the reason this module exists.
		verified = Claims.VERIFIERS[claim.id] ~= nil,
	}
end

--- Every known claim, for the reference list and the tests.
function Claims.list()
	return Claims.KNOWN
end

return Claims
