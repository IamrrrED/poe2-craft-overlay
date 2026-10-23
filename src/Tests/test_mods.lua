-- PoE2 Craft Overlay : Tests/test_mods.lua
-- Verifies the modifier data pipeline: normalization parity with
-- tools/extract_mods.py, exact tier resolution, item-level estimates and the
-- annotation of a parsed item.
--
-- Expected tiers/levels below are facts taken from the generated data
-- (Data/mods.lua), not guesses: e.g. IncreasedLife|Prefix T5 is (120-149) at level 60.

local Mods = require("Item.Mods")
local Parser = require("Item.Parser")

	local RARE = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
]]

-- One recognised modifier plus one that is not in the data: the prefix/suffix split
-- must be reported as unknown instead of invented.
local PARTIAL = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
Utterly Unknown Modifier Line
]]

-- Four suffixes on a rare is impossible in game, which means one line was misread.
-- Slot-based advice must be withheld rather than derived from impossible data.
local INCONSISTENT = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+45% to Fire Resistance
+38% to Cold Resistance
+30 to Strength
+35 to Dexterity
]]

return function(H)
	local stats = Mods.stats()
	H.eq("mods: data entries loaded", stats.entries > 3000, true)
	H.eq("mods: data groups loaded", stats.groups > 700, true)

	-- Normalization must mirror the Python extractor exactly.
	H.eq("mods: normalize range", Mods.normalize("+(5-8) to Strength"), "+# to strength")
	H.eq("mods: normalize value", Mods.normalize("+7 to Strength"), "+# to strength")
	H.eq("mods: normalize percent range", Mods.normalize("(16-20)% increased Duration"), "#% increased duration")
	H.eq("mods: normalize percent value", Mods.normalize("20% increased Duration"), "#% increased duration")
	H.eq("mods: normalize decimals", Mods.normalize("Gains 0.15 Charges per Second"), "gains # charges per second")

	-- Exact tier resolution driven by the modifier value.
	local life = Mods.resolve("+120 to maximum Life", 82)
	H.eq("mods: life type", life and life.type, "Prefix")
	H.eq("mods: life tier", life and life.tier, 5)
	H.eq("mods: life level requirement", life and life.lvl, 60)
	H.eq("mods: life resolved exactly", life and life.exact, true)
	H.eq("mods: life group size", life and life.maxTier, 13)

	local fire = Mods.resolve("+45% to Fire Resistance", 82)
	H.eq("mods: fire resistance type", fire and fire.type, "Suffix")
	H.eq("mods: fire resistance tier", fire and fire.tier, 1)

	local cold = Mods.resolve("+38% to Cold Resistance", 82)
	H.eq("mods: cold resistance tier", cold and cold.tier, 2)

	local strength = Mods.resolve("+7 to Strength", 1)
	H.eq("mods: strength tier", strength and strength.tier, 9)

	-- Advanced copy carries both the rolled value and its tier range. When the value
	-- alone cannot pick a tier, the range decides - and a range that contradicts the
	-- value must win, because that range is what the game printed for this item.
	-- Note: the fire-resistance group stores parallel ladders (T9 "(5-7)" and
	-- T8 "(6-10)" both start at level 1), so the estimate reports the *best* tier
	-- reachable at that item level, which is T8.
	local withoutRange = Mods.resolve("+1% to Fire Resistance", 1)
	H.eq("mods: value outside every range -> estimate", withoutRange and withoutRange.exact, false)
	H.eq("mods: estimate reports best tier for item level", withoutRange and withoutRange.tier, 8)

	local advanced = Mods.resolve("+1% to Fire Resistance", 1, { { 36, 40 } })
	H.eq("mods: advanced copy range tier", advanced and advanced.tier, 2)
	H.eq("mods: advanced copy exact", advanced and advanced.exact, true)
	H.eq("mods: advanced copy level requirement", advanced and advanced.lvl, 71)

	-- Unknown text is reported, never guessed.
	H.eq("mods: unknown modifier resolves to nil", Mods.resolve("Totally not a real modifier", 82), nil)

	-- Rollable-tier statistics (group share, not spawn weights).
	local low = Mods.rollableStats(1)
	local high = Mods.rollableStats(100)
	H.eq("mods: rollable groups counted", high.groups > 700, true)
	H.eq("mods: t1 share grows with item level", high.t1Groups >= low.t1Groups, true)
	H.eq("mods: t1 percent within range", high.t1Percent >= 0 and high.t1Percent <= 100, true)
	H.eq("mods: average best tier improves with item level", high.avgBestTier <= low.avgBestTier, true)
	H.eq("mods: tiered groups tracked separately", high.tieredGroups > 0 and high.tieredGroups <= high.groups, true)
	H.eq("mods: tiered metrics defined", high.avgBestTierTiered > 0, true)

	-- Base restriction: modifiers that cannot spawn on gloves (jewels, flasks) must
	-- not inflate the ceiling. Without this the reported T1 share was ~99% nonsense.
	local glovesHints = Mods.hintsFor({ itemClass = "Gloves" })
	H.eq("mods: class fallback hints for gloves", glovesHints and glovesHints[1], "gloves")
	local gloves = Mods.rollableStats(82, glovesHints)
	H.eq("mods: base filter narrows the pool", gloves.groups < gloves.allGroups, true)
	H.eq("mods: base-filtered t1 share is realistic", gloves.t1Percent < 100, true)
	H.eq("mods: base-filtered average best tier is above T1", gloves.avgBestTier > 1, true)
	H.eq("mods: unknown class yields no hints", Mods.hintsFor({ itemClass = "" }), nil)

	-- Exact tags from Data/bases.lua beat the class fallback: a strength glove can
	-- also roll str_armour modifiers, which the bare "gloves" tag would miss.
	local baseHints, hintSource = Mods.hintsFor({ baseType = "Stocky Mitts", itemClass = "Gloves" })
	H.eq("mods: hints come from base data", hintSource, "base")
	H.contains("mods: base hints include the class tag", table.concat(baseHints, ","), "gloves")
	H.contains("mods: base hints include the defence tag", table.concat(baseHints, ","), "str_armour")
	local stocky = Mods.rollableStats(82, baseHints)
	H.eq("mods: exact base pool beats class-only pool", stocky.groups > gloves.groups, true)
	H.eq("mods: exact base pool stays bounded", stocky.groups < stocky.allGroups, true)

	-- The ceiling must react to item level; otherwise the number is decorative.
	local midLevel = Mods.rollableStats(40, baseHints)
	H.eq("mods: lower item level lowers the ceiling", midLevel.tieredT1 < stocky.tieredT1, true)
	H.eq("mods: lower item level worsens the average tier",
		midLevel.avgBestTierTiered > stocky.avgBestTierTiered, true)

	-- An unknown base (new league content) must degrade to the class fallback.
	local unknownBase, unknownSource = Mods.hintsFor({ baseType = "Base From Next League", itemClass = "Gloves" })
	H.eq("mods: unknown base falls back to class", unknownSource, "class")
	H.eq("mods: unknown base still yields hints", unknownBase and unknownBase[1], "gloves")

	-- Weighted roll pool: this is what turns "an Exalted Orb adds a mod" into
	-- "and here is the chance of each modifier".
	local baseItem = { baseType = "Stocky Mitts", itemClass = "Gloves" }
	baseHints = Mods.hintsFor(baseItem)
	local baseSources = Mods.sourcesFor(baseItem)
	H.eq("mods: equipment uses the item table", baseSources[1], "ModItem")
	H.eq("mods: flasks use the flask table", Mods.sourcesFor({ itemClass = "Life Flasks" })[1], "ModFlask")
	H.eq("mods: jewels use the jewel table", Mods.sourcesFor({ itemClass = "Jewels" })[1], "ModJewel")

	local pool = Mods.rollPool(82, baseHints, { side = "prefix", sources = baseSources })
	H.eq("mods: pool has tiers", pool.tierCount > 0, true)
	H.eq("mods: pool has groups", pool.groupCount > 0, true)
	H.eq("mods: prefix pool is prefix-only", pool.entries[1].type, "Prefix", nil)
	local sum = 0
	for _, entry in ipairs(pool.entries) do
		sum = sum + entry.chance
	end
	H.eq("mods: tier chances sum to 100%", math.abs(sum - 100) < 0.001, true)
	H.eq("mods: entries sorted by chance", pool.entries[1].chance >= pool.entries[#pool.entries].chance, true)
	H.eq("mods: life modifier has a real chance", Mods.groupChance(pool, "IncreasedLife|Prefix") > 0, true)

	-- A "default" spawn tag means "any base inside its own table", so flask/charm
	-- modifiers must never show up in an equipment pool.
	local flaskLeak = 0
	for _, entry in ipairs(pool.entries) do
		if tostring(entry.groupKey):find("Flask") or tostring(entry.groupKey):find("Charm") then
			flaskLeak = flaskLeak + 1
		end
	end
	H.eq("mods: no flask/charm modifiers in a gloves pool", flaskLeak, 0)

	local suffixPool = Mods.rollPool(82, baseHints, { side = "suffix", sources = baseSources })
	H.eq("mods: suffix pool is suffix-only", suffixPool.entries[1].type, "Suffix", nil)

	-- Greater / Perfect minimum modifier levels thin the pool.
	local greater = Mods.rollPool(82, baseHints, { side = "prefix", minModLevel = 35, sources = baseSources })
	local perfect = Mods.rollPool(82, baseHints, { side = "prefix", minModLevel = 50, sources = baseSources })
	H.eq("mods: min mod level thins the pool", greater.tierCount < pool.tierCount, true)
	H.eq("mods: higher floor thins it further", perfect.tierCount <= greater.tierCount, true)
	H.eq("mods: a floor never empties the pool", perfect.tierCount > 0, true)

	-- "One modifier per group": a group already on the item leaves the pool.
	local lifeChance = Mods.groupChance(pool, "IncreasedLife|Prefix")
	local withoutLife = Mods.rollPool(82, baseHints,
		{ side = "prefix", sources = baseSources, excludeGroups = { ["IncreasedLife|Prefix"] = true } })
	H.eq("mods: excluded group is gone", Mods.groupChance(withoutLife, "IncreasedLife|Prefix"), 0)
	H.eq("mods: exclusion removes its weight",
		math.abs(withoutLife.totalWeight - (pool.totalWeight * (1 - lifeChance / 100))) < 1, true)

	-- Integration: annotate a parsed item.
	local item = Mods.annotate(Parser.parse(RARE))
	H.eq("mods: prefix count", item.prefixCount, 1)
	H.eq("mods: suffix count", item.suffixCount, 2)
	H.eq("mods: open prefixes", item.openPrefixes, 2)
	H.eq("mods: open suffixes", item.openSuffixes, 1)
	H.eq("mods: tiers resolved exactly", item.tiersExact, 3)
	H.eq("mods: unclassified mods", item.unclassifiedMods, 0)
	H.eq("mods: tier attached to mod line", item.explicitMods[1].mod.tier, 5)
	H.eq("mods: mod line keeps its group", item.explicitMods[1].mod.groupKey, "IncreasedLife|Prefix")
	H.eq("mods: split complete for fully recognised item", item.affixSplitComplete, true)
	H.eq("mods: split consistent for a legal rare", item.affixSplitConsistent, true)

	-- A partially recognised item must not have its slots invented.
	local partial = Mods.annotate(Parser.parse(PARTIAL))
	H.eq("mods: unclassified counted", partial.unclassifiedMods, 1)
	H.eq("mods: split flagged incomplete", partial.affixSplitComplete, false)
	H.eq("mods: open prefixes withheld", partial.openPrefixes, nil)
	H.eq("mods: open suffixes withheld", partial.openSuffixes, nil)
	H.eq("mods: the recognised prefix is still counted", partial.prefixCount, 1)

	-- Four suffixes on a rare is impossible: withhold slot advice, do not guess.
	local inconsistent = Mods.annotate(Parser.parse(INCONSISTENT))
	H.eq("mods: four suffixes classified", inconsistent.suffixCount, 4)
	H.eq("mods: all lines recognised", inconsistent.affixSplitComplete, true)
	H.eq("mods: impossible split flagged", inconsistent.affixSplitConsistent, false)
	H.eq("mods: impossible split withholds slots", inconsistent.openSuffixes, nil)

	-- Invariants over the whole data set: normalization round-trips for every tier
	-- (proves the Lua and Python implementations agree on real data), and groups are
	-- ordered with tiers descending as level rises.
	local data = require("Data.mods")
	local roundTripIssues = 0
	local orderIssues = 0
	for groupKey, group in pairs(data.groups) do
		local previous = nil
		for _, tier in ipairs(group.tiers) do
			local normalized = Mods.normalize(tier.text)
			local bucket = data.index[normalized]
			local found = false
			if bucket then
				for _, candidate in ipairs(bucket) do
					if candidate == groupKey then
						found = true
						break
					end
				end
			end
			if not found then
				roundTripIssues = roundTripIssues + 1
			end

			if previous then
				if tier.lvl < previous.lvl or tier.tier ~= previous.tier - 1 then
					orderIssues = orderIssues + 1
				end
			end
			previous = tier
		end
	end
	H.check("mods: normalize round-trips for every tier", roundTripIssues == 0,
		"проблем=" .. roundTripIssues)
	H.check("mods: group tiers ordered by level, tier numbers descending", orderIssues == 0,
		"проблем=" .. orderIssues)

	-- Affix caps are not fixed at 3/3: amulet and ring implicits trade one side for the other
	-- ("+1 Prefix Modifier allowed", "-1 Suffix Modifier allowed"). Reading only the rarity reported
	-- slots the item does not have, which is the whole point of those bases.
	local Parser = require("Item.Parser")
	local function capsFor(itemText)
		local item = Parser.parse(itemText)
		Mods.annotate(item)
		return item
	end
	local SWAPPED = table.concat({
		"Item Class: Amulets",
		"Rarity: Rare",
		"Rapture Beads",
		"Stellar Amulet",
		"--------",
		"+1 Prefix Modifier allowed",
		"-1 Suffix Modifier allowed",
		"--------",
		"Item Level: 79",
		"--------",
		"{ Prefix Modifier \"Substantial\" (Tier: 1) }",
		"+38 to maximum Life",
		"{ Prefix Modifier \"Heated\" (Tier: 1) }",
		"+40 to maximum Mana",
		"{ Suffix Modifier \"of the Prism\" (Tier: 1) }",
		"+42% to Fire Resistance",
		"{ Suffix Modifier \"of the Ice\" (Tier: 1) }",
		"+38% to Cold Resistance",
	}, "\n")
	local swapped = capsFor(SWAPPED)
	H.eq("mods: the implicit raises the prefix cap", swapped.affixCaps.prefixes, 4)
	H.eq("mods: and lowers the suffix cap", swapped.affixCaps.suffixes, 2)
	-- Two prefixes and two suffixes on a 4/2 item: the prefix side still has room, the suffix side is
	-- exactly full. With the ordinary 3/3 caps the same item would report a free suffix instead.
	H.eq("mods: the raised prefix side has room", swapped.openPrefixes, 2)
	H.eq("mods: the reduced suffix side is exactly full", swapped.openSuffixes, 0)
	H.eq("mods: the caps record that they were adjusted", swapped.affixCaps.adjusted, true)
	H.eq("mods: and the split is accepted as consistent", swapped.affixSplitConsistent, true)

	-- The same item without the implicit has ordinary 3/3 caps and one free suffix, so the adjustment
	-- is real and not a blanket widening of every item.
	local PLAIN = (SWAPPED:gsub("%+1 Prefix Modifier allowed\n%-1 Suffix Modifier allowed\n", ""))
	local plain = capsFor(PLAIN)
	H.eq("mods: a plain amulet keeps three prefixes", plain.affixCaps.prefixes, 3)
	H.eq("mods: and three suffixes", plain.affixCaps.suffixes, 3)
	H.eq("mods: so two prefixes leave one prefix slot", plain.openPrefixes, 1)
	H.eq("mods: and its suffix side is still open", plain.openSuffixes, 1)
	H.eq("mods: a plain amulet reports no adjustment", plain.affixCaps.adjusted, nil)

	-- A crafted modifier that grants the same thing counts too (the Jewel-exclusive craft), and a
	-- reduced prefix side is what makes a three-prefix item full.
	local CRAFTED = table.concat({
		"Item Class: Jewels",
		"Rarity: Rare",
		"Entropy Shard",
		"Ruby",
		"--------",
		"Item Level: 80",
		"--------",
		"{ Suffix Modifier \"of the Craft\" (Tier: 1) }",
		"-1 Prefix Modifier allowed",
		"{ Prefix Modifier \"Heated\" (Tier: 1) }",
		"+18% to Fire Resistance",
		"{ Suffix Modifier \"of the Ice\" (Tier: 1) }",
		"+12 to Strength",
	}, "\n")
	local crafted = capsFor(CRAFTED)
	-- A Rare jewel's base caps are 2/2, so "-1 Prefix Modifier allowed" leaves one prefix slot, which the
	-- single prefix fills: the item is full on that side. The important part is that the cap-modifying
	-- modifier is READ at all; the numbers follow the jewel's real base, not the generic 3/3.
	H.eq("mods: a crafted cap-reducing modifier is counted", crafted.affixCaps.prefixes, 1)
	H.eq("mods: so one prefix was given up", crafted.affixCaps.base.prefixes, 2)
	H.eq("mods: and no prefix slot remains", crafted.openPrefixes, 0)

	-- Pipeline integrity. Two separate bugs in this project were an extractor that silently dropped
	-- whole families of data (139 of 305 runes, and every implicit modifier) while still reporting
	-- "skipped: 0", so the numbers in the generated tables are checked against the tables themselves
	-- here rather than trusted. A regeneration that loses a source file, a group or an entry now fails
	-- the suite instead of quietly shipping less data.
	local expectedSources = {
		"ModItem.lua", "ModItemExclusive.lua", "ModJewel.lua",
		"ModFlask.lua", "ModCharm.lua", "ModVeiled.lua",
	}
	local declared = { }
	for _, name in ipairs(data.sourceFiles or { }) do
		declared[name] = true
	end
	local missingSources = { }
	for _, name in ipairs(expectedSources) do
		if not declared[name] then
			missingSources[#missingSources + 1] = name
		end
	end
	H.check("mods: every source table still contributes", #missingSources == 0,
		table.concat(missingSources, ", "))

	local countedGroups, countedTiers = 0, 0
	for _, group in pairs(data.groups) do
		countedGroups = countedGroups + 1
		countedTiers = countedTiers + #(group.tiers or { })
	end
	H.eq("mods: the declared group count is the real one", (data.stats or { }).groups, countedGroups)
	H.eq("mods: the declared entry count is the real one", (data.stats or { }).entries, countedTiers)
	H.eq("mods: the extractor reports no unparsed layout", (data.stats or { }).skipped, 0)
	-- The implicit table is the one that used to be dropped entirely, so its presence is asserted
	-- directly rather than only through the source list.
	local implicitGroups = 0
	for _, group in pairs(data.groups) do
		if group.type == "Implicit" then
			implicitGroups = implicitGroups + 1
			break
		end
	end
	H.eq("mods: implicit modifiers are present at all", implicitGroups > 0, true)

	-- The other generated tables get the same treatment: their own stats against their own contents.
	local runeData = require("Data.runes")
	local runeNames, runeEntries = { }, 0
	for _, items in pairs((runeData.bySlot or { })) do
		for _, item in ipairs(items) do
			runeEntries = runeEntries + 1
			runeNames[item.name] = true
		end
	end
	local distinctRunes = 0
	for _ in pairs(runeNames) do
		distinctRunes = distinctRunes + 1
	end
	H.eq("mods: the rune table matches its declared entries", runeData.stats.entries, runeEntries)
	H.eq("mods: and its declared rune count", runeData.stats.runes, distinctRunes)
	H.eq("mods: and its declared slot count",
		runeData.stats.slots, (function()
			local slots = 0
			for _ in pairs(runeData.bySlot or { }) do
				slots = slots + 1
			end
			return slots
		end)())

	local essenceData = require("Data.essences")
	H.eq("mods: the essence table matches its declared count",
		essenceData.stats.essences, #(essenceData.list or { }))
	local baseData = require("Data.bases")
	local baseCount = 0
	for _ in pairs(baseData.tags or { }) do
		baseCount = baseCount + 1
	end
	H.eq("mods: the base table matches its declared count", baseData.stats.bases, baseCount)

	-- Loading the implicit table must not change the ROLL pool. Implicits share wording with explicit
	-- modifiers and they are 58% of the modifier table now, so if they leaked into the pool every shown
	-- chance would be diluted - and, worse, the panel would offer implicits as something a currency can
	-- roll. The pool may only draw from the item's own source tables.
	local GLOVES = Parser.parse(table.concat({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Andvarius' Hide",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		"+20 to maximum Life",
	}, "\n"))
	Mods.annotate(GLOVES)
	local rollPool = Mods.rollPool(GLOVES.itemLevel, GLOVES.baseHints, { sources = GLOVES.baseSources })
	H.check("mods: the roll pool is populated", rollPool ~= nil and rollPool.tierCount > 0)
	local implicitInPool, foreignSource = 0, 0
	for _, group in ipairs(rollPool.groups or { }) do
		if group.type == "Implicit" then
			implicitInPool = implicitInPool + 1
		end
		local allowed = false
		for _, source in ipairs(GLOVES.baseSources or { }) do
			if group.src == source then
				allowed = true
			end
		end
		if not allowed then
			foreignSource = foreignSource + 1
		end
	end
	H.eq("mods: the roll pool holds no implicit modifiers", implicitInPool, 0)
	H.eq("mods: and nothing from a table that cannot roll on this item", foreignSource, 0)
	-- A sanity band: gloves roll from a few hundred tiers. A number far outside it would mean the pool
	-- picked up another table (the implicit one has thousands of tiers).
	H.check("mods: the pool size is plausible", rollPool.tierCount > 50 and rollPool.tierCount < 600,
		tostring(rollPool.tierCount))
end
