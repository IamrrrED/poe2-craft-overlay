-- PoE2 Craft Overlay : Item/Parser.lua
-- Parses the Path of Exile 2 clipboard item text (Ctrl+C / advanced copy) into a
-- structured table. Rule set derived from the community PoB2 parser
-- (vendor/PathOfBuilding-PoE2/src/Classes/Item.lua) so the section keywords and
-- modifier tags match what the game actually emits.
--
-- Deliberately tolerant: unknown lines become mods instead of errors, and every
-- uncertain classification is reported through `item.notes` rather than guessed silently.

local util = require("Core.util")
local Bases = require("Item.Bases")

local Parser = { }

local SECTION_SEP = "--------"

-- Standalone lines that are item flags, never modifiers.
--
-- Both languages are listed because the parser is handed the client's raw text as well as the
-- translated one. Missing a flag is not a cosmetic problem: an unrecognised "Освящено" left the item
-- looking modifiable, so the panel advised an Exalted Orb for an item that cannot be crafted at all.
-- A sanctified item is unmodifiable - the Omen of Sanctification randomises the values once and
-- multiplies them by 80-120%, after which most methods of crafting and modification refuse it.
local FLAG_LINES = {
	["Corrupted"] = "corrupted",
	["Осквернено"] = "corrupted",
	["Twice Corrupted"] = "doubleCorrupted",
	["Двойное осквернение"] = "doubleCorrupted",
	["Sanctified"] = "sanctified",
	["Освящено"] = "sanctified",
	["Освещено"] = "sanctified",
	["Mirrored"] = "mirrored",
	["Отзеркалено"] = "mirrored",
	["Split"] = "split",
	["Разделённый"] = "split",
	["Unidentified"] = "unidentified",
	["Неопознанный"] = "unidentified",
	-- The item STATE line of a fractured item. It was not recognised, so it was parsed as a modifier and
	-- showed up as a Russian bullet in the trade list ("Расколотый предмет") on an English card.
	["Fractured Item"] = "fractured",
	["Расколотый предмет"] = "fractured",
	["Desecrated Prefix"] = "desecratedPrefix",
	["Desecrated Suffix"] = "desecratedSuffix",
	-- An amulet that already carries an instilled notable, or a Waystone that carries an instilled
	-- reward modifier, cannot be instilled again - it has to be overwritten, which costs the emotions
	-- again. Both spellings appear: the item text says "Instilled", the parser also sees the word in
	-- modifier annotations.
	["Instilled"] = "instilled",
	["Инстиллировано"] = "instilled",
	["Настоянный"] = "instilled",
}

-- "<Key>: <value>" style property lines that may appear in the property section.
-- The Russian entries matter because the parser is handed the client's own text as well as the
-- translated one: a property line that is not recognised is counted as a modifier, which inflates the
-- item and can switch off slot advice. "Содержит зарядов:" is a property of a flask, not a modifier.
local PROPERTY_PREFIXES = {
	"Quality", "Physical Damage", "Elemental Damage", "Fire Damage", "Cold Damage",
	"Lightning Damage", "Chaos Damage", "Critical Hit Chance", "Attacks per Second",
	"Weapon Range", "Armour", "Evasion Rating", "Energy Shield", "Runic Ward",
	"Block chance", "Spirit", "Charm Limit", "Stack Size", "Radius", "Limited to",
	"Level", "Str", "Dex", "Int", "Requires",
	-- Russian spellings of the same lines.
	"Качество", "Физический урон", "Элементарный урон", "Урон от огня", "Урон от холода",
	"Урон от молнии", "Урон хаосом", "Шанс критического удара", "Атак в секунду",
	"Дальность оружия", "Броня", "Уклонение", "Энергетический щит", "Руническая защита",
	"Шанс блокировки", "Дух", "Лимит талисманов", "Размер стопки", "Радиус", "Ограничено",
	"Уровень", "Сила", "Ловкость", "Интеллект", "Требуется",
	"Содержит зарядов", "Восстанавливает", "Расходует", "Зарядов",
	-- A weapon or sceptre that grants a skill writes it as its own block: "Grants Skill: Level 18 Summon
	-- Skeletons" / "Дарует умение: Приспешник скелет-воин 18 уровня". This line is neither a modifier nor
	-- a known property, and leaving it out made the item carry one unclassified line - which is enough for
	-- the advisor to refuse a rule and for the panel to answer with the previous screen. Found on the
	-- customer's sceptre, where it advised a Divine reroll on an item the engine had not parsed at all.
	"Grants Skill", "Дарует умение",
}

local PROPERTY_LOOKUP = { }
for _, name in ipairs(PROPERTY_PREFIXES) do
	PROPERTY_LOOKUP[name:lower()] = true
end

local MOD_TAG_KINDS = {
	implicit = "implicitMods",
	crafted = "craftedMods",
	enchant = "enchantMods",
	rune = "runeMods",
	desecrated = "desecratedMods",
	scourge = "scourgeMods",
}

local function newItem()
	return {
		raw = nil,
		itemClass = nil,
		rarity = nil,
		name = nil,
		baseType = nil,
		itemLevel = nil,
		-- Waystones only: the tier, read from the property line or from the name.
		tier = nil,
		quality = nil,
		properties = { },
		requirements = { },
		sockets = { },
		runes = { },
		implicitMods = { },
		explicitMods = { },
		craftedMods = { },
		enchantMods = { },
		runeMods = { },
		desecratedMods = { },
		flags = { },
		sections = { },
		notes = { },
	}
end

local function addNote(item, code, params)
	item.notes[#item.notes + 1] = { code = code, params = params }
end

--- Parse a single modifier line into text + metadata.
local function parseModLine(line)
	local mod = { line = line, text = line, tags = { }, ranges = { } }

	local body, tag = util.popTrailingTag(line)
	-- A trailing "(...)" may be a tag, a range, or plain brackets; handle both.
	local tags = { }
	while tag do
		local isRange = tag:match("^%-?%d+%.?%d*%s*%-%s*%-?%d+%.?%d*$")
		if isRange then
			local mn, mx = tag:match("^(%-?%d+%.?%d*)%s*%-%s*(%-?%d+%.?%d*)$")
			mod.ranges[#mod.ranges + 1] = { min = tonumber(mn), max = tonumber(mx) }
		else
			tags[#tags + 1] = tag:lower()
		end
		body, tag = util.popTrailingTag(body)
	end
	mod.tags = tags

	local cleaned, ranges = util.extractRanges(body)
	for _, r in ipairs(ranges) do
		mod.ranges[#mod.ranges + 1] = r
	end

	mod.text = cleaned
	mod.kind = "explicit"
	for _, t in ipairs(tags) do
		for needle, bucket in pairs(MOD_TAG_KINDS) do
			if t:find(needle, 1, true) then
				mod.kind = needle
				mod.bucket = bucket
			end
		end
	end
	return mod
end

-- Property lines that carry no "Key:" at all. Flasks and charms are written this way: "Recovers 1327
-- Life over 4 Seconds", "Consumes 10 of 75 Charges on use", "Currently has 75 Charges", "Lasts 3
-- Seconds", "Grants immunity to Ignite". Not recognising them turned every one of those sentences into a
-- modifier, so a two-affix flask looked like a six-mod item and the panel offered slot advice for an item
-- that has no free affix at all.
--
-- A line is only treated this way when it does NOT resolve as a known modifier, because flasks and
-- charms also write some AFFIXES as sentences ("Grants Immunity to Poison for 6 seconds if used while
-- Poisoned" is a real suffix). Resolution decides first; these keywords only handle what is left.
local PLAIN_PROPERTY_LINES = {
	"recovers", "consumes", "currently has", "restores", "grants", "lasts",
	"восстанавливает", "расходует", "содержит", "дарует", "длится", "даёт", "дает",
}

local function isPlainPropertyLine(line)
	local lowered = util.trim(line):lower()
	for _, start in ipairs(PLAIN_PROPERTY_LINES) do
		if lowered:sub(1, #start) == start then
			return true
		end
	end
	return false
end

local function parsePropertyLine(item, line)
	local key, value = line:match("^([^:]+):%s*(.+)$")
	if not key then
		-- No colon at all: the flask lines are written as whole sentences ("Recovers 1327 Life over
		-- 4 Seconds"). They are properties with no separate value, so the sentence is the key.
		if not isPlainPropertyLine(line) then
			return false
		end
		item.properties[util.trim(line)] = { value = "", augmented = false }
		return true
	end
	key = util.trim(key)
	value = util.trim(value)

	local augmented = value:find("%(augmented%)") ~= nil
	value = util.trim((value:gsub("%s*%(augmented%)", "")))

	item.properties[key] = { value = value, augmented = augmented }
	local lowered = key:lower()
	if lowered == "quality" then
		item.quality = util.firstNumber(value)
	elseif lowered == "item level" then
		item.itemLevel = util.firstNumber(value)
	elseif lowered == "tier" or lowered == "waystone tier" or lowered == "map tier" then
		-- Waystones carry their tier as a property line as well as in the name ("Waystone (Tier 15)").
		-- The tier decides what the endgame crafting advice may suggest, so it is read explicitly.
		item.tier = util.firstNumber(value)
	elseif lowered == "sockets" then
		for token in value:gmatch("%S+") do
			item.sockets[#item.sockets + 1] = token
		end
	elseif lowered == "rune" then
		item.runes[#item.runes + 1] = value
	end
	return true
end

--- Is this line one of the affix-cap implicits, and nothing else?
-- "±N Prefix Modifier allowed" / "±N Suffix Modifiers allowed" appear on amulet and ring implicits and on
-- the Jewel-exclusive crafted modifier. They are the only lines that change the affix caps, and the
-- wording is unambiguous, so they must not be counted as ordinary affixes. Declared up here on purpose:
-- consumeBlock is defined further down and Lua allows only 200 locals per function scope, so a helper
-- placed next to its use is simply not visible to it.
-- @param line string
-- @return boolean
local function isImplicitOnlyLine(line)
	if type(line) ~= "string" then
		return false
	end
	return line:match("^[%-+]?%d+%s+Prefix Modifiers? allowed$") ~= nil
		or line:match("^[%-+]?%d+%s+Suffix Modifiers? allowed$") ~= nil
end

local function isPropertyLine(line)
	if isPlainPropertyLine(line) then
		return true
	end
	local key = line:match("^([^:]+):")
	if not key then return false end
	key = util.trim(key):lower()
	if key == "requirements" or key == "item level" or key == "sockets" or key == "rune" then
		return true
	end
	return PROPERTY_LOOKUP[key] == true
end

--- Does this line describe a modifier the engine can actually resolve?
--
-- Checked before the property keywords, because flasks and charms write some of their AFFIXES as plain
-- sentences too ("Recovers 297 Life when used", "58% increased Charges"), and the same sentence can be a
-- base action rather than an affix. Whether the line resolves as a known modifier is the only reliable
-- distinction, so it decides first and the keyword list only handles what is left.
local function resolvesAsModifier(line)
	local ok, mod = pcall(parseModLine, line)
	return ok and type(mod) == "table" and mod.mod ~= nil
end

--- One line that belongs in the property section rather than the modifier section.
local function isPropertyOnlyLine(line)
	if line == "Requirements:" or line:match("^Requires:") then
		return true
	end
	if line:match("^Sockets:") or line:match("^Rune:") or line:match("^Item Level:") then
		return true
	end
	return isPropertyLine(line)
end

--- Classify one "--------" delimited block.
--
-- Line by line, not block by block. Classifying the whole block on its FIRST property-looking line is
-- what lost the customer's charm: the block held the charm's base action ("Recovers 297 Life when
-- used") and its real affix ("58% increased Charges"), the first line matched the property keywords, and
-- both lines were filed as properties. The charm then had no modifiers at all, the prefix/suffix split
-- was unknown, and the panel advised a Regal Orb on an item whose slots it could not see.
local function consumeBlock(item, block)
	if block[1] == "Requirements:" or (block[1] or ""):match("^Requires:") then
		item.sections[#item.sections + 1] = { kind = "requirements", lines = block }
		for _, line in ipairs(block) do
			local key, value = line:match("^([^:]+):%s*(.+)$")
			if key and util.trim(key):lower() ~= "requirements" then
				item.requirements[util.trim(key)] = util.trim(value)
			end
		end
		return
	end

	local implicitSection = (#item.explicitMods == 0 and #item.implicitMods == 0)
	item.sections[#item.sections + 1] = { kind = "mixed", lines = block }
	for _, line in ipairs(block) do
		local bucket = nil
		if FLAG_LINES[line] then
			item.flags[FLAG_LINES[line]] = true
		elseif line:match("^Desecrated ") then
			item.flags[FLAG_LINES[line] or "desecrated"] = true
		elseif isImplicitOnlyLine(line) then
			-- "±N Prefix/Suffix Modifier allowed" is unambiguous and it CHANGES how many affix slots the
			-- item has. Filed as an explicit modifier it counted towards the prefix/suffix total and
			-- corrupted the slot arithmetic, so a rare with a slot-swapping implicit was told it was
			-- full. Recorded as an implicit, which is what the game prints it as.
			item.implicitMods[#item.implicitMods + 1] = { text = line, implicit = true }
		elseif not line:match("^{ ") and resolvesAsModifier(line) then
			bucket = parseModLine(line).bucket or "explicitMods"
		elseif isPropertyOnlyLine(line) then
			if not parsePropertyLine(item, line) then
				if not line:match("^Requirements:$") then
					addNote(item, "unparsed_property", { line })
				end
			end
		else
			local mod = parseModLine(line)
			bucket = mod.bucket
			if not bucket then
				bucket = "explicitMods"
				if implicitSection then
					-- Untagged mods in the first modifier block are *probably* implicits:
					-- the game prints implicits first, but plain Ctrl+C omits the "(implicit)"
					-- tag. Recorded as a suspicion, never as a fact.
					mod.suspectedImplicit = true
					item.suspectedImplicitMods = item.suspectedImplicitMods or { }
					item.suspectedImplicitMods[#item.suspectedImplicitMods + 1] = mod
				end
			end
			item[bucket][#item[bucket] + 1] = mod
		end
	end
end

--- Parse PoE2 clipboard item text.
-- @param raw string
-- @return table item
function Parser.parse(raw)
	local item = newItem()
	if type(raw) ~= "string" or util.trim(raw) == "" then
		addNote(item, "empty_input")
		item.valid = false
		return item
	end

	item.raw = raw:gsub("\r\n", "\n")
	local lines = util.splitLines(item.raw)

	local i = 1
	if lines[i] and lines[i]:match("^Item Class:") then
		item.itemClass = util.trim(lines[i]:gsub("^Item Class:%s*", ""))
		i = i + 1
	end
	if lines[i] and lines[i]:match("^Rarity:") then
		item.rarity = util.upper(util.trim(lines[i]:gsub("^Rarity:%s*", "")))
		i = i + 1
	end
	if not item.rarity then
		-- Wiki-style pastes omit the header: treat the first line as the name.
		item.rarity = "UNKNOWN"
		addNote(item, "no_rarity_header")
	end

	-- Name / base type block (everything up to the first separator).
	local nameLines = { }
	while lines[i] and lines[i] ~= SECTION_SEP do
		nameLines[#nameLines + 1] = lines[i]
		i = i + 1
	end
	if item.rarity == "NORMAL" or item.rarity == "MAGIC" then
		item.name = nameLines[1]
		item.baseType = item.name
	else
		item.name = nameLines[1]
		item.baseType = nameLines[2] or nameLines[1]
	end
	-- A Magic item is named "<prefix> <base> <suffix>", and the game writes those affix words in the
	-- client's language, so the base type read above can be the whole name. Normalise it here, at the
	-- moment the name is known: every modifier lookup starts from the base type, and a decorated one
	-- resolved nothing at all - no tiers, no prefix/suffix split, and advice built on a guess.
	local known = Bases.find(item.baseType)
	if known and known ~= item.baseType then
		item.baseTypeFromName = item.baseType
		item.baseType = known
		addNote(item, "base_from_decorated_name", { known })
	end
	-- A Waystone has no base name of its own: it is written "Waystone (Tier 15)", and the tier is the
	-- only thing that distinguishes one from another. Read it from there when the property line is
	-- absent, so the endgame advice knows what it is looking at.
	if not item.tier and item.baseType then
		local tier = item.baseType:match("[Tt]ier%s*:?%s*(%d+)")
		if tier then
			item.tier = tonumber(tier)
		end
	end
	if not item.name then
		addNote(item, "no_name")
	end
	if item.rarity ~= "NORMAL" and item.rarity ~= "MAGIC" and not nameLines[2] then
		addNote(item, "no_base")
	end

	-- Remaining blocks separated by "--------".
	local block = { }
	for idx = i, #lines do
		local line = lines[idx]
		if line == SECTION_SEP then
			if #block > 0 then
				consumeBlock(item, block)
				block = { }
			end
		else
			block[#block + 1] = line
		end
	end
	if #block > 0 then
		consumeBlock(item, block)
	end

	-- Flags can also appear inside property blocks in some copy modes.
	for _, line in ipairs(lines) do
		if FLAG_LINES[line] then
			item.flags[FLAG_LINES[line]] = true
		end
	end

	local explicitCount = #item.explicitMods
	local implicitCount = #item.implicitMods
	local suspected = item.suspectedImplicitMods and #item.suspectedImplicitMods or 0

	item.modCount = explicitCount + implicitCount + suspected
	item.affixCount = explicitCount
	item.isModifiable = not (item.flags.corrupted or item.flags.sanctified or item.flags.mirrored)
	item.valid = item.name ~= nil and item.rarity ~= "UNKNOWN"

	if suspected > 0 then
		addNote(item, "suspected_implicit", { suspected })
	end

	return item
end

--- Convenience: total number of explicit affixes (prefixes + suffixes guess).
function Parser.affixSummary(item)
	return string.format("явных модов: %d", item.affixCount or 0)
end

return Parser
