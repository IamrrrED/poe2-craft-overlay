-- PoE2 Craft Overlay : Craft/ModPool.lua
-- "What can still land on this item, how often, and which of it is worth hunting" - for the details panel.
--
-- The pool itself is not computed here: Mods.rollPool already answers it from the base-specific tier weights and
-- the item level, and it is what the adviser uses for its odds. This module only groups that answer into families,
-- scores it against the player's goal, and keeps the claims honest:
--   * "chance" is the share of the roll weight at this item level (a rarity number, not a price);
--   * "wanted" is our judgement for THIS goal, and it is labelled as such;
--   * price is not invented - the slot says "not checked" until a market pass fills it.
local Mods = require("Item.Mods")
local Ru = require("Item.Ru")

local ModPool = { }

-- Families are matched on the stat text as the data prints it (English), which is stable across bases. Order is
-- the order the panel shows them in: the things a crafter looks for first. A family lists several substrings
-- because the game words the same idea differently ("to all Attributes", "+X to Strength", "reduced Attribute
-- Requirements") and a single keyword quietly pushed most of the pool into "Other".
ModPool.families = {
	{ id = "resist", ru = "Сопротивления", en = "Resistances", patterns = { "resistance" } },
	{ id = "es", ru = "Энергощит", en = "Energy shield", patterns = { "energy shield" } },
	{ id = "life", ru = "Здоровье", en = "Life", patterns = { "maximum life", " life ", "life regeneration" } },
	{ id = "mana", ru = "Мана", en = "Mana", patterns = { "maximum mana", " mana ", "mana regeneration" } },
	{ id = "damage", ru = "Урон", en = "Damage", patterns = { "damage", "attack", "spell" } },
	{ id = "crit", ru = "Критические", en = "Critical", patterns = { "critical" } },
	{ id = "speed", ru = "Скорость", en = "Speed", patterns = { "speed" } },
	{ id = "attributes", ru = "Характеристики", en = "Attributes",
		patterns = { "strength", "dexterity", "intelligence", "attribute" } },
	{ id = "defence", ru = "Защита", en = "Defence",
		patterns = { "armour", "evasion", "block", "stun threshold" } },
	{ id = "utility", ru = "Полезное", en = "Utility", patterns = { "rarity", "accuracy", "movement" } },
	{ id = "other", ru = "Прочее", en = "Other", patterns = { } },
}

-- Which families the goals care about. A goal is a short id from the panel context ("res", "es", "damage", ...);
-- an unknown or empty goal falls back to the general order, so nothing is claimed that the player did not ask for.
ModPool.goalFamilies = {
	res = { resist = 2.0, life = 1.2 },
	es = { es = 2.0, resist = 1.3 },
	life = { life = 2.0, resist = 1.2 },
	damage = { damage = 2.0, crit = 1.5, speed = 1.2 },
	speed = { speed = 2.0, damage = 1.2 },
	attributes = { attributes = 2.0 },
	mana = { mana = 1.6, es = 1.1 },
}

-- With no stated goal there is still something to highlight, because "what is worth hunting" has a general
-- answer: defences first, then offence. Kept deliberately milder than an explicit goal so it never looks like
-- the player asked for something they did not.
ModPool.defaultBoosts = { resist = 1.5, life = 1.4, es = 1.3, damage = 1.2, speed = 1.1, crit = 1.1 }

local function familyOf(text)
	local lower = tostring(text or ""):lower()
	for _, family in ipairs(ModPool.families) do
		for _, pattern in ipairs(family.patterns or { }) do
			if lower:find(pattern, 1, true) then
				return family
			end
		end
	end
	return ModPool.families[#ModPool.families]
end

local function boostFor(familyId, goal)
	local table_ = ModPool.goalFamilies[tostring(goal or ""):lower()]
	if not table_ then
		-- No goal given: fall back to the general "defences, then offence" preference rather than highlighting
		-- nothing at all.
		return ModPool.defaultBoosts[familyId] or 1
	end
	return table_[familyId] or 1
end

--- Build the pool for one item.
-- @param item parsed item (ilvl, baseType, mods)
-- @param opts { goal = "res"|"es"|..., hints = {...} }
-- @return table { sides = { prefix = {...}, suffix = {...} }, wanted = {...}, note = {...} }
function ModPool.forItem(item, opts)
	opts = opts or { }
	local ilvl = tonumber(item and item.itemLevel) or 0
	local baseName = item and (item.baseType or item.name) or nil
	local goal = opts.goal

	-- The pool is meaningless without the spawn tags of the base: eligibility is decided from them, and without
	-- hints an entire side can come back empty. Deriving them here means a caller cannot forget.
	-- Which language the caller asked for: the stat lines are the game's text, so Russian replies translate them
	-- where the dictionary knows the sentence.
	local wantsRussian = tostring(opts.lang or "ru"):lower() ~= "en"

	local hints = opts.hints
	if hints == nil and item then
		hints = Mods.hintsFor(item)
	end

	-- Modifiers the item already carries cannot land again: their groups are excluded and their exact wording is
	-- excluded too (the same sentence can live in another group).
	local excludeGroups, excludeTexts = { }, { }
	for _, mod in ipairs((item and item.mods) or { }) do
		if mod.groupKey then
			excludeGroups[mod.groupKey] = true
		end
		if mod.text then
			excludeTexts[mod.text] = true
		end
	end

	local result = { sides = { }, wanted = { }, goal = goal, ilvl = ilvl, families = { } }
	for _, family in ipairs(ModPool.families) do
		-- One name in the language that was asked for: the gate's twin handling would drop both if the key naming
		-- ever drifted, and a missing label is worse than a duplicated one.
		result.families[#result.families + 1] = { id = family.id, name = wantsRussian and family.ru or family.en }
	end

	for _, side in ipairs({ "prefix", "suffix" }) do
		local pool = Mods.rollPool(ilvl, hints, {
			baseName = baseName,
			side = side,
			excludeGroups = excludeGroups,
			excludeTexts = excludeTexts,
			sources = opts.sources,
		}) or { groups = { }, totalWeight = 0 }

		local byFamily = { }
		local groups = { }
		for _, group in ipairs(pool.groups or { }) do
			local family = familyOf(group.bestText)
			local boost = boostFor(family.id, goal)
			-- The stat line is the game's text, so it is shown as the client would: translated when the dictionary
			-- knows the sentence, verbatim otherwise (and then marked, so the page can tell the difference).
			local text = group.bestText
			if wantsRussian then
				local okRu, russian = pcall(Ru.toRussian, tostring(text or ""))
				if okRu and type(russian) == "string" and russian ~= "" and russian ~= text then
					text = russian
				end
			end
			local entry = {
				family = family.id,
				bestText = text,
				bestTextSource = (text ~= group.bestText) and "dictionary" or "game",
				bestTier = group.bestTier,
				tierCount = group.tierCount,
				chance = group.chance,
				weightSource = group.weightSource,
				-- "wanted" is a judgement, not a measurement: family fit for the goal, sharpened by how many
				-- tiers exist (a family with one tier is not a hunt) and by the raw chance of landing it.
				score = boost * (1 + math.min(tonumber(group.tierCount) or 1, 4) / 8)
					* (0.5 + (tonumber(group.chance) or 0) / 20),
				boost = boost,
			}
			groups[#groups + 1] = entry
			byFamily[family.id] = (byFamily[family.id] or 0) + (tonumber(group.chance) or 0)
		end
		table.sort(groups, function(left, right)
			if left.score == right.score then
				return (left.chance or 0) > (right.chance or 0)
			end
			return left.score > right.score
		end)

		result.sides[side] = {
			totalWeight = pool.totalWeight or 0,
			groupCount = #groups,
			groups = groups,
			byFamily = byFamily,
		}
	end

	-- The headline: the few best entries across both sides. It is what the card can show without a wall of text,
	-- and it is ordered by the goal first and by the score second - a "resistances" goal must not open with a
	-- life modifier that merely happens to be common. Never ordered by an invented price.
	local wanted = { }
	for _, side in ipairs({ "prefix", "suffix" }) do
		for _, group in ipairs(result.sides[side].groups or { }) do
			if (group.boost or 1) > 1 and (tonumber(group.chance) or 0) > 0 then
				wanted[#wanted + 1] = {
					side = side,
					family = group.family,
					bestText = group.bestText,
					bestTier = group.bestTier,
					chance = group.chance,
					tierCount = group.tierCount,
					score = group.score,
					boost = group.boost,
				}
			end
		end
	end
	table.sort(wanted, function(left, right)
		if (left.boost or 1) ~= (right.boost or 1) then
			return (left.boost or 1) > (right.boost or 1)
		end
		return (left.score or 0) > (right.score or 0)
	end)
	-- At most two entries per family: the three elemental resistances are three groups with almost the same
	-- wording, and letting them take the whole headline hides the other families the player could also hunt.
	local perFamily, capped = { }, { }
	for _, entry in ipairs(wanted) do
		local count = perFamily[entry.family] or 0
		if count < 2 then
			perFamily[entry.family] = count + 1
			capped[#capped + 1] = entry
		end
		if #capped >= 7 then
			break
		end
	end
	result.wanted = capped

	result.price = {
		checked = false,
		noteRu = "цена не проверялась: это локальный расчёт по весам, без запроса к трейду",
		noteEn = "price not checked: this is a local calculation from the weights, no trade request",
	}
	return result
end

return ModPool
