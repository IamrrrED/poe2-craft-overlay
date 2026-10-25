-- PoE2 Craft Overlay : Mcp/api.lua
-- The overlay's engine, exposed as Model Context Protocol tools.
--
-- The panel answers "what should I do with this item"; these tools answer the same
-- question for an AI client (Claude Desktop, Cursor, ...). Both go through the *same*
-- modules (Item.Mods for PoB spawn weights, Craft.Advisor for plans, Item.Runes /
-- Item.Essences / Item.Runeforging for the league crafts), so the numbers cannot drift
-- apart between the overlay and the MCP server.
--
-- The host has no network and no stdio here: a request is a Lua table (written by the
-- bridge in mcp/server.js), the answer is JSON written to a file.

local Parser = require("Item.Parser")
local Guide = require("Data.crafting_guide")
local Coach = require("Craft.Coach")
local Mods = require("Item.Mods")
local Ocr = require("Item.Ocr")
local Ru = require("Item.Ru")
local OutRu = require("Mcp.out_ru")
local RulesRu = require("Data.rules_ru")
local Recipes = require("Data.recipes")
local ModPool = require("Craft.ModPool")
local Categories = require("Item.Categories")
local Advisor = require("Craft.Advisor")
local Essences = require("Item.Essences")
local Runes = require("Item.Runes")
local Runeforging = require("Item.Runeforging")
local Prices = require("Craft.Prices")
local ValueHint = require("Craft.ValueHint")
local Stage = require("Craft.Stage")
local Claims = require("Craft.Claims")
local Techniques = require("Craft.Techniques")
local Curriculum = require("Craft.Curriculum")
local CraftOrBuy = require("Craft.CraftOrBuy")
local GenesisTree = require("Craft.GenesisTree")
local config = require("Data.config")

local api = { }

local rulesetCache = nil

-- ---- language ----------------------------------------------------------------------------
--
-- The engine's own prose is Russian, and its English twin lives next to it in a field with an "En"
-- suffix ("title" / "titleEn"); game data that the engine keeps in English gets the opposite twin
-- ("name" / "nameRu"). Choosing one of the two happens HERE, once, for every tool, so a module can
-- never forget to translate - it only has to add the twin, and Tests.test_language fails on a
-- missing one instead of letting the panel show a sentence in two languages.
--
-- Russian is the default because that is what every existing test asserts, and a caller that says
-- nothing is the panel's own Russian mode.

local TWIN_SUFFIX = { en = "En", ru = "Ru" }

local function languageOf(args)
	local asked = type(args) == "table" and (args.lang or args.language)
	if asked == "en" then
		return "en"
	end
	return "ru"
end

local function isTwinKey(key)
	if type(key) ~= "string" or #key < 3 then
		return false
	end
	local tail = key:sub(-2)
	return tail == "En" or tail == "Ru"
end

--- Deep copy of a payload with one language chosen and the twins dropped.
local function localise(value, lang)

	if type(value) ~= "table" then
		return value
	end
	local suffix = TWIN_SUFFIX[lang]
	local out = { }
	for key, item in pairs(value) do
		if not isTwinKey(key) then
			local chosen = item
			if suffix then
				local twin = value[tostring(key) .. suffix]
				if type(twin) == "string" or type(twin) == "table" then
					chosen = twin
				end
			end
			out[key] = localise(chosen, lang)
		end
	end
	return out
end

api.localise = localise
api.languageOf = languageOf

--- Fields whose value is the game's own name rather than our prose.
-- Keys, not values: a warning sentence may contain a currency name, but only a name field is a name.
local NAMED_KEYS = {
	title = true, label = true, name = true, base = true, baseType = true,
	baseName = true, itemClass = true, text = true, effect = true,
	wombgift = true, costLine = true, why = true, ifSuccess = true, ifFail = true, after = true,
	note = true, rule = true, line = true, priceNote = true, oddsNote = true, effect2 = true,
}

--- Fields that carry a machine value, even when it looks like a game name.
-- These are the fields a name substitution must leave alone: "step.currency = 'Regal Orb'" is compared
-- against the ruleset and against the tests, and the trade recipe's class is sent to the trade site as a
-- filter. Translating one of these would look right on screen and break the engine or the search.
local MACHINE_KEYS = {
	id = true, currency = true, currencyId = true, kind = true, verdict = true,
	side = true, source = true, url = true, model = true, weightSource = true, stage = true,
	ruleId = true, type = true, slot = true, code = true, choice = true,
	choices = true, previousStep = true, reason = true,
}

local function escapePattern(text)
	return (tostring(text):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

--- Put the official Russian names of game objects into a reply that is already Russian.
--
-- Our prose is Russian by then, but the names inside it are still the game's Latin ones: "Orb of
-- Augmentation", "Pariah Mask", "+30% to Cold Resistance". The reverse dictionaries exist (the official
-- localised pairs inverted by tools/build_display_names.py), so they are applied here - in the same one
-- place that picks the language, and only for the Russian direction.
--
-- Two passes, because a name can be a whole field or a fragment of a sentence:
--   1. collect the names this reply actually mentions, translating the name-like fields;
--   2. rewrite every string, longest name first, so "Orb of Augmentation" cannot be cut by a shorter
--      "Augmentation". A string with no known name is left exactly as it was, which is why this cannot
--      mangle our own prose.
local function russianNames(payload)
	local okRu, Ru = pcall(require, "Item.Ru")
	if not okRu or type(Ru) ~= "table" or type(Ru.toRussian) ~= "function" then
		return payload
	end
	local known = { }
	local function collect(value, key)
		if type(value) == "string" then
			-- Every string is a candidate, not only the name-like fields: a longer name can sit in a field
			-- this table does not list ("Greater Exalted Orb" in a short label), and if it is not collected
			-- the shorter "Exalted Orb" would be substituted inside it, giving "Greater Сфера возвышения".
			local translated = Ru.toRussian(value)
			if translated and translated ~= value then
				known[value] = translated
			end
			return
		end
		if type(value) ~= "table" then
			return
		end
		for innerKey, item in pairs(value) do
			collect(item, innerKey)
		end
	end
	collect(payload, nil)
	local ordered = { }
	for english, russian in pairs(known) do
		ordered[#ordered + 1] = { english, russian }
	end
	if #ordered == 0 then
		return payload
	end
	table.sort(ordered, function(left, right) return #left[1] > #right[1] end)
	-- The last visible language mix: our Russian sentences carry the game's ENGLISH currency names ("после
	-- Regal предмет станет редким", "Exalted занимает пустой слот"). The display dictionary knows the official
	-- Russian names, so they are substituted here - longest name first, on a word boundary, only inside text
	-- that is already Russian.
	local currencyPairs = nil
	local function currencyNames()
		if currencyPairs then
			return currencyPairs
		end
		currencyPairs = { }
		local okIcons, icons = pcall(require, "Data.currency_icons")
		if not okIcons or type(icons) ~= "table" then
			return currencyPairs
		end
		for english in pairs(icons) do
			if type(english) == "string" and #english >= 6 then
				local okRu, russian = pcall(Ru.toRussian, english)
				if okRu and type(russian) == "string" and russian ~= "" and russian ~= english then
					currencyPairs[#currencyPairs + 1] = { english = english, russian = russian }
				end
			end
		end
		-- Our prose also names a currency by its adjective only ("Exalted занимает пустой слот"), so the bare
		-- words map to the official full Russian name instead of staying English.
		local bare = {
			["Exalted"] = "Сфера возвышения",
			["Divine"] = "Божественная сфера",
			["Chaos"] = "Сфера хаоса",
			["Vaal"] = "Сфера ваал",
			["Regal"] = "Сфера царей",
			["Alchemy"] = "Сфера алхимии",
			["Transmutation"] = "Сфера превращения",
			["Augmentation"] = "Сфера усиления",
			["Annulment"] = "Сфера отмены",
		}
		for english, russian in pairs(bare) do
			currencyPairs[#currencyPairs + 1] = { english = english, russian = russian }
		end
		-- Longest first, and bare words last, so "Orb of Annulment" wins over "Annulment".
		table.sort(currencyPairs, function(left, right) return #left.english > #right.english end)
		return currencyPairs
	end
	local function rewrite(value, key)
		if type(value) == "string" then
			if MACHINE_KEYS[key] then
				return value
			end
			-- The item's quality, as the craft memory writes it: one display line the engine builds
			-- itself, English so that the stored fingerprint reads the same in both languages.
			if value:match("^Quality:%s*%d+%%$") then
				return (value:gsub("^Quality:", "Качество:"))
			end
			local whole = NAMED_KEYS[key] and known[value]
			if whole then
				return whole
			end
			local text = value
			for _, pair in ipairs(ordered) do
				if text:find(pair[1], 1, true) then
					text = text:gsub(escapePattern(pair[1]), function() return pair[2] end)
				end
			end
			-- English currency names inside our Russian prose ("после Regal предмет станет редким") are the last visible
-- mix: the sentence is ours and Russian, the name is the game's English one. The display dictionary knows the
-- official Russian name, so it is substituted on a word boundary (and skipped inside longer Latin words).
if text:find("[\208-\209][\128-\191]") then
	for _, pair in ipairs(currencyNames()) do
		if text:find(pair.english, 1, true) then
			local pattern = escapePattern(pair.english)
			text = text:gsub("([%a])" .. pattern, function(before) return before .. pair.russian end)
			text = text:gsub("(%s)" .. pattern, function(space) return space .. pair.russian end)
			text = text:gsub("^" .. pattern, pair.russian)
		end
	end
end
			return text
		end
		if type(value) ~= "table" then
			return value
		end
		local out = { }
		for innerKey, item in pairs(value) do
			out[innerKey] = rewrite(item, innerKey)
		end
		return out
	end
	return rewrite(payload, nil)

end

api.russianNames = russianNames

local function ruleset()
	if not rulesetCache then
		local ok, loaded = pcall(require, config.leagueFile)
		rulesetCache = (ok and type(loaded) == "table") and loaded
			or { currencies = { }, omens = { }, rules = { } }
	end
	return rulesetCache
end

-- Methods that are not a plain currency apply their own pool.
local METHOD_NOTES = {
	desecration = "Desecration pool (PoB veiled table, tag breach_desecration). "
		.. "The game offers three options at the Well of Souls, so the reveal chance is "
		.. "3/pool for one modifier (echoes: 1-(1-3/pool)^2); that model comes from the "
		.. "community project poe2-crafting-mcp and is reported separately from the "
		.. "weighted share.",
}

api.TOOLS = {
	{
		name = "sources",
		description = "Where every number comes from: PoB data files, official patch "
			.. "notes and the community references the overlay relies on.",
		inputSchema = { type = "object", properties = { }, additionalProperties = false },
	},
	{
		name = "analyze_item",
		description = "Analyse a copied Path of Exile 2 item: rarity, class, base, "
			.. "modifier tiers, the MIN and MAX crafting plans and any warnings.",
		inputSchema = {
			type = "object",
			properties = {
				item_text = { type = "string", description = "Item text as copied in game (Ctrl+C)." },
			},
			required = { "item_text" },
			additionalProperties = false,
		},
	},
	{
		name = "mod_chances",
		description = "Chance of each modifier a crafting method can add, computed from "
			.. "Path of Building spawn weights, filtered by base type, item level, open "
			.. "affix side and the currency's minimum modifier level.",
		inputSchema = {
			type = "object",
			properties = {
				item_text = { type = "string", description = "Item text as copied in game." },
				method = {
					type = "string",
					description = "Currency id (exalted, greater_exalted, perfect_exalted, "
						.. "chaos, divine, annulment, regal, transmutation, augmentation, "
						.. "essence, fracturing, vaal, alchemy) or 'desecration'.",
				},
			},
			required = { "item_text", "method" },
			additionalProperties = false,
		},
	},
	{
		name = "league_methods",
		description = "League 0.5.5 crafting methods for this item: omens, desecration, "
			.. "essences, runes and alloys, each with the odds it produces.",
		inputSchema = {
			type = "object",
			properties = {
				item_text = { type = "string", description = "Item text as copied in game." },
			},
			required = { "item_text" },
			additionalProperties = false,
		},
	},
	{
		name = "runeforging",
		description = "Runeforging lookup: which base type an item's base turns into.",
		inputSchema = {
			type = "object",
			properties = {
				base_type = { type = "string", description = "Base type name, e.g. 'Blacksteel Gauntlets'." },
			},
			required = { "base_type" },
			additionalProperties = false,
		},
	},
	{
		name = "prices",
		description = "Currency price snapshot (Craft of Exile data) with the league it "
			.. "belongs to and its fetch time, plus whether it applies to the configured "
			.. "league. Prices are quoted in chaos.",
		inputSchema = { type = "object", properties = { }, additionalProperties = false },
	},
	{
		name = "craft_summary",
		description = "Everything needed to decide how to finish an item: for every way to "
			.. "craft it, how many pieces it takes (average and a 90% bound), what it costs in "
			.. "exalted/chaos/divine, and the modifiers it can produce. Methods that cannot be "
			.. "used are reported with a reason.",
		inputSchema = {
			type = "object",
			properties = {
				item_text = { type = "string", description = "Item text (copied or read from the tooltip)." },
			},
			required = { "item_text" },
			additionalProperties = false,
		},
	},
	{
		name = "craft_cost",
		description = "Cost of crafting a chosen modifier onto the item with a chosen "
			.. "method: chance per attempt, expected number of attempts and the expected "
			.. "currency cost (priced from the Craft of Exile snapshot, and only when that "
			.. "snapshot covers the league being played).",
		inputSchema = {
			type = "object",
			properties = {
				item_text = { type = "string", description = "Item text (copied or read from the tooltip)." },
				method = { type = "string", description = "Currency id or 'desecration'." },
				target = { type = "string", description = "Modifier text to aim for; the best group is assumed when omitted." },
			},
			required = { "item_text", "method" },
			additionalProperties = false,
		},
	},
	-- Internal: the bridge asks for the tool list instead of duplicating it in JS.
	{
		name = "__describe__",
		description = "Internal: returns the tool descriptors.",
		internal = true,
		inputSchema = { type = "object", properties = { }, additionalProperties = false },
	},
}

--- Public tool list (what an MCP client sees).
function api.describe()
	local list = { }
	for _, tool in ipairs(api.TOOLS) do
		if not tool.internal then
			list[#list + 1] = {
				name = tool.name,
				description = tool.description,
				inputSchema = tool.inputSchema,
			}
		end
	end
	return list
end

local function parseItem(itemText)
	if type(itemText) ~= "string" or itemText == "" then
		return nil, "item_text is required"
	end
	-- Text read from a picture has no section separators (OCR drops them), so it is
	-- rebuilt into the copied-item layout first. Pasted or copied text already has them
	-- and is passed through untouched.
	-- A Russian client copies Russian text, and the engine is built on English Path of
	-- Building data, so the text is translated first (labels, rarity, annotations and the
	-- common modifier phrases). Lines that stay Russian are reported as unrecognised.
	if Ru.looksRussian(itemText) then
		local translated, report = Ru.toEnglish(itemText)
		itemText = translated
		inputLanguage = "ru"
		coverage = report
	end
	if not itemText:find("--------", 1, true) then
		itemText = Ocr.toItemText(itemText)
	end
	local ok, item = pcall(Parser.parse, itemText)
	if not ok or not item then
		return nil, "could not parse the item text: " .. tostring(item)
	end
	Mods.annotate(item)
	-- The language the text arrived in travels with the item, so the site can follow it.
	item.language = inputLanguage or "en"
	-- How much of the Russian text the dictionaries actually covered, line by line: this is
	-- what shows which wording is still missing instead of only "8 unrecognised".
	item.ruCoverage = coverage
	-- The game's own category for the base type: an independent check on the class the
	-- parser read, and a source of information when the base is unknown to PoB.
	item.officialCategory = Categories.of(item.baseType)
	return item
end

--- Groups already on the item: the game never rolls the same group twice.
local function existingGroups(item)
	local set = { }
	for _, mod in ipairs(item.explicitMods or { }) do
		if mod.mod then
			set[mod.mod.groupKey] = true
		end
	end
	return set
end

--- How many modifier groups a caller asked to see. Absent or zero means everything.
local function desiredGroupLimit(args)
	if type(args) ~= "table" then
		return 5
	end
	local wanted = tonumber(args.limit)
	if not wanted then
		return 5
	end
	if wanted <= 0 then
		return nil
	end
	return wanted
end
local function groupList(pool, limit)
	local out, seen = { }, { }
	if not pool or not pool.groups then
		return out
	end
	for _, group in ipairs(pool.groups) do
		if not seen[group.bestText] then
			seen[group.bestText] = true
			out[#out + 1] = {
				text = group.bestText,
				tier = group.bestTier,
				chance = math.floor(group.chance * 100 + 0.5) / 100,
				weightSource = group.weightSource,
			}
			if limit and #out >= limit then
				break
			end
		end
	end
	return out
end

local function toolSources(args)
	local list = { }
	for _, source in ipairs(ruleset().sources or { }) do
		list[#list + 1] = {
			id = source.id, label = source.label, detail = source.detail, url = source.url,
		}
	end
	local payload = { sources = list }
	-- The site asks for the sources separately, so it passes the language it already knows.
	if args and args.language == "ru" then
		if OutRu.wantsRussian(args) and languageOf(args) ~= "en" then payload = OutRu.translate(payload) end
	end
	return payload
end

local function toolAnalyze(args)
	local item, err = parseItem(args.item_text)
	if not item then
		return nil, err
	end
	local advice = Advisor.analyze(item, ruleset())
	local plans = { }
	for _, plan in ipairs(advice.plans or { }) do
		local steps = { }
		for _, step in ipairs(plan.steps or { }) do
			steps[#steps + 1] = {
				name = step.en or step.id,
				cost = step.cost,
				effect = step.effectEn or step.effect,
				-- The ruleset writes descriptions in English; the Russian side lives in Data/rules_ru.lua.
				effectRu = step.effectRu or (RulesRu and RulesRu.text(step.effectEn or step.effect)),
			}
		end
		plans[#plans + 1] = {
			id = plan.id,
			title = plan.title or plan.titleEn,
			titleEn = plan.titleEn or plan.title,
			reason = plan.reason or plan.reasonEn,
			reasonEn = plan.reasonEn or plan.reason,
			-- The quality plan carries a currency description as its reason, and the ruleset writes those
			-- in English, so the Russian side comes from the same table as the effects.
			reasonRu = plan.reasonRu or (RulesRu and RulesRu.text(plan.reasonEn or plan.reason)),
			steps = steps,
		}
	end
	local priceInfo = Prices.info() or { }
	local payload = {
		language = item.language or "en",
		category = item.officialCategory,
		ruCoverage = item.ruCoverage,
		-- The currency rates the page shows instead of the whole price snapshot: three
		-- numbers, each derived from the same snapshot the crafting costs come from, plus the
		-- local icon of each currency.
		currencyRates = {
			league = priceInfo.league,
			fetchedAt = priceInfo.fetchedAt,
			rates = Prices.rates(),
			icons = Prices.icons(),
		},
		item = {
			name = item.name,
			baseType = item.baseType,
			itemClass = item.itemClass,
			rarity = item.rarity,
			itemLevel = item.itemLevel,
			quality = item.quality,
			-- The card shows the item's own modifiers, so the texts travel with the counts. The
		-- counts alone were all that was sent before, and the page had nothing to render.
		implicitLines = (function()
			local out = { }
			for _, mod in ipairs(item.implicitMods or { }) do
				out[#out + 1] = mod.text or mod.name or ""
			end
			return out
		end)(),
		explicitLines = (function()
			local out = { }
			for _, mod in ipairs(item.explicitMods or { }) do
				out[#out + 1] = mod.text or mod.name or ""
			end
			for _, mod in ipairs(item.desecratedMods or { }) do
				out[#out + 1] = mod.text or mod.name or ""
			end
			for _, mod in ipairs(item.craftedMods or { }) do
				out[#out + 1] = mod.text or mod.name or ""
			end
			return out
		end)(),
		implicits = #(item.implicitMods or { }),
			explicits = #(item.explicitMods or { }),
			-- The split can be known while the OPEN counts are not: the counts need the class's slot caps,
			-- and those are not known for every class. Formatting them straight into %d aborted the whole
			-- analysis with "bad argument #4 to 'format' (number expected, got nil)" and the panel showed
			-- "движок не ответил" instead of a card, so each number is checked and the string says what is
			-- actually known rather than failing on what is not.
			affixes = (function()
				if not item.affixSplitComplete then
					return nil
				end
				local prefixes = tonumber(item.prefixCount)
				local suffixes = tonumber(item.suffixCount)
				local openPrefixes = tonumber(item.openPrefixes)
				local openSuffixes = tonumber(item.openSuffixes)
				local known = string.format("%sP/%sS", tostring(prefixes or "?"), tostring(suffixes or "?"))
				if openPrefixes and openSuffixes then
					return string.format("%s open %dP/%dS", known, openPrefixes, openSuffixes)
				end
				return known .. " open unknown (no slot caps for this class)"
			end)(),
			affixesRu = (function()
				if not item.affixSplitComplete then
					return nil
				end
				local prefixes = tonumber(item.prefixCount)
				local suffixes = tonumber(item.suffixCount)
				local openPrefixes = tonumber(item.openPrefixes)
				local openSuffixes = tonumber(item.openSuffixes)
				local known = string.format("%sП/%sС", tostring(prefixes or "?"), tostring(suffixes or "?"))
				if openPrefixes and openSuffixes then
					return string.format("%s свободно %dП/%dС", known, openPrefixes, openSuffixes)
				end
				return known .. " свободно неизвестно (для этого класса нет потолка слотов)"
			end)(),
		},
		ruleId = advice.ruleId,
		blocker = advice.blocker,

		-- Prices only ever travel with their league and fetch time; the verdict says
		-- whether they apply to the league this overlay is configured for.
		prices = (function()
			local info = Prices.info()
			local applies, why = Prices.matchesLeague(ruleset().league, config.ui.pricesLeague)
			return {
				appliesToThisLeague = applies,
				reason = why,
				league = info.league,
				fetchedAt = info.fetchedAt,
				source = info.source,
				unit = info.unit,
			}
		end)(),
		plans = plans,
		notes = Advisor.notesFor(advice, "en"),
		notesRu = Advisor.notesFor(advice, "ru"),
	}
	-- A Russian client gets Russian explanations: the numbers are untouched, only the text.
	if item.language == "ru" then
		if OutRu.wantsRussian(args) and languageOf(args) ~= "en" then payload = OutRu.translate(payload) end
	end
	return payload, nil
end

local RARITY_GATE = {
	["Orb of Transmutation"] = "normal",
	["Greater Orb of Transmutation"] = "normal",
	["Perfect Orb of Transmutation"] = "normal",
	["Orb of Augmentation"] = "magic",
	["Greater Orb of Augmentation"] = "magic",
	["Perfect Orb of Augmentation"] = "magic",
	["Orb of Alchemy"] = "normal",
	["Orb of Chance"] = "normal",
	["Regal Orb"] = "magic",
	["Greater Regal Orb"] = "magic",
	["Perfect Regal Orb"] = "magic",
	["Orb of Annulment"] = "magic+",
	["Divine Orb"] = "magic+",
	["Chaos Orb"] = "rare",
	["Greater Chaos Orb"] = "rare",
	["Perfect Chaos Orb"] = "rare",
	["Exalted Orb"] = "rare",
	["Greater Exalted Orb"] = "rare",
	["Perfect Exalted Orb"] = "rare",
	["Fracturing Orb"] = "rare",
}

--- Why a currency cannot be used on this item, or nil when it can.
-- "magic+" means "magic or better" (annulment and divine work on rare items too), while
-- "magic" is exactly magic: an Orb of Augmentation or a Regal Orb upgrades a magic item and
-- cannot touch a rare one.
local function rarityGate(label, rarity)
	local wanted = RARITY_GATE[tostring(label or "")]
	if not wanted then
		return nil
	end
	local actual = tostring(rarity or ""):lower()
	if actual == wanted then
		return nil
	end
	if wanted == "magic+" and (actual == "rare" or actual == "unique") then
		return nil
	end
	if wanted == "rare" and actual == "unique" then
		return nil
	end
	local shown = wanted == "magic+" and "magic or better" or wanted
	return "works only on " .. shown .. " items, and this one is " .. (actual ~= "" and actual or "?")
end

--- The same refusal in Russian, for the Russian panel.
local function rarityGateRu(label, rarity)
	local english = rarityGate(label, rarity)
	if not english then
		return nil
	end
	-- The sentence is rebuilt rather than translated by dictionary: the two words that vary (the wanted
	-- rarity and the item's own) are game terms, so they stay as the engine knows them.
	local wanted = RARITY_GATE[tostring(label or "")] or ""
	local actual = tostring(rarity or ""):lower()
	local shown = (wanted == "magic+" and "волшебный или выше") or tostring(wanted)
	return "работает только с редкостью " .. shown .. ", а этот предмет — " .. (actual ~= "" and actual or "?")
end
local function toolCraftSummary(args)
	local item, err = parseItem(args.item_text)
	if not item then
		return nil, err
	end
	local rules = ruleset()
	local applies, why = Prices.matchesLeague(rules.league or rules.leagueShort, config.ui.pricesLeague)

	local chaosUnit = Prices.unitPrice("Chaos Orb") or 1
	local exaltedUnit = Prices.unitPrice("Exalted Orb")
	local divineUnit = Prices.unitPrice("Divine Orb")

	--- Cost of an amount of chaos in the three currencies, in the order they are shown:
	-- exalted first (what a craftsman usually spends), then chaos, then divine.
	local function inCurrencies(chaos)
		if not chaos then
			return nil
		end
		local out = { }
		if exaltedUnit and exaltedUnit > 0 then
			out.exalted = math.floor((chaos / exaltedUnit) * 100 + 0.5) / 100
		end
		out.chaos = math.floor(chaos * 100 + 0.5) / 100
		if divineUnit and divineUnit > 0 then
			out.divine = math.floor((chaos / divineUnit) * 1000 + 0.5) / 1000
		end
		return out
	end

	--- Attempts needed for a 90% chance of at least one success (geometric distribution).
	local function attemptsFor(chance, target)
		if not chance or chance <= 0 then
			return nil
		end
		if chance >= 1 then
			return 1
		end
		return math.ceil(math.log(1 - target) / math.log(1 - chance))
	end

	local entries = { }
	-- Currencies that differ only in name share their pool conditions, and building a pool is
	-- the expensive part. Caching by (side, minimum modifier level) turns two dozen pool
	-- builds into a handful, which is what keeps the whole summary inside the bridge timeout.
	local poolCache = { }
	local function poolFor(currency, side)
		local key = tostring(side or "any") .. "|" .. tostring(currency and currency.minModLevel or 0)
		if poolCache[key] == nil then
			poolCache[key] = Mods.rollPool(item.itemLevel, item.baseHints, { baseName = item.baseType,
				side = (side and side ~= "any") and side or nil,
				minModLevel = currency and currency.minModLevel or nil,
				excludeGroups = existingGroups(item),
				sources = item.baseSources,
			})
		end
		return poolCache[key]
	end

	local function add(method, label, kind, side)
		local currency = (rules.currencies or { })[method]
		-- Rarity first: a currency that cannot be applied is not a crafting option at all, and
		-- saying why is more useful than a chance nobody can act on.
		local blocked = rarityGate(label, item.rarity)
		if blocked then
			entries[#entries + 1] = {
				method = method, label = label, kind = kind or "currency",
				cost = currency and currency.cost or "medium",
				poolSize = 0, applicable = false, reason = blocked,
				reasonRu = rarityGateRu(label, item.rarity), topMods = { },
			}
			return
		end
		local pool, reveal = nil, false
		if method == "desecration" then
			pool = Mods.desecrationPool(item.itemLevel, item.baseHints, { excludeGroups = existingGroups(item), excludeTexts = Mods.presentTexts(item) })
			Mods.attachReveal(pool)
			reveal = true
		else
			pool = poolFor(currency, side)
		end

		local groups = groupList(pool, 40)
		-- attachReveal keeps the reveal chance on the pool's own groups; the listed groups are
		-- copies, so the number has to be carried over explicitly, as the cost tool does. Without
		-- it the summary printed the weight share (10%) as if it were the chance of being one of
		-- the three options the reveal offers (30% for a pool of ten).
		if reveal and pool then
			for index, group in ipairs(groups) do
				local source = (pool.groups or { })[index]
				if source then
					group.revealChance = source.revealChance
				end
			end
		end
		local entry = {
			method = method,
			label = label,
			kind = kind or "currency",
			cost = currency and currency.cost or "medium",
			poolSize = pool and pool.tierCount or 0,
			applicable = groups[1] ~= nil,
			-- The best modifier the method can produce, with the next two as context: this is
			-- the answer to "what can I actually get".
			topMods = { },
		}
		for index = 1, math.min(3, #groups) do
			local group = groups[index]
			entry.topMods[#entry.topMods + 1] = {
				text = group.text,
				tier = group.tier,
				chance = group.chance,
				revealChance = group.revealChance,
				-- Whether the chance comes from the exact Craft of Exile weights or is an estimate.
				-- The panel shows it, so an estimate is never mistaken for a fact.
				weightSource = group.weightSource,
			}
		end
		if not entry.applicable then
			entry.reason = "no eligible modifier for this item"
			entry.reasonRu = "для этого предмета нет подходящего мода"
			entries[#entries + 1] = entry
			return
		end

		local chance = entry.topMods[1].chance / 100
		if reveal and entry.topMods[1].revealChance then
			chance = entry.topMods[1].revealChance
		end
		entry.chancePerAttempt = math.floor(chance * 1e6 + 0.5) / 1e6
		-- Where that chance came from: the exact Craft of Exile weights or an estimate. The panel
		-- reads it next to the chance, so a player can tell a fact from a guess.
		entry.weightSource = (entry.topMods[1] or { }).weightSource
		entry.expectedAttempts = math.floor((1 / chance) * 100 + 0.5) / 100
		entry.attemptsFor90 = attemptsFor(chance, 0.9)


		local perAttempt, unpriced = 0, { }
		local function addCost(name)
			local price = Prices.unitPrice(name)
			if price then
				perAttempt = perAttempt + price
			else
				unpriced[#unpriced + 1] = name
			end
		end
		if method == "desecration" then
			addCost("Omen of Sinistral Necromancy")
			-- The BONE is the expensive part of a desecration attempt, and it used to be left out
			-- entirely, so the route came out at the price of the omen alone and ranked as "the cheapest
			-- way" on every item. The bone is chosen by the same rule the advice uses, so the number here
			-- matches the consumable the player is told to buy.
			local bone = Advisor.desecrationBoneFor(rules, item)
			if bone and bone.en then
				addCost(bone.en)
			end
		elseif currency and currency.en then
			addCost(currency.en)
		end
		entry.unpriced = #unpriced > 0 and unpriced or nil
		-- A total that is missing a component is a LOWER BOUND, not a price, and saying so is the whole
		-- difference between honest advice and a plausible number. Desecration is the case that exposed
		-- this: we price the omen but not the bone, so the route came out at 0.02 chaos and sorted first as
		-- "the cheapest way", when the bone is the expensive part. Anything comparing costs (the craft-or-buy
		-- block) must skip these rather than rank them.
		entry.costIncomplete = entry.unpriced ~= nil
		-- Costs only make sense together with the attempt count: a method whose odds are
		-- withheld (see above) must not be priced either.
		if applies and perAttempt > 0 and entry.expectedAttempts then
			entry.perAttempt = inCurrencies(perAttempt)
			entry.expectedCost = inCurrencies(perAttempt * entry.expectedAttempts)
			entry.costFor90 = entry.attemptsFor90 and inCurrencies(perAttempt * entry.attemptsFor90) or nil
		end
		entries[#entries + 1] = entry
	end

	for method, currency in pairs(rules.currencies or { }) do
		add(method, currency.en or method, currency.kind or "currency", currency.side)
	end
	add("desecration", "Desecration", "desecration", nil)

	-- Cheapest applicable way first: that is the natural reading of "what should I use".
	table.sort(entries, function(a, b)
		if a.applicable ~= b.applicable then
			return a.applicable
		end
		local left = a.expectedCost and a.expectedCost.chaos or math.huge
		local right = b.expectedCost and b.expectedCost.chaos or math.huge
		if left ~= right then
			return left < right
		end
		return tostring(a.label) < tostring(b.label)
	end)

	local affordable = 0
	for _, entry in ipairs(entries) do
		if entry.applicable then
			affordable = affordable + 1
		end
	end

	local payload = {
		ready = affordable > 0,
		applicable = affordable,
		total = #entries,
		pricesApply = applies,
		pricesReason = why,
		league = rules.league or rules.leagueShort,
		units = { exalted = exaltedUnit, chaos = chaosUnit, divine = divineUnit },
		entries = entries,
	}
	if item.language == "ru" then
		if OutRu.wantsRussian(args) and languageOf(args) ~= "en" then payload = OutRu.translate(payload) end
	end
	return payload, nil
end

local function toolModChances(args)
	local item, err = parseItem(args.item_text)
	if not item then
		return nil, err
	end
	local method = tostring(args.method or "")
	local exclude = existingGroups(item)
	local hints = item.baseHints
	local sources = item.baseSources

	if method == "desecration" then
		local pool = Mods.desecrationPool(item.itemLevel, hints, { excludeGroups = exclude, excludeTexts = Mods.presentTexts(item) })
		-- The reveal model lives on the pool (Mods.attachReveal), so the MCP answer and
		-- the panel quote exactly the same numbers.
		Mods.attachReveal(pool)
		local groups = { }
		local groupLimit = desiredGroupLimit(args)
		for _, group in ipairs(groupList(pool, groupLimit)) do
			groups[#groups + 1] = group
		end
		-- groupList drops the reveal fields, so they are added back per group.
		for index, group in ipairs(groups) do
			local source = (pool.groups or { })[index]
			group.targetCount = source and source.tierCount or 1
			group.revealChance = source and source.revealChance or nil
			group.revealEchoes = source and source.revealEchoes or nil
		end
		local reveal = nil
		if pool.reveal and (pool.reveal.poolSize or 0) > 0 and groups[1] then
			reveal = {
				draws = pool.reveal.draws,
				poolSize = pool.reveal.poolSize,
				perGroup = math.floor(groups[1].revealChance * 10000 + 0.5) / 10000,
				withEchoes = math.floor(groups[1].revealEchoes * 10000 + 0.5) / 10000,
				model = "community model from poe2-crafting-mcp (three options offered per "
					.. "reveal); our implementation is verified row by row against theirs in "
					.. "Tests/reveal_reference.lua",
			}
		end
		return {
			method = method,
			name = "Desecration",
			tierCount = pool.tierCount,
			groups = groups,
			reveal = reveal,
			note = METHOD_NOTES.desecration,
		}, nil
	end

	local currency = (ruleset().currencies or { })[method]
	if not currency then
		return nil, "unknown method '" .. method .. "'; try a currency id from the league table or 'desecration'"
	end
	local pool = Mods.rollPool(item.itemLevel, hints, { baseName = item.baseType,
		side = (currency.side and currency.side ~= "any") and currency.side or nil,
		minModLevel = currency.minModLevel,
		excludeGroups = exclude,
		sources = sources,
	})
	return {
		method = method,
		name = currency.en,
		effect = currency.effectEn or currency.effect,
		side = currency.side,
		minModLevel = currency.minModLevel,
		tierCount = pool and pool.tierCount or 0,
		
		groups = groupList(pool, desiredGroupLimit(args)),
		note = "chances are the weighted share of each modifier group in the eligible "
			.. "pool; weights come from Craft of Exile for the item's own base where available, otherwise from Path of Building spawn weights"
	}, nil
end

--- The three currencies the panel quotes every price in, cheapest first by definition of the order
-- the customer asked for: "показывать сразу в трёх валютах, начиная с самой дешёвой".
--
-- The snapshot is quoted in chaos, so a cost in chaos is converted with the snapshot's own rates. The
-- order is decided by VALUE, not by which currency is named first: that is the only way "cheapest first"
-- means anything, and it keeps working if the rates move.
local PRICE_CURRENCIES = {
	{ id = "exalted", name = "Exalted Orb", short = "ex" },
	{ id = "chaos", name = "Chaos Orb", short = "chaos" },
	{ id = "divine", name = "Divine Orb", short = "div" },
}

--- Convert a cost in the snapshot's unit into all three currencies, cheapest first.
-- @param amount cost in the snapshot unit (chaos)
-- @return list of { id, name, short, amount } or nil when no snapshot is loaded
--- A cost in chaos as the picker's rows, cheapest first.
--
-- The summary also carries its own three-currency table, but it rounds each amount for its own layout
-- (a 0.46-chaos cost came back as "29 ex"), and the picker quotes money - so the conversion is done here
-- from the raw chaos value with four decimals. The order is decided by VALUE, which is what "начиная с
-- самой дешёвой" means: a fixed order would print the dearest first for some prices.
-- @param chaos cost in the snapshot's unit
-- @return list of { id, name, short, amount } or nil
local function priceRows(chaos)
	local value = tonumber(chaos)
	if not value then
		return nil
	end
	local rows = { }
	for _, currency in ipairs(PRICE_CURRENCIES) do
		local unit = (currency.id == "chaos") and 1 or Prices.unitPrice(currency.name)
		if unit and unit > 0 then
			local amount = math.floor((value / unit) * 10000 + 0.5) / 10000
			rows[#rows + 1] = {
				id = currency.id,
				name = currency.name,
				short = currency.short,
				amount = amount,
				-- The face value in the item's own currency, and the real value in chaos: the ex price of
				-- a one-exalted cost is a large number that is still the cheapest thing on the list.
				inItemCurrency = currency.id == "chaos" and nil or amount,
				sortValue = amount * unit,
			}
		end
	end
	if #rows == 0 then
		return nil
	end
	table.sort(rows, function(left, right)
		if left.sortValue == right.sortValue then
			return left.id < right.id
		end
		return left.sortValue < right.sortValue
	end)
	for _, row in ipairs(rows) do
		row.sortValue = nil
	end
	return rows
end

--- A pool entry as the picker shows it: readable text, tier, chance and where the weight came from.
-- @param pool pool from Mods.rollPool
-- @param limit optional cap (nil = every modifier, which is what the customer asked for)
-- @return list of { text, tier, chance, weightSource }
local function pooledMods(pool, limit)
	local out, seen = { }, { }
	if not pool or not pool.groups then
		return out
	end
	for _, group in ipairs(pool.groups) do
		if not seen[group.bestText] then
			seen[group.bestText] = true
			out[#out + 1] = {
				text = group.bestText,
				tier = group.bestTier,
				chance = math.floor(group.chance * 100 + 0.5) / 100,
				weightSource = group.weightSource,
			}
			if limit and #out >= limit then
				break
			end
		end
	end
	return out
end

--- Every crafting method available on the item right now, grouped for the picker.
--
-- The panel used to offer ONE recommended step. The customer asked for the opposite: show everything that
-- can be done, group it by kind, and let the player choose. All of this is assembled from what the advisor
-- already computed - the rules, the quality step, the league options - plus the roll pools, so the menu and
-- the recommendation cannot disagree about what is possible.
local function toolMethods(args)
	local item, err = parseItem(args.item_text)
	if not item then
		return nil, err
	end
	local rules = ruleset()
	local advice = Advisor.analyze(item, rules)
	local exclude = existingGroups(item)
	local hints = item.baseHints
	local sources = item.baseSources

	local function poolFor(currencyId)
		local currency = (rules.currencies or { })[currencyId]
		if not currency then
			return nil
		end
		return Mods.rollPool(item.itemLevel, hints, {
			baseName = item.baseType,
			side = (currency.side and currency.side ~= "any") and currency.side or nil,
			minModLevel = currency.minModLevel,
			excludeGroups = exclude,
			sources = sources,
			excludeTexts = Mods.presentTexts(item),
		})
	end

	--- One row of the menu.
	local function method(id, kind, currencyId, extra)
		extra = extra or { }
		local currency = (rules.currencies or { })[currencyId] or { }
		local pool = extra.pool
		if pool == nil and currencyId and not extra.noPool then
			pool = poolFor(currencyId)
		end
		local mods = extra.mods or pooledMods(pool)
		return {
			id = id,
			kind = kind,
			title = extra.title or currency.en or id,
			titleEn = extra.titleEn or currency.en or id,
			currencyId = currencyId,
			side = extra.side or (currency.side ~= "any" and currency.side) or nil,
			cost = extra.cost or currency.cost,
			status = extra.status or currency.status,
			effect = extra.effect or currency.effectEn or currency.effect,
			effectEn = extra.effectEn or currency.effectEn or currency.effect,
			effectRu = extra.effectRu or currency.effectRu
				or (RulesRu and RulesRu.text(extra.effectEn or extra.effect
					or currency.effectEn or currency.effect)),
			why = extra.why,
			oddsUnknown = extra.oddsUnknown and true or false,
			oddsNote = extra.oddsNote,
			oddsNoteEn = extra.oddsNoteEn,
			deterministic = extra.deterministic and true or false,
			removal = extra.removal,
			warning = extra.warning or currency.warningEn or currency.warning,
			warningRu = RulesRu and RulesRu.text(currency.warningEn or currency.warning),
			-- The number the picker shows next to a method before anything is opened.
			modCount = #mods,
			tierCount = pool and pool.tierCount or nil,
			mods = mods,
		}
	end

	--- The chance of the pool's best single modifier, as a fraction, for the summary line.
	local function bestChance(mods)
		local best = nil
		for _, mod in ipairs(mods or { }) do
			if mod.chance and (best == nil or mod.chance > best) then
				best = mod.chance
			end
		end
		return best
	end

	local groups = { }
	local function addGroup(id, title, titleEn, methods)
		if #methods == 0 then
			return
		end
		groups[#groups + 1] = { id = id, title = title, titleEn = titleEn, methods = methods }
	end

	local openSuffix = tonumber(item.openSuffixes) or 0
	local openPrefix = tonumber(item.openPrefixes) or 0
	local splitKnown = item.affixSplitComplete == true

	-- 1. Adding a modifier. Only when a slot is actually free.
	local addMods = { }
	if splitKnown and (openSuffix > 0 or openPrefix > 0) then
		for _, currencyId in ipairs({ "exalted", "greater_exalted", "perfect_exalted" }) do
			if (rules.currencies or { })[currencyId] then
				local row = method(currencyId, "add", currencyId)
				row.chance = bestChance(row.mods)
				addMods[#addMods + 1] = row
			end
		end
		-- Essences guarantee one modifier; they are in the league options with their own wording.
		for _, option in ipairs(advice.omenOptions or { }) do
			if option.kind == "essence" then
				addMods[#addMods + 1] = method("essence:" .. tostring(option.titleEn), "add",
					option.currencyId, {
						title = option.title or option.titleEn,
						titleEn = option.titleEn or option.title,
						effect = option.effectEn or option.effect,
						why = option.why or option.whyEn,
						status = option.status,
						deterministic = true,
						noPool = true,
					})
			end
		end
		-- Runes: s socketed rune is a guaranteed modifier, not a roll.
		for _, rune in ipairs(advice.runes or { }) do
			addMods[#addMods + 1] = method("rune:" .. tostring(rune.name or rune.en), "add", nil, {
				title = tostring(rune.name or rune.en or "Rune"),
				titleEn = tostring(rune.name or rune.en or "Rune"),
				effect = rune.effect or rune.text,
				deterministic = true,
				noPool = true,
			})
		end
	end
	addGroup("add", "Добавить мод", "Add a modifier", addMods)

	-- 2. Replacing or removing. This is what "free the slot" means, and it is the answer to "the mod I
	--    wanted did not come out": these are the ways to empty a side and try again.
	local replaceMods = { }
	for _, currencyId in ipairs({ "chaos", "greater_chaos", "perfect_chaos", "annulment" }) do
		if (rules.currencies or { })[currencyId] then
			local row = method(currencyId, "replace", currencyId)
			row.chance = bestChance(row.mods)
			replaceMods[#replaceMods + 1] = row
		end
	end
	for _, option in ipairs(advice.omenOptions or { }) do
		if option.removal or option.kind == "removal" then
			replaceMods[#replaceMods + 1] = method("omen:" .. tostring(option.omenId or option.titleEn),
				"replace", option.currencyId, {
					title = option.title or option.titleEn,
					titleEn = option.titleEn or option.title,
					effect = option.effectEn or option.effect,
					why = option.why or option.whyEn,
					removal = option.removal,
					status = option.status,
					noPool = true,
				})
		end
	end
	addGroup("replace", "Заменить или снять мод", "Replace or remove a modifier", replaceMods)

	-- 3. Improving what is already there. Quality and value rerolls change no modifier, so they are not
	--    in the mod list - the customer asked for them as their own block.
	local improveMods = { }
	if advice.qualityStep then
		local quality = advice.qualityStep
		improveMods[#improveMods + 1] = {
			id = "quality",
			kind = "improve",
			title = tostring(quality.en or quality.name or "Quality"),
			titleEn = tostring(quality.en or quality.name or "Quality"),
			effect = quality.effectEn or quality.effect,
			effectEn = quality.effectEn or quality.effect,
			cost = quality.cost,
			status = quality.status,
			deterministic = true,
			oddsUnknown = true,
			oddsNote = "качество не бросает мод: оно множит характеристики предмета",
			oddsNoteEn = "quality does not roll a modifier: it multiplies the item's own values",
			modCount = 0,
			mods = { },
		}
	end
	if (rules.currencies or { }).divine and #(item.explicitMods or { }) > 0 then
		local divine = method("divine", "improve", "divine", { noPool = true })
		divine.modCount = 0
		divine.mods = { }
		divine.oddsUnknown = true
		divine.oddsNote = "перебрасывает числа существующих модов, набор модов не меняет"
		divine.oddsNoteEn = "rerolls the numbers of the existing modifiers, the set of modifiers stays"
		improveMods[#improveMods + 1] = divine
	end
	for _, option in ipairs(advice.omenOptions or { }) do
		if option.kind == "quality" or option.kind == "catalyst" then
			improveMods[#improveMods + 1] = method("improve:" .. tostring(option.titleEn), "improve",
				option.currencyId, {
					title = option.title or option.titleEn,
					titleEn = option.titleEn or option.title,
					effect = option.effectEn or option.effect,
					why = option.why or option.whyEn,
					status = option.status,
					noPool = true,
				})
		end
	end
	addGroup("improve", "Улучшить существующее", "Improve what is there", improveMods)

	-- 4. Freeing a slot on a full item: the ways to empty one side, with what each can remove.
	local freeMods = { }
	if splitKnown and openSuffix == 0 and openPrefix == 0 then
		for _, option in ipairs(advice.omenOptions or { }) do
			if option.removal then
				freeMods[#freeMods + 1] = method("free:" .. tostring(option.omenId or option.titleEn),
					"free", option.currencyId, {
						title = option.title or option.titleEn,
						titleEn = option.titleEn or option.title,
						effect = option.effectEn or option.effect,
						why = option.why or option.whyEn,
						removal = option.removal,
						status = option.status,
						noPool = true,
					})
			end
		end
		local annulment = (rules.currencies or { }).annulment
		if annulment and item.modCount and item.modCount > 0 then
			freeMods[#freeMods + 1] = {
				id = "annulment",
				kind = "free",
				title = annulment.en,
				titleEn = annulment.en,
				currencyId = "annulment",
				effect = annulment.effectEn or annulment.effect,
				effectEn = annulment.effectEn or annulment.effect,
				cost = annulment.cost,
				status = annulment.status,
				removal = "random",
				modCount = 0,
				mods = { },
				-- The chance of hitting the side you want is a real number: 1 of the affixes present.
				oddsUnknown = false,
				oddsNote = string.format("снимает один случайный мод: шанс попасть в нужную сторону 1 из %d",
					math.max(1, item.modCount)),
				oddsNoteEn = string.format(
					"removes one random modifier: the chance of hitting the side you want is 1 in %d",
					math.max(1, item.modCount)),
			}
		end
	end
	addGroup("free", "Освободить слот", "Free a slot", freeMods)

	-- 5. Irreversible. Kept apart on purpose: this is the one step that can destroy the craft.
	local riskyMods = { }
	if (rules.currencies or { }).vaal and item.rarity and tostring(item.rarity):lower():find("rare") then
		local vaal = method("vaal", "risky", "vaal", { noPool = true })
		vaal.modCount = 0
		vaal.mods = { }
		vaal.oddsUnknown = true
		vaal.oddsNote = "исход осквернения не публикуется: возможен и порча предмета"
		vaal.oddsNoteEn = "the corruption outcome is not published: ruining the item is one of them"
		riskyMods[#riskyMods + 1] = vaal
	end
	addGroup("risky", "Рискованное (необратимо)", "Risky (irreversible)", riskyMods)

	-- One row per method. The quality step and the league options both know about the Arcanist's Etcher,
	-- so a sceptre listed it twice under the same name: two identical rows, and clicking either looked
	-- like nothing happened because the other row kept its highlight. The key is the kind plus the
	-- currency, because the same currency can legitimately appear in two different roles.
	-- Fill in the Russian side of every row from the ruleset table in ONE place, so a row built by hand
	-- (the quality step, the annulment and Vaal rows are) cannot be forgotten. A row whose effect is not in
	-- the table keeps its English text rather than inventing a translation.
	for _, group in ipairs(groups) do
		for _, row in ipairs(group.methods or { }) do
			if type(row) == "table" then
				if row.effectRu == nil then
					row.effectRu = RulesRu and RulesRu.text(row.effectEn or row.effect)
				end
				if row.warningRu == nil then
					row.warningRu = RulesRu and RulesRu.text(row.warningEn or row.warning)
				end
			end
		end
	end

	for _, group in ipairs(groups) do
		local kept, seenKey = { }, { }
		for _, row in ipairs(group.methods) do
			local key = tostring(row.kind) .. "|" .. tostring(row.currencyId or row.title)
			if not seenKey[key] then
				seenKey[key] = true
				kept[#kept + 1] = row
			end
		end
		group.methods = kept
	end

	-- Prices: what one attempt of each method costs, in the three currencies the panel quotes.
	local summary = select(1, toolCraftSummary({ item_text = args.item_text, lang = args.lang })) or { }
	local costByMethod = { }
	for _, entry in ipairs(summary.entries or { }) do
		local label = tostring(entry.label or entry.method or "")
		if label ~= "" then
			costByMethod[label] = entry
		end
		local methodId = tostring(entry.method or "")
		if methodId ~= "" and costByMethod[methodId] == nil then
			-- Also reachable by the currency id: the label is localised ("Очернение" for chaos-based
			-- desecration) and a title comparison alone missed those rows entirely.
			costByMethod[methodId] = entry
		end
	end
	if args.debug_lookup then
		local names = { }
		for label in pairs(costByMethod) do
			names[#names + 1] = label
		end
		table.sort(names)
		local out = io.open("zz_lookup.txt", "w")
		out:write("summary entries: " .. #(summary.entries or { }) .. "\nkeys: "
			.. table.concat(names, " | ") .. "\n")
		out:close()
	end
	for _, group in ipairs(groups) do
		for _, row in ipairs(group.methods) do
			local entry = costByMethod[row.title] or costByMethod[row.titleEn]
				or costByMethod[tostring(row.currencyId)]
			if entry then
				row.chancePerAttempt = entry.chancePerAttempt
				row.expectedAttempts = entry.expectedAttempts
				row.attemptsFor90 = entry.attemptsFor90
				row.pricesApply = entry.applicable
				row.weightSource = entry.weightSource
				row.poolSize = entry.poolSize
				row.unpriced = entry.unpriced
				-- What one attempt costs, and what 90% confidence costs, both in the three currencies.
				row.price = priceRows(entry.perAttempt and entry.perAttempt.chaos)
				row.priceFor90 = priceRows(entry.costFor90 and entry.costFor90.chaos)
				row.expectedCost = priceRows(entry.expectedCost and entry.expectedCost.chaos)
			end
		end
	end

	-- What can be removed right now, and by what. This is the honest version of "roll back": in this game
	-- the item is already changed, so the advice is which modifier can be taken off and with which tool.
	local removable = { }
	for _, mod in ipairs(item.explicitMods or { }) do
		local text = type(mod) == "table" and mod.text or mod
		if type(text) == "string" and text ~= "" then
			removable[#removable + 1] = {
				text = text,
				side = mod.mod and mod.mod.type or nil,
			}
		end
	end

	-- The stage decides which of the available methods are worth SPENDING on. Every guide agrees that
	-- campaign gear gets Transmute/Augment/Regal and the expensive orbs wait: a level-40 item is replaced
	-- before an Exalted Orb spent on it pays back. A method is not hidden, it is marked, with the reason -
	-- hiding it would look like a bug and teach nothing.
	local stage = Stage.forItemLevel(item.itemLevel)
	local stageId = tostring(args.stage or stage)
	for _, group in ipairs(groups) do
		for _, row in ipairs(group.methods) do
			local method = tostring(row.currencyId or row.id or "")
			local allowed = Stage.allows(stageId, method)
			row.allowedAtStage = allowed
			row.stage = stageId
			if not allowed then
				row.stageNote = Stage.describe(stageId, "ru")
				row.stageNoteEn = Stage.describe(stageId, "en")
			end
		end
	end

	return {
		groups = groups,
		removable = removable,
		-- Advanced methods that only apply to a specific item state (jewel suffix cap, tag hunt,
		-- desecration wash). Each comes with its precondition already checked against this item.
		techniques = Techniques.forItem(item),
		-- The mentor's course, with this item as the state: each lesson says whether the item
		-- already demonstrates the point, so the panel can skip what the player knows.
		curriculum = Curriculum.forItem(item, advice),
		stage = {
			id = stageId,
			fromItemLevel = stage,
			label = Stage.LABELS[stageId] or stageId,
			labelEn = Stage.LABELS_EN[stageId] or stageId,
			description = Stage.describe(stageId, "ru"),
			descriptionEn = Stage.describe(stageId, "en"),
			--- Which stages the caller may switch to.
			choices = Stage.ORDER,
		},
		split = {
			known = splitKnown,
			openPrefixes = splitKnown and openPrefix or nil,
			openSuffixes = splitKnown and openSuffix or nil,
			prefixes = item.prefixCount,
			suffixes = item.suffixCount,
		},
		prices = {
			unit = (Prices.info() or { }).unit,
			fetchedAt = (Prices.info() or { }).fetchedAt,
			league = (Prices.info() or { }).league,
			currencies = PRICE_CURRENCIES,
		},
		note = "каждый способ доступен только если он применим сейчас: нет свободной стороны — нет "
			.. "способов её добавить",
		noteEn = "a method is listed only if it applies right now: no free side means nothing that adds to it",
	}, nil
end

local function toolLeagueMethods(args)
	local item, err = parseItem(args.item_text)
	if not item then
		return nil, err
	end
	local advice = Advisor.analyze(item, ruleset())
	local options = { }
	for _, option in ipairs(advice.omenOptions or { }) do
		local entry = {
			kind = option.kind or "omen",
			title = option.title or option.titleEn,
			why = option.why or option.whyEn,
			cost = option.cost,
			status = option.status,
		}
		if option.pool then
			-- The full pool travels with the reveal numbers, so a client can show the
			-- "three options offered" model instead of only the weighted share.
			local pool = { }
			for _, group in ipairs(option.pool.groups or { }) do
				pool[#pool + 1] = {
					text = group.bestText,
					tier = group.bestTier,
					chance = math.floor(group.chance * 100 + 0.5) / 100,
					tierCount = group.tierCount,
					-- coe = weights came from the base-specific table, mixed/weights = approximation was involved.
					weightSource = group.weightSource,
					revealChance = group.revealChance and math.floor(group.revealChance * 10000 + 0.5) / 10000 or nil,
					revealEchoes = group.revealEchoes and math.floor(group.revealEchoes * 10000 + 0.5) / 10000 or nil,
				}
			end
			entry.pool = pool
			entry.poolSize = option.pool.tierCount
			entry.reveal = option.pool.reveal and {
				draws = option.pool.reveal.draws,
				poolSize = option.pool.reveal.poolSize,
				echoes = option.pool.reveal.echoes,
			} or nil
		end
		if option.essence then
			entry.essence = {
				name = option.essence.name,
				mod = option.essence.mod.text,
				tier = option.essence.mod.tier,
				modLevel = option.essence.mod.lvl,
				chance = option.essence.chance,
				limit = 1,
			}
		end
		if option.rune then
			entry.rune = {
				name = option.rune.name,
				type = option.rune.type,
				mod = option.rune.text,
				limit = option.rune.limit,
				levelReq = option.rune.levelReq,
				chance = option.rune.chance,
			}
		end
		if option.alloyNames then
			entry.alloyNames = option.alloyNames
		end
		if option.oddsUnknown then
			entry.odds = "not computable from the available data"
		end
		if option.oddsNote then
			entry.oddsNote = option.oddsNote
		end
		-- Fields the newer step kinds carry: which bone to buy for a desecration, the catalysts that
		-- match a piece of jewellery, a waystone's tier, and whether an item is already instilled.
		if option.bone then
			entry.bone = option.bone
		end
		if option.catalysts then
			entry.catalysts = option.catalysts
		end
		if option.tier then
			entry.tier = option.tier
		end
		if option.alreadyInstilled then
			entry.alreadyInstilled = true
		end
		if option.emotions then
			entry.emotionCount = option.emotions
		end
		options[#options + 1] = entry
	end

	-- The quality step is decided separately from the plan, so it travels as its own field rather than
	-- as one more option: a client that ignores it still gets every league method.
	local qualityStep = advice.qualityStep
	local quality = qualityStep and {
		name = qualityStep.en or qualityStep.name,
		effect = qualityStep.effectEn or qualityStep.effect,
		catalysts = qualityStep.catalysts,
	} or nil

	-- The currencies a client may ask mod_chances about, so a user interface can build a
	-- picker without hard-coding the league table.
	local methods = { }
	for id, currency in pairs(ruleset().currencies or { }) do
		methods[#methods + 1] = { id = id, name = currency.en or id, side = currency.side }
	end
	table.sort(methods, function(a, b) return tostring(a.name) < tostring(b.name) end)

	local payload = {
		league = advice.league,
		runeforging = advice.runeforging,
		quality = quality,
		options = options,
		methods = methods,
		runeCount = advice.runeCount,
		alloyNote = "alloy modifiers carry zero spawn weight in PoB, so no odds are reported for them",
	}
	if item.language == "ru" then
		if OutRu.wantsRussian(args) and languageOf(args) ~= "en" then payload = OutRu.translate(payload) end
	end
	return payload, nil
end

local function toolRuneforging(args)
	local base = tostring(args.base_type or "")
	local results = Runeforging.forBase(base)
	if not results then
		return { base_type = base, runeforgeable = false }, nil
	end
	return { base_type = base, runeforgeable = true, results = results }, nil
end

local function toolPrices()
	local info = Prices.info()
	local result = {
		available = info.available,
		league = info.league,
		fetchedAt = info.fetchedAt,
		source = info.source,
		url = info.url,
		unit = info.unit,
		currencies = info.currencies,
		reason = info.reason,
	}
	local rules = ruleset()
	local applies, why = Prices.matchesLeague(rules.league or rules.leagueShort, config.ui.pricesLeague)
	result.appliesToConfiguredLeague = applies
	result.appliesReason = why
	result.configuredLeague = rules.league or rules.leagueShort

	-- The currencies this overlay actually recommends, so an AI client does not have to
	-- guess which price matters for a crafting plan.
	local interesting = { "Chaos Orb", "Exalted Orb", "Greater Exalted Orb",
		"Perfect Exalted Orb", "Divine Orb", "Orb of Annulment", "Regal Orb",
		"Orb of Transmutation", "Orb of Augmentation" }
	result.usedByMethods = { }
	for _, name in ipairs(interesting) do
		local price = Prices.unitPrice(name)
		if price then
			result.usedByMethods[#result.usedByMethods + 1] = { name = name, chaos = price }
		end
	end
	return result, nil
end

--- Which rarities a currency accepts, by display name.
--
-- The ruleset describes what a currency does, not what it may be used on, so the crafting
-- summary offered an Orb of Transmutation for a rare helmet - a currency that only works on
-- normal items. These gates come from the game's own item rules and are checked before a
-- method is offered.

--- Everything the player needs to answer "can I finish this item, with what, and how much".
--
-- One pass over the ruleset instead of one request per currency: the page asks once and
-- gets a row per way to craft, with how many pieces it takes (average and a 90% bound), what
-- it costs in the three currencies players think in, and what it can produce. Methods that
-- cannot be used at all are reported with a reason instead of being dropped silently.
local function toolCraftCost(args)
	local item, err = parseItem(args.item_text)
	if not item then
		return nil, err
	end
	local method = tostring(args.method or "")
	local target = args.target and tostring(args.target) or nil

	-- What the method does to the item: the same pool the overlay shows.
	local chances
	if method == "desecration" then
		local pool = Mods.desecrationPool(item.itemLevel, item.baseHints,
			{ excludeGroups = existingGroups(item), excludeTexts = Mods.presentTexts(item) })
		Mods.attachReveal(pool)
		chances = { name = "Desecration", tierCount = pool.tierCount, groups = groupList(pool, 40) }
		for index, group in ipairs(chances.groups) do
			local source = (pool.groups or { })[index]
			group.revealChance = source and source.revealChance or nil
		end
	else
		local currency = (ruleset().currencies or { })[method]
		if not currency then
			return nil, "unknown method '" .. method .. "'"
		end
		-- A currency that does not accept this item's rarity is refused with the reason, not
		-- computed into a chance the player could never use.
		local gate = rarityGate(currency.en or method, item.rarity)
		if gate then
			return nil, "cannot be applied: " .. gate
		end
		local pool = Mods.rollPool(item.itemLevel, item.baseHints, { baseName = item.baseType,
			side = (currency.side and currency.side ~= "any") and currency.side or nil,
			minModLevel = currency.minModLevel,
			excludeGroups = existingGroups(item),
			sources = item.baseSources,
		})
		chances = { name = currency.en or method, tierCount = pool and pool.tierCount or 0,
			groups = groupList(pool, 40) }
	end

	-- The target is the modifier the player wants; without one the best group is assumed.
	local chosen = chances.groups[1]
	if target then
		for _, group in ipairs(chances.groups) do
			if group.text == target then
				chosen = group
				break
			end
		end
	end
	if not chosen then
		return nil, "this method has no eligible modifiers for the item"
	end

	-- Probability per attempt: the desecration reveal (three options offered) when that is
	-- what the game does, otherwise the weighted share.
	local chance = chosen.chance / 100
	local revealNote = nil
	if method == "desecration" and chosen.revealChance then
		chance = chosen.revealChance
		revealNote = "chance includes the Well of Souls reveal (three options per attempt)"
	end
	local expectedAttempts = chance > 0 and (1 / chance) or nil

	-- Cost per attempt: the currencies the method consumes, priced from the snapshot.
	-- Every price is quoted with its league, and a snapshot from another league is not
	-- used for a number - the caller gets the attempt count and the reason instead.
	local rules = ruleset()
	local applies, why = Prices.matchesLeague(rules.league or rules.leagueShort, config.ui.pricesLeague)
	local chaosUnit = Prices.unitPrice("Chaos Orb") or 1
	local exaltedUnit = Prices.unitPrice("Exalted Orb")
	local divineUnit = Prices.unitPrice("Divine Orb")
	local attemptCost, unpriced = { }, { }
	local function addCost(name)
		local price = Prices.unitPrice(name)
		if price then
			attemptCost[#attemptCost + 1] = { name = name, chaos = price }
		else
			unpriced[#unpriced + 1] = name
		end
	end
	if method == "desecration" then
		addCost("Omen of Sinistral Necromancy")
	else
		local currency = (rules.currencies or { })[method]
		if currency and currency.en then
			addCost(currency.en)
		end
	end

	local perAttempt = 0
	for _, entry in ipairs(attemptCost) do
		perAttempt = perAttempt + entry.chaos
	end
	local totalCost = (applies and perAttempt > 0 and expectedAttempts)
		and perAttempt * expectedAttempts or nil

	-- "Craft until it happens": how many pieces each confidence level needs and what that
	-- costs. The counts come from the geometric distribution (the same model as the expected
	-- number of attempts), the money from the per-attempt price above.
	local function attemptsFor(target)
		if not chance or chance <= 0 then
			return nil
		end
		if chance >= 1 then
			return 1
		end
		return math.ceil(math.log(1 - target) / math.log(1 - chance))
	end

	local costTo = nil
	if applies and perAttempt > 0 then
		costTo = { }
		for _, level in ipairs({ { "p50", 0.5 }, { "p90", 0.9 }, { "p99", 0.99 } }) do
			local count = attemptsFor(level[2])
			if count then
				costTo[level[1]] = {
					attempts = count,
					chaos = math.floor(perAttempt * count * 100 + 0.5) / 100,
					exalted = exaltedUnit and math.floor((perAttempt * count / exaltedUnit) * 100 + 0.5) / 100 or nil,
					divine = divineUnit and math.floor((perAttempt * count / divineUnit) * 1000 + 0.5) / 1000 or nil,
				}
			end
		end
	end

	return {
		method = method,
		name = chances.name,
		target = chosen.text,
		tier = chosen.tier,
		poolSize = chances.tierCount,
		chancePerAttempt = math.floor(chance * 1e6 + 0.5) / 1e6,
		expectedAttempts = expectedAttempts and math.floor(expectedAttempts * 100 + 0.5) / 100 or nil,
		attemptCost = attemptCost,
		attemptCostTotal = perAttempt > 0 and math.floor(perAttempt * 1e4 + 0.5) / 1e4 or nil,
		expectedCost = totalCost and math.floor(totalCost * 100 + 0.5) / 100 or nil,
		costTo = costTo,
		pricesApply = applies,
		pricesReason = why,
		pricesLeague = Prices.info().league,
		pricesFetchedAt = Prices.info().fetchedAt,
		unpricedCurrencies = unpriced,
		note = revealNote,
		otherGroups = #chances.groups,
	}, nil
end

--- Dispatch one tool call.
-- @return result table, or nil plus an error message
local function dispatch(name, args)
	args = args or { }
	-- The lines the player's own client wrote: the panel and the overlay show the item in
	-- the client's language, while the parsed item is English (the engine translates it).
	-- The reference the overlay shows: written once, in data, so every screen explains a
	-- mechanic with the same words.
	if name == "crafting_guide" then
		return {
			league = Guide.league, sources = Guide.SOURCES, caps = Guide.CAPS,
			mainRule = Guide.MAIN_RULE, mainRuleEn = Guide.MAIN_RULE_EN,
			orbs = Guide.ORBS, tiers = Guide.TIERS,
			essence = Guide.ESSENCE, groups = Guide.GROUPS, desecration = Guide.DESECRATION,
			omens = Guide.OMENS, alloys = Guide.ALLOYS, mistakes = Guide.MISTAKES,
			-- An array of sentences cannot carry a twin inside itself, so the English list travels as
			-- a twin of the whole field and Mcp/api.lua's language gate swaps it in.
			loop = Guide.LOOP, loopEn = Guide.LOOP_EN,
			-- The traps, so the reference can list them before the player meets them in a video.
			claims = Claims.list(),
			-- The Genesis Tree as plans with expected births, so the reference can answer "how do I
			-- get the catalyst I need" - the question 0.5.0's drop change made unavoidable.
			qualityBaseCaps = (ruleset().quality or {}).baseCaps,
			genesisTree = {
				location = (ruleset().genesisTree or {}).location,
				locationEn = (ruleset().genesisTree or {}).locationEn,
				notes = (ruleset().genesisTree or {}).notes,
				notesEn = (ruleset().genesisTree or {}).notesEn,
				goals = GenesisTree.overview(ruleset()),
				-- The passives that change what a womb produces. A subset on purpose, with its own source, so
				-- the reference can say "these are the ones that matter" rather than implying it is the tree.
				wombPassives = (ruleset().genesisTree or {}).wombPassives,
				wombPassivesSource = (ruleset().genesisTree or {}).wombPassivesSource,
				wombPassivesSourceEn = (ruleset().genesisTree or {}).wombPassivesSourceEn,
			},
			-- How many of them our own ruleset settles, so the reference can say "checked against the data"
			-- rather than "we wrote this down".
			claimsChecked = (function()
				local result = Claims.verifyAll(ruleset())
				return { checked = result.checked, failed = #result.failed, total = #Claims.list() }
			end)(),
		}, nil
	end

	-- One screen for the beginner: what is locked, what to do next, what not to do.
	if name == "craft_step" then
		local itemText = args and args.item_text
		if type(itemText) ~= "string" or itemText == "" then
			return nil, "item_text is required"
		end
		local parsed = parseItem(itemText)
		if not parsed then
			return nil, "the item could not be parsed"
		end
		local advice = select(1, dispatch("analyze_item", { item_text = itemText, lang = args.lang })) or { }
		local report = Coach.report(parsed, advice, itemText)
		-- "Should I craft this at all?" - the expected cost of the cheapest route plus exactly what to
		-- search in trade to compare. The finished-item price is NOT filled in: the price snapshot has
		-- never carried rare items, and inventing one would be the worst thing a mentor could do.
		report.craftOrBuy = CraftOrBuy.forItem(parsed, advice,
		{ marketUrl = (type(args.market_url) == "string" and args.market_url ~= "") and args.market_url or nil })
		-- The player's own situation, which every human crafter asks about before advising: how much currency
		-- there is, whether trade exists at all, and whether the item is for wearing or for selling. The two
		-- lines built here are the answers a person gives - "your currency buys about 34 attempts, that is a
		-- 91% chance" and, in SSF, "there is nowhere to buy the finished item, so the stop rule is different".
		local step = report.step or { }
		local budget = tonumber(args and args.budget_chaos)
		local mode = tostring((args and args.mode) or "trade")
		local goal = tostring((args and args.goal) or "sell")
		local cost = tonumber(step.cost)
		if budget and budget > 0 and cost and cost > 0 then
			local attempts = math.floor(budget / cost)
			local chance = tonumber(step.chancePerAttempt)
			step.affordableAttempts = attempts
			step.affordableBudget = budget
			if attempts >= 1 and chance then
				local success = 1 - ((1 - chance) ^ attempts)
				step.affordableChance = success
				step.budgetReply = string.format(
					"на %s %s хватит ≈ %d попыток — это шанс дойти до результата ≈ %.0f %%",
					tostring(budget), tostring(step.costUnit or ""), attempts, success * 100)
				step.budgetReplyEn = string.format(
					"your %s %s buys about %d attempts - that is a %.0f%% chance of getting there",
					tostring(budget), tostring(step.costUnit or ""), attempts, success * 100)
			elseif attempts < 1 then
				step.budgetReply = string.format(
					"на %s %s не хватает даже на одну попытку (одна стоит ≈ %s %s)",
					tostring(budget), tostring(step.costUnit or ""), tostring(step.cost),
					tostring(step.costUnit or ""))
				step.budgetReplyEn = string.format(
					"%s %s does not even buy one attempt (one costs about %s %s)",
					tostring(budget), tostring(step.costUnit or ""), tostring(step.cost),
					tostring(step.costUnit or ""))
			end
		end
		if mode == "ssf" then
			step.modeNote = "SSF: готовый предмет купить негде, поэтому стоп-правило — только про твою валюту, "
				.. "а не про цену в трейде"
			step.modeNoteEn = "SSF: there is nowhere to buy the finished item, so the stop rule is about your "
				.. "own currency, not about a trade price"
			step.stopRule = nil
			step.stopRuleEn = nil
		end
		if goal == "wear" then
			step.goalNote = "предмет для себя: переплатить за идеал можно, важно не сорвать крафт на последнем шаге"
			step.goalNoteEn = "for wearing: overpaying for the ideal roll is fine - what matters is not "
				.. "wrecking the craft on the last step"
		end
		report.step = step
		-- The plan a person would give: goal, three steps, where to stop - built only from rules that
		-- passed the consensus bar (docs/craft-consensus-0.5.md); each step names its rule.
		report.routes = Recipes.forItem(parsed)
		-- What the item's own state forbids, before any step: one crafted slot, one desecrated slot (C1, C8).
		-- Saying it here stops the card from proposing a step that cannot work.
		report.stateNotes = Recipes.stateNotes(report.state or { })
		-- What can still land on this item, grouped and ranked for the goal. Lives in "показать всё", not on the
		-- card: the pool is 40+ entries and the card is for one action.
		report.modPool = ModPool.forItem(parsed, { goal = args.goal, lang = languageOf(args) })
		-- Which candidate is worth chasing, and what raises its chance. Built from the pool the report already
		-- carries, so the card highlights a modifier the engine itself ranks - and only attaches a boost when a
		-- technique names that family. Nothing here invents a probability or a price.
		report.valueHints = ValueHint.forWanted(
			(report.modPool and report.modPool.wanted) or { },
			{ minBoost = tonumber(args.value_boost) })
		report.valueHintText = ValueHint.summary(report.valueHints, languageOf(args))
		return report, nil
	end

	if name == "item_lines" then
		local text = args and args.item_text
		if type(text) ~= "string" or text == "" then
			return nil, "item_text is required"
		end
		return Lines.split(text), nil
	end

	if name == "__describe__" then
		return { tools = api.describe() }, nil
	elseif name == "sources" then
		-- The caller's language goes through: without it the labels stayed English on a
		-- Russian page, because the dispatcher used to drop the arguments here.
		return toolSources(args), nil
	elseif name == "analyze_item" then
		-- The summary is attached here, not inside toolAnalyze: it is defined further down
		-- (it reuses the cost maths), and a local defined later is not visible in an earlier
		-- function - the call silently became a nil global and the field never appeared.
		local payload, err = toolAnalyze(args)
		if payload then
			payload.craftSummary = select(1, toolCraftSummary({ item_text = args.item_text, lang = args.lang }))
			-- The methods picker rides along with the analysis: the panel already makes this call, and a
			-- second round trip per capture would double the wait for the same data. The STAGE travels too:
			-- it used to be dropped here, so the panel's campaign/early/endgame buttons re-analysed the item
			-- and got the same answer every time - the engine silently fell back to the stage the item level
			-- implies and ignored the player's choice, which made the buttons look broken.
			payload.methods = select(1, toolMethods({ item_text = args.item_text, stage = args.stage, lang = args.lang }))
		end
		return payload, err
	elseif name == "mod_chances" then
		return toolModChances(args)
	elseif name == "league_methods" then
		return toolLeagueMethods(args)
	elseif name == "methods" then
		return toolMethods(args)
	elseif name == "check_claim" then
		-- "Is this true?" - the one question a beginner cannot answer alone, and the one that protects him
		-- from the fabricated guides documented in docs/mentor-research.md.
		local text = args and (args.text or args.claim or args.question)
		if type(text) ~= "string" or text == "" then
			return nil, "text is required"
		end
		return Claims.answer(text), nil
	elseif name == "market_query" then
		-- The market half of craft-vs-buy: what to ASK the trade site, built from the parsed item. The
		-- trade stat text wants numbers blanked to "#" and no leading plus, and the minimum is the roll the
		-- item actually has - comparing against a worse item would understate what it is worth.
		local itemText = args and args.item_text
		if type(itemText) ~= "string" or itemText == "" then
			return nil, "item_text is required"
		end
		local parsed, parseErr = parseItem(itemText)
		if not parsed then
			return nil, parseErr or "the item could not be parsed"
		end
		local base = tostring(parsed.baseType or "")
		if base == "" then
			return nil, "the item has no base type, so it cannot be looked up"
		end
		-- The trade site is localised by HOST: a Russian item goes to ru.pathofexile.com with its own names
		-- (that catalogue knows bases the English one lacks), an English item goes to the main site.
		local keepRussian = languageOf(args) ~= "en"
		local mods = { }
		for _, mod in ipairs(parsed.explicitMods or { }) do
			local line = type(mod) == "table" and (mod.text or "") or mod
			if type(line) == "string" and line ~= "" and line:sub(1, 1) ~= "{" then
				-- "37% increased Energy Shield" -> "#% increased Energy Shield"
				local stat = line:gsub("%-?%d+%.?%d*", "#")
				stat = stat:gsub("^%+", "")
				-- The item's own lowest number becomes the floor for the search.
				local minimum = nil
				for number in line:gmatch("(%-?%d+%.?%d*)") do
					local value = tonumber(number)
					if value and (minimum == nil or value < minimum) then minimum = value end
				end
				-- The side travels too. When the search has to loosen it keeps one prefix and one suffix,
				-- because the first two lines may both come from the same side and the price would then
				-- describe a different item.
				-- The annotation the game prints above the line is the authority on the side; the resolved
				-- table only supplies the tier and disagrees on some modifiers. A wrong side would make the
				-- market search price one prefix and one suffix as if they were the other way round.
				local sideSource = type(mod) == "table" and (mod.side or (mod.mod and mod.mod.type)) or nil
				local side = sideSource and string.lower(tostring(sideSource)) or ""
				-- The trade site only knows English stat names. A Russian line resolves to nothing, so the
				-- search would burn all four ladder rungs and the hourly budget to learn that. Translate
				-- first; if the line stays non-Latin, drop it rather than send junk.
				if not keepRussian and stat:find("[\128-\255]") then
					local translated = nil
					local ok, value = pcall(Ru.toEnglish, stat)
					if ok and type(value) == "string" and value ~= "" then translated = value end
					if translated then
						stat = translated:gsub("%-?%d+%.?%d*", "#"):gsub("^%+", "")
					end
				end
				if not stat:find("[\128-\255]") then
					-- The tier's own roll range travels too: a listing at the bottom of the same tier is still
					-- the same kind of item, which a guessed "-20%" is not. This is the first thing the search
					-- loosens when nothing matches at the current roll.
					local range = type(mod) == "table" and type(mod.ranges) == "table" and mod.ranges[1] or nil
					mods[#mods + 1] = {
						text = stat,
						min = minimum,
						rangeMin = range and tonumber(range.min) or nil,
						rangeMax = range and tonumber(range.max) or nil,
						side = side,
					}
				end
			end
		end
		if #mods == 0 then
			return nil, "the item has no explicit modifiers to match"
		end
		return {
			base = base,
			tradeHost = keepRussian and "ru.pathofexile.com" or "www.pathofexile.com",
			-- The trade site knows this league as "Forbidden Rites", without the version prefix our
			-- ruleset carries. Sending "0.5.5 Forbidden Rites" relied on the caller falling back to a
			-- substring match, which is a guess where an exact name is available.
			league = (tostring((ruleset() or { }).league or ""):gsub("^%d+%.%d+%.?%d*%s*", "")),
			mods = mods,
			note = "Запрос к трейду: та же база и те же моды, с минимумом по текущему роллу.",
			noteEn = "Trade query: the same base and the same modifiers, with the current roll as the minimum.",
		}, nil
	elseif name == "craft_or_buy" then
		-- "Is crafting this cheaper than buying it?" The player supplies the market price, because no
		-- feed prices individual rares; the engine supplies the craft cost it can compute exactly.
		local itemText = args and args.item_text
		if type(itemText) ~= "string" or itemText == "" then
			return nil, "item_text is required"
		end
		local price = tonumber(args and (args.buy_price or args.price))
		if not price or price < 0 then
			return nil, "buy_price is required and must be a number in chaos"
		end
		local parsed = parseItem(itemText)
		if not parsed then
			return nil, "the item could not be parsed"
		end
		local advice = select(1, dispatch("analyze_item", { item_text = itemText, lang = args.lang })) or { }
		local verdict = CraftOrBuy.verdictFor(price, advice, args)
		if not verdict then
			return nil, "the craft cost is unknown for this item, so there is nothing to compare against"
		end
		return verdict, nil
	elseif name == "claims" then
		return { claims = Claims.list() }, nil
	elseif name == "runeforging" then
		return toolRuneforging(args)
	elseif name == "prices" then
		return toolPrices()
	elseif name == "craft_summary" then
		return toolCraftSummary(args)
	elseif name == "craft_cost" then
		return toolCraftCost(args)
	end
	return nil, "unknown tool '" .. tostring(name) .. "'"
end

--- Dispatch one tool call, answering in the caller's language.
-- The payload is built in the language each module holds (Russian for the engine's own prose), and the
-- twin is chosen here, at one point: a module only has to carry the twin, and Tests.test_language
-- reports every string that has none instead of letting the panel show two languages in one card.
function api.call(name, args)
	args = args or { }
	local result, err = dispatch(name, args)
	if type(result) == "table" then
		local lang = languageOf(args)
		result = localise(result, lang)
		if lang == "ru" then
			-- The names of game objects are the game's Latin ones even in a Russian reply; the official
			-- Russian spellings come from the inverted dictionaries.
			result = russianNames(result)
		end
	end
	return result, err
end

--- Statistics for the diagnostics log.
function api.stats()
	return {
		tools = #api.describe(),
		essences = Essences.stats().essences,
		runes = Runes.stats().runes,
		runeforgingBases = Runeforging.stats().bases,
		mods = Mods.stats and (Mods.stats().mods or Mods.stats().groups) or 0,
	}
end

return api
