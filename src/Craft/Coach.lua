--- The coach: one step at a time, in the words a beginner needs.
--
-- It reads what the engine already knows about the item (parsed modifiers, affix counts, item
-- level) plus the advisor's plans, and turns that into: what is locked, what is still open, what
-- would be a mistake right now, and the single next action. Nothing here invents numbers - every
-- figure comes from the item or from the advisor.
local Coach = { }

-- Prices are read, never invented: when the snapshot does not cover the league, the step simply
-- carries no cost instead of a wrong one.
local Prices = require("Craft.Prices")
local Memory = require("Craft.Memory")
-- The principle behind a step, so the player learns it and not only this item.
local Lesson = require("Craft.Lesson")
local RulesRu = require("Data.rules_ru")

local function text(value)
	return tostring(value or "")
end

--- Is the text of the item carrying the given annotation, in either language?
local function annotated(rawText, ...)
	local haystack = text(rawText):lower()
	for _, needle in ipairs({ ... }) do
		if haystack:find(needle:lower(), 1, true) then
			return true
		end
	end
	return false
end

--- How many EXTRA created modifiers the item has paid for.
--
-- Since 0.5.0 an item holds one "created" modifier - the guaranteed mod from an essence, an alloy or a rune.
-- Astrid's Creativity is the documented exception: it grants "Can have 1 additional Crafted Modifier", and a
-- 0.5-era guide relies on it to run two guaranteed essence modifiers on one item. The wording is read from the
-- item text in both languages because the rune's effect is printed as a modifier, not as a structured field.
-- @param item parsed item
-- @param rawText the copied item text
-- @param annotated the annotation helper (kept as a parameter so this stays above its caller's scope)
-- @return number of extra slots (0 when absent)
local function additionalCraftedSlots(item, rawText, annotated)
	local extra = 0
	-- English and Russian wordings of the rune's line, plus the parser's augment table wording.
	local markers = {
		"additional crafted modifier",
		"дополнительных ремесленных свойств",
		"additional crafted modifiers",
	}
	local haystack = text(rawText):lower()
	for _, marker in ipairs(markers) do
		-- Count the lines that carry it: a hypothetical "+2" rune would print the line once but say "2".
		local at = 1
		while true do
			local from = haystack:find(marker, at, true)
			if not from then break end
			-- Read the number just before the phrase; default to one.
			local before = haystack:sub(math.max(1, from - 4), from - 1)
			local amount = tonumber((before:match("([%+%-]?%d+)%s*$")))
			extra = extra + (amount or 1)
			at = from + #marker
		end
	end
	if extra == 0 then
		return 0
	end
	return extra
end

--- What is already locked on the item, and how much room is left.
-- The counts come from the parser ("1P/2S open 2P/1S"); the anchors come from the annotations the
-- game itself writes into the copied text, so nothing has to be guessed.
function Coach.state(item, rawText)
	local item_ = item or { }
	local flags = item_.flags or { }
	local counts = item_.affixCount
	local prefixes, suffixes = 0, 0
	if type(counts) == "table" then
		prefixes = tonumber(counts.prefixes) or 0
		suffixes = tonumber(counts.suffixes) or 0
	end
	-- The parser's own counters are authoritative: they are filled from the annotations the game prints, and
	-- they exist even when `affixCount` does not. A full Magic wand used to report no split at all because
	-- only `affixCount` was consulted, and then the advisor described an item whose two slots it could see.
	if (tonumber(item_.prefixCount) or 0) + (tonumber(item_.suffixCount) or 0) > 0 then
		prefixes = tonumber(item_.prefixCount) or 0
		suffixes = tonumber(item_.suffixCount) or 0
	end
	-- The cap is the ITEM'S cap, not three. A Magic item holds one prefix and one suffix, and a base can move
	-- the cap either way ("+1 Prefix Modifier allowed"). Subtracting from a hardcoded three claimed two open
	-- prefix slots on a full Magic wand - a currency offered for space that does not exist.
	local caps = item_.affixCaps
	local capPrefixes = (type(caps) == "table" and tonumber(caps.prefixes)) or 3
	local capSuffixes = (type(caps) == "table" and tonumber(caps.suffixes)) or 3
	local used = tonumber(item_.modCount) or (prefixes + suffixes)
	-- Open slots may only be claimed when the split is actually known. `modCount` counts every modifier
	-- LINE the parser saw, properties included, so a charm with two properties and one modifier looked
	-- like a ten-modifier item with no room left - which is what made the panel announce "no free
	-- affixes" for an item whose slots it had already said it could not determine.
	local classified = (tonumber(item_.prefixCount) or 0) + (tonumber(item_.suffixCount) or 0)
	local slotsKnown = item_.affixSplitComplete == true
	local openTotal
	if slotsKnown then
		openTotal = math.max(0, 6 - classified)
	else
		openTotal = math.max(0, 6 - used)
	end
	return {
		itemLevel = tonumber(item_.itemLevel) or 0,
		rarity = text(item_.rarity),
		rarityId = text(item_.rarity),
		splitKnown = slotsKnown,
		slotsKnown = slotsKnown,
		prefixes = prefixes,
		suffixes = suffixes,
		modCount = used,
		openPrefixes = math.max(0, capPrefixes - prefixes),
		openSuffixes = math.max(0, capSuffixes - suffixes),
		openSlots = openTotal,
		modifiable = item_.isModifiable ~= false,
		corrupted = (flags.corrupted == true) or annotated(rawText, "Осквернено", "Corrupted"),
		-- Sanctified is a separate one-way state: the Omen of Sanctification randomises the values
		-- once and multiplies them by 80-120%, after which most methods of crafting refuse the item.
		-- It used to be missed here, so the card offered a next step for an item that cannot be
		-- crafted at all - and the game would have refused the currency.
		sanctified = (flags.sanctified == true) or annotated(rawText, "Освящено", "Освещено", "Sanctified"),
		-- The parsed item knows which mods are crafted, runed or desecrated: no need to guess it from the
		-- copied text. "(augmented)" must NOT be counted here - the game adds it to a modifier whose
		-- VALUE has been changed ("58% increased Charges (augmented)"), which says nothing about the
		-- modifier being crafted. Counting it told the customer that a charm's crafted slot was taken.
		craftedAnchorUsed = #(item_.craftedMods or { }) > 0 or #(item_.runeMods or { }) > 0
			or annotated(rawText, "(crafted)", "(rune)"),
		-- How MANY created modifiers are already on the item, and how many it allows: one by the 0.5.0 rule,
		-- plus whatever Astrid's Creativity bought. Both are needed - the count alone cannot tell a legal
		-- second essence from an illegal one.
		createdModifierCount = #(item_.craftedMods or { }) + #(item_.runeMods or { }),
		-- How many created modifiers the item can hold. One is the rule since 0.5.0, but Astrid's Creativity
		-- ("Can have 1 additional Crafted Modifier", in Data/runes.lua) buys a second - and a 0.5-era guide
		-- relies on exactly that to run two guaranteed essences. Without this the card warned "a second will
		-- not fit" on an item that had deliberately paid for the slot.
		createdSlots = 1 + additionalCraftedSlots(item_, rawText, annotated),
		desecratedAnchorUsed = #(item_.desecratedMods or { }) > 0
			or annotated(rawText, "Очернённое", "Desecrated", "Осквернённое"),
	}
end
--- Mistakes worth catching before they cost currency. Only the ones this item can actually reach.
function Coach.warnings(item, rawText, state)
	local list = { }
	local add = function(id, text_, textEn) list[#list + 1] = { id = id, text = text_, textEn = textEn } end

	if state.corrupted then
		add("corrupted", "Предмет осквернён: менять его больше нельзя. Крафт закончен, остается только оценить результат.",
			"The item is corrupted: it can no longer be changed. The craft is finished, and all that is left "
				.. "is to assess the result.")
	end
	if state.sanctified then
		add("sanctified", "Предмет освящён: значения модов уже перебрасывались и умножались один раз. "
			.. "Больше крафт не применяется — остаётся оценить результат.",
			"The item is sanctified: the modifier values have already been rerolled and multiplied once. "
				.. "No further crafting applies, and all that is left is to assess the result.")
	end
	if state.desecratedAnchorUsed then
		add("desecrated_used", "Осквернённый слот уже занят — второй осквернённый мод на предмет не встанет.",
			"The desecrated slot is already taken - a second desecrated modifier will not go on the item.")
	end
	-- The created slot is full only when the item's actual allowance is used. Astrid's Creativity buys a second
	-- one, so an item carrying it must not be told that a second created modifier will not fit.
	local createdSlots = tonumber(state.createdSlots) or 1
	local createdUsed = tonumber(state.createdModifierCount) or (state.craftedAnchorUsed and 1 or 0)
	if state.craftedAnchorUsed and createdUsed >= createdSlots then
		add("crafted_used", "Созданный слот уже занят (эссенция, сплав или руна). Второй такой мод не встанет.",
			"The crafted slot is already taken (an essence, an alloy or a rune). A second modifier of that "
				.. "kind will not fit.")
	elseif state.craftedAnchorUsed and createdSlots > createdUsed then
		add("crafted_slot_free", "Созданный мод уже есть, но предмет разрешает ещё один (Astrid's Creativity): "
			.. "второй гарантированный мод встанет.",
			"A crafted modifier is already there, but the item allows one more (Astrid's Creativity): "
				.. "a second guaranteed modifier will fit.")
	end
	if state.itemLevel > 0 and state.itemLevel < 50 then
		add("low_ilvl", "Уровень предмета " .. state.itemLevel .. ": Perfect-валюта здесь не даст топовый тир — это выброшенные деньги.",
			"Item level " .. state.itemLevel .. ": Perfect currency cannot roll a top tier here - that is "
				.. "money thrown away.")
	end
	if state.openSlots == 0 and not state.corrupted and state.slotsKnown ~= false then
		add("no_room", "Свободных аффиксов нет: сначала придётся убрать один мод (Annulment или Chaos), и только потом добавлять новый.",
			"No free affixes: one modifier has to be removed first (Annulment or Chaos), and only then can a "
				.. "new one be added.")
	end
	if not state.craftedAnchorUsed and state.rarity:lower():find("rare") then
		add("essence_slot_free", "Созданный слот ещё свободен: его стоит потратить на мод, который вы обязаны иметь, а не на то, что и так катится.",
			"The crafted slot is still free: spend it on a modifier the item must have, not on one that rolls "
				.. "anyway.")
	end
	add("divine_timing", "Divine перебрасывает только числа. Использовать его до того, как список модов финальный, — потеря валюты.",
		"Divine rerolls the numbers only. Using it before the modifier list is final wastes currency.")
	add("vaal_last", "Vaal необратим: только последним шагом и только если не боитесь потерять предмет.",
		"Vaal is irreversible: the last step only, and only if losing the item does not frighten you.")
	return list
end

--- The plans carry the steps; this picks which one to show given what happened last time.
-- index is 1-based: 1 starts the plan, and after a successful step the next one follows.
--- Pick the step to act on, given the previous step's index and verdict.
--
-- The parameter used to be named `index` as well as the local that tracks the current position, so the
-- local shadowed it and the argument was ignored outright: the selector always started from step 1.
-- @param advice advisor output
-- @param memory remembered previous step (may be nil)
-- @return table|nil { step, plan, index, prefix, whyFromVerdict } or { finished = true, ... }
local function stepFromPlan(advice, memory)
	-- The verdict from the previous step decides what to show now: carry on after a success, repeat
	-- when nothing changed, step back after a loss, and offer the retry tools after a swap.
	local index, prefix, whyFromVerdict = tonumber(memory and memory.previousStepIndex) or 1,
		"Следующий шаг: ", nil
	local prefixEn, whyFromVerdictEn = "Next step: ", nil
	if memory and memory.sameItem then
		local verdict = memory.verdict or "nothing"
		if verdict == "progress" then
			index = index + 1
			whyFromVerdict = "Предыдущий шаг сработал — идём дальше по плану."
			whyFromVerdictEn = "The previous step worked - carry on down the plan."
		elseif verdict == "nothing" then
			whyFromVerdict = "Прошлый шаг ничего не изменил: эссенция в уже занятую группу модов не срабатывает, "
				.. "а занятый созданный или осквернённый слот не даст поставить второй такой мод. Повторяем тот же шаг."
			whyFromVerdictEn = "The previous step changed nothing: an essence does not apply to a modifier group "
				.. "that is already taken, and an occupied crafted or desecrated slot will not take a second "
				.. "modifier of that kind. Repeat the same step."
		elseif verdict == "loss" then
			index = math.max(1, index - 1)
			prefix = "Модов стало меньше — вернитесь к шагу: "
			prefixEn = "Fewer modifiers than before - go back to the step: "
			whyFromVerdict = "Сначала восстановите потерянное, потом добавляйте новое."
			whyFromVerdictEn = "Restore what was lost first, then add something new."
		else
			prefix = "Мод заменился — вернитесь к шагу: "
			prefixEn = "A modifier was swapped - go back to the step: "
			whyFromVerdict = "Чтобы заменить именно худший мод, нужен Chaos с Omen of Whittling; чтобы снять только осквернённый — Annulment с Omen of Light."
			whyFromVerdictEn = "To replace the worst modifier specifically, use Chaos with Omen of Whittling; to "
				.. "remove only the desecrated one, use Annulment with Omen of Light."
		end
	end

	local plans = (advice or { }).plans or { }
	local plan = plans[1]
	if not plan then
		return nil, nil
	end
	local steps = plan.steps or { }
	local step = steps[index]
	if not step and index <= #steps then
		-- The remembered index is smaller than the plan is, but that position does not exist any more:
		-- the plan itself changed since it was remembered (the quality step disappears once the quality
		-- is at the cap, for instance). Falling back to the plan's first step is the honest answer;
		-- returning nothing left the card empty for an item that does have advice.
		step = steps[1]
		index = 1
		prefix = "План изменился — вот шаг с начала: "
		prefixEn = "The plan changed - here is the step from the start: "
		whyFromVerdict = "Предыдущий шаг сработал, и после него план стал другим, так что начнём с его первого шага."
		whyFromVerdictEn = "The previous step worked, and the plan changed after it, so start from its first step."
	end
	if not step and index > #steps then
		-- The plan is finished: the previous step was the last one, so repeating it is not advice. On a
		-- Magic item whose prefix and suffix are both taken this is the normal end - nothing can be
		-- added, and the panel used to fall back to the last step and offer the same useless orb again
		-- round after round.
		local last = steps[#steps]
		local text = last and (last.name or last.en or last.currency) or "?"
		return {
			finished = true,
			lastStep = last,
			lastName = text,
			plan = plan,
		}
	end
	step = step or steps[#steps]
	if not step then
		return nil
	end
	return { step = step, plan = plan, index = index, prefix = prefix, whyFromVerdict = whyFromVerdict,
		prefixEn = prefixEn, whyFromVerdictEn = whyFromVerdictEn }
end
--- The value reroll, when the item has numbers that can be rerolled.
--
-- The one step that does not depend on how many slots are free: a Divine Orb rerolls the values of the
-- modifiers already on the item. That makes it the honest answer for an item whose slot count cannot be
-- determined (a flask or charm whose modifier line did not resolve) and for an item whose plan has run
-- out while the values are still rollable. Offered only when a value is actually there, and worded to
-- say both what it does and that the modifier set is not changed.
-- @return step table or nil
local function valueRerollStep(item)
	local hasValue = false
	for _, bucket in ipairs({ (item or { }).explicitMods or { }, (item or { }).craftedMods or { },
			(item or { }).desecratedMods or { }, (item or { }).runeMods or { } }) do
		for _, mod in ipairs(bucket) do
			local text = type(mod) == "table" and mod.text or mod
			if type(text) == "string" and text:match("%d") then
				hasValue = true
				break
			end
		end
		if hasValue then
			break
		end
	end
	if not hasValue then
		return nil
	end
	return {
		currency = "Divine Orb",
		index = 1,
		count = 1,
		title = "Следующий шаг: Divine Orb",
		titleEn = "Next step: Divine Orb",
		why = "Числа существующих модов можно перебросить, и это не зависит от того, сколько слотов "
			.. "свободно. Набор модов Divine не меняет: он трогает только значения, и вернуть прежнее "
			.. "число нельзя.",
		whyEn = "The numbers on the existing modifiers can be rerolled, and that does not depend on how many "
			.. "slots are free. Divine does not change the modifier set: it touches the values only, and the "
			.. "old number cannot be brought back.",
		effect = "Divine перебрасывает значения модов; набор остаётся тем же.",
		effectEn = "Divine rerolls the modifier values; the set stays the same.",
		ifSuccess = "Числа переброшены — скопируйте предмет снова (Ctrl+C) и нажмите Ctrl+Q: помощник посмотрит, что вышло.",
		ifSuccessEn = "The numbers are rerolled - copy the item again (Ctrl+C) and press Ctrl+Q: the helper will "
			.. "look at what came out.",
		ifFail = "Набор модов Divine не меняет. Если число стало хуже, придётся тратить ещё одну сферу.",
		ifFailEn = "Divine does not change the modifier set. If a number got worse, another orb has to be spent.",
		after = "После шага скопируйте предмет снова (Ctrl+C) и нажмите Ctrl+Q.",
		afterEn = "After the step, copy the item again (Ctrl+C) and press Ctrl+Q.",
	}
end

--- The single next action. The advisor has already worked out the plans; the coach only picks the
-- cheapest applicable one and explains it, so the number and the reasoning stay in one place.
function Coach.step(item, advice, state, memory)
	if state.corrupted or state.sanctified then
		return {
			currency = nil,
			title = "Крафт завершён",
			titleEn = "Craft finished",
			why = state.corrupted
				and "Предмет осквернён, изменения невозможны. Можно оценить его и продать."
				or "Предмет освящён, изменения невозможны. Можно оценить его и продать.",
			whyEn = state.corrupted
				and "The item is corrupted, changes are impossible. It can be assessed and sold."
				or "The item is sanctified, changes are impossible. It can be assessed and sold.",
		}
	end

	-- The verdict from the previous step decides what to show now: carry on after a success, repeat
	-- when nothing changed, step back after a loss, and offer the retry tools after a swap.
	local index, prefix, whyFromVerdict = 1, "Следующий шаг: ", nil
	local prefixEn, whyFromVerdictEn = "Next step: ", nil
	if memory and memory.sameItem then
		index = tonumber(memory.previousStepIndex) or 1
		local verdict = memory.verdict or "nothing"
		if verdict == "progress" then
			index = index + 1
			whyFromVerdict = "Предыдущий шаг сработал — идём дальше по плану."
			whyFromVerdictEn = "The previous step worked - carry on down the plan."
		elseif verdict == "nothing" then
			whyFromVerdict = "Прошлый шаг ничего не изменил: эссенция в уже занятую группу модов не срабатывает, "
				.. "а занятый созданный или осквернённый слот не даст поставить второй такой мод. Повторяем тот же шаг."
			whyFromVerdictEn = "The previous step changed nothing: an essence does not apply to a modifier group "
				.. "that is already taken, and an occupied crafted or desecrated slot will not take a second "
				.. "modifier of that kind. Repeat the same step."
		elseif verdict == "loss" then
			index = math.max(1, index - 1)
			prefix = "Модов стало меньше — вернитесь к шагу: "
			prefixEn = "Fewer modifiers than before - go back to the step: "
			whyFromVerdict = "Сначала восстановите потерянное, потом добавляйте новое."
			whyFromVerdictEn = "Restore what was lost first, then add something new."
		else
			prefix = "Мод заменился — вернитесь к шагу: "
			prefixEn = "A modifier was swapped - go back to the step: "
			whyFromVerdict = "Чтобы заменить именно худший мод, нужен Chaos с Omen of Whittling; чтобы снять только осквернённый — Annulment с Omen of Light."
			whyFromVerdictEn = "To replace the worst modifier specifically, use Chaos with Omen of Whittling; to "
				.. "remove only the desecrated one, use Annulment with Omen of Light."
		end
	end

	-- Quality is the first step of the plan, so it is chosen by the same selector as every other step -
	-- no separate branch. This is what the customer's flask exposed: the branch returned index 0, which
	-- is not a step, and the memory then either repeated the quality step forever or fell back to the
	-- plan's LAST step (a Regal Orb that could not change a full Magic item).
	local qualityStep = (advice or { }).qualityStep
	local qualityIsTuning = qualityStep
		and (qualityStep.en or qualityStep.name) == "Divine Orb"

	local plans = (advice or { }).plans or { }
	-- The plan selection lives in ONE place. It used to be written twice - here and inside
	-- stepFromPlan - and the two drifted: the fix for "past the end of the plan" landed in the copy
	-- that nothing called, while this one kept falling back to the last step and repeating a currency
	-- that had already changed nothing.
	local stepAdvice = stepFromPlan(advice, memory)
	if stepAdvice and stepAdvice.finished then
		-- The plan is exhausted. That does not always mean the item is finished: with the quality already
		-- at the cap and modifiers that carry values, a Divine Orb still does something, and it is the one
		-- step that needs no free slot. The value reroll is offered here too, so the card does not say
		-- "nothing left" while a usable step exists.
		local reroll = valueRerollStep(item)
		if reroll then
			return reroll
		end
		-- Otherwise the plan is finished: repeating the last step is not advice.
		local lastName = stepAdvice.lastName or "?"
		return {
			currency = nil,
			index = 0,
			count = 0,
			planFinished = true,
			title = "План пройден: " .. tostring(lastName) .. " — это был последний шаг",
			titleEn = "Plan complete: " .. tostring(lastName) .. " - that was the last step",
			why = "Дальше по плану шагов нет. Для этого предмета это значит, что добавить больше нечего: "
				.. "занятые слоты не дают поставить новый мод, а повторять последний шаг смысла не имеет — "
				.. "он уже ничего не изменил.",
			whyEn = "There are no steps left in the plan. For this item that means nothing more can be added: "
				.. "the taken slots leave no room for a new modifier, and repeating the last step makes no "
				.. "sense - it has already changed nothing.",
			effect = "Оцените предмет как есть; если нужны другие моды, начинайте с новой базы.",
			effectEn = "Assess the item as it is; if different modifiers are needed, start from a new base.",
			ifSuccess = "Если моды устраивают, предмет готов — можно выставлять на продажу.",
			ifSuccessEn = "If the modifiers are good, the item is done - it can be listed for sale.",
			ifFail = "Если нет — этот предмет не доделать: нужна другая база.",
			ifFailEn = "If not, this item cannot be finished: a different base is needed.",
			after = "Скопируйте предмет снова (Ctrl+C) и нажмите Ctrl+Q, если хотите посмотреть расклад заново.",
			afterEn = "Copy the item again (Ctrl+C) and press Ctrl+Q to see the layout again.",
		}
	end

	local chosen, chosenPlan, chosenIndex, chosenPrefix, chosenWhy, chosenPrefixEn, chosenWhyEn
	if stepAdvice then
		chosen = stepAdvice.step
		chosenPlan = stepAdvice.plan
		chosenIndex = stepAdvice.index
		chosenPrefix = stepAdvice.prefix
		chosenWhy = stepAdvice.whyFromVerdict
		chosenPrefixEn = stepAdvice.prefixEn
		chosenWhyEn = stepAdvice.whyFromVerdictEn
	end
	-- Prefer the plan the selector chose (it knows the step index the memory implies); otherwise fall back
	-- to the first plan that yields a step.
	local candidates = { }
	if chosenPlan then
		candidates[#candidates + 1] = chosenPlan
	end
	for _, plan in ipairs(plans) do
		if plan ~= chosenPlan then
			candidates[#candidates + 1] = plan
		end
	end
	for _, plan in ipairs(candidates) do
		local steps = plan.steps or { }
		local first = plan == chosenPlan and chosen or (steps[1])
		if first then
			local currency = first.name or first.en or first.currency
			if currency then
				local count = tonumber(first.count) or 1
				-- What follows THIS step, not merely the second entry: with the quality step in front,
				-- the next step after the rule's own add is not steps[2].
				local position = 0
				for indexInPlan, candidate in ipairs(steps) do
					if candidate == first then
						position = indexInPlan
						break
					end
				end
				local following = steps[position + 1]
				local nextStep = following and (following.name or following.en or following.currency) or nil
				-- A step is never the whole story: what happens next depends on what rolled. Both
				-- branches are taken from the same plan, so they cannot contradict the advice.
				local ifSuccess = nextStep
					and ("Выпало нужное — дальше: " .. text(nextStep) .. ". Снова Ctrl+C и Ctrl+Q.")
					or "Выпало нужное — скопируйте предмет и нажмите Ctrl+Q: помощник подберёт следующий шаг."
				local ifSuccessEn = nextStep
					and ("The right modifier rolled - next: " .. text(nextStep) .. ". Ctrl+C and Ctrl+Q again.")
					or "The right modifier rolled - copy the item and press Ctrl+Q: the helper will pick the next "
						.. "step."
				local ifFail = "Не то — не спешите тратить ещё: снова Ctrl+C и Ctrl+Q, помощник посмотрит на предмет "
					.. "и предложит либо повтор, либо замену мода (Chaos с Omen of Whittling, Annulment с Omen of Light)."
				local ifFailEn = "Not the one - do not spend more yet: Ctrl+C and Ctrl+Q again, the helper will look "
					.. "at the item and offer either a repeat or a modifier swap (Chaos with Omen of Whittling, "
					.. "Annulment with Omen of Light)."
				local stepIndex = plan == chosenPlan and (chosenIndex or 1) or 1
				local stepPrefix = plan == chosenPlan and (chosenPrefix or "Следующий шаг: ") or "Следующий шаг: "
				local stepPrefixEn = plan == chosenPlan and (chosenPrefixEn or "Next step: ") or "Next step: "
				-- Quality at the cap is a value reroll rather than a quality raise, and it says so.
				local isQuality = first.id == "quality" or first.en == "Glassblower's Bauble"
					or first.en == "Armourer's Scrap" or first.en == "Blacksmith's Whetstone"
					or first.en == "Arcanist's Etcher" or first.en == "Gemcutter's Prism"
					or (qualityStep ~= nil and first.en == qualityStep.en)
				local title = stepPrefix .. text(currency) .. (count > 1 and (" ×" .. tostring(count)) or "")
				local titleEn = stepPrefixEn .. text(currency) .. (count > 1 and (" ×" .. tostring(count)) or "")
				-- The memory verdict explains ONE step: the one the last round repeated. It used to be used
				-- for every step of the chosen plan, so a card that had moved on to a different currency
				-- still carried "nothing changed, let us repeat the same step" - an explanation of an action
				-- the player is not being asked to take. The pointer check keeps the verdict with its step.
				local why = (plan == chosenPlan and first == chosen and chosenWhy)
					or (text(plan.reason) ~= "" and text(plan.reason) or text(first.effect))
				local whyEn = (plan == chosenPlan and first == chosen and chosenWhyEn)
					or (text(plan.reasonEn) ~= "" and text(plan.reasonEn) or text(first.effectEn or first.effect))
				-- The lesson travels with the step: it states the PRINCIPLE rather than this one action, so
				-- the player stops needing the tool for the next item. It is resolved before the quality
				-- wording because a `local` may not follow a statement in the same block.
				local lesson = Lesson.reasonFor(first)
				if isQuality then
					-- Quality closes the craft out. The old wording said "quality first", which was the
					-- old order and is now the opposite of what the panel does: modifiers first, quality
					-- right before the step after which nothing can be done.
					stepPrefix = qualityIsTuning and "Значения уже можно править: " or "Закрываем качеством: "
					stepPrefixEn = qualityIsTuning and "Values can already be tuned: " or "Closing with quality: "
					title = stepPrefix .. text(currency)
					titleEn = stepPrefixEn .. text(currency)
					why = qualityIsTuning
						and ("Качество уже максимальное, а набор модов менять не нужно: Divine перебрасывает только "
							.. "числа существующих модов и не убирает их. Если число станет хуже — вернуть прежнее нельзя.")
						or ("Моды уже стоят, и качество — последнее, что можно сделать до необратимого шага. Оно не "
							.. "занимает аффикс и множит собственные характеристики предмета (например, энергетический "
							.. "щит у шлема): поднимать его раньше не было смысла, потому что оно множит итог.")
					whyEn = qualityIsTuning
						and ("Quality is already at the cap and the modifier set does not need changing: Divine "
							.. "rerolls only the numbers of the existing modifiers and does not remove them. If a "
							.. "number gets worse, the old one cannot be brought back.")
						or ("The modifiers are in place, and quality is the last thing that can be done before the "
							.. "irreversible step. It takes no affix and multiplies the item's own stats (a helmet's "
							.. "energy shield, for example): raising it earlier made no sense, because it multiplies "
							.. "the final result.")
				end
				return {
					currency = currency,
					index = stepIndex,
					count = count,
					title = title,
					titleEn = titleEn,
					why = why,
					whyEn = whyEn,
					effect = text(first.effect),
					effectEn = text(first.effectEn or first.effect),
					effectRu = text(first.effectRu or RulesRu.text(first.effectEn or first.effect)),
					plan = plan.id,
					ifSuccess = ifSuccess,
					ifSuccessEn = ifSuccessEn,
					ifFail = ifFail,
					ifFailEn = ifFailEn,
					lessonTitle = lesson and lesson.title or nil,
					lessonTitleEn = lesson and lesson.titleEn or nil,
					lesson = lesson and lesson.text or nil,
					lessonEn = lesson and lesson.textEn or nil,
					after = "После шага скопируйте предмет снова (Ctrl+C) и нажмите Ctrl+Q: следующий шаг зависит от того, что выпало.",
					afterEn = "After the step, copy the item again (Ctrl+C) and press Ctrl+Q: the next step depends "
						.. "on what rolled.",
				}
			end
		end
	end
	if state.rarity:lower():find("normal") or state.rarity == "" then
		return {
			currency = "Transmutation",
			index = 1,
			title = "Следующий шаг: Transmutation",
			titleEn = "Next step: Transmutation",
			why = "Предмет обычный: сначала сделайте его магическим — это самые дешёвые попытки.",
			whyEn = "The item is normal: make it magic first - those are the cheapest attempts.",
			ifSuccess = "Стал магическим — снова Ctrl+C и Ctrl+Q: помощник скажет, катить дальше или уже поднимать до редкого.",
			ifSuccessEn = "It is magic now - Ctrl+C and Ctrl+Q again: the helper will say whether to keep rolling "
				.. "or raise it to rare.",
			ifFail = "Предмет не изменился — проверьте, что скопировали нужный предмет.",
			ifFailEn = "The item did not change - check that the right item was copied.",
			after = "После шага скопируйте предмет снова и нажмите Ctrl+Q.",
			afterEn = "After the step, copy the item again and press Ctrl+Q.",
		}
	end

	-- Nothing matched. The value reroll is the one step that does not depend on how many slots are free,
	-- which is what makes it the honest answer for an item whose slot count cannot be determined; the
	-- helper carries the wording. The customer's charm is exactly this case.
	local reroll = valueRerollStep(item)
	if reroll then
		return reroll
	end
	return {
		currency = nil,
		title = "Нужен план",
		titleEn = "A plan is needed",
		why = "Для этого предмета движок не предложил ни одного подходящего способа. Проверьте, что предмет скопирован полностью.",
		whyEn = "The engine offered no applicable method for this item. Check that the item was copied in full.",
	}
end

--- Cost and chance for one currency, taken from the engine's own snapshot and summary.
-- Returns nil fields when the data is absent: a missing number is honest, a guess is not.
local function enrich(step, advice)
	local currency = step and step.currency
	if not currency then
		return step
	end
	-- The lesson is attached HERE, not in the branch that builds the step. The step card has several return
	-- paths (a plan step, a quality close, a finished plan) and a lesson added to only one of them vanished
	-- for the others, leaving an instruction with no principle behind it - found by the end-to-end mentor
	-- test, which asserted a lesson exists on an item whose step came from a different branch.
	if not step.lesson then
		local lesson = Lesson.forName(currency, step.kind)
		if lesson then
			step.lessonTitle = step.lessonTitle or lesson.title
			step.lessonTitleEn = step.lessonTitleEn or lesson.titleEn
			step.lesson = lesson.text
			step.lessonEn = lesson.textEn
		end
	end
	local advice_ = advice or { }
	local prices = advice_.prices
	if prices and prices.fetchedAt then
		local per = Prices.unitPrice(currency)
		if per then
			local count = tonumber(step.count) or 1
			step.costPerUnit = per
			step.cost = per * count
			step.costUnit = tostring(Prices.info().unit or "")
		end
	end
	local summary = advice_.craftSummary or { }
	for _, entry in ipairs(summary.entries or { }) do
		local label = tostring(entry.label or entry.method or "")
		if label == currency or (label ~= "" and label:find(currency, 1, true)) then
			step.chancePerAttempt = entry.chancePerAttempt
			step.attemptsFor90 = entry.attemptsFor90
			break
		end
	end
	-- One line the beginner can act on: what it costs and what the odds are.
	local parts = { }
	local partsEn = { }
	if step.cost then
		parts[#parts + 1] = string.format("≈ %.4f %s за попытку", step.cost, step.costUnit)
		partsEn[#partsEn + 1] = string.format("≈ %.4f %s per attempt", step.cost, step.costUnit)
	else
		parts[#parts + 1] = "цену проверить не удалось (нет снимка курсов для этой лиги)"
		partsEn[#partsEn + 1] = "the price could not be checked (no price snapshot for this league)"
	end
	if step.chancePerAttempt then
		parts[#parts + 1] = string.format("шанс %.2f %%", (tonumber(step.chancePerAttempt) or 0) * 100)
		partsEn[#partsEn + 1] = string.format("%.2f%% chance", (tonumber(step.chancePerAttempt) or 0) * 100)
	end
	if step.attemptsFor90 then
		parts[#parts + 1] = string.format("до 90 %% нужно попыток: %s", tostring(step.attemptsFor90))
		partsEn[#partsEn + 1] = string.format("attempts needed for 90%%: %s", tostring(step.attemptsFor90))
	end
	step.costLine = table.concat(parts, " · ")
	step.costLineEn = table.concat(partsEn, " · ")

	-- The two things an experienced crafter says out loud and a probability table never does: how much
	-- money the whole attempt takes, and when to walk away. Both are derived from numbers that are already
	-- here (cost per attempt, attempts for 90%), so this is a sentence, not a new model.
	if step.cost then
		local attempts = tonumber(step.attemptsFor90) or tonumber(step.chancePerAttempt) and 1 or nil
		if attempts then
			local budget = (tonumber(step.cost) or 0) * attempts
			step.budget90 = budget
			step.budgetLine = string.format(
				"если идти до 90 %%, на этот шаг уйдёт ≈ %s %s — это и есть цена «попробовать как следует»",
				string.format("%.4f", budget):gsub("0+$", ""):gsub("%.$", ""), tostring(step.costUnit or ""))
			step.budgetLineEn = string.format(
				"going all the way to 90%% costs about %s %s - that is what 'trying properly' means here",
				string.format("%.4f", budget):gsub("0+$", ""):gsub("%.$", ""), tostring(step.costUnit or ""))
			-- The stop rule a person uses: the craft must stay cheaper than the finished item, and the
			-- honest way to say it without knowing that price is to name the threshold.
			step.stopRule = string.format(
				"стоп-правило: если готовый предмет в трейде дешевле ≈ %s %s — этот шаг не окупится, "
					.. "бросайте и покупайте",
				string.format("%.4f", budget):gsub("0+$", ""):gsub("%.$", ""), tostring(step.costUnit or ""))
			step.stopRuleEn = string.format(
				"stop rule: if the finished item is cheaper than about %s %s in trade, this step does not pay "
					.. "off - stop and buy it",
				string.format("%.4f", budget):gsub("0+$", ""):gsub("%.$", ""), tostring(step.costUnit or ""))
		end
	end
	return step
end

--- Everything the interface needs for one screen.
function Coach.report(item, advice, rawText)
	local state = Coach.state(item, rawText)
	-- The memory is read before the step is chosen, because what happened last time decides what to
	-- do this time - that is the whole point of the step loop.
	local memory = Memory.load()
	local review = nil
	if memory and memory.fingerprint == Memory.fingerprint(item) then
		review = {
			sameItem = true,
			verdict = (function()
				local changes = Memory.compare(memory.mods or { }, Memory.mods(item))
				if #changes.added == 0 and #changes.removed == 0 then return "nothing" end
				if #changes.added > #changes.removed then return "progress" end
				if #changes.removed > #changes.added then return "loss" end
				return "swap"
			end)(),
			changes = Memory.compare(memory.mods or { }, Memory.mods(item)),
			previousStep = memory.step or "",
			previousStepIndex = tonumber(memory.stepIndex) or 1,
			before = memory.mods or { },
		}
	else
		review = { sameItem = false, first = true, previousStep = (memory or { }).step or "" }
		if memory then
			-- Another item: the remembered steps belong to it, not to what is in hand now.
			Memory.clear()
		end
	end
	review.after = Memory.mods(item)

	local step = enrich(Coach.step(item, advice, state, review), advice)
	-- Remember the item as it is now, together with what was recommended for it.
	Memory.save(Memory.fingerprint(item), review.after, step)
	return {
		state = state,
		warnings = Coach.warnings(item, rawText, state),
		step = step,
		review = review,
	}
end

return Coach