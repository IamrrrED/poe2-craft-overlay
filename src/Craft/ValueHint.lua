-- PoE2 Craft Overlay : Craft/ValueHint.lua
-- Which of the candidate modifiers is worth chasing, and what actually raises the chance of getting it.
--
-- The advisor already ranks candidates by the player's goal (Craft/ModPool.lua, the `wanted` list) and already knows
-- which techniques exist (Craft/Techniques.lua). What was missing is the sentence a person says next: "this one is the
-- money modifier - if you want it more often, use X, and here is what X costs you".
--
-- This module only arranges facts that already exist. It invents no price and no probability: the chance it prints is
-- the chance it was handed, and a boost is printed only when a technique explicitly matches that family.

local ValueHint = { }

--- A modifier is worth highlighting when it carries a real goal boost.
-- boost comes from ModPool: 1 means "same as any other modifier for this goal", above 1 means the player's goal
-- favours it. The threshold is 1 so a neutral family is never dressed up as valuable.
ValueHint.MIN_BOOST = 1.05

--- Boosts that are known to target a family, with the cost of using them.
-- Kept as data with an explicit `family` field: a technique is only attached to a family it names, so the panel can
-- never claim that an omen helps a modifier it has nothing to do with.
ValueHint.BOOSTS = {
	{
		family = "life",
		action = "Omen of Homogenising Exaltation + Exalted Orb",
		actionEn = "Omen of Homogenising Exaltation + Exalted Orb",
		effect = "мод той же группы, что уже есть на предмете — шанс попасть в жизнь резко выше",
		effectEn = "a modifier of the same group as one already on the item, so life is far more likely",
		risk = "если на предмете несколько групп, гарантии нет",
		riskEn = "if the item carries several groups, nothing is guaranteed",
	},
	{
		family = "resistance",
		action = "Omen of Homogenising Exaltation + Exalted Orb",
		actionEn = "Omen of Homogenising Exaltation + Exalted Orb",
		effect = "подтягивает сопротивления, когда на предмете уже есть сопротивление",
		effectEn = "pulls resistances when the item already has one",
		risk = "считаются группы обеих сторон",
		riskEn = "groups on both sides count",
	},
}

--- Attach the boosts that name a family.
-- @param family family name of a wanted entry (e.g. "life", "resistance")
-- @return array of boosts (possibly empty)
function ValueHint.boostsFor(family, boosts)
	local source = boosts or ValueHint.BOOSTS
	local found = { }
	local wanted = tostring(family or ""):lower()
	if wanted == "" then
		return found
	end
	for _, boost in ipairs(source) do
		local key = tostring(boost.family or ""):lower()
		if key ~= "" and (key == wanted or wanted:find(key, 1, true) or key:find(wanted, 1, true)) then
			found[#found + 1] = {
				action = boost.action,
				actionEn = boost.actionEn or boost.action,
				effect = boost.effect,
				effectEn = boost.effectEn or boost.effect,
				risk = boost.risk,
				riskEn = boost.riskEn or boost.risk,
			}
		end
	end
	return found
end

--- Split the wanted list into "worth chasing" and "the rest", and give each valuable one its boost.
-- @param wanted entries from ModPool's `wanted` (fields: side, family, bestText, chance, score, boost).
--   `chance` is a PERCENTAGE, the same unit the advisor uses (Advisor computes 100/affixes and 100/prefixCount),
--   so it travels to the card untouched - a fraction would need converting, a percentage must not be.
-- @param options { minBoost = number, boosts = table }
-- @return { valuable = {...}, others = {...}, boosts = {...} } - never nil, so the card can draw it unconditionally
function ValueHint.forWanted(wanted, options)
	local settings = type(options) == "table" and options or { }
	local minBoost = tonumber(settings.minBoost) or ValueHint.MIN_BOOST
	local result = { valuable = { }, others = { }, boosts = { }, minBoost = minBoost }
	if type(wanted) ~= "table" then
		return result
	end
	for _, entry in ipairs(wanted) do
		if type(entry) == "table" then
			local boost = tonumber(entry.boost) or 1
			local item = {
				side = entry.side,
				family = entry.family,
				bestText = entry.bestText,
				tradeText = entry.tradeText,
				chance = tonumber(entry.chance),
				score = tonumber(entry.score),
				boost = boost,
			}
			if boost >= minBoost then
				item.chasing = true
				item.boosts = ValueHint.boostsFor(entry.family, settings.boosts)
				result.valuable[#result.valuable + 1] = item
				for _, boostEntry in ipairs(item.boosts) do
					result.boosts[#result.boosts + 1] = boostEntry
				end
			else
				result.others[#result.others + 1] = item
			end
		end
	end
	-- Best chance first: the card highlights the one that is both wanted and reachable, not the rarest dream.
	table.sort(result.valuable, function(left, right)
		local leftChance = left.chance or 0
		local rightChance = right.chance or 0
		if leftChance ~= rightChance then
			return leftChance > rightChance
		end
		return (left.boost or 1) > (right.boost or 1)
	end)
	return result
end

--- One sentence for the card: what to chase and how to raise its chance.
-- Returns nil when there is nothing valuable, so the panel can skip the block entirely.
function ValueHint.summary(hints, language)
	local data = type(hints) == "table" and hints or { }
	local valuable = data.valuable or { }
	if #valuable == 0 then
		return nil
	end
	local english = tostring(language or ""):lower():sub(1, 2) == "en"
	local first = valuable[1]
	local boost = (first.boosts or { })[1]
	local text
	if english then
		text = string.format("chase %s", tostring(first.bestText or first.family or "the goal modifier"))
		if boost then
			text = text .. string.format(" - %s raises its chance (%s)", boost.actionEn or boost.action,
				boost.effectEn or boost.effect or "")
		end
	else
		text = string.format("цель — %s", tostring(first.bestText or first.family or "нужный мод"))
		if boost then
			text = text .. string.format("; шанс выше через %s (%s)", boost.action, boost.effect or "")
		end
	end
	return text
end

return ValueHint
