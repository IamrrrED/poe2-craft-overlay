-- PoE2 Craft Overlay : Item/Mods.lua
-- Matches clipboard modifier lines against the item-modifier table extracted from
-- Path of Building (see tools/extract_mods.py -> Data/mods.lua).
--
-- Why: the game's clipboard text carries no prefix/suffix flag and no tier, yet both
-- decide what a crafting step can even do ("all three prefixes are taken, so an
-- Exalted Orb can only roll a suffix").
--
-- Tier resolution works from the *value*, not from the item level alone:
--   item line "+118 to maximum Life"  ->  data tier whose range is (100-120) -> exact
-- If no range contains the value, the best tier the item level can produce is reported
-- and marked `estimated = true` instead of being presented as fact.

local util = require("Core.util")
local Bases = require("Item.Bases")

local Mods = { }

-- Affix caps per rarity: Magic carries one prefix and one suffix, Rare three of each.
-- Normals and Uniques are not crafted with modifiers, so no caps are exposed for them.
local AFFIX_CAPS = {
	MAGIC = { prefixes = 1, suffixes = 1 },
	RARE = { prefixes = 3, suffixes = 3 },
}

-- Classes whose RARE caps differ from the generic three and three.
--
-- Jewels are the case that matters: a Rare jewel holds TWO prefixes and TWO suffixes. The third slot that
-- makes the strongest jewel craft possible comes from Potent Liquid of Contempt, which pushes ONE side to
-- three - and the item then states that as "+1 Suffix Modifier allowed", which affixCapDelta already reads.
-- Reading a jewel as 3/3 (or, as an earlier correction had it, 3/2) misreports both the finished state and
-- the technique that depends on it: the over-cap suffix side only exists once the emotion has been used.
-- Verified against 0.5.x sources while auditing which guide techniques still hold (docs/mentor-research.md).
local CLASS_CAPS = {
	jewels = { RARE = { prefixes = 2, suffixes = 2 } },
}

-- Item class -> base tags used by PoB's spawn weights. Tags are matched as
-- substrings, so "armour" covers str_armour / dex_armour / str_dex_armour and so on.
local CLASS_HINTS = {
	["Gloves"] = { "gloves" },
	["Boots"] = { "boots" },
	["Body Armours"] = { "armour" },
	["Helmets"] = { "helmet" },
	["Shields"] = { "shield" },
	["Quivers"] = { "quiver" },
	["Rings"] = { "ring" },
	["Amulets"] = { "amulet" },
	["Belts"] = { "belt" },
	["Jewels"] = { "jewel" },
	["Talismans"] = { "talisman" },
}

-- Fallback substrings for classes not covered by the exact table above.
local CLASS_WORDS = {
	"gloves", "boots", "helmet", "shield", "quiver", "ring", "amulet", "belt",
	"jewel", "flask", "charm", "bow", "crossbow", "wand", "staff", "sceptre",
	"sword", "axe", "mace", "dagger", "claw", "spear", "flail", "trap", "talisman",
	"armour",
}

local data = nil

local function ensureData()
	if data == nil then
		local ok, loaded = pcall(require, "Data.mods")
		if ok and type(loaded) == "table" and loaded.groups then
			data = loaded
		else
			-- Data file missing or unreadable: the overlay degrades to tier-less advice
			-- rather than failing to start.
			data = { groups = { }, index = { }, stats = { entries = 0 } }
		end
	end
	return data
end

--- Normalize modifier text for lookups.
-- MUST stay byte-for-byte in sync with normalize() in tools/extract_mods.py;
-- tests/test_mods.lua cross-checks both directions.
function Mods.normalize(text)
	local s = tostring(text):lower()
	-- Ranges collapse to one placeholder first, so "(5-8) to Strength" and
	-- "+7 to Strength" both become "+# to strength".
	s = s:gsub("%(%s*%-?%d+%.?%d*%s*%-%s*%-?%d+%.?%d*%s*%)", "#")
	s = s:gsub("%-?%d+%.?%d*", "#")
	s = s:gsub("%s+", " ")
	return util.trim(s)
end

--- Value ranges of a data template: "(5-8) to (10-12)" -> { {5,8}, {10,12} }.
function Mods.tierRanges(text)
	local ranges = { }
	local body = tostring(text)
	body = body:gsub("%(%s*(%-?%d+%.?%d*)%s*%-%s*(%-?%d+%.?%d*)%s*%)", function(a, b)
		ranges[#ranges + 1] = { tonumber(a), tonumber(b) }
		return ""
	end)
	for number in body:gmatch("%-?%d+%.?%d*") do
		ranges[#ranges + 1] = { tonumber(number), tonumber(number) }
	end
	return ranges
end

--- Plain numbers in an item modifier line: "+118 to maximum Life" -> { 118 }.
function Mods.values(text)
	local values = { }
	for number in tostring(text):gmatch("%-?%d+%.?%d*") do
		values[#values + 1] = tonumber(number)
	end
	return values
end

--- Does a reference (values or advanced-copy ranges) fit a tier's ranges?
-- * plain value v        -> must satisfy range.min <= v <= range.max
-- * advanced-copy (a-b)  -> must equal the tier range exactly
	local function rangesFit(reference, tierRanges)
	if #reference ~= #tierRanges then
		return false
	end
	for index, ref in ipairs(reference) do
		local tier = tierRanges[index]
		-- Both sides must be complete: a half-parsed range (typical for modifier text that
		-- came through translation) means "does not fit" rather than a crash.
		if not ref or ref[1] == nil or ref[2] == nil then
			return false
		end
		if not tier or tier[1] == nil or tier[2] == nil then
			return false
		end
		if ref[1] == ref[2] then
			if ref[1] < tier[1] or ref[1] > tier[2] then
				return false
			end
		elseif ref[1] ~= tier[1] or ref[2] ~= tier[2] then
			return false
		end
	end
	return true
end

local function bestTierForLevel(group, ilvl)
	local best = nil
	for _, tier in ipairs(group.tiers) do
		if not ilvl or tier.lvl <= ilvl then
			best = tier
		else
			break
		end
	end
	return best or group.tiers[1]
end

--- Base tags a tier can roll on ("gloves", "belt,default", ...), split lazily.
local function basesOf(tier)
	if tier._bases then
		return tier._bases
	end
	local list = { }
	if tier.bases and tier.bases ~= "" then
		for base in tostring(tier.bases):gmatch("[^,]+") do
			list[#list + 1] = base
		end
	end
	tier._bases = list
	return list
end

--- Spawn tags identifying the item's modifier pool.
-- Prefers the exact tags of the item's base type (Data/bases.lua, generated from
-- PoB's base tables) and falls back to item-class hints when the base is unknown
-- (a base added by a newer patch, or hand-written item text).
-- @return hints table, source ("base" | "class" | nil)
function Mods.hintsFor(item)
	if not item then
		return nil, nil
	end

	local baseName = item.baseType
	if baseName and baseName ~= "" then
		local raw = Bases.tags(baseName)
		if not raw then
			-- The name may carry affix words around the base. The parser normalises the base when it
			-- reads the name, so this is the second line of defence for an item table built by hand.
			local found = Bases.find(baseName)
			if found then
				item.baseType = found
				item.baseTypeFromName = true
				raw = Bases.tags(found)
			end
		end
		if raw then
			local hints = { }
			for tag in tostring(raw):gmatch("[^,]+") do
				hints[#hints + 1] = tag
			end
			if #hints > 0 then
				return hints, "base"
			end
		end
	end

	local class = tostring(item.itemClass or "")
	if class == "" then
		return nil, nil
	end
	local exact = CLASS_HINTS[class]
	if exact then
		return exact, "class"
	end
	local lowered = class:lower()
	local hints = { }
	for _, word in ipairs(CLASS_WORDS) do
		if lowered:find(word, 1, true) then
			hints[#hints + 1] = word
		end
	end
	if #hints == 0 then
		return nil, nil
	end
	return hints, "class"
end

--- Can this tier spawn on an item described by `hints`?
-- @param tier table
-- @param hints base tags (nil = no restriction)
-- @param sources optional allowed source tables; in PoB data a "default" spawn tag
--        means "any base within this table", so the table must match too
--- May a group read from `groupSource` describe this item at all?
-- The item's own source table decides: gear is ModItem, jewels ModJewel, flasks ModFlask. A group from
-- another table sharing the same wording (the implicit table mirrors plenty of explicit stats) is not a
-- candidate, and treating it as one made tier estimates wrong.
-- @param groupSource string table the group came from ("ModItemExclusive", ...)
-- @param sources table|nil allowed tables for this item
function Mods.sourceAllowed(groupSource, sources)
	if not sources then
		return true
	end
	for _, source in ipairs(sources) do
		if source == groupSource then
			return true
		end
	end
	return false
end

function Mods.tierEligible(tier, hints, sources, groupSource)
	if not Mods.sourceAllowed(groupSource, sources) then
		return false
	end

	if not hints then
		return true
	end

	local bases = basesOf(tier)
	if #bases == 0 then
		-- No spawn weights recorded: refusing would hide a legitimate modifier.
		return true
	end
	for _, base in ipairs(bases) do
		if base == "default" then
			-- Wildcard *within a table*: only meaningful once the table matched.
			-- Without a source filter this would leak flask mods into gloves.
			if sources then
				return true
			end
		else
			for _, hint in ipairs(hints) do
				if base:find(hint, 1, true) then
					return true
				end
			end
		end
	end
	return false
end

--- Modifier tables (Data/mods.lua sources) that apply to an item class.
function Mods.sourcesFor(item)
	local class = tostring(item and item.itemClass or ""):lower()
	if class == "" then
		return nil
	end
	if class:find("flask", 1, true) then
		return { "ModFlask" }
	end
	if class:find("charm", 1, true) then
		return { "ModCharm" }
	end
	if class:find("jewel", 1, true) then
		return { "ModJewel" }
	end
	return { "ModItem" }
end

--- Resolve one modifier line to { groupKey, type, tier, lvl, affix, text, exact }.
-- @param text item modifier line as parsed from the clipboard
-- @param ilvl item level, used for the estimate fallback
-- @param knownRanges optional { {min,max}, ... } taken from an advanced-copy line
-- @param hints optional base tags: candidates that can spawn on that base are
--        preferred, and only accepted exclusively when such a match exists
function Mods.resolve(text, ilvl, knownRanges, hints, sources)
	local store = ensureData()
	local key = Mods.normalize(text)
	local buckets = store.index[key]
	if not buckets then
		return nil, key
	end

	local values = Mods.values(text)
	local reference = knownRanges
	if (not reference or #reference == 0) and #values > 0 then
		reference = { }
		for _, value in ipairs(values) do
			reference[#reference + 1] = { value, value }
		end
	end

	local function makeInfo(groupKey, group, tier, exact)
		return {
			groupKey = groupKey,
			type = group.type,
			tier = tier.tier,
			lvl = tier.lvl,
			affix = tier.affix,
			text = tier.text,
			maxTier = #group.tiers,
			exact = exact,
		}
	end

	local function search(requireEligible)
		local exactInfo, estimateInfo = nil, nil
		for _, groupKey in ipairs(buckets) do
			local group = store.groups[groupKey]
			-- A group read from a table that cannot roll on this kind of item is not a candidate at
			-- all. This matters now that the implicit table is loaded: it shares stat wording with
			-- explicit modifiers ("+1% to Fire Resistance"), and without this filter an implicit group
			-- with more tiers answered for an explicit modifier - the tier estimate jumped from 8 to
			-- 35 and a value that fits no range was reported as an exact match.
			if group and not Mods.sourceAllowed(group.src, sources) then
				group = nil
			end
			-- Implicits are their own table now, and with no source list to go by they must not answer
			-- for a modifier line: an implicit "+(7-10)% to all Elemental Resistances" shares wording
			-- with explicit stats, and letting it compete made the tier estimate wrong. A caller that
			-- wants implicits asks for them by naming the table.
			if group and group.type == "Implicit" and not sources then
				group = nil
			end
			if group then
				-- Exact tier: the value (or advanced-copy range) fits the tier's ranges.
				if reference and #reference > 0 then
					for _, tier in ipairs(group.tiers) do
						if (not requireEligible or Mods.tierEligible(tier, hints, sources, group.src))
							and rangesFit(reference, Mods.tierRanges(tier.text)) then
							exactInfo = makeInfo(groupKey, group, tier, true)
							break
						end
					end
				end
				if exactInfo then
					break
				end

				-- Estimate: the best tier this item level can produce. Collected but
				-- never allowed to hide an exact match from the other pass.
				local best = nil
				for _, tier in ipairs(group.tiers) do
					if (not ilvl or tier.lvl <= ilvl)
						and (not requireEligible or Mods.tierEligible(tier, hints, sources, group.src)) then
						best = tier
					end
				end
				if best and (not estimateInfo or best.tier < estimateInfo.tier) then
					estimateInfo = makeInfo(groupKey, group, best, false)
				end
			end
		end
		return exactInfo, estimateInfo
	end

	-- Prefer modifiers that can spawn on this base type, but an exact value match from
	-- the unrestricted pass always beats a bare estimate from the restricted one.
	local exactRestricted, estimateRestricted = search(true)
	if exactRestricted then
		return exactRestricted, key
	end
	local exactAny, estimateAny = search(false)
	if exactAny then
		return exactAny, key
	end
	return estimateRestricted or estimateAny, key
end

--- Which side does an annotation line name, if it is one?
--
-- The game prints a line above each modifier: "{ Prefix Modifier \"Baronness'\" (Tier: 8) }" in
-- English, "{ Префикс \"Непоколебимое\" (Уровень: 1) }" in Russian, with "Очернённое" (desecrated)
-- and "Ремесленное" (crafted) as extra words. Reading the side out of that line is what makes the
-- split independent of the translation dictionary, which covers modifier wording only partly.
-- @return "prefix" | "suffix" | nil
local function annotationSide(line)
	local text = tostring(line or "")
	if text == "" then
		return nil
	end
	local has = function(needle) return text:find(needle, 1, true) ~= nil end
	if not (has("{") and has("}")) then
		return nil
	end
	if has("Префикс") or has("Prefix") then
		return "prefix"
	end
	if has("Суффикс") or has("Suffix") then
		return "suffix"
	end
	return nil
end

--- Is this brace annotation the implicit block rather than a real affix?
--
-- The game also brackets implicits: "{ Implicit Modifier — Mana }" / "{ Собственное свойство — Мана }". That
-- annotation names no side, so the line used to fall through to the resolver, fail, and count as an
-- UNCLASSIFIED modifier - which switched `affixSplitComplete` off for every item that had an implicit. The
-- practical symptom on a real Russian amulet: three prefixes and three suffixes were read correctly, yet the
-- panel reported the split as unknown and offered a currency to add a modifier to a full item.
local function annotationIsImplicit(line)
	local text = tostring(line or "")
	if not (text:find("{", 1, true) and text:find("}", 1, true)) then
		return false
	end
	return text:find("Implicit", 1, true) ~= nil
		or text:find("Собственное свойство", 1, true) ~= nil
end

local function annotateBucket(item, bucket, kind, hints, sources)	-- The game writes each modifier's side into the copied text, and the parser keeps those
	-- annotation lines ("{ Prefix Modifier ... }"), which is the one source of truth about the split
	-- that does not depend on knowing the modifier's English wording. It matters for a Russian
	-- client: the dictionary translates modifier text only partly, so the matcher misses some lines
	-- while their own annotation names the side plainly. Without this the item looked half empty
	-- (three prefixes, no suffixes) and the plan offered an Exalted Orb for an item that was full -
	-- or, after the advisor learned to distrust an incomplete split, the opposite mistake: Chaos for
	-- an item that still had room.
	local expectedSide = nil
	local groupSeen = false
	for _, mod in ipairs(bucket or { }) do
		-- The implicit block: its annotation names no side, and every line under it is an implicit, not an
		-- affix. Without this the block counted as unclassified and the whole split was distrusted.
		if annotationIsImplicit(mod.line) then
			expectedSide = "implicit"
			groupSeen = false
			mod.annotation = true
			goto continue
		end
		if expectedSide == "implicit" and not mod.line:find("{", 1, true) then
			mod.implicitText = true
			mod.kind = "implicit"
			mod.bucket = "implicitMods"
			goto continue
		end
		local side = annotationSide(mod.line)
		if side then
			-- An annotation is not a modifier. It names the side the stat lines below belong to,
			-- and it is counted once per group: a prefix may carry two stat lines ("+23 to maximum
			-- Energy Shield" and "34% increased Energy Shield" are one affix).
			expectedSide = side
			groupSeen = false
			mod.annotation = true
			goto continue
		end

		local info = Mods.resolve(mod.text, item.itemLevel, mod.ranges, hints, sources)
		-- The annotation the game prints above a modifier names its side, and that beats our data. The
		-- probe that found this: "19% increased Rarity of Items found" is a SUFFIX in Path of Building's
		-- tables, but a helmet can carry it as a PREFIX ("Exotic"), and the game says so in the line
		-- above it. Trusting the table's type counted that prefix as a suffix, and the item came out as
		-- 2 prefixes and 4 suffixes - a shape no rare can have, which switched slot advice off entirely.
		-- The resolution is still used for the TIER, which the annotation only names, not describes.
		if expectedSide then
			mod.kind = kind
			-- The annotation is the authority for the SIDE, so it is recorded on the mod itself. The resolved
			-- table still supplies the tier, but its `type` comes from Path of Building and disagrees with the
			-- game on some modifiers ("+123 to maximum Life" is a PREFIX on an amulet and a SUFFIX in the
			-- table). Anything that asks a modifier what side it is on - the market search, for one - has to
			-- get the game's answer, not the table's.
			mod.side = expectedSide
			if info then
				mod.mod = info
			end
			if not groupSeen then
				if expectedSide == "prefix" then
					item.prefixCount = (item.prefixCount or 0) + 1
				else
					item.suffixCount = (item.suffixCount or 0) + 1
				end
				groupSeen = true
				-- Affix-level counters. Counting stat LINES instead reported seven affixes and seven tier
				-- verdicts for a six-affix item, because a prefix may carry two stat lines. What the panel
				-- reports is how many AFFIXES exist and how many of their tiers are exact, so that is what
				-- is counted.
				item.sideFromAnnotation = (item.sideFromAnnotation or 0) + 1
				if info then
					if info.exact then
						item.tiersExact = (item.tiersExact or 0) + 1
					else
						item.tiersEstimated = (item.tiersEstimated or 0) + 1
					end
				end
			end
		elseif info then
			mod.mod = info
			mod.kind = kind
			if info.type == "Prefix" then
				item.prefixCount = (item.prefixCount or 0) + 1
				groupSeen = true
			elseif info.type == "Suffix" then
				item.suffixCount = (item.suffixCount or 0) + 1
				groupSeen = true
			else
				item.unclassifiedMods = (item.unclassifiedMods or 0) + 1
			end
			if info.exact then
				item.tiersExact = (item.tiersExact or 0) + 1
			else
				item.tiersEstimated = (item.tiersEstimated or 0) + 1
			end
		else
			item.unclassifiedMods = (item.unclassifiedMods or 0) + 1
		end

		::continue::
	end
end

--- How many prefix and suffix slots a single modifier lines grant or remove.
--
-- The wording is the only reliable signal here, and it has to be read from the text rather than from the
-- table keys: in Path of Building's data the group called "PrefixSuffixAllowed|Prefix" carries the text
-- "+1 Suffix Modifier allowed" and is typed "Prefix" - the two are swapped relative to their names. The
-- text is what the game prints on the item, so the text is what decides.
-- @param text modifier line
-- @return prefixes, suffixes (either may be 0)
local function affixCapDelta(text)
	local delta = { prefixes = 0, suffixes = 0 }
	if type(text) ~= "string" then
		return delta
	end
	-- Both spellings appear: "+1 Prefix Modifier allowed" and "+2 Prefix Modifiers allowed", and the
	-- sign can be negative on the other side of the same implicit.
	for amount in text:gmatch("([%-+]?%d+)%s+Prefix Modifiers? allowed") do
		delta.prefixes = delta.prefixes + tonumber(amount)
	end
	for amount in text:gmatch("([%-+]?%d+)%s+Suffix Modifiers? allowed") do
		delta.suffixes = delta.suffixes + tonumber(amount)
	end
	return delta
end

--- The prefix/suffix cap for this item, taking its implicit modifiers into account.
-- @param item parsed item
-- @param rarity the rarity to take the base caps from
-- @return caps table or nil
local function affixCapsFor(item, rarity)
	local base = AFFIX_CAPS[rarity or ""]
	if not base then
		return nil
	end
	-- A class can override the generic caps. Jewels hold three prefixes and only two suffixes, which is
	-- exactly what makes the league's strongest jewel craft work, so getting this wrong changes the advice.
	local classKey = tostring((item or { }).itemClass or ""):lower()
	local override = CLASS_CAPS[classKey] and CLASS_CAPS[classKey][rarity or ""]
	if override then
		base = override
	end
	local prefixes, suffixes = base.prefixes, base.suffixes
	local adjusted = false
	-- Implicits, and any explicit modifier that states the same thing (a Jewel-exclusive craft grants
	-- "+1 Prefix Modifier allowed" as a suffix).
	for _, bucket in ipairs({ item.implicitMods or { }, item.explicitMods or { }, item.craftedMods or { } }) do
		for _, mod in ipairs(bucket) do
			local text = type(mod) == "table" and mod.text or mod
			local delta = affixCapDelta(text)
			if delta.prefixes ~= 0 or delta.suffixes ~= 0 then
				prefixes = prefixes + delta.prefixes
				suffixes = suffixes + delta.suffixes
				adjusted = true
			end
		end
	end
	if not adjusted then
		return base
	end
	-- A cap below zero is not a slot count; refuse rather than report a negative number of slots.
	prefixes = math.max(0, prefixes)
	suffixes = math.max(0, suffixes)
	return { prefixes = prefixes, suffixes = suffixes, base = base, adjusted = true }
end

--- Enrich a parsed item with prefix/suffix counts and per-mod tier information.
-- Non-destructive: original fields are kept, new ones are added.
function Mods.annotate(item)
	item.prefixCount = 0
	item.suffixCount = 0
	item.unclassifiedMods = 0
	item.tiersExact = 0
	item.tiersEstimated = 0

	-- Base tags let the matcher prefer modifiers that can actually spawn on this item;
	-- the source table keeps flask/charm/jewel tables out of equipment pools.
	local hints = Mods.hintsFor(item)
	item.baseHints = hints
	local sources = Mods.sourcesFor(item)
	item.baseSources = sources

	-- Some classes have no modifier pool in our data at all: waystones, tablets, relics and wombgifts
	-- are not in Path of Building's modifier tables, and the trade API publishes only item names. An
	-- unclassified modifier there is not a parsing failure, it is an absent pool, and the difference
	-- matters a great deal: treating it as "everything is classified, and there are six affixes" made
	-- the panel call a one-modifier rare FULL and withhold advice that was perfectly valid.
	if item.itemClass and not hints then
		item.poolMissing = true
	end

	annotateBucket(item, item.explicitMods, "explicit", hints, sources)
	annotateBucket(item, item.craftedMods, "crafted", hints, sources)
	annotateBucket(item, item.desecratedMods, "desecrated", hints, sources)

	item.modsAnnotated = item.prefixCount + item.suffixCount

	-- The prefix/suffix split is only trustworthy when every modifier was recognised
	-- AND the result is arithmetically possible. A rare cannot carry four suffixes;
	-- if classification says otherwise, one line was misread, so slot-based advice is
	-- withheld instead of being derived from impossible data.
	-- The caps are not fixed at 3/3 for every rare: amulet and ring implicits trade one side for the
	-- other ("+1 Prefix Modifier allowed", "-2 Suffix Modifiers allowed"), which is exactly what those
	-- bases exist for. Reading only the rarity reported slots the item does not have.
	local caps = affixCapsFor(item, item.rarity)
	item.affixCaps = caps
	item.affixSplitComplete = (item.unclassifiedMods == 0) and (item.modsAnnotated > 0)

	local consistent = caps ~= nil
		and item.prefixCount <= caps.prefixes
		and item.suffixCount <= caps.suffixes
	item.affixSplitConsistent = consistent

	if caps and item.affixSplitComplete and consistent then
		item.openPrefixes = math.max(0, caps.prefixes - item.prefixCount)
		item.openSuffixes = math.max(0, caps.suffixes - item.suffixCount)
	else
		item.openPrefixes = nil
		item.openSuffixes = nil
	end
	return item
end

--- Spawn weights of a tier, split lazily from "gloves=1,belt=1" into a map.
local function weightsOf(tier)
	if tier._weights then
		return tier._weights
	end
	local map = { }
	if tier.w and tier.w ~= "" then
		for pair in tostring(tier.w):gmatch("[^,]+") do
			local tag, value = pair:match("^([^=]+)=(%-?%d+)$")
			if tag then
				map[tag] = tonumber(value)
			end
		end
	end
	tier._weights = map
	return map
end

--- Craft of Exile weights, loaded once: text -> modifier id, bases, and weights per base.
-- The join between our wording and theirs was done in Python (tools/map_mod_texts.py), so no
-- normalisation happens here: the map is keyed by our own text exactly as it appears in the data.
-- Data missing means nil, and every caller falls back to the tag-based weights below.
local coe = nil

local function ensureCoe()
	if coe == nil then
		local okA, textMap = pcall(require, "Data.coe_text_map")
		local okB, bases = pcall(require, "Data.coe_bases")
		local okC, weights = pcall(require, "Data.coe_weights")
		if okA and okB and okC
			and type(textMap) == "table" and type(bases) == "table" and type(weights) == "table" then
			coe = {
				textToId = textMap.map or { },
				bases = bases.bases or { },
				weights = weights.weights or { },
			}
		else
			coe = false
		end
	end
	return coe
end

--- Weight of a tier from Craft of Exile data, or nil when it holds nothing for this case.
-- Craft of Exile states a weight per base and item level, as a list of { ilvl, weight } rows.
-- The row that applies is the one with the highest ilvl that does not exceed the item's level.
-- Keys are strings on both sides of the lookup: in Lua t["5049"] and t[5049] are different keys,
-- and the generated tables are keyed by strings.
function Mods.coeTierWeight(tier, ilvl, baseName)
	local store = ensureCoe()
	if not store or not tier or not baseName then
		return nil
	end
	local base = store.bases[baseName]
	if not base or not base.id_bitem then
		return nil
	end
	local modifierId = store.textToId[tier.text]
	if not modifierId then
		return nil
	end
	local perBase = store.weights[tostring(modifierId)]
	local rows = perBase and perBase[tostring(base.id_bitem)]
	if type(rows) ~= "table" then
		return nil
	end
	local best = nil
	for _, row in ipairs(rows) do
		local level = tonumber(row.ilvl) or 0
		if (not ilvl or level <= ilvl) and (not best or level > best.level) then
			best = { level = level, weight = tonumber(row.weight) }
		end
	end
	if best and best.weight then
		return best.weight, best.level
	end
	return nil
end

--- Spawn weight of a tier for a base described by `hints`.
-- Exact weights from Craft of Exile win when they exist for this base and item level; otherwise
-- the tag-based weights from Path of Building are used, and the second return value says which
-- of the two answered, so the caller can mark an approximation as one.
-- Weights are stored per base tag; the heaviest non-"default" tag that the base
-- carries wins, and "default" is the fallback. Returns nil when the modifier cannot
-- spawn on that base at all.
function Mods.tierWeight(tier, hints, ilvl, baseName)
	local exact = Mods.coeTierWeight(tier, ilvl, baseName)
	if exact then
		return exact, "coe"
	end
	local map = weightsOf(tier)
	local best = nil
	for _, hint in ipairs(hints or { }) do
		if hint ~= "default" then
			local weight = map[hint]
			if weight and (not best or weight > best) then
				best = weight
			end
		end
	end
	if best then
		return best, "weights"
	end
	local fallback = map["default"]
	if fallback then
		return fallback, "weights"
	end
	return nil
end

--- Tiers of a group that a roll can produce at this item level, honouring a
-- minimum modifier level (Greater / Perfect currency floors).
-- Rule from the patch notes: a floor never removes a modifier family entirely - if
-- no tier reaches the floor, the family's best available tier stays in the pool.
local function tiersForRoll(group, ilvl, minModLevel)
	local eligible = { }
	for _, tier in ipairs(group.tiers) do
		if not ilvl or tier.lvl <= ilvl then
			eligible[#eligible + 1] = tier
		end
	end
	if minModLevel and minModLevel > 0 and #eligible > 0 then
		local above = { }
		for _, tier in ipairs(eligible) do
			if tier.lvl >= minModLevel then
				above[#above + 1] = tier
			end
		end
		if #above > 0 then
			eligible = above
		end
	end
	return eligible
end

--- Weighted pool of modifiers a random roll can produce.
-- @param ilvl item level
-- @param hints base tags (see hintsFor)
-- @param opts table {
--   side = "prefix" | "suffix" | nil (nil = both sides),
--   minModLevel = number|nil (currency floor),
--   excludeGroups = table|nil (modifier groups already on the item),
--   sources = table|nil (allowed source tables, see sourcesFor),
-- }
-- @return table { totalWeight, entries (per tier, sorted by chance), groups (aggregated) }
function Mods.rollPool(ilvl, hints, opts)
	opts = opts or { }
	local store = ensureData()
	local wanted = opts.side and opts.side:lower() or nil
	local excluded = opts.excludeGroups or { }

	local total = 0
	local entries = { }
	local groups = { }

	for groupKey, group in pairs(store.groups) do
		if not excluded[groupKey] and (not wanted or tostring(group.type):lower() == wanted) then
			for _, tier in ipairs(tiersForRoll(group, ilvl, opts.minModLevel)) do
				if Mods.tierEligible(tier, hints, opts.sources, group.src)
					and (not opts.keep or opts.keep(tier.text))
					-- A modifier the item already carries must not be offered again, and the
					-- text is the reliable key: the same wording can live in another group.
					and not (opts.excludeTexts and opts.excludeTexts[tier.text]) then
					local weight, weightSource = Mods.tierWeight(tier, hints, ilvl, opts.baseName)
					if weight and weight > 0 then
						total = total + weight
						entries[#entries + 1] = {
							groupKey = groupKey,
							type = group.type,
							-- The table the tier came from. Carried through so a caller can prove the pool
							-- only holds modifiers that can actually roll on this item.
							src = group.src,
							tier = tier.tier,
							lvl = tier.lvl,
							text = tier.text,
							affix = tier.affix,
							weight = weight,
							-- "coe" means the weight came from the base-specific table; anything
							-- else is the tag-based approximation and may be reported as such.
							weightSource = weightSource,
						}
					end
				end
			end
		end
	end

	for _, entry in ipairs(entries) do
		entry.chance = total > 0 and (entry.weight * 100 / total) or 0
		local aggregate = groups[entry.groupKey]
		if not aggregate then
			aggregate = {
				groupKey = entry.groupKey,
				type = entry.type,
				src = entry.src,
				weight = 0,
				chance = 0,
				tierCount = 0,
				bestTier = entry.tier,
				bestText = entry.text,
				affix = entry.affix,
			}
			groups[entry.groupKey] = aggregate
		end
		aggregate.weight = aggregate.weight + entry.weight
		-- Where a group's weights came from: "coe" while every tier answered from the base-specific
		-- table, "mixed" once the tag-based approximation is involved. Surfaced so a player can tell
		-- an exact number from an estimated one.
		if aggregate.weightSource == nil then
			aggregate.weightSource = entry.weightSource
		elseif aggregate.weightSource ~= entry.weightSource then
			aggregate.weightSource = "mixed"
		end		-- Counts as well as weights: the desecration reveal model draws modifiers, so it
		-- needs how many eligible modifiers a group offers and how large the pool is.
		aggregate.tierCount = (aggregate.tierCount or 0) + 1
		if entry.tier < aggregate.bestTier then
			aggregate.bestTier = entry.tier
			aggregate.bestText = entry.text
		end
	end

	table.sort(entries, function(a, b)
		if a.chance == b.chance then
			return a.tier < b.tier
		end
		return a.chance > b.chance
	end)

	local groupList = { }
	for _, aggregate in pairs(groups) do
		aggregate.chance = total > 0 and (aggregate.weight * 100 / total) or 0
		groupList[#groupList + 1] = aggregate
	end
	table.sort(groupList, function(a, b)
		if a.chance == b.chance then
			return a.groupKey < b.groupKey
		end
		return a.chance > b.chance
	end)

	return {
		totalWeight = total,
		entries = entries,
		groups = groupList,
		tierCount = #entries,
		groupCount = #groupList,
		side = opts.side,
		minModLevel = opts.minModLevel,
	}
end

--- Add the "three options offered" (reveal) chances to a pool's groups.
--
-- Only pools that are revealed rather than rolled need this - desecration at the Well of
-- Souls - so it is a separate step: the weighted share stays the primary number and the
-- reveal chance is attached next to it.
-- @param pool pool from Mods.rollPool / Mods.desecrationPool
-- @param opts { draws = number|nil, echoes = boolean|nil }
function Mods.attachReveal(pool, opts)
	opts = opts or { }
	if not pool then
		return nil
	end
	local draws = opts.draws or 3
	local size = pool.tierCount or 0
	pool.reveal = {
		draws = draws,
		poolSize = size,
		echoes = opts.echoes == true,
	}
	for _, group in ipairs(pool.groups or { }) do
		local targets = group.tierCount or 1
		group.revealChance = Mods.revealChance(size, targets, draws, false)
		group.revealEchoes = Mods.revealChance(size, targets, draws, true)
	end
	return pool
end

--- Chance that a specific modifier group comes up in a pool (0 when absent).
function Mods.groupChance(pool, groupKey)
	for _, aggregate in ipairs(pool.groups or { }) do
		if aggregate.groupKey == groupKey then
			return aggregate.chance
		end
	end
	return 0
end

--- Resolve a modifier *entry key* from PoB data ("IncreasedLife7") to its group/tier.
-- Guaranteed crafts (essences, alloys) reference modifiers by key, not by text.
function Mods.byKey(key)
	local store = ensureData()
	local entry = store.byKey and store.byKey[key]
	if not entry then
		return nil
	end
	local groupKey, tierNumber = tostring(entry):match("^(.-)|(%d+)$")
	if not groupKey or not tierNumber then
		return nil
	end
	local group = store.groups[groupKey]
	if not group then
		return nil
	end
	local wanted = tonumber(tierNumber)
	for _, tier in ipairs(group.tiers) do
		if tier.tier == wanted then
			return {
				groupKey = groupKey,
				type = group.type,
				tier = tier.tier,
				lvl = tier.lvl,
				text = tier.text,
				affix = tier.affix,
				maxTier = #group.tiers,
				exact = true,
				key = key,
			}
		end
	end
	return nil
end

--- The modifier texts an item already carries.
-- Pools that must not offer a modifier twice (desecration) use this: the same wording can
-- appear in a different group, so a group key alone is not enough.
function Mods.presentTexts(item)
	local set = { }
	if not item then
		return set
	end
	for _, list in ipairs({ item.explicitMods, item.implicitMods, item.desecratedMods, item.craftedMods }) do
		for _, mod in ipairs(list or { }) do
			if type(mod) == "table" and type(mod.text) == "string" then
				set[mod.text] = true
			end
		end
	end
	return set
end
--- Reduce a modifier line to a comparable template: numbers become '#'.
local function desecrationTemplate(text)
	local value = tostring(text)
	value = value:gsub("%(%s*[-+]?%d+%.?%d*%s*%-%s*[-+]?%d+%.?%d*%s*%)", "#")
	value = value:gsub("[-+]?%d+%.?%d*", "#")
	value = value:gsub("%+", "")
	value = value:gsub("#%s+#", "#")
	value = value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return value:lower()
end

--- Desecration pool: the modifiers the Well of Souls can offer.
--
-- What counts as desecrated is decided by the official trade API - stat type `desecrated`,
-- 749 entries in English and Russian (Data/desecrated.lua) - and matched here by the
-- modifier's text template. The local tag this used to filter by only covered 36
-- breach-themed modifiers and missed the plain ones the game really offers, which is why
-- the Well of Souls kept proposing modifiers the overlay did not list.
-- Levels, tiers and spawn weights still come from the datamined table, so eligibility and
-- the odds are computed exactly like in every other pool.
function Mods.desecrationPool(ilvl, hints, opts)
	opts = opts or { }
	local official = require("Data.desecrated")
	local allowed = { }
	for template in pairs(official.byTemplate or { }) do
		allowed[template] = true
	end
	for template in pairs(official.byTemplateEn or { }) do
		allowed[template] = true
	end
	local allowedCount = 0
	for _ in pairs(allowed) do
		allowedCount = allowedCount + 1
	end

	local function keep(text)
		return allowed[desecrationTemplate(text)] == true
	end

	local pool = Mods.rollPool(ilvl, hints, {
		side = opts.side,
		excludeGroups = opts.excludeGroups,
		keep = keep,
	})
	if pool then
		pool.officialTemplates = allowedCount
		pool.filter = "official desecrated stat set (data/trade2/stats)"
	end
	return pool
end

--- Templates of the official alloy ("augment") stat set, cached for the process.
-- Data/augments.lua is generated from the trade API's own stat type `augment` (595 entries,
-- English and Russian). The local affix that used to select alloys ("Verisium") disagreed
-- with this set on half of the modifiers, so the official one decides the membership.
local alloyTemplateCache = nil
local function alloyTemplates()
	if alloyTemplateCache == nil then
		local ok, data = pcall(require, "Data.augments")
		local set = { }
		if ok and type(data) == "table" then
			for template in pairs(data.byTemplate or { }) do
				set[template] = true
			end
			for template in pairs(data.byTemplateEn or { }) do
				set[template] = true
			end
		end
		alloyTemplateCache = set
	end
	return alloyTemplateCache
end
--- Alloy-only modifier pool.
-- PoB marks alloy modifiers with the "Verisium" (prefix) / "of the Stars" (suffix)
-- affix and gives them NO spawn weight, i.e. they never come out of a random pool.
-- Because the weights are absent, their odds are genuinely unknown: the caller is told
-- so via oddsKnown = false instead of being handed invented numbers. PoB also carries
-- no alloy -> modifier mapping, so this is a pool, not a per-alloy answer.
-- @param ilvl item level to filter by tier level
-- @return { tierCount, entries = { { text, tier, lvl, affix, type, groupKey } }, oddsKnown = false }
function Mods.alloyPool(ilvl)
	local store = ensureData()
	local level = tonumber(ilvl) or 100
	local entries = { }
	for groupKey, group in pairs(store.groups) do
		for _, tier in ipairs(group.tiers) do
			local affix = tostring(tier.affix or "")
			-- Membership comes from the official augment stat set; the affix is kept only as a
			-- label. Modifiers the official set does not list (some are unique-item mods) are
			-- not alloys and no longer appear here.
			-- Membership comes from the official augment stat set (Data/augments.lua, 595
			-- entries of the trade API's own stat type). The local affix alone disagreed with it
			-- on half of the modifiers, including some that are not alloys at all.
			local officialAlloys = alloyTemplates()
			if (affix == "Verisium" or affix == "of the Stars")
				and (next(officialAlloys) == nil
					or officialAlloys[desecrationTemplate(tier.text)] == true) then
				local weighted = false
				-- An empty weight set is serialised as "" rather than a table, so the
				-- type is checked before iterating.
				if type(tier.w) == "table" then
					for _, weight in ipairs(tier.w) do
						if tonumber(weight) and tonumber(weight) > 0 then
							weighted = true
							break
						end
					end
				end
				-- Tiers without text carry nothing to show, so they are left out rather
				-- than rendered as "nil".
				if not weighted and (tier.lvl or 0) <= level
					and type(tier.text) == "string" and tier.text ~= "" then
					entries[#entries + 1] = {
						text = tier.text,
						tier = tier.tier,
						lvl = tier.lvl or 0,
						affix = affix,
						type = group.type,
						groupKey = groupKey,
					}
				end
			end
		end
	end
	table.sort(entries, function(a, b)
		if a.lvl ~= b.lvl then
			return a.lvl < b.lvl
		end
		return a.text < b.text
	end)
	return { tierCount = #entries, entries = entries, oddsKnown = false }
end

--- Binomial coefficient C(n, k), iteratively and exactly for the small k we use.
local function binom(n, k)
	if k < 0 or n < 0 or k > n then
		return 0
	end
	if k == 0 or k == n then
		return 1
	end
	k = math.min(k, n - k)
	local result = 1
	for index = 1, k do
		result = result * (n - k + index) / index
	end
	return math.floor(result + 0.5)
end

--- Chance that at least one of `targetCount` mods is among the `draws` options offered.
--
-- Desecration does not roll one modifier out of a pool the way a currency does: the
-- Well of Souls offers a choice of three. The share of a modifier in the pool therefore
-- understates the real chance of seeing it, and this is the model for the difference:
--
--   P(hit) = 1 - C(pool - targets, draws) / C(pool, draws)
--
-- With Abyssal Echoes the reveal is rerolled (two independent draws of three), which is
-- P = 1 - miss^2. Both formulas, including the edge cases below, match the community
-- implementation in poe2-crafting-mcp (crafting/desecration.py), which is the only
-- published model for this mechanic; see docs/comparison_poe2_crafting_mcp.md.
--
-- @param poolSize total eligible modifiers in the pool
-- @param targetCount how many of them count as a hit
-- @param draws options per reveal (3 in game)
-- @param echoes reroll available
function Mods.revealChance(poolSize, targetCount, draws, echoes)
	poolSize = tonumber(poolSize) or 0
	targetCount = tonumber(targetCount) or 1
	draws = tonumber(draws) or 3
	if poolSize <= 0 or targetCount <= 0 then
		return 0
	end
	if targetCount >= poolSize or draws >= poolSize then
		return 1
	end
	if draws <= 0 then
		return 0
	end
	local nonTargets = poolSize - targetCount
	if nonTargets < draws then
		return 1
	end
	local missSingle = binom(nonTargets, draws) / binom(poolSize, draws)
	if echoes then
		return 1 - missSingle * missSingle
	end
	return 1 - missSingle
end

--- How good a random modifier can be at a given item level.
-- @param ilvl item level
-- @param hints optional base tags; without them every group counts, including ones
--        that could never spawn on the item in question
-- Counts *mod groups*, not spawn weights, so it is a group share, not a probability.
function Mods.rollableStats(ilvl, hints, sources)
	local store = ensureData()
	local bestSum, counted, t1Groups, allGroups = 0, 0, 0, 0
	-- Groups with a single tier always "reach T1", which says nothing; they are
	-- tracked separately so the headline number is about real tier ladders.
	local tieredGroups, tieredBestSum, tieredT1 = 0, 0, 0

	for _, group in pairs(store.groups) do
		allGroups = allGroups + 1
		local best = nil
		for _, tier in ipairs(group.tiers) do
			if (not ilvl or tier.lvl <= ilvl) and Mods.tierEligible(tier, hints, sources, group.src) then
				best = tier
			end
		end
		if best then
			counted = counted + 1
			bestSum = bestSum + best.tier
			if best.tier == 1 then
				t1Groups = t1Groups + 1
			end
			if #group.tiers > 1 then
				tieredGroups = tieredGroups + 1
				tieredBestSum = tieredBestSum + best.tier
				if best.tier == 1 then
					tieredT1 = tieredT1 + 1
				end
			end
		end
	end

	return {
		groups = counted,
		allGroups = allGroups,
		t1Groups = t1Groups,
		t1Percent = counted > 0 and (t1Groups * 100 / counted) or 0,
		avgBestTier = counted > 0 and (bestSum / counted) or 0,
		tieredGroups = tieredGroups,
		tieredT1 = tieredT1,
		tieredT1Percent = tieredGroups > 0 and (tieredT1 * 100 / tieredGroups) or 0,
		avgBestTierTiered = tieredGroups > 0 and (tieredBestSum / tieredGroups) or 0,
		hints = hints,
	}
end

--- Data provenance, for the UI footer.
function Mods.stats()
	local store = ensureData()
	return store.stats or { entries = 0 }
end

return Mods
