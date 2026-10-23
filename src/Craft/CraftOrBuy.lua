-- PoE2 Craft Overlay : Craft/CraftOrBuy.lua
-- "Should I craft this at all?" - the one question every guide says to answer BEFORE spending.
--
-- What this can and cannot do, stated plainly because the difference matters:
--
--   CAN:  the expected cost of a craft, exactly. We have the modifier weights (Craft of Exile and Path of
--         Building), the success chance per attempt, and live currency prices, so "≈ 3.4 div and 30 attempts
--         for 90%" is arithmetic on real numbers.
--
--   CANNOT: the price of a FINISHED item. The price snapshot covers currencies, runes, essences, ritual,
--         breach, verisium and soul cores - it has never carried rare items, and there is no public feed for
--         "what a rare with these three modifiers sells for" (rares are unique per item, so trade prices them
--         one listing at a time). Comparing a computed number against an invented one would be the worst
--         thing this mentor could do.
--
-- So the honest shape of the advice is: here is what the craft costs, and here is EXACTLY what to search in
-- trade to compare, plus the rule for the decision. A beginner who runs the search once learns the habit; a
-- beginner given a fabricated "buy price" learns to trust nonsense.
local CraftOrBuy = { }

--- The cheapest route to a useful outcome on this item, by expected cost.
--
-- Only FULLY priced routes are eligible. A route whose total is missing a component (a desecration bone, a
-- catalyst the snapshot does not carry) has a number that is a lower bound, and ranking a lower bound as
-- "cheapest" is how a beginner gets told that the expensive route is the cheap one. Those routes are reported
-- separately so the panel can say "unknown price" instead of a false number.
-- @param advice advisor result (its craftSummary carries the priced methods)
-- @return table|nil { method, chance, expectedAttempts, expectedCost, costFor90, attemptsFor90 }
function CraftOrBuy.cheapest(advice)
	local summary = advice and advice.craftSummary
	if type(summary) ~= "table" then
		return nil
	end
	local best = nil
	for _, entry in ipairs(summary.entries or { }) do
		if entry.applicable ~= false and entry.expectedCost and entry.expectedCost.chaos
			and not entry.costIncomplete
			and (best == nil or entry.expectedCost.chaos < best.expectedCost.chaos) then
			best = {
				method = tostring(entry.label or entry.method or ""),
				chance = entry.chancePerAttempt,
				expectedAttempts = entry.expectedAttempts,
				expectedCost = entry.expectedCost,
				costFor90 = entry.costFor90,
				attemptsFor90 = entry.attemptsFor90,
				weightSource = entry.weightSource,
			}
		end
	end
	return best
end

--- Routes that cannot be priced because the snapshot lacks a component.
-- @param advice advisor result
-- @return list of { method, missing = { names } }
function CraftOrBuy.unpricedRoutes(advice)
	local summary = advice and advice.craftSummary
	if type(summary) ~= "table" then
		return { }
	end
	local out = { }
	for _, entry in ipairs(summary.entries or { }) do
		if entry.applicable ~= false and entry.unpriced and #entry.unpriced > 0 then
			out[#out + 1] = {
				method = tostring(entry.label or entry.method or ""),
				missing = entry.unpriced,
			}
		end
	end
	return out
end

--- What to type into trade to find a comparable finished item.
--
-- The recipe is built from the item's OWN modifiers, so it searches for what the player is trying to make
-- rather than for something generic: same class, at least this item level, and the modifiers already on the
-- item as stat filters. Tiers are included because a search without them returns items that are not
-- comparable, which is how beginners talk themselves into a bad comparison.
--
-- Annotation lines are skipped. The captured text carries them as their own lines (`{ Prefix Modifier "X"
-- (Tier: 2) }`), and an early version of this listed them as separate "modifiers" - a search for a line that
-- no trade filter understands returns nothing, and the player would conclude the item does not exist.
-- @param item parsed item
-- @return { class, itemLevel, rarity, stats = { ... }, note }
function CraftOrBuy.searchRecipe(item)
	local stats, seen = { }, { }
	for _, bucket in ipairs({ item.explicitMods or { }, item.implicitMods or { } }) do
		for _, mod in ipairs(bucket) do
			local text = type(mod) == "table" and mod.text or mod
			local info = type(mod) == "table" and mod.mod or nil
			-- A real modifier line never starts with the annotation brace.
			local isAnnotation = type(text) == "string" and text:sub(1, 1) == "{"
			if type(text) == "string" and text ~= "" and not isAnnotation and not seen[text] then
				seen[text] = true
				stats[#stats + 1] = {
					text = text,
					tier = info and info.tier or nil,
					type = info and info.type or nil,
				}
			end
		end
	end
	return {
		class = item.itemClass,
		itemLevel = item.itemLevel,
		rarity = item.rarity,
		stats = stats,
		note = "Ищите предмет того же класса и редкости, с тем же уровнем предмета и этими модами "
			.. "(не ниже тира). Без фильтров поиск вернёт несравнимые предметы.",
		noteEn = "Search for an item of the same class and rarity, with the same item level and these "
			.. "modifiers (not below the tier). Without filters the search returns items that are not "
			.. "comparable.",
	}
end

--- A price, with enough precision to be readable at its own scale.
--
-- Craft costs and market prices live on wildly different scales: a craft may cost 0.11 chaos while a cheap rare
-- sells for 0.0142. Printing everything to two decimals showed 0.01, which reads as "worthless" when the real
-- figure is 0.0142 - and for a comparison whose whole point is a 20% margin, that rounding can flip the verdict.
-- @param value number in chaos
-- @return string
local function money(value)
	local number = tonumber(value) or 0
	if number == 0 then
		return "0"
	end
	local formatted
	if number >= 10 then
		formatted = string.format("%.1f", number)
	elseif number >= 1 then
		formatted = string.format("%.2f", number)
	else
		formatted = string.format("%.4f", number)
	end
	-- "0.1100" and "137.0" both read worse than "0.11" and "137" to someone scanning a card, so the padding
	-- zeros go - but the decimal point goes only when nothing is left after it.
	formatted = formatted:gsub("0+$", "")
	formatted = formatted:gsub("%.$", "")
	return formatted
end

--- Compare a craft against a price the PLAYER looked up.
--
-- This is how the missing half of the question gets answered honestly. We cannot fetch what a rare with these
-- modifiers sells for - no feed prices individual rares - but the player can look it up in trade and type the
-- number. Then the comparison is real arithmetic on our computed cost and his observed price, and the source of
-- the price is stated rather than implied.
--
-- The margin matters: our cost is an AVERAGE, so a craft that is 5% cheaper than the market is a coin flip, not
-- a saving. The verdict only calls it when the difference is large enough to survive the variance.
-- @param buyPriceChaos the market price, in chaos
-- @param advice advisor result
-- @return table|nil { craftCost, buyPrice, verdict, difference, margin, text, note }
function CraftOrBuy.compare(buyPriceChaos, advice)
	local price = tonumber(buyPriceChaos)
	if not price or price < 0 then
		return nil
	end
	local cheapest = CraftOrBuy.cheapest(advice)
	if not cheapest or not cheapest.expectedCost or not cheapest.expectedCost.chaos then
		return nil
	end
	local craft = tonumber(cheapest.expectedCost.chaos) or 0
	if craft <= 0 then
		return nil
	end
	-- How far apart they are, as a fraction of the craft cost.
	local margin = (craft - price) / craft
	local verdict, text, textEn
	if margin > 0 then
		-- The market is cheaper than the craft.
		if margin >= 0.2 then
			verdict = "buy"
			text = "Покупайте: готовый предмет дешевле крафта примерно на "
				.. string.format("%.0f%%", margin * 100) .. "."
			textEn = "Buy: the finished item is cheaper than the craft by about "
				.. string.format("%.0f%%", margin * 100) .. "."
		else
			verdict = "either"
			text = "Разница небольшая (" .. string.format("%.0f%%", margin * 100) .. ") — это в пределах "
				.. "разброса, так что решайте по удобству: крафт даёт свои моды, покупка — сразу."
			textEn = "The difference is small (" .. string.format("%.0f%%", margin * 100) .. ") - that is "
				.. "within the variance, so decide on convenience: the craft gives its own modifiers, the "
				.. "purchase gives them at once."
		end
	else
		local saving = -margin
		if saving >= 0.2 then
			verdict = "craft"
			text = "Крафтите: готовый предмет дороже крафта примерно на "
				.. string.format("%.0f%%", saving * 100) .. "."
			textEn = "Craft: the finished item is more expensive than the craft by about "
				.. string.format("%.0f%%", saving * 100) .. "."
		else
			verdict = "either"
			text = "Разница небольшая (" .. string.format("%.0f%%", saving * 100) .. ") — это в пределах "
				.. "разброса, так что решайте по удобству."
			textEn = "The difference is small (" .. string.format("%.0f%%", saving * 100) .. ") - that is "
				.. "within the variance, so decide on convenience."
		end
	end
	return {
		craftCost = craft,
		buyPrice = price,
		verdict = verdict,
		difference = craft - price,
		margin = margin,
		text = text,
		textEn = textEn,
		method = cheapest.method,
		-- Said out loud, because the number the player just typed into the decision is an average.
		note = "Стоимость крафта — это СРЕДНЕЕ по шансам, а не гарантия: часть попыток выйдет дешевле, "
			.. "часть дороже. Цену готового предмета вы посмотрели сами — панель её не проверяет.",
		noteEn = "The craft cost is an AVERAGE over the chances, not a guarantee: some attempts come out "
			.. "cheaper, some dearer. The finished item's price is the one the player looked up - the panel "
			.. "does not verify it.",
	}
end

--- One line for the panel: what to do, given a price the player typed.
-- @param buyPriceChaos the market price in chaos
-- @param advice advisor result
-- @return table|nil same shape as compare, with a ready-to-show sentence
function CraftOrBuy.verdictFor(buyPriceChaos, advice, args)
	local result = CraftOrBuy.compare(buyPriceChaos, advice)
	if not result then
		return nil
	end
	-- The card offers the trade search this verdict was built from (or the closest one tried): a loose
	-- match should be checkable in one click instead of "look it up on the trade site".
	if type(args) == "table" and type(args.market_url) == "string" and args.market_url ~= "" then
		result.marketUrl = args.market_url
	end
	result.line = string.format("Крафт ~%s хаоса · готовый %s хаоса · %s",
		money(result.craftCost), money(result.buyPrice), result.text)
	result.lineEn = string.format("Craft ~%s chaos | finished %s chaos | %s",
		money(result.craftCost), money(result.buyPrice), result.textEn)
	return result
end

-- Exposed so the panel can print a price the same way the line does.
CraftOrBuy.money = money

--- The decision block for the step card.
-- @param item parsed item
-- @param advice advisor result
-- @return table|nil { hasCost, costLine, cheapest, unpriced, recipe, rule, pricesAsOf }
function CraftOrBuy.forItem(item, advice, extras)
	if not item then
		return nil
	end
	-- A full item cannot take another modifier, so a "cost of the cheapest way to add one" is meaningless there:
	-- the cheapest route is the one you cannot take. Reporting 0.03 chaos for an Exalted Orb on a 3/3 amulet
	-- reads as "you can improve this cheaply" when in fact nothing can be added at all.
	local caps = item.affixCaps
	local prefixes = tonumber(item.prefixCount) or 0
	local suffixes = tonumber(item.suffixCount) or 0
	local hasRoom = true
	if type(caps) == "table" then
		hasRoom = prefixes < (tonumber(caps.prefixes) or 3) or suffixes < (tonumber(caps.suffixes) or 3)
	end
	local cheapest = hasRoom and CraftOrBuy.cheapest(advice) or nil
	local unpriced = hasRoom and CraftOrBuy.unpricedRoutes(advice) or { }
	local recipe = CraftOrBuy.searchRecipe(item)
	-- The age of the prices travels with the numbers. A cost computed from a snapshot weeks old is still the
	-- best we have, but a beginner must not treat it as today's market - and saying so is cheaper than being
	-- wrong confidently.
	local info = (require("Craft.Prices").info() or { })
	-- The rule is the point. It is stated even when no cost is known, because it is what the guides teach
	-- and what a beginner has to internalise: compare, then decide - do not craft on faith.
	local rule = "Правило простое: если готовый предмет в трейде дешевле ожидаемой стоимости крафта — "
		.. "покупайте. Крафт оправдан, когда нужных модов в продаже нет или они дороже."
	local ruleEn = "The rule is simple: if the finished item in trade is cheaper than the expected craft "
		.. "cost - buy. The craft is justified when the modifiers you need are not on sale or cost more."
	return {
		hasCost = cheapest ~= nil,
		-- The trade search the price came from (or the closest one tried). The card turns it into a button, so
		-- a loose match can be checked in one click instead of "look it up on the trade site".
		marketUrl = (extras and extras.marketUrl) or info.marketUrl,
		-- Why there is no cost, when there is none because the item is full rather than because prices are
		-- missing. The panel turns this into a sentence instead of an empty gap.
		fullItem = not hasRoom,
		cheapest = cheapest,
		unpriced = unpriced,
		recipe = recipe,
		rule = rule,
		ruleEn = ruleEn,
		pricesAsOf = info.fetchedAt,
		-- A full item needs a different sentence: not "we have no price" but "there is nothing left to
		-- add". Reporting a cheap Exalted Orb on a 3/3 item reads as "you can improve this cheaply".
		fullNote = (not hasRoom) and ("Свободных аффиксов нет: добавить мод некуда. Остаются качество, "
			.. "переброс чисел Divine и необратимый Vaal последним шагом.") or nil,
		fullNoteEn = (not hasRoom) and ("No free affixes: there is nowhere to add a modifier. What is left "
			.. "is quality, a Divine number reroll and an irreversible Vaal as the last step.") or nil,
		-- The "currency prices are a snapshot from ..." line was removed on request: it explained our own
		-- bookkeeping to the player instead of telling them anything about the item, and it took the place
		-- where the actual answer belongs.
	}
end

return CraftOrBuy
