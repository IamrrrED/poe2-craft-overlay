-- PoE2 Craft Overlay : Craft/Advisor.lua
-- Turns a parsed item + a league ruleset into concrete MIN / MAX crafting plans.
--
-- Design notes:
--  * Rules are data (see Data/league_<ver>.lua); this module only evaluates them.
--  * Every step is resolved against the currency catalog, so the UI gets a title,
--    a one-line description (Russian for files/console, ASCII English for the panel,
--    because the host's bitmap fonts have no Cyrillic glyphs) and a cost tier.
--  * Anything uncertain is surfaced (blockers / warnings / notes) instead of being
--    silently smoothed over - a crafting advisor that guesses is worse than none.

local util = require("Core.util")
local i18n = require("Core.i18n")
local Strings = require("Core.strings")
local RulesRu = require("Data.rules_ru")
local Mods = require("Item.Mods")
local Essences = require("Item.Essences")
local Runes = require("Item.Runes")
local Runeforging = require("Item.Runeforging")

local Advisor = { }

-- A rare in PoE2 carries at most 3 prefixes + 3 suffixes.
local MAX_AFFIXES = 6

local function affixCount(item)
	-- Total affix count is always reliable; the prefix/suffix *split* is not, and is
	-- handled separately via item.affixSplitComplete.
	return #item.explicitMods + #item.craftedMods + #item.desecratedMods
end

--- Does a rule's `when` clause match the item?
local function matches(when, item, affixes)
	if when.rarity and when.rarity ~= item.rarity then
		return false
	end
	-- A rule that reasons from the number of affixes must not fire when that number is not known.
	-- The client's own language decides it: on a Russian item several modifier lines stay
	-- untranslated, so classification saw three prefixes where the item really carries six affixes -
	-- and the "a slot is open" rule matched with nil affixes (in Lua nil > 5 is simply false), which
	-- offered an Exalted Orb for a full item. Withholding the rule is the honest answer; the
	-- full-item rule below has no affix condition and still matches.
	-- Rules that depend on how many slots are free state `requireSplit`: they are skipped while the
	-- prefix/suffix split is unknown, because acting on a guessed slot count is how a Regal Orb gets
	-- offered for an item that may already be full.
	if when.requireSplit and item.affixSplitComplete ~= true then
		return false
	end
	if when.maxAffixes and item.affixSplitComplete ~= true then
		return false
	end
	if when.maxAffixes and affixes > when.maxAffixes then
		return false
	end
	if when.minAffixes and affixes < when.minAffixes then
		return false
	end
	-- Open affix slots (only known when the modifier data classified the item).
	if when.maxOpenPrefixes and (item.openPrefixes == nil or item.openPrefixes > when.maxOpenPrefixes) then
		return false
	end
	if when.minOpenPrefixes and (item.openPrefixes == nil or item.openPrefixes < when.minOpenPrefixes) then
		return false
	end
	if when.maxOpenSuffixes and (item.openSuffixes == nil or item.openSuffixes > when.maxOpenSuffixes) then
		return false
	end
	if when.minOpenSuffixes and (item.openSuffixes == nil or item.openSuffixes < when.minOpenSuffixes) then
		return false
	end
	if when.minItemLevel and (item.itemLevel or 0) < when.minItemLevel then
		return false
	end
	if when.maxItemLevel and (item.itemLevel or math.huge) > when.maxItemLevel then
		return false
	end
	if when.itemClassMatch and not tostring(item.itemClass or ""):find(when.itemClassMatch, 1, true) then
		return false
	end
	if when.anyFlag then
		local hit = false
		for _, flag in ipairs(when.anyFlag) do
			if item.flags[flag] then
				hit = true
				break
			end
		end
		if not hit then
			return false
		end
	end
	return true
end

local function resolveStep(ruleset, currencyId)
	local currency = ruleset.currencies[currencyId]
	if not currency then
		return {
			id = currencyId,
			ru = currencyId,
			en = currencyId,
			effect = "no description in the ruleset",
			effectEn = "no description in the ruleset",
			cost = "?",
			status = "unverified",
			adds = 0,
			removes = 0,
			minModLevel = 0,
			side = "any",
		}
	end
	return {
		id = currencyId,
		en = currency.en,
		effect = currency.effectEn or currency.effect,
		effectEn = currency.effectEn or currency.effect,
		cost = currency.cost,
		status = currency.status,
		-- Machine-readable behaviour, used by the probability engine.
		adds = currency.adds or 0,
		removes = currency.removes or 0,
		minModLevel = currency.minModLevel or 0,
		side = currency.side or "any",
		guaranteed = currency.guaranteed,
		-- A step can carry its own warning (the Vaal Orb does: one-way, and it can destroy the craft).
		-- It used to be dropped here, so the risk never reached the card even when the data stated it.
		warning = currency.warning,
		warningEn = currency.warningEn,
		-- The ruleset writes its descriptions in English; Data/rules_ru.lua holds the Russian side, keyed
		-- by the English sentence. Without it the Russian card showed "As Exalted, with a minimum modifier
		-- level of 35" instead of the sentence.
		effectRu = currency.effectRu or RulesRu.text(currency.effectEn or currency.effect),
		warningRu = RulesRu.text(currency.warningEn or currency.warning),
	}
end

--- Attach odds to a step: which modifiers a random add can produce (with chances)
-- and, for removal steps, the chance of hitting a given modifier.
local function attachOdds(step, context)
	if not context or not context.ilvl then
		return
	end

	if step.adds > 0 then
		local side = (step.side ~= "any" and step.side) or context.side
		step.pool = Mods.rollPool(context.ilvl, context.hints, { baseName = context.baseType,
			side = side,
			minModLevel = step.minModLevel,
			excludeGroups = context.excludeGroups,
			sources = context.sources,
		})
		step.poolSide = side
	end

	if step.removes > 0 and (context.affixes or 0) > 0 then
		step.removal = {
			affixes = context.affixes,
			perModChance = 100 / context.affixes,
			prefixes = context.prefixCount,
			suffixes = context.suffixCount,
			prefixChance = (context.prefixCount or 0) > 0 and (100 / context.prefixCount) or 0,
			suffixChance = (context.suffixCount or 0) > 0 and (100 / context.suffixCount) or 0,
		}
	end
end

local function buildPlan(ruleset, id, title, titleEn, stepIds, reason, reasonEn, context)
	local steps = { }
	for _, currencyId in ipairs(stepIds or { }) do
		local step = resolveStep(ruleset, currencyId)
		local glossary = ruleset.glossary and ruleset.glossary[currencyId]
		local glossaryEn = ruleset.glossaryEn and ruleset.glossaryEn[currencyId]
		step.hint = glossary
		step.hintEn = glossaryEn
		if step.status == "unverified" then
			-- The unverified note is about the DATA; a step's own warning is about the RISK. Overwriting
			-- keeps both only if they are joined, so they are joined rather than one winning.
			local unverified = ruleset.warnings and ruleset.warnings.unverified
			local unverifiedEn = ruleset.warnings and ruleset.warnings.unverifiedEn
			step.warning = step.warning and (step.warning .. " " .. tostring(unverified)) or unverified
			step.warningEn = step.warningEn and (step.warningEn .. " " .. tostring(unverifiedEn)) or unverifiedEn
		end
		attachOdds(step, context)
		steps[#steps + 1] = step
	end
	return {
		id = id,
		-- English text sits in both slots: the Russian halves were removed, and keeping
		-- one empty slot only invites nil checks at the call sites.
		-- The Russian slot must win when it is filled, otherwise every plan and option loses its
		-- Russian title to the English one and the panel turns into a mixture of languages.
		title = title or titleEn,
		titleEn = titleEn or title,
		-- `reason` is what the panel prints. It used to prefer the ENGLISH text, so every explanation
		-- reached a Russian player in English even when a Russian one existed - the comment above this
		-- line said the opposite of what the code did.
		reason = reason or reasonEn,
		reasonEn = reasonEn or reason,
		steps = steps,
	}
end

--- Item state block shown at the top of the panel (English only).
local function buildState(item, affixes, lang)
	local state = { }
	state[#state + 1] = string.format("Rarity: %s", tostring(item.rarity))
	if item.itemClass then state[#state + 1] = string.format("Class: %s", item.itemClass) end
	if item.name and item.baseType and item.name ~= item.baseType then
		state[#state + 1] = string.format("%s (%s)", item.name, item.baseType)
	elseif item.name then
		state[#state + 1] = tostring(item.name)
	end
	if item.itemLevel then state[#state + 1] = string.format("Item level: %d", item.itemLevel) end
	if item.quality then state[#state + 1] = string.format("Quality: %d%%", item.quality) end
	if #item.implicitMods > 0 then state[#state + 1] = string.format("Implicits: %d", #item.implicitMods) end
	state[#state + 1] = string.format("Explicit mods: %d (open slots: %d)",
		affixes, math.max(0, MAX_AFFIXES - affixes))
	if #item.sockets > 0 then state[#state + 1] = string.format("Sockets: %d", #item.sockets) end

	local flagNames = { }
	for _, name in ipairs({ "corrupted", "doubleCorrupted", "sanctified", "mirrored", "split", "unidentified" }) do
		if item.flags[name] then
			flagNames[#flagNames + 1] = name
		end
	end
	if #flagNames > 0 then
		state[#state + 1] = "Flags: " .. table.concat(flagNames, ", ")
	end

	-- Prefix/suffix split, only when every modifier was recognised.
	if item.affixSplitComplete then
		state[#state + 1] = string.format("Affixes: %dP / %dS   open: %dP / %dS",
			item.prefixCount, item.suffixCount, item.openPrefixes, item.openSuffixes)
	end

	-- Per-modifier tiers ("~" marks a tier estimated from item level, not the value).
	for _, mod in ipairs(item.explicitMods) do
		if mod.mod then
			state[#state + 1] = string.format("T%d%s %s", mod.mod.tier, mod.mod.exact and "" or "~",
				tostring(mod.text))
		end
	end

	return state
end

--- Modifier with the lowest mod level among the item's explicit modifiers.
-- Omen of Whittling removes exactly this one, so the overlay can name it.
local function lowestLevelExplicit(item)
	local target, level = nil, nil
	for _, mod in ipairs(item.explicitMods) do
		if mod.mod then
			if not level or mod.mod.lvl < level then
				target, level = mod, mod.mod.lvl
			end
		end
	end
	return target, level
end

--- Side ("prefix"/"suffix") a modifier sits on, from its group type.
local function sideOf(mod)
	if mod and mod.mod then
		return tostring(mod.mod.type):lower()
	end
	return nil
end

--- Build the omen + currency combinations worth using on this item.
-- Each option carries the odds the omen changes: a side-locked pool for additions,
-- or the exact/deterministic removal target for removals.
local function slotForItem(item)
	local class = tostring(item.itemClass or ""):lower()
	if class == "" then
		return nil
	end
	local function has(needle) return class:find(needle, 1, true) ~= nil end
	if has("jewel") then
		return "jewel"
	end
	if has("waystone") or has("map") then
		return "waystone"
	end
	if has("amulet") or has("ring") or has("belt") then
		return "jewellery"
	end
	if has("shield") or has("helmet") or has("gloves") or has("boots") or has("body armour")
		or has("armour") or has("quiver") then
		return "armour"
	end
	if has("sword") or has("axe") or has("mace") or has("bow") or has("crossbow") or has("claw")
		or has("dagger") or has("spear") or has("staff") or has("stave") or has("wand")
		or has("sceptre") or has("scepter") or has("weapon") then
		return "weapon"
	end
	return nil
end

--- Which bone does this item need to be desecrated?
--
-- The bone decides which classes can be desecrated at all, and its grade decides how good the offered
-- modifier can be: Gnawed only fits items up to item level 64, Preserved fits anything, Ancient fits
-- anything and guarantees a modifier level of at least 40. So the advice names a concrete bone instead
-- of "a bone", which told the player nothing.
-- @return bone table from the ruleset, or nil when the class needs no bone / is unknown
local function desecrationBoneFor(ruleset, item)
	local bones = (ruleset or { }).bones
	if type(bones) ~= "table" then
		return nil
	end
	local slot = slotForItem(item)
	if not slot then
		return nil
	end
	local itemLevel = tonumber(item.itemLevel) or 0
	local best = nil
	for _, bone in ipairs(bones) do
		if bone.slot == slot and not bone.altered then
			-- Preserved and Ancient fit any item; Gnawed only the campaign ones.
			local fits = bone.grade ~= "gnawed" or itemLevel <= (bone.maxItemLevel or 64)
			-- Above the campaign cap the Gnawed bone cannot be used at all, so prefer Preserved.
			if fits and (best == nil or (itemLevel > 64 and bone.grade == "preserved")) then
				best = bone
			end
		end
	end
	return best
end

--- The distinct modifier groups present on one side of the item.
--
-- Stands in for the "tag families" the guides talk about. Our tables do not carry the guide's tag names
-- (they live in the trade site's data, not in the PoB modifier tables), so the honest proxy is the modifier
-- GROUP: a group is one family of related modifiers, which is what the Homogenising omen narrows toward.
-- @param item parsed item
-- @param side "prefix" | "suffix"
-- @return sorted list of group keys
local function tagFamiliesOnSide(item, side)
	local families, seen = { }, { }
	local wanted = tostring(side or ""):lower()
	for _, bucket in ipairs({ item.explicitMods or { }, item.implicitMods or { },
			item.craftedMods or { }, item.desecratedMods or { } }) do
		for _, mod in ipairs(bucket) do
			local info = type(mod) == "table" and mod.mod or nil
			if info and tostring(info.type or ""):lower() == wanted then
				local key = tostring(info.groupKey or "")
				if key ~= "" and not seen[key] then
					seen[key] = true
					families[#families + 1] = key
				end
			end
		end
	end
	table.sort(families)
	return families
end

local function buildOmenOptions(item, ruleset, context)
	local omens = ruleset.omens
	-- A ruleset without omens (e.g. a minimal test one) simply offers no omen advice.
	if type(omens) ~= "table" or not next(omens) then
		return { }
	end
	local options = { }
	local lang = Strings.lang

	-- option(omenId, currencyId, whyEn, extra)
	--
	-- The bilingual version passed the Russian sentence as the third argument; those
	-- arguments were removed, and this guard keeps any call site that still carries one
	-- from shifting the extra table into the wrong slot.
	local function option(omenId, currencyId, whyEn, extraOrWhyEn, maybeExtra)
		local why, extra
		if type(extraOrWhyEn) == "table" or extraOrWhyEn == nil then
			why, extra = whyEn, extraOrWhyEn
		else
			why, extra = extraOrWhyEn, maybeExtra
		end
		local omen = omens[omenId]
		local currency = ruleset.currencies[currencyId]
		if not omen or not currency then
			return nil
		end

		local entry = {
			omenId = omenId,
			currencyId = currencyId,
			omen = omen,
			currency = currency,
			-- English only: the panel used to be bilingual, and the Russian halves of
			-- these labels were dropped with the language switch.
			title = string.format("%s + %s", omen.en or omen.ru, currency.en or currency.ru),
			titleEn = string.format("%s + %s", omen.en or omen.ru, currency.en or currency.ru),
			effect = omen.effectEn or omen.effect,
			effectEn = omen.effectEn or omen.effect,
			effectRu = omen.effectRu or RulesRu.text(omen.effectEn or omen.effect),
			why = why,
			whyEn = why,
			cost = omen.cost or currency.cost,
			status = omen.status,
			removal = extra and extra.removal or nil,
			pool = extra and extra.pool or nil,
			poolSide = extra and extra.poolSide or nil,
			multiRoll = extra and extra.multiRoll or nil,
			atLeastOnce = extra and extra.atLeastOnce or nil,
			deterministic = extra and extra.deterministic or nil,
			-- Kept as a real boolean: "false" means the odds ARE known, which the panel
			-- distinguishes from "not computed".
			oddsUnknown = (extra and extra.oddsUnknown) and true or false,
			oddsNote = extra and extra.oddsNote or nil,
			-- The concrete consumable to buy, when the option has one (desecration bones).
			bone = extra and extra.bone or nil,
		}
		return entry
	end

	local function addPool(omen)
		if not omen then
			return nil, nil
		end
		local side = omen.side or context.side
		return Mods.rollPool(context.ilvl, context.hints, { baseName = context.baseType,
			side = side,
			minModLevel = omen.minModLevel or (ruleset.currencies[omen.applies] or { }).minModLevel,
			excludeGroups = context.excludeGroups,
			sources = context.sources,
		}), side
	end

	-- 1. Whittling: deterministic removal of the weakest modifier, then a new roll.
	if (item.rarity == "RARE" or item.rarity == "MAGIC") and context.affixes > 0 then
		local target, level = lowestLevelExplicit(item)
		if target then
			local pool, side = addPool(omens.whittling)
			local entry = option("whittling", "chaos", string.format("The Chaos Orb will remove %s (mod level %d) - the weakest modifier, not a random one.",
					target.text, level), { pool = pool, poolSide = side, deterministic = {
					text = target.text, level = level, side = sideOf(target),
				} })
			if entry then
				options[#options + 1] = entry
			end
		end
	end

	-- 2. Erasure: side-locked removal, probability = 1 / modifiers on that side.
	if context.affixes > 0 then
		local target = lowestLevelExplicit(item)
		local side = sideOf(target)
		local count = (side == "prefix") and context.prefixCount or context.suffixCount
		if side and count and count > 0 then
			local omenId = (side == "prefix") and "sinistral_erasure" or "dextral_erasure"
			local pool, poolSide = addPool(omens[omenId])
			local chance = 100 / count
			local entry = option(omenId, "chaos", string.format("The Chaos Orb removes only a %s: %.1f%% chance to hit %s (%d modifiers on that side).",
					side, chance, target.text, count), { pool = pool, poolSide = poolSide, deterministic = {
					text = target.text, level = target.mod and target.mod.lvl, side = side, chance = chance,
				} })
			if entry then
				options[#options + 1] = entry
			end
		end
	end

	-- 3. Side-locked Exaltation when exactly one side still has room.
	if context.side then
		local omenId = (context.side == "prefix") and "sinistral_exaltation" or "dextral_exaltation"
		local pool, side = addPool(omens[omenId])
		local entry = option(omenId, "exalted", string.format("Only the %s side is open, so the omen guarantees the orb adds there.", context.side), { pool = pool, poolSide = side })
		if entry then
			options[#options + 1] = entry
		end
	end

	-- 4. Greater Exaltation: two modifiers at once, with "at least one" odds.
	local openBoth = (item.openPrefixes or 0) + (item.openSuffixes or 0)
	if openBoth >= 2 then
		local omen = omens.greater_exaltation
		local pool, side = addPool(omen)
		local atLeastOnce = { }
		for index, group in ipairs(pool.groups) do
			if index > 5 then break end
			local single = group.chance / 100
			atLeastOnce[#atLeastOnce + 1] = {
				text = group.bestText,
				tier = group.bestTier,
				chance = (1 - (1 - single) ^ (omen.count or 2)) * 100,
				single = group.chance,
			}
		end
		local entry = option("greater_exaltation", "exalted", string.format("%d slots are open - the omen grants two modifiers per orb; below are 'at least one' odds.", openBoth), { pool = pool, poolSide = side, multiRoll = omen.count or 2, atLeastOnce = atLeastOnce })
		if entry then
			options[#options + 1] = entry
		end
	end

	-- 4b. Homogenising Exaltation: the strongest technique in the game, and the one the guides teach last.
	--
	-- The omen makes the next Exalted Orb add a modifier that SHARES A TAG with one already on the item. If
	-- only one tag family is reachable on the chosen side, the outcome stops being random: GhazzyTV's guide
	-- (transcript analysed in docs/mentor-research.md) shows triple energy shield prefixes and triple
	-- resistance suffixes being assembled this way.
	--
	-- The catch it also shows, and the reason this option is only offered for a side with a single reachable
	-- family: with a suffix already carrying a life tag, a prefix slam can pull life-per-kill in, so the
	-- method is NOT deterministic until the other side's tags are accounted for. We offer it only where the
	-- data says the family is unambiguous, and say so otherwise.
	-- The omen is offered per SIDE that still has room, not only for the single "add side" the rest of this
	-- function uses: when both sides are open the player chooses where the orb lands, and the answer differs
	-- per side. The old guard on context.side skipped the omen entirely on an item with both sides open,
	-- which is the common case while building one.
		-- Offered only while the omen is actually obtainable: in 0.5 it is missing from the league exchange, so the
	-- method is not advised at all (status = "removed" in the ruleset).
	if omens.homogenising_exaltation and omens.homogenising_exaltation.status ~= "removed" then
		local omen = omens.homogenising_exaltation
		for _, candidateSide in ipairs({ "prefix", "suffix" }) do
			local openOnSide = tonumber(candidateSide == "prefix" and item.openPrefixes or item.openSuffixes) or 0
			local families = tagFamiliesOnSide(item, candidateSide)
			if openOnSide > 0 and #families == 1 then
				local pool, side = addPool(omen)
				local entry = option("homogenising_exaltation", "exalted", string.format(
					"On the %s side only the '%s' family is reachable, so the omen makes the orb land in it - "
						.. "this is the closest PoE 2 gets to a guaranteed modifier.",
					candidateSide, tostring(families[1])), { pool = pool, poolSide = side,
					deterministic = { family = families[1], side = candidateSide } })
				if entry then
					entry.guaranteedFamily = families[1]
					entry.guaranteedSide = candidateSide
					entry.title = string.format("%s (%s)", tostring(omen.en), candidateSide)
					options[#options + 1] = entry
				end
			elseif openOnSide > 0 and #families >= 2 then
				-- Several families are reachable: the omen narrows the pool but does not guarantee a
				-- modifier, and the player must know that before paying for it.
				local entry = option("homogenising_exaltation", "exalted", string.format(
					"On the %s side %d families are reachable, so the omen narrows the pool but does NOT "
						.. "guarantee one modifier. Finish the other side first if you need certainty.",
					candidateSide, #families), { oddsUnknown = true,
					oddsNote = "омены той же группы сужают пул, но не гарантируют мод, пока на выбранной "
						.. "стороне достижимо больше одного семейства модов" })
				if entry then
					entry.narrowedSide = candidateSide
					entry.title = string.format("%s (%s)", tostring(omen.en), candidateSide)
					options[#options + 1] = entry
				end
			end
		end
	end

	-- 5. Blessed: reroll implicit values only.
	if #item.implicitMods > 0 or item.flags.corrupted then
		local entry = option("blessed", "divine", "Leaves explicit modifiers untouched and rerolls implicits only.", { oddsNote = "implicit values reroll uniformly; PoB carries no weights for them" })
		if entry then
			options[#options + 1] = entry
		end
	end

	-- 6. Desecration: a separate slot (limit: one desecrated modifier). The pool comes
	-- from the veiled table's "breach_desecration" tag, so the odds are real - and the bone
	-- the player has to buy is named, because the bone decides which classes can be
	-- desecrated at all and its grade decides how good the offered modifier can be.
	if (item.rarity == "RARE" or item.rarity == "MAGIC") and context.affixes < MAX_AFFIXES then
		local hasDesecrated = item.flags.desecrated or item.flags.desecratedPrefix or item.flags.desecratedSuffix
		if not hasDesecrated then
			local pool = Mods.desecrationPool(context.ilvl, context.hints, {
					excludeTexts = Mods.presentTexts(item),
				excludeGroups = context.excludeGroups,
			})
			-- Desecration offers three options at the Well of Souls, so the pool gets the
			-- reveal chances next to the weighted share.
			Mods.attachReveal(pool)
			local computable = pool and pool.tierCount > 0
			local bone = desecrationBoneFor(ruleset, item)
			local note = bone
				and ("odds are for the general desecration pool; " .. bone.en .. " narrows what the Well of Souls offers")
				or "odds are for the general desecration pool; a specific bone can narrow the choice at the Well of Souls"
			local why = "Desecration uses its own slot (limit: one desecrated modifier): a bone adds a hidden modifier, then the Well of Souls offers three to pick from."
			if bone then
				why = why .. " For this item: " .. bone.en
					.. (bone.grade == "ancient" and " (guarantees a modifier level of 40 or higher)." or ".")
			end
			local entry = option("sinistral_necromancy", "bone", why, {
					pool = pool,
					bone = bone and bone.en or nil,
					oddsUnknown = not computable,
					oddsNote = computable and note or nil,
				})
			if entry then
				options[#options + 1] = entry
			end
		end
	end

	-- 6b. Instilling: amulets (a notable passive) and Waystones (a reward modifier), from Liquid
	-- Emotions. This is Delirium, not flask work and not desecration, and it is not a currency at all -
	-- three emotions in a fixed order are combined at the instilling station, so there are no odds to
	-- compute and the step has to say what the player buys instead. The exact recipes are not in our
	-- data: the game shows them on Alt-hover over the notable, which is the only authoritative source.
	local class = tostring(item.itemClass or ""):lower()
	local instilSlot = class:find("amulet", 1, true) and "amulet"
		or (class:find("waystone", 1, true) and "waystone" or nil)
	if instilSlot and ruleset.liquidEmotions then
		local already = item.flags.instilled
		local emotionCount = 0
		for _ in ipairs(ruleset.liquidEmotions) do
			emotionCount = emotionCount + 1
		end
		local why
		if instilSlot == "amulet" then
			why = "Instilling an amulet grants one notable passive from the skill tree for free, using three "
				.. "Liquid Emotions in a fixed order - a different order can be a different notable. Do it at "
				.. "the instilling station on a non-corrupted amulet."
		else
			why = "Instilling a Waystone uses Liquid Emotions as reward modifiers (rarity, rare monsters)."
		end
		if already then
			why = why .. " This item is already instilled: instilling again replaces what is there, and the "
				.. "emotions are spent."
		end
		options[#options + 1] = {
			kind = "instil",
			slot = instilSlot,
			title = instilSlot == "amulet" and "Instil the amulet (notable passive)"
				or "Instil the Waystone (reward modifier)",
			titleEn = instilSlot == "amulet" and "Instil the amulet (notable passive)"
				or "Instil the Waystone (reward modifier)",
			en = "Liquid Emotions",
			cost = "medium",
			status = "league",
			alreadyInstilled = already and true or nil,
			emotions = emotionCount,
			why = why,
			whyEn = why,
			oddsUnknown = true,
			oddsNote = "no odds: the recipe is a fixed set of three emotions in a fixed order, and the "
				.. "current combinations are shown in game by holding Alt over the notable",
		}
	end

	-- 6c. Waystones. Nothing in our data carries waystone modifier weights, so this is deliberately not
	-- a plan with odds: it states the mechanics that matter. The interesting part is the tier, because
	-- a tier 16 can only be made by corrupting a tier 15, and the four Chaotic omens exclude a reward
	-- type rather than guaranteeing one (0.5.0 turned them around).
	if tostring(item.itemClass or ""):lower():find("waystone", 1, true) or item.tier then
		local waystones = ruleset.waystones or { }
		local tier = tonumber(item.tier)
		local why
		if tier and tier >= (waystones.maxTier or 16) then
			why = string.format("Tier %d is the top: rolling it changes the modifiers, and a corruption can "
				.. "still move the tier, but there is nothing above it.", tier)
		elseif tier then
			why = string.format("Tier %d. Rolling with a currency rerolls the modifiers; a Vaal Orb can move "
				.. "the tier by one, and tier %d is reached ONLY by corrupting a tier %d - so a tier %d is "
				.. "worth keeping rather than vendoring.", tier, waystones.maxTier or 16,
				(waystones.maxTier or 16) - 1, (waystones.maxTier or 16) - 1)
		else
			why = "Waystones are rolled with a currency and instilled with Liquid Emotions."
		end
		options[#options + 1] = {
			kind = "waystone",
			tier = tier,
			title = tier and ("Waystone: roll the modifiers (tier " .. tostring(tier) .. ")")
				or "Waystone: roll the modifiers",
			titleEn = tier and ("Waystone: roll the modifiers (tier " .. tostring(tier) .. ")")
				or "Waystone: roll the modifiers",
			en = "Waystone rolling",
			cost = "low",
			status = "league",
			why = why,
			whyEn = why,
			oddsUnknown = true,
			oddsNote = waystones.modsNote or "waystone modifier weights are not in our data",
			omens = { "chaotic_effectiveness", "chaotic_monsters", "chaotic_quantity", "chaotic_rarity" },
		}
	end

	-- 7. Essences: the only craft that guarantees a specific modifier (100%).
	for _, essence in ipairs(Essences.optionsFor(item, {
		excludeGroups = context.excludeGroups,
		limit = 3,
	})) do
		local blockedNote = essence.blocked
			and ("cannot apply: a modifier from this group is already on the item")
			or nil
		local levelNote = essence.needsLevel
			and string.format("needs item level %d or higher",
				essence.mod.lvl)
			or nil
		options[#options + 1] = {
			kind = "essence",
			essence = essence,
			title = essence.label or essence.name,
			titleEn = essence.name,
			en = essence.name,
			cost = essence.cost or "medium",
			status = "core",
			why = string.format("Guaranteed modifier: %s - 100%%, no randomness.",
				Strings.modName(essence.mod.text, lang)),
			whyEn = string.format("Guaranteed modifier: %s - 100%%, no randomness.", essence.mod.text),
			oddsNote = blockedNote or levelNote,
		}
	end

	return options
end

--- Analyse a parsed item.
-- @param item table parsed by Item.Parser
-- @param ruleset table loaded from Data/league_*.lua
-- @return table advice (language-neutral; call Advisor.stateFor / Advisor.toText to render)
--- The catalysts whose tag matches a modifier already on the item.
--
-- Catalysts do not work like the class quality currencies: each one covers ONE modifier tag, and using
-- a catalyst replaces quality of another tag rather than adding to it. The modifier data carries no
-- tags, but the tag names are ordinary words that appear in the modifier text ("physical", "fire",
-- "life"), so the matches are a real hint rather than a guess.
--
-- Returns EVERY match, best first, because an item usually matches several: a ring with physical
-- damage, fire resistance and attack speed matches three different catalysts, and quietly picking one
-- of them would send the player to raise the quality of a modifier they may not care about.
-- @return array of catalyst names (may be empty)
local function catalystsFor(ruleset, item)
	local catalysts = (ruleset or { }).catalysts
	if type(catalysts) ~= "table" then
		return { }
	end
	local haystack = { }
	for _, mod in ipairs(item.explicitMods or { }) do
		if type(mod) == "table" and type(mod.text) == "string" then
			haystack[#haystack + 1] = mod.text:lower()
		end
	end
	if #haystack == 0 then
		return { }
	end
	local text = table.concat(haystack, " ")
	-- Jewels take the Refined versions, everything else the plain ones, so only the matching half of
	-- the catalogue competes.
	local class = tostring(item.itemClass or ""):lower()
	local wantRefined = class:find("jewel", 1, true) ~= nil
	local scored = { }
	for index, catalyst in ipairs(catalysts) do
		local tag = catalyst.tag
		-- "adaptive" covers every tag, so it never singles one out and cannot be a specific answer.
		local rightHalf = (catalyst.refined == true) == wantRefined
		if rightHalf and type(tag) == "string" and tag ~= "adaptive" and text:find(tag, 1, true) then
			-- How many distinct modifiers carry the tag: the more of them, the more the player gains
			-- from raising it. Ties keep catalogue order.
			local hits = 0
			for _, one in ipairs(haystack) do
				if one:find(tag, 1, true) then
					hits = hits + 1
				end
			end
			scored[#scored + 1] = { name = catalyst.en, hits = hits, index = index }
		end
	end
	table.sort(scored, function(left, right)
		if left.hits ~= right.hits then
			return left.hits > right.hits
		end
		return left.index < right.index
	end)
	local names = { }
	for _, entry in ipairs(scored) do
		names[#names + 1] = entry.name
	end
	return names
end

--- Which currency raises the quality of this kind of item?
--
-- Quality is not an affix and does not use a slot: it is a separate number that scales the item's own
-- base stats - a flask's recovery, a weapon's physical damage, armour's defences. Each class has its
-- own currency, and the panel has to name the one the player actually has to buy. Rings, amulets and
-- jewels are the exception: they take a catalyst, which is chosen by the modifier it should cover.
-- @return currency id in the ruleset, or nil when quality cannot be raised on this item
local function qualityCurrencyFor(item)
	local class = tostring(item.itemClass or ""):lower()
	if class:find("flask", 1, true) then
		return "bauble"
	end
	if class:find("gem", 1, true) then
		return "prism"
	end
	if class:find("ring", 1, true) or class:find("amulet", 1, true) or class:find("belt", 1, true)
		or class:find("jewel", 1, true) then
		return "quality"
	end
	if class:find("armour", 1, true) or class:find("shield", 1, true) or class:find("helmet", 1, true)
		or class:find("gloves", 1, true) or class:find("boots", 1, true) then
		return "scrap"
	end
	if class:find("wand", 1, true) or class:find("staff", 1, true) or class:find("stave", 1, true)
		or class:find("sceptre", 1, true) or class:find("scepter", 1, true) then
		return "etcher"
	end
	if class:find("sword", 1, true) or class:find("axe", 1, true) or class:find("mace", 1, true)
		or class:find("bow", 1, true) or class:find("crossbow", 1, true) or class:find("claw", 1, true)
		or class:find("dagger", 1, true) or class:find("spear", 1, true) or class:find("quarterstaff", 1, true) then
		return "whetstone"
	end
	return nil
end

--- Does this step change the modifier set (add or remove a modifier)?
--
-- Quality and value rerolls do not: they touch the item's own numbers.
-- @param step resolved step table
-- @return boolean
local function changesModifierSet(step)
	local adds = tonumber(step.adds) or 0
	local removes = tonumber(step.removes) or 0
	return adds > 0 or removes > 0
end

--- Put the quality step where the player expects it: after the value reroll, before corruption.
--
-- The customer's rule, stated twice and refined the second time: quality closes the craft out, and it goes
-- AFTER the Divine Orb. Both halves follow from what quality does - it multiplies the item's own numbers,
-- so it is worth least before those numbers are final and most once they are. Earlier versions put it first
-- (cheapest while the item is plain), then before the value step; the customer corrected both.
--
-- Where it lands, in order of preference:
--   * directly after the LAST value-reroll step, so the multiplier applies to the numbers that stay;
--   * otherwise directly before the first irreversible step (Vaal), which is the end of the craft;
--   * otherwise after the last step that changes the modifier set.
-- A Normal item has no numbers to reroll and no modifiers to multiply, so the last case applies.
-- @param plan plan table whose steps are modified in place
-- @param quality the resolved quality step
local function insertQuality(plan, quality)
	if not plan or not quality or type(plan.steps) ~= "table" then
		return
	end
	local steps = plan.steps
	-- At the quality cap the "quality" step IS the value reroll. There is nothing to insert in that case:
	-- a plan with one Divine Orb is already in the right order.
	if quality.id == "divine" then
		local hasReroll = false
		for _, step in ipairs(steps) do
			if step.id == "divine" then
				hasReroll = true
			end
		end
		if hasReroll then
			return
		end
	end
	local lastRerollAt, firstFinalAt, lastModifierAt = nil, nil, nil
	for position, step in ipairs(steps) do
		if step.id == "divine" then
			lastRerollAt = position
		end
		if step.id == "vaal" and not firstFinalAt then
			firstFinalAt = position
		end
		if changesModifierSet(step) then
			lastModifierAt = position
		end
	end
	local at
	if lastRerollAt then
		at = lastRerollAt + 1
	elseif firstFinalAt then
		at = firstFinalAt
	else
		at = (lastModifierAt or 0) + 1
	end
	table.insert(steps, at, quality)
end

--- The quality step, when the item can still take quality and does not have the full 20% yet.
--
-- It is placed in the plan after the modifier steps and before the finishing ones (see insertQuality).
-- The customer hit the case where it was missing entirely - a Magic flask with both affixes taken and no
-- quality at all, where the panel went straight to the rarity upgrade.
--
-- With quality already at the cap the only thing left that improves what the item already has is a
-- Divine Orb: it rerolls the numeric values of the existing modifiers without touching the set, so it
-- is the correct next step for an item whose mods are the ones the player wants. That is the
-- customer's case - a flask at +20% quality with its two mods already in place.
-- @return step table or nil
--- The highest quality this item can reach.
--
-- 20% is only the default. Raised caps come from the item itself, and several 0.5-era guides rely on them:
--   * a base whose implicit says how high it goes - a Breach Ring reads "Maximum Quality is 40%", a Refined
--     Breach Ring 45%;
--   * an explicit/implicit line of the form "+N% to Maximum Quality" (Essence of the Breach puts exactly that
--     on jewellery, at the cost of the item's one created modifier slot).
-- Vaal Infusers are a separate route that lifts armour, a martial or caster weapon, or a Vaal-crafted piece
-- from above 20 up to 30 - with a chance to corrupt it, so it is not a cap this function can promise.
-- @param item parsed item
-- @return number
local DEFAULT_MAX_QUALITY = 20
local INFUSER_MAX_QUALITY = 30

local function qualityCapFor(item)
	local best = DEFAULT_MAX_QUALITY
	for _, bucket in ipairs({ item.implicitMods or { }, item.explicitMods or { },
			item.craftedMods or { }, item.enchantMods or { } }) do
		for _, mod in ipairs(bucket) do
			local line = type(mod) == "table" and mod.text or mod
			if type(line) == "string" then
				-- "Maximum Quality is 40%" and "+20% to Maximum Quality" say the same thing two ways.
				local isMax = line:match("([%+%-]?%d+)%%?%s*to%s+[Mm]aximum%s+[Qq]uality")
					or line:match("[Mm]aximum%s+[Qq]uality%s+is%s+([%d]+)%%")
				if isMax then
					local amount = tonumber(isMax)
					if amount then
						-- "Maximum Quality is 40%" is absolute; "+20%" is a raise on the default.
						local value = line:lower():find("maximum quality is", 1, true) and amount
							or (DEFAULT_MAX_QUALITY + amount)
						if value > best then
							best = value
						end
					end
				end
			end
		end
	end
	return best
end

local function qualityStep(ruleset, item, context)
	local quality = tonumber(item.quality) or 0
	local cap = qualityCapFor(item)
	if quality >= cap then
		-- At the item's own ceiling: tune the values instead. Nothing to tune without a modifier.
		if #(item.explicitMods or { }) == 0 or not ruleset.currencies.divine then
			return nil
		end
		-- 20% is the ceiling of the ordinary quality currencies, NOT the ceiling of every item, and those are
		-- two different statements. The wording follows where the item actually stands.
		local why = cap > DEFAULT_MAX_QUALITY
			and ("Качество " .. tostring(quality) .. "% — это потолок ИМЕННО ЭТОГО предмета (" .. tostring(cap)
				.. "%). Дальше его не поднять, поэтому остаётся править числа: Divine Orb перебрасывает "
				.. "значения существующих модов и не меняет набор.")
			or ("Качество уже на обычном потолке " .. tostring(DEFAULT_MAX_QUALITY) .. "%. Выше него поднимают "
				.. "только особые пути: Vaal-инфьюзер (до " .. tostring(INFUSER_MAX_QUALITY) .. "%, с шансом "
				.. "осквернить), база с «Maximum Quality» (Breach Ring 40%, Refined Breach Ring 45%) или "
				.. "Essence of the Breach (+20% к максимуму качества, но она занимает created-слот). "
				.. "Набор модов при этом менять нельзя, поэтому остаются только числа.")
		local plan = buildPlan(ruleset, "quality", "Values", "Values", { "divine" }, why, why, context)
		return (plan.steps or { })[1]
	end

	local currencyId = qualityCurrencyFor(item)
	if not currencyId or not ruleset.currencies[currencyId] then
		return nil
	end
	-- Jewellery: a catalyst, not a class currency. The step names the catalysts that match modifiers on
	-- the item (usually several - a catalyst covers one tag each), and if nothing matches it says only
	-- that a catalyst is needed rather than naming the wrong one.
	if currencyId == "quality" then
		local candidates = catalystsFor(ruleset, item)
		local note
		if #candidates > 0 then
			note = "A catalyst raises the quality of one modifier tag only and replaces quality of "
				.. "another tag. Matching this item's modifiers: " .. table.concat(candidates, ", ")
				.. ". Pick the one for the modifier you want to improve."
		else
			note = "A catalyst raises the quality of one modifier tag only, and replaces quality of "
				.. "another tag: pick the catalyst for the modifier you want to improve. This item's "
				.. "modifiers did not point at one clearly, so none is guessed."
		end
		local plan = buildPlan(ruleset, "quality", "Quality", "Quality", { "quality" }, note, note, context)
		local step = (plan.steps or { })[1]
		if step then
			step.catalysts = candidates
			if #candidates > 0 then
				step.en = candidates[1]
			end
		end
		return step
	end
	local step = buildPlan(ruleset, "quality", "Quality", "Quality", { currencyId },
		"Quality scales the item's own base stats and uses no affix slot, so it is worth doing first.",
		"Quality scales the item's own base stats and uses no affix slot, so it is worth doing first.", context)
	return (step.steps or { })[1]
end

--- Warnings about slots the item has already spent, independent of which rule matched.
--
-- Kept out of the rule path on purpose: an item with no matching rule (an unknown split, or a class with
-- no modifier pool) can still carry a crafted modifier, and the player still has to be told that the
-- crafted slot is taken before spending an essence on it.
local function addSlotWarnings(advice, item)
	local craftedCount = #(item.craftedMods or { })
	if craftedCount > 0 then
		advice.craftedModCount = craftedCount
		local offered = false
		for _, plan in ipairs(advice.plans or { }) do
			for _, step in ipairs(plan.steps or { }) do
				if step.guaranteed then
					offered = true
				end
			end
		end
		-- Warned when a guaranteed craft is on offer, and also when no plan was built at all: the slot
		-- being spent is a fact about the item either way.
		if offered or #(advice.plans or { }) == 0 then
			advice.notes[#advice.notes + 1] = { code = "crafted_slot_taken", params = { craftedCount } }
		end
	end
end

--- Analyze one item against a league ruleset.
-- @param item table parsed by Item.Parser
-- @param ruleset table loaded from Data/league_*.lua
-- @return table advice (language-neutral; call Advisor.stateFor / Advisor.toText to render)
function Advisor.analyze(item, ruleset)
	-- Enrich with prefix/suffix classification and per-modifier tiers before looking
	-- at rules: "3 prefixes taken" changes what a crafting step can even do.
	Mods.annotate(item)

	-- The classified count is the real affix count (a prefix with two stat lines is still one
	-- affix). When nothing was classified but there ARE modifier lines, the total is unknown rather
	-- than zero: reading it as the number of lines made an item with three prefixes and three
	-- suffixes look half empty. Six is the cap a rare can hold and is the safe reading - it never
	-- claims that a slot is free.
	local affixes = (item.prefixCount or 0) + (item.suffixCount or 0)
	local splitUnknown = false
	if affixes == 0 and #(item.explicitMods or { }) > 0 then
		affixes = MAX_AFFIXES
		splitUnknown = true
	end
	local advice = {
		item = item,
		league = ruleset.league,
		affixes = affixes,
		openAffixes = math.max(0, MAX_AFFIXES - affixes),
		prefixCount = item.prefixCount,
		suffixCount = item.suffixCount,
		openPrefixes = item.openPrefixes,
		openSuffixes = item.openSuffixes,
		plans = { },
		notes = { },
		blocker = nil,
		blockerEn = nil,
		-- True when the modifier data could not classify the item, so the affix total above is the
		-- safe reading rather than a measurement. The panel says so instead of implying it knows.
		splitUnknown = splitUnknown,
		-- True when the item's class has no modifier pool in our data at all (waystones, tablets,
		-- relics, wombgifts). Not a parsing failure: there is nothing to classify against, so the
		-- affix counts above mean "unknown", and no rule may treat the item as full.
		poolMissing = item.poolMissing and true or nil,
		ruleId = nil,
	}

	for _, note in ipairs(item.notes or { }) do
		advice.notes[#advice.notes + 1] = note
	end

	-- Context for the probability engine: which modifiers a random add can still
	-- produce on this item, and how likely each removal is.
	local excludeGroups = { }
	for _, mod in ipairs(item.explicitMods) do
		if mod.mod then
			excludeGroups[mod.mod.groupKey] = true
		end
	end
	local addSide = nil
	if item.openPrefixes == 0 and (item.openSuffixes or 0) > 0 then
		addSide = "suffix"
	elseif item.openSuffixes == 0 and (item.openPrefixes or 0) > 0 then
		addSide = "prefix"
	end
	local context = {
		ilvl = item.itemLevel,
		hints = item.baseHints,
		baseType = item.baseType,
		sources = item.baseSources,
		side = addSide,
		excludeGroups = excludeGroups,
		affixes = affixes,
		prefixCount = item.prefixCount or 0,
		suffixCount = item.suffixCount or 0,
	}
	advice.addSide = addSide
	advice.excludedGroups = excludeGroups

	local rule = nil
	-- Quality is decided here, BEFORE any rule is chosen, because it does not depend on a rule: it scales
	-- the item's own base stats, uses no affix slot, and is cheapest while the item is still plain. It
	-- used to be computed only on the rule path, so an item with no matching rule (a flask whose modifier
	-- did not resolve, a class with no pool) was never offered quality at all - the customer's flask with
	-- no quality was told to spend a Divine Orb instead of a Bauble, and the flask's quality cannot be
	-- raised with a Divine.
	local quality = nil
	-- The locked state is the exception: nothing at all may be applied to a corrupted, sanctified or
	-- mirrored item, so it gets no quality step either. That is decided by the rule, so the rule is
	-- looked up first when one exists - only the "no rule" path needs quality before it.
	local matched = nil
	if not advice.poolMissing then
		for _, candidate in ipairs(ruleset.rules) do
			if matches(candidate.when, item, affixes) then
				matched = candidate
				break
			end
		end
	end
	if not (matched and matched.id == "locked") then
		quality = qualityStep(ruleset, item, context)
		if quality then
			advice.qualityStep = quality
		end
	end

	local rule = matched

	if not rule then
		-- The warnings about slots that are already spent do not depend on which rule matched, so they
		-- are added here as well. They were only added on the rule path, and skipping the rule (an item
		-- whose split is unknown, or a class with no modifier pool) silently lost them.
		addSlotWarnings(advice, item)
		if advice.poolMissing then
			-- No affix-based rule applies, but these classes do have their own advice (waystone rolling,
			-- instilling), and that is exactly the advice that matters for them. Build it here instead of
			-- returning before it: the first version of this fix returned early and the panel lost the
			-- waystone step entirely.
			advice.notes[#advice.notes + 1] = { code = "pool_missing", params = { tostring(item.itemClass) } }
			advice.omenOptions = buildOmenOptions(item, ruleset, context)
			return advice
		end
		-- The split is unknown when a modifier line did not resolve, which happens on flasks and charms
		-- whose plain Ctrl+C text carries no annotations. Say that, rather than picking a rule that
		-- assumes a slot count: the customer's charm was offered a Regal Orb this way.
		if item.affixSplitComplete ~= true and (item.unclassifiedMods or 0) > 0 then
			advice.notes[#advice.notes + 1] = { code = "split_unknown_no_rule", params = { item.unclassifiedMods } }
			advice.omenOptions = buildOmenOptions(item, ruleset, context)
			-- Whatever the quality step found still stands, and it is the one thing that does not need the
			-- slot count. It travels in its own plan so the coach finds it like any other step.
			if quality then
				advice.plans[#advice.plans + 1] = buildPlan(ruleset, "quality",
					"Качество", "Quality", { }, quality.effect, quality.effectEn, context)
				advice.plans[#advice.plans].steps = { quality }
			end
			return advice
		end
		advice.notes[#advice.notes + 1] = { code = "no_rule" }
		local steps = { }
		if quality then
			steps[#steps + 1] = quality
		end
		steps[#steps + 1] = "quality"
		local plan = buildPlan(ruleset, "min",
			"МИН — минимальный бюджет", "MIN - lowest budget",
			steps,
			"Universal safe step: raise quality and recheck the item.",
			"Universal safe step: raise quality, then re-check the item.", context)
		advice.plans[#advice.plans + 1] = plan
		return advice
	end

	advice.ruleId = rule.id
	advice.blocker = rule.blockerEn or rule.blocker
	advice.blockerEn = rule.blockerEn or rule.blocker
	advice.plans[#advice.plans + 1] = buildPlan(ruleset, "min",
		"МИН — минимальный бюджет", "MIN - lowest budget",
		rule.min, rule.why and rule.why.min, rule.whyEn and rule.whyEn.min, context)
	advice.plans[#advice.plans + 1] = buildPlan(ruleset, "max",
		"МАКС — максимальное качество", "MAX - best result",
		rule.max, rule.why and rule.why.max, rule.whyEn and rule.whyEn.max, context)
	-- The quality step goes in the plan, not only on the advice table: the coach walks the plan by index,
	-- so a step kept outside it was invisible. Its POSITION comes from insertQuality: after the value
	-- reroll, before corruption. That needs the value reroll to BE in the plan, so it is added when the
	-- item has numbers to reroll and the rule's own minimal plan left it out - otherwise quality had
	-- nothing to follow there and landed before the numbers were final, which is the mistake the customer
	-- corrected twice.
	local minPlan = advice.plans[#advice.plans - 1]
	if quality and minPlan and ruleset.currencies.divine then
		local hasReroll, hasModifierStep = false, false
		for _, step in ipairs(minPlan.steps or { }) do
			if step.id == "divine" then
				hasReroll = true
			end
			if changesModifierSet(step) then
				hasModifierStep = true
			end
		end
		if not hasReroll and hasModifierStep then
			table.insert(minPlan.steps, resolveStep(ruleset, "divine"))
		end
	end
	if quality then
		insertQuality(advice.plans[#advice.plans - 1], quality)
		insertQuality(advice.plans[#advice.plans], quality)
	end

	if item.itemLevel and item.itemLevel < 60 then
		advice.notes[#advice.notes + 1] = { code = "low_item_level", params = { item.itemLevel } }
	end
	if item.flags.corrupted and rule.id ~= "locked" then
		advice.notes[#advice.notes + 1] = { code = "corrupted_check" }
	end
	if affixes >= MAX_AFFIXES and rule.id ~= "locked" then
		advice.notes[#advice.notes + 1] = { code = "full_affixes" }
	end
	if item.openPrefixes == 0 and (item.openSuffixes or 0) > 0 then
		advice.notes[#advice.notes + 1] = { code = "prefixes_full", params = { item.openSuffixes } }
	elseif item.openSuffixes == 0 and (item.openPrefixes or 0) > 0 then
		advice.notes[#advice.notes + 1] = { code = "suffixes_full", params = { item.openPrefixes } }
	end
	if (item.unclassifiedMods or 0) > 0 then
		advice.notes[#advice.notes + 1] = { code = "affix_split_unknown", params = { item.unclassifiedMods } }
	elseif item.affixSplitComplete and item.affixSplitConsistent == false then
		advice.notes[#advice.notes + 1] = {
			code = "affix_split_inconsistent",
			params = { item.prefixCount, item.suffixCount, tostring(item.rarity) },
		}
	end
	if (item.tiersEstimated or 0) > 0 then
		advice.notes[#advice.notes + 1] = { code = "tier_estimated", params = { item.tiersEstimated } }
	end

	-- How good a randomly rolled modifier can be at this item level, restricted to
	-- modifiers that can spawn on this base type (share of mod groups, not weights).
	if item.itemLevel then
		advice.rollStats = Mods.rollableStats(item.itemLevel, item.baseHints, item.baseSources)
	end

	-- Omen + currency combinations for this item state (with the odds each omen changes).
	advice.omenOptions = buildOmenOptions(item, ruleset, context)

	-- Runes / soul cores / idols: guaranteed modifiers for this item's slots.
	advice.runeOptions = Runes.optionsFor(item, { limit = 3 })
	advice.runeCount = Runes.countFor(item)

	-- Runeforging (runemastering): which base this item's base turns into, if any.
	advice.runeforging = Runeforging.forItem(item)

	-- Alloy-only modifier pool. PoB gives these modifiers weight 0 and carries no
	-- alloy -> modifier mapping, so the pool is listed and the odds are reported as
	-- not computable rather than guessed.
	advice.alloyPool = Mods.alloyPool(item.itemLevel)
	advice.alloys = ruleset.alloys

	-- Where every number comes from, so the panel can print its sources.
	advice.sources = ruleset.sources

	-- Runes and alloys are league crafting methods as well, so they share the panel
	-- block with the omens instead of getting a block each.
	local methods = advice.omenOptions or { }
	advice.omenOptions = methods
	-- Quality belongs in this list as well as in the plan: for jewellery the step IS the decision
	-- (a catalyst covers one modifier tag and replaces quality of another), and a client that reads
	-- only the methods list would otherwise never see it.
	if advice.qualityStep and (advice.qualityStep.en or advice.qualityStep.name) then
		local step = advice.qualityStep
		methods[#methods + 1] = {
			kind = "quality",
			title = tostring(step.en or step.name),
			titleEn = tostring(step.en or step.name),
			en = tostring(step.en or step.name),
			catalysts = step.catalysts,
			cost = "low",
			status = "core",
			why = step.effect,
			whyEn = step.effectEn or step.effect,
		}
	end
	local lang = Strings.lang or "ru"
	for _, rune in ipairs(advice.runeOptions) do
		local typeKey = tostring(rune.type or "Rune")
		local typeLabel = Strings.runeType(typeKey, lang)
		methods[#methods + 1] = {
			kind = "rune",
			rune = rune,
			title = string.format("%s: %s", typeLabel, Strings.baseName(rune.name, lang)),
			titleEn = string.format("%s: %s", typeKey, rune.name),
			cost = "low",
			status = "core",
			why = "Socketing the rune grants exactly this modifier - no randomness.",
			whyEn = "Socketing the rune grants exactly this modifier - no randomness.",
		}
	end
	if advice.alloyPool and advice.alloyPool.tierCount > 0 then
		local names = { }
		for _, alloy in ipairs(advice.alloys or { }) do
			names[#names + 1] = Strings.baseName(alloy.en, lang)
		end
		methods[#methods + 1] = {
			kind = "alloy",
			pool = advice.alloyPool,
			alloyNames = names,
			title = Strings.t(lang, "alloyTitle"),
			titleEn = Strings.t("en", "alloyTitle"),
			cost = "high",
			status = "league",
			-- The panel prints its own explanation for this pool: the modifiers exist in
			-- the data but carry weight 0, so there is nothing to compute odds from.
			oddsUnknown = false,
		}
	end

	-- 0.5 limit: an item carries at most ONE crafted modifier, and essences, Perfect
	-- essences and Runic Alloys all compete for that same slot.
	addSlotWarnings(advice, item)

	return advice
end

--- Item state lines in the requested language.
--- Which bone does this item need to be desecrated? (public: the cost model needs the same answer)
-- @return bone table from the ruleset, or nil when the class needs no bone / is unknown
Advisor.desecrationBoneFor = desecrationBoneFor

-- Public so the panel and the tests can ask the same question the quality step asks.
Advisor.qualityCapFor = qualityCapFor
Advisor.DEFAULT_MAX_QUALITY = DEFAULT_MAX_QUALITY
Advisor.INFUSER_MAX_QUALITY = INFUSER_MAX_QUALITY

--- The quality ceiling of a base, looked up by NAME.
--
-- qualityCapFor reads a captured item, which answers the question only after the base has been bought. This
-- answers it before: a Breach Ring reaches 40% and a Refined one 45%, and that is a reason to choose the base,
-- not a detail discovered afterwards. Bases whose ceiling is the ordinary 20% return the default.
-- @param baseName string, e.g. "Breach Ring"
-- @param ruleset league table
-- @return number
function Advisor.qualityCapForBase(baseName, ruleset)
	local caps = ((ruleset or { }).quality or { }).baseCaps or { }
	local name = tostring(baseName or "")
	local cap = caps[name]
	if tonumber(cap) then
		return tonumber(cap)
	end
	-- The base line of a rare is sometimes decorated ("Rare Breach Ring"), so fall back to a containment
	-- check, longest name first so "Refined Breach Ring" is not matched by "Breach Ring".
	local best, bestLength = DEFAULT_MAX_QUALITY, 0
	for known, value in pairs(caps) do
		if name:find(known, 1, true) and #known > bestLength then
			best, bestLength = tonumber(value) or DEFAULT_MAX_QUALITY, #known
		end
	end
	return best
end

function Advisor.stateFor(advice, lang)
	return buildState(advice.item, advice.affixes, lang)
end

--- Notes in the requested language.
function Advisor.notesFor(advice, lang)
	return i18n.notes(advice.notes, lang)
end

--- Compact Russian text rendering for the console and last_advice.txt (UTF-8 safe).
function Advisor.toText(advice)
	local out = { }
	local function line(s) out[#out + 1] = s end
	line(string.format("League: %s", tostring(advice.league)))
	line("--- Item ---")
	for _, s in ipairs(Advisor.stateFor(advice, "ru")) do
		line("  " .. s)
	end
	if advice.blocker then
		line("!!! " .. advice.blocker)
	end
	for _, plan in ipairs(advice.plans) do
		line(string.format("--- %s ---", plan.title))
		if plan.reason then
			line("  " .. plan.reason)
		end
		for i, step in ipairs(plan.steps) do
			line(string.format("  %d) %s [%s]", i, step.ru, tostring(step.cost)))
			line("     " .. step.effect)
			if step.hint then
				line("     tip: " .. step.hint)
			end
			if step.warning then
				line("     " .. step.warning)
			end
		end
	end
	-- The quality step is decided before the plan (quality scales base stats and uses no affix slot),
	-- so it is printed before it here too. It used to live only on the advice table and reach the card
	-- through the coach, which meant the text rendering and the MCP path never mentioned it.
	if advice.qualityStep and (advice.qualityStep.en or advice.qualityStep.name) then
		line("--- Quality first ---")
		line("  * " .. tostring(advice.qualityStep.en or advice.qualityStep.name))
		if advice.qualityStep.effect then
			line("    " .. tostring(advice.qualityStep.effect))
		end
		if advice.qualityStep.catalysts and #advice.qualityStep.catalysts > 0 then
			line("    matching catalysts: " .. table.concat(advice.qualityStep.catalysts, ", "))
		end
	end
	-- League crafting methods: omens, desecration and guaranteed essence crafts.
	if advice.omenOptions and #advice.omenOptions > 0 then
		line("--- League crafting methods ---")
		for _, option in ipairs(advice.omenOptions) do
			line("  * " .. tostring(option.title))
			if option.why then
				line("    " .. option.why)
			end
			if option.deterministic then
				local target = option.deterministic
				if target.chance then
					line(string.format("    removes only a %s, %.1f%% to hit",
						tostring(target.side), target.chance))
				else
					line(string.format("    removes: %s (mod level %s)",
						tostring(target.text), tostring(target.level)))
				end
			end
			if option.kind == "rune" and option.rune then
				local rune = option.rune
				line(string.format("    guaranteed: %s - 100%%, limit %d%s",
					tostring(rune.text), rune.limit or 1,
					(rune.levelReq or 0) > 0 and string.format(", requires level %d", rune.levelReq) or ""))
			end
			if option.kind == "alloy" and option.pool then
				for index, entry in ipairs(option.pool.entries) do
					if index > 3 then break end
					line(string.format("    %s (T%d, mod level %d, affix %s)",
						tostring(entry.text), entry.tier, entry.lvl, tostring(entry.affix)))
				end
				if option.alloyNames and #option.alloyNames > 0 then
					line("    " .. table.concat(option.alloyNames, ", "))
				end
			end
			if option.pool and option.pool.groups then
				for index, group in ipairs(option.pool.groups) do
					if index > 3 then break end
					line(string.format("    %.2f%%  %s (T%d)", group.chance,
						tostring(group.bestText), group.bestTier))
				end
			end
			if option.oddsNote then
				line("    ! " .. option.oddsNote)
			end
			if option.oddsUnknown then
				line("    ! odds not shown")
			end
		end
	end

	local notes = Advisor.notesFor(advice, "ru")
	if #notes > 0 then
		line("--- Notes ---")
		for _, note in ipairs(notes) do
			line("  * " .. note)
		end
	end

	-- Provenance: every mechanic lists the data file or official note it came from.
	if advice.sources and #advice.sources > 0 then
		line("--- Data sources ---")
		for _, source in ipairs(advice.sources) do
			line(string.format("  * %s — %s", tostring(source.label), tostring(source.detail)))
			line("    " .. tostring(source.url))
		end
	end
	return table.concat(out, "\n")
end

return Advisor
