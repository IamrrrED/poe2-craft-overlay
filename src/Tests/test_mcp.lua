-- PoE2 Craft Overlay : Tests/test_mcp.lua
-- The MCP layer: the JSON codec and the tools an AI client can call. Both are pure Lua
-- over the same modules the panel uses, so they are testable headlessly - the only part
-- that needs the host is the file/process bridge in mcp/server.js.

local Json = require("Mcp.json")
local Api = require("Mcp.api")
local Parser = require("Item.Parser")
local Mods = require("Item.Mods")
local league = require("Data.league_0_5_5")

local ITEM = [[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
+45% to Fire Resistance
+38% to Cold Resistance
]]

return function(H)
	-- JSON codec: the bridge depends on it in both directions.
	H.eq("mcp/json: string escaping", Json.encode('a"b\\c\nd'), '"a\\"b\\\\c\\nd"')
	H.eq("mcp/json: integers stay integers", Json.encode(42), "42")
	H.eq("mcp/json: booleans and null", Json.encode(true) .. Json.encode(false), "truefalse")
	-- An empty table is an empty array: Lua has no way to tell them apart.
	H.eq("mcp/json: empty table encodes as an empty array", Json.encode({ }), "[]")
	H.eq("mcp/json: single-key object", Json.encode({ x = 1 }), "{\"x\":1}")

	local decoded = Json.decode('{"a":[1,2,3],"b":{"c":"x"},"d":true,"e":null}')
	H.eq("mcp/json: round-trip object", decoded.b.c, "x")
	H.eq("mcp/json: round-trip array", decoded.a[3], 3)
	H.eq("mcp/json: round-trip boolean", decoded.d, true)
	H.eq("mcp/json: round-trip null", decoded.e, nil)

	local nested = { plans = { { id = "min", steps = { { name = "Exalted Orb" } } } } }
	local roundTrip = Json.decode(Json.encode(nested))
	H.eq("mcp/json: nested round-trip", roundTrip.plans[1].steps[1].name, "Exalted Orb")

	local bad, err = Json.decode('{"a": }')
	H.eq("mcp/json: invalid document reports an error", bad == nil and type(err) == "string", true)
	local unicode = Json.decode('"\\u0416"')
	H.eq("mcp/json: \\u escapes become UTF-8", #unicode, 2)

	-- Tool descriptors: what an MCP client sees.
	local tools = Api.describe()
	H.eq("mcp: several tools exposed", #tools >= 4, true)
	local byName = { }
	for _, tool in ipairs(tools) do
		byName[tool.name] = tool
		H.eq("mcp: tool has a description", type(tool.description) == "string" and #tool.description > 10, true)
		H.eq("mcp: tool has an input schema", type(tool.inputSchema), "table")
	end
	H.eq("mcp: analyze_item is exposed", byName.analyze_item ~= nil, true)
	H.eq("mcp: mod_chances is exposed", byName.mod_chances ~= nil, true)
	H.eq("mcp: league_methods is exposed", byName.league_methods ~= nil, true)
	H.eq("mcp: internal tool is hidden", byName.__describe__, nil)

	-- sources: every number must come with its provenance.
	local sources = assert(Api.call("sources", { }))
	H.eq("mcp: sources returned", #sources.sources >= 4, true)
	local missing = 0
	for _, source in ipairs(sources.sources) do
		if not (source.label and source.detail and source.url) then
			missing = missing + 1
		end
	end
	H.eq("mcp: every source is complete", missing, 0)

	-- analyze_item: same engine as the panel.
		-- lang = "en": the parsed fields are compared against the game's canonical English names.
	-- The Russian spellings of the same fields are covered by Tests.test_language.
	local analysis = assert(Api.call("analyze_item", { item_text = ITEM, lang = "en" }))
	H.eq("mcp: item parsed", analysis.item.baseType, "Blacksteel Gauntlets")
	H.eq("mcp: item level reported", analysis.item.itemLevel, 82)
	-- Two prefixes and two suffixes on a Rare, so one slot stays open on each side.
	H.eq("mcp: affinity split reported", analysis.item.affixes, "2P/2S open 1P/1S")
	H.eq("mcp: rule reported", analysis.ruleId, "rare_open_affix")
	H.eq("mcp: two plans", #analysis.plans, 2)
	H.eq("mcp: min plan has steps", #analysis.plans[1].steps >= 1, true)
	H.eq("mcp: step carries a name", analysis.plans[1].steps[1].name ~= nil, true)

	-- A Warden's Bow: the class has no slot caps in our data, so the split can be complete while the OPEN
	-- counts are nil. Formatting those straight into %d aborted the whole analysis - the panel showed
	-- "движок не ответил. нет ответа analyze_item" instead of a card - because the code assumed that a
	-- known split means known slot counts.
	local WARDEN = table.concat({
		"Item Class: Bows",
		"Rarity: Rare",
		"Warden's Bow",
		"--------",
		"Item Level: 80",
		"--------",
		'{ Prefix Modifier "Charged" (Tier: 2) }',
		"Adds 10 to 20 Lightning Damage",
		'{ Suffix Modifier "of the Wind" (Tier: 1) }',
		"12% increased Attack Speed",
	}, "\n")
	local warden = assert(Api.call("analyze_item", { item_text = WARDEN }))
	H.eq("mcp: a class without slot caps still answers", warden.item.baseType, "Warden's Bow")
	H.check("mcp: and says the open counts are unknown instead of failing",
		type(warden.item.affixes) == "string", tostring(warden.item.affixes))

	-- mod_chances: weighted pool, same numbers as the panel.
	local exalted = assert(Api.call("mod_chances", { item_text = ITEM, method = "exalted" }))
	H.eq("mcp: exalted pool is not empty", exalted.tierCount > 0, true)
	H.eq("mcp: exalted reports groups", #exalted.groups > 0, true)
	local group = exalted.groups[1]
	H.eq("mcp: group chance is a percentage", group.chance > 0 and group.chance < 100, true)
	H.eq("mcp: group carries its tier", group.tier >= 1, true)

	-- Desecration adds the community "three options offered" model on top of the share.
	local desecration = assert(Api.call("mod_chances", { item_text = ITEM, method = "desecration" }))
	H.eq("mcp: desecration pool is not empty", desecration.tierCount > 0, true)
	H.eq("mcp: desecration reports a reveal model", type(desecration.reveal), "table")
	H.eq("mcp: reveal is three draws", desecration.reveal.draws, 3)
	H.eq("mcp: reveal reports the pool size", desecration.reveal.poolSize, desecration.tierCount)
	-- The top group's reveal chance comes from the pool (Mods.attachReveal), which the
	-- reference table pins against the community implementation row by row.
	local top = desecration.groups[1]
	local expected = Mods.revealChance(desecration.tierCount, top.targetCount, 3, false)
	H.eq("mcp: reveal chance matches the pool maths",
		math.abs(desecration.reveal.perGroup - expected) < 0.0002, true)
	H.eq("mcp: echoes raise the chance combinatorially",
		math.abs(desecration.reveal.withEchoes - (1 - (1 - expected) ^ 2)) < 0.0002, true)
	H.eq("mcp: every group carries its own reveal chance",
		type(top.revealChance) == "number" and type(top.revealEchoes) == "number", true)

	-- prices: reported with the league they belong to, never as a bare number.
	local prices = assert(Api.call("prices", { }))
	H.eq("mcp: prices tool reports availability", prices.available, true)
	H.eq("mcp: prices tool names its league", type(prices.league) == "string" and #prices.league > 0, true)
	H.eq("mcp: prices tool reports fetch time", type(prices.fetchedAt) == "string", true)
	H.eq("mcp: prices tool says whether it applies", type(prices.appliesToConfiguredLeague), "boolean")
	H.eq("mcp: prices tool lists method currencies", #prices.usedByMethods > 0, true)

	-- analyze_item carries the same verdict, so a client cannot miss the caveat.
	H.eq("mcp: analyze_item includes prices context", type(analysis.prices), "table")
	H.eq("mcp: prices context is labelled", analysis.prices.league ~= nil, true)
	-- league_methods: omens, essences, runes and alloys in one call.
	local methods = assert(Api.call("league_methods", { item_text = ITEM }))
	local kinds = { }
	for _, option in ipairs(methods.options) do
		kinds[option.kind or "omen"] = true
	end
	H.eq("mcp: rune crafts offered", kinds.rune, true)
	H.eq("mcp: essence crafts offered", kinds.essence, true)
	H.eq("mcp: omen crafts offered", kinds.omen, true)
	H.eq("mcp: alloy pool offered", kinds.alloy, true)
	H.eq("mcp: runeforging attached", type(methods.runeforging), "table")

	-- The newer step kinds carry fields a client needs, and they used to be dropped on the way out:
	-- which bone to buy, the catalysts matching a piece of jewellery, a waystone's tier, the emotion
	-- count for instilling, and the quality step - which is decided outside the plan and therefore
	-- travels as its own field.
	local AMULET = table.concat({
		"Item Class: Amulets",
		"Rarity: Rare",
		"Rapture Beads",
		"Stellar Amulet",
		"--------",
		"Item Level: 79",
		"--------",
		'+{ Prefix Modifier "Heated" (Tier: 2) }',
		"Adds 12 to 21 Fire Damage to Attacks",
	}, "\n")
	-- lang = "en": the bone names are asserted in English, and the Russian spellings are covered by
	local amuletMethods = assert(Api.call("league_methods", { item_text = AMULET, lang = "en" }))
	local sawBone, sawInstil = false, false
	for _, option in ipairs(amuletMethods.options) do
		if option.bone then
			sawBone = true
			H.check("mcp: the bone is named for the item", option.bone:find("Collarbone", 1, true) ~= nil,
				tostring(option.bone))
		end
		if option.kind == "instil" then
			sawInstil = true
			H.eq("mcp: instilling reports the emotion count", option.emotionCount, 26)
		end
	end
	H.eq("mcp: a desecration option carries its bone", sawBone, true)
	H.eq("mcp: instilling is offered for an amulet", sawInstil, true)
	H.check("mcp: the quality step travels separately", amuletMethods.quality ~= nil)

	local RING = table.concat({
		"Item Class: Rings",
		"Rarity: Rare",
		"Doom Loop",
		"Gold Ring",
		"--------",
		"Item Level: 78",
		"--------",
		'+{ Prefix Modifier "Merciless" (Tier: 3) }',
		"Adds 12 to 21 Physical Damage to Attacks",
	}, "\n")
	local ringMethods = assert(Api.call("league_methods", { item_text = RING, lang = "en" }))
	H.check("mcp: jewellery quality is a catalyst, not a class currency",
		ringMethods.quality ~= nil and ringMethods.quality.name ~= nil
			and ringMethods.quality.name:find("Catalyst", 1, true) ~= nil,
		tostring(ringMethods.quality and ringMethods.quality.name))
	H.check("mcp: and it lists the matching catalysts",
		type(ringMethods.quality.catalysts) == "table" and #ringMethods.quality.catalysts > 0)
	-- It also has to appear in the OPTIONS list, not only in the quality field: a client that reads the
	-- methods list is the normal case, and for jewellery the catalyst choice is the decision.
	local sawQualityOption = false
	for _, option in ipairs(ringMethods.options) do
		if option.kind == "quality" then
			sawQualityOption = true
			H.check("mcp: the quality option carries the catalysts",
				type(option.catalysts) == "table" and #option.catalysts > 0)
		end
	end
	H.eq("mcp: the quality step is also a listed method", sawQualityOption, true)

	local WAYSTONE = table.concat({
		"Item Class: Waystones",
		"Rarity: Rare",
		"Waystone (Tier 15)",
		"--------",
		"Item Level: 79",
		"--------",
		"Monsters deal 20% increased Damage",
	}, "\n")
	local waystoneMethods = assert(Api.call("league_methods", { item_text = WAYSTONE }))
	local sawWaystone = false
	for _, option in ipairs(waystoneMethods.options) do
		if option.kind == "waystone" then
			sawWaystone = true
			H.eq("mcp: the waystone tier is reported", option.tier, 15)
		end
	end
	H.eq("mcp: a waystone gets its own step", sawWaystone, true)

	-- The text rendering has to mention the quality step as well: it is the first thing the player does.
	local Advisor = require("Craft.Advisor")
	local Parser = require("Item.Parser")
	local league = require("Data.league_0_5_5")
	local text = Advisor.toText(Advisor.analyze(Parser.parse(RING), league))
	H.check("mcp: the text rendering mentions the quality step",
		text:find("Quality first", 1, true) ~= nil)

	-- runeforging tool.
	local forging = assert(Api.call("runeforging", { base_type = "Blacksteel Gauntlets", lang = "en" }))
	H.eq("mcp: runeforging resolves", forging.runeforgeable, true)
	H.eq("mcp: runeforging result named", forging.results[1]:find("Runeforged", 1, true) ~= nil, true)
	local unknown = assert(Api.call("runeforging", { base_type = "Not A Real Base" }))
	H.eq("mcp: unknown base is not invented", unknown.runeforgeable, false)

	-- The methods picker: everything that can be done with the item right now, grouped, with prices in
	-- the three currencies and the FULL modifier list per method (the customer asked for all of them,
	-- not a truncated "top few").
	local SCEPTRE = table.concat({
		"Item Class: Sceptres",
		"Rarity: Rare",
		"Dire Growth",
		"Rattling Sceptre",
		"--------",
		"Spirit: 114 (augmented)",
		"--------",
		"Item Level: 78",
		"--------",
		'{ Prefix Modifier "of Mana" (Tier: 3) - Mana }',
		"+35 to maximum Mana",
		'{ Suffix Modifier "of Skills" (Tier: 3) }',
		"+3 to Level of all Minion Skills",
	}, "\n")
	-- lang = "en" on purpose: this block checks which METHODS are offered, and the English names are the
	-- canonical ones the rest of the file compares against. The Russian spellings are covered by
	-- Tests.test_language.
	local methods = assert(Api.call("methods", { item_text = SCEPTRE, lang = "en" }))
	local byGroup = { }
	for _, group in ipairs(methods.groups or { }) do
		byGroup[group.id] = group
	end
	H.check("methods: the picker has groups", (methods.groups or { })[1] ~= nil)
	H.eq("methods: adding a modifier is offered while a slot is free", byGroup.add ~= nil, true)
	H.eq("methods: replacing is offered", byGroup.replace ~= nil, true)
	H.eq("methods: improving is offered", byGroup.improve ~= nil, true)
	-- A sceptre is a caster weapon: its quality currency is the Arcanist's Etcher, and it must appear.
	local improveTitles = { }
	for _, row in ipairs((byGroup.improve or { }).methods or { }) do
		improveTitles[#improveTitles + 1] = tostring(row.title)
	end
	H.check("methods: the sceptre's quality currency is offered",
		table.concat(improveTitles, " | "):find("Etcher", 1, true) ~= nil,
		table.concat(improveTitles, " | "))
	local addTitles = { }
	for _, row in ipairs((byGroup.add or { }).methods or { }) do
		addTitles[#addTitles + 1] = tostring(row.title)
	end
	H.check("methods: the exalted orb is offered for the free slot",
		table.concat(addTitles, " | "):find("Exalted", 1, true) ~= nil, table.concat(addTitles, " | "))

	-- Every method carries its whole pool, and each modifier its own chance.
	local exaltedRow = nil
	for _, row in ipairs((byGroup.add or { }).methods or { }) do
		if row.title == "Exalted Orb" then
			exaltedRow = row
		end
	end
	H.check("methods: the exalted row is found", exaltedRow ~= nil)
	if exaltedRow then
		H.check("methods: the pool is not truncated to a handful",
			#(exaltedRow.mods or { }) >= 10, tostring(#(exaltedRow.mods or { })))
		H.check("methods: a modifier carries its chance",
			tonumber((exaltedRow.mods or { })[1].chance) ~= nil,
			tostring((exaltedRow.mods or { })[1].chance))
		H.check("methods: and its tier", tonumber((exaltedRow.mods or { })[1].tier) ~= nil)
		-- Prices in the three currencies, cheapest first, with the divine orb last for a cheap cost.
		local prices = exaltedRow.price or { }
		H.eq("methods: three price rows", #prices, 3)
		-- "начиная с самой дешёвой": the order is by real value, so each row must be worth at least as
		-- much as the one before it. The rates come from the same snapshot the costs do.
		local Prices = require("Craft.Prices")
		local chaosOf = { chaos = 1, exalted = Prices.unitPrice("Exalted Orb"),
			divine = Prices.unitPrice("Divine Orb") }
		local previousValue = nil
		local ordered = true
		local sawChaos, sawExalted = false, false
		for _, price in ipairs(prices) do
			local unit = chaosOf[price.id]
			if unit then
				local value = price.amount * unit
				if previousValue and value < previousValue - 1e-9 then
					ordered = false
				end
				previousValue = value
			end
			if price.id == "chaos" then
				sawChaos = true
			end
			if price.id == "exalted" then
				sawExalted = true
			end
		end
		H.eq("methods: the prices are ordered cheapest first", ordered, true)
		H.eq("methods: the chaos price is present", sawChaos, true)
		H.eq("methods: the exalted price is present", sawExalted, true)
	end

	-- Errors are reported, not raised.
	local result, callError = Api.call("nope", { })
	H.eq("mcp: unknown tool returns an error", result == nil and type(callError) == "string", true)
	local noItem, itemError = Api.call("analyze_item", { })
	H.eq("mcp: missing item text is rejected", noItem == nil and itemError ~= nil, true)
	local badMethod, methodError = Api.call("mod_chances", { item_text = ITEM, method = "not_a_currency" })
	H.eq("mcp: unknown method is rejected", badMethod == nil and methodError ~= nil, true)

	-- The tools must use the same engine as the panel, not a copy of the numbers.
	local item = Mods.annotate(Parser.parse(ITEM))
	local hints = Mods.hintsFor(item)
	H.eq("mcp: hints come from the item's base", type(hints), "table")
	H.eq("mcp: league table loaded by the api", type(league.currencies.exalted), "table")
end
