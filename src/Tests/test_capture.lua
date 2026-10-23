-- The capture path, end to end, without the game: the text the client copies goes through the
-- parser, the advisor and the panel's line builder. This is what F6 does after reading the
-- clipboard, so a failure here is a failure the player would see as a panel that closes.
return function()
	local H = require("Tests.harness")
	local Parser = require("Item.Parser")
	local Advisor = require("Craft.Advisor")
	local Coach = require("Craft.Coach")
	local Lines = require("Item.Lines")
	local Mods = require("Item.Mods")
	local league = require("Data.league_0_5_5")

	-- A realistic rare, in the client's Russian, with the sections the game writes.
	local CAPTURED = table.concat({
		"Класс предмета: Перчатки",
		"Редкость: Редкий",
		"Символический захват",
		"Перчатки из чешуи сирены",
		"--------",
		"Качество: +20% (augmented)",
		"Энергетический щит: 259 (augmented)",
		"--------",
		"Требуется: Уровень 80, 101 Инт",
		"--------",
		"18% повышение брони, уклонения и энергетического щита (rune)",
		'{ Очернённое Префикс "Сверкающий" (Уровень: 1) — Энергетический щит }',
		"+60(48-60) к максимуму энергетического щита",
		'{ Префикс "Неустрашимый" (Уровень: 3) — Энергетический щит }',
		"71(68-79)% увеличение энергетического щита",
		"--------",
		"Осквернено",
	}, "\n")

	-- The same two steps the panel takes: translate the client's Russian, then parse. A test
	-- that called the parser directly would prove nothing about what the player sees.
	local Ru = require("Item.Ru")
	local parseText = CAPTURED
	if Ru.looksRussian(CAPTURED) then
		parseText = Ru.toEnglish(CAPTURED) or CAPTURED
	end
	H.eq("capture: the client's Russian is detected", Ru.looksRussian(CAPTURED), true)
	local item = Parser.parse(parseText)
	H.eq("capture: the item is recognised", item.valid, true)
	H.eq("capture: the base survives parsing", item.baseType ~= nil, true)

	local advice = Advisor.analyze(item, league)
	H.eq("capture: the advisor answers", type(advice), "table")
	H.eq("capture: plans are a list", type(advice.plans), "table")
	H.eq("capture: the item block exists", type(advice.item), "table")

	-- What the panel draws from, so a plain text capture cannot slip through unpainted.
	local lines = Lines.split(CAPTURED)
	H.eq("capture: properties are read", #lines.properties >= 3, true)
	H.eq("capture: modifiers are read", #lines.mods >= 3, true)
	H.eq("capture: the rune modifier is kept", lines.mods[1].text:find("брони", 1, true) ~= nil, true)
	H.eq("capture: corruption is flagged", lines.flags.corrupted, true)
	local shown = #lines.properties + #lines.mods
	H.eq("capture: there is something to draw", shown > 0, true)

	-- A Magic item is named "<prefix> <base> <suffix>", so the parsed base type can be the whole
	-- name. Every modifier lookup starts from the base, so a decorated base type made a real capture
	-- resolve nothing at all: no tiers, no affix split, and advice built on a guess. The base has to
	-- be found inside the name.
	local MAGIC_FLASK = table.concat({
		"Item Class: Life Flasks",
		"Rarity: Magic",
		"Abundant Transcendent Life Flask of the Surgeon",
		"--------",
		"Recovers 1327 Life over 4 Seconds",
		"Consumes 10 of 75 Charges on use",
		"Currently has 75 Charges",
		"--------",
		"Requirements: Level 50",
		"--------",
		"Item Level: 54",
		"--------",
		'{ Prefix Modifier "Abundant" (Tier: 5) }',
		"58(56-60)% increased Recovery Amount",
		'{ Suffix Modifier "of the Surgeon" (Tier: 1) }',
		"31(31-35)% Chance to gain a Charge when you Kill an Enemy",
	}, "\n")
	local flask = Parser.parse(MAGIC_FLASK)
	H.eq("capture: the base is found inside the decorated name", flask.baseType, "Transcendent Life Flask")
	Mods.annotate(flask)
	H.eq("capture: its base tags are known", table.concat(flask.baseHints or { }, ","), "default,flask,life_flask")
	H.eq("capture: the prefix is counted", flask.prefixCount, 1)
	H.eq("capture: the suffix is counted", flask.suffixCount, 1)
	H.eq("capture: the split is complete", flask.affixSplitComplete, true)
	H.eq("capture: the flask's charge line is a property, not a modifier", flask.properties["Currently has 75 Charges"] ~= nil, true)

	-- Waystones have no base name to match: the item is written "Waystone (Tier 15)", so the tier is the
	-- only thing that tells one from another and it has to be read, both from a property line and from
	-- the name when the property line is absent.
	local WAYSTONE = table.concat({
		"Item Class: Waystones",
		"Rarity: Rare",
		"Waystone (Tier 15)",
		"--------",
		"Waystone Tier: 15",
		"--------",
		"Item Level: 79",
		"--------",
		"Monsters deal 20% increased Damage",
	}, "\n")
	local waystone = Parser.parse(WAYSTONE)
	H.eq("capture: the waystone tier is read from the property", waystone.tier, 15)
	H.eq("capture: and it is recognised as a waystone", waystone.itemClass, "Waystones")

	local NO_TIER_LINE = (WAYSTONE:gsub("Waystone Tier: 15\n", ""))
	local fromName = Parser.parse(NO_TIER_LINE)
	H.eq("capture: the tier falls back to the name", fromName.tier, 15)

	-- The advisor has to say what a waystone is for, and the one thing worth saying about a tier 15 is
	-- that a tier 16 only ever comes out of a corruption.
	local advice = Advisor.analyze(waystone, league)
	local waystoneOption = nil
	for _, entry in ipairs(advice.omenOptions or { }) do
		if entry.kind == "waystone" then
			waystoneOption = entry
		end
	end
	H.check("capture: a waystone gets its own option", waystoneOption ~= nil)
	H.eq("capture: the option carries the tier", waystoneOption.tier, 15)
	H.contains("capture: and explains how a tier 16 appears", waystoneOption.why, "ONLY by corrupting")
	H.eq("capture: the option names the four Chaotic omens", #(waystoneOption.omens or { }), 4)
	H.eq("capture: the odds are declared unknown rather than guessed", waystoneOption.oddsUnknown, true)
	H.eq("capture: the ruleset admits the modifier pool is missing", league.waystones.modsInData, false)

	-- The bug this guards against: a class whose modifier pool is absent from our data used to have its
	-- unrecognised modifiers read as a FULL item, so a waystone with one modifier was told it had no
	-- room. The panel has to say the pool is missing instead of inventing an affix count.
	H.eq("capture: the item is marked as having no modifier pool", waystone.poolMissing, true)
	H.eq("capture: so no affix rule is applied to it", advice.ruleId, nil)
	H.eq("capture: the unknown split is not claimed as complete", waystone.affixSplitComplete, false)
	local sawPoolNote = false
	for _, note in ipairs(advice.notes or { }) do
		if note.code == "pool_missing" then
			sawPoolNote = true
		end
	end
	H.eq("capture: and the panel is told why", sawPoolNote, true)

	-- The same for the other classes missing from the data, and a sanity check that ordinary gear is
	-- NOT marked this way - otherwise the fix would silently disable advice everywhere.
	local TABLET = table.concat({
		"Item Class: Tablets",
		"Rarity: Rare",
		"Breach Tablet",
		"--------",
		"Item Level: 80",
		"--------",
		"Breaches in Map contain an additional Rare Monster",
	}, "\n")
	local tablet = Parser.parse(TABLET)
	Mods.annotate(tablet)
	H.eq("capture: a tablet is also marked pool-less", tablet.poolMissing, true)
	local GEAR = table.concat({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		"+120 to maximum Life",
	}, "\n")
	local gear = Parser.parse(GEAR)
	Mods.annotate(gear)
	H.eq("capture: ordinary gear keeps its pool", gear.poolMissing, nil)

	-- A charm, from the customer's screenshot. Two things went wrong here at once. Its block mixed the
	-- charm's own actions ("Lasts 3 Seconds", "Recovers 297 Life when used") with a real modifier
	-- ("58% increased Charges"), and classifying the whole block on its first property-looking line
	-- filed everything as properties - the charm ended up with no modifiers at all. Then, with the
	-- split unknown, a slot rule was applied anyway and the panel advised a Regal Orb on an item whose
	-- free slots it could not see.
	local CHARM = table.concat({
		"Item Class: Charms",
		"Rarity: Magic",
		"Evergreen Dousing Charm of Plenty",
		"Dousing Charm",
		"--------",
		"Lasts 3 Seconds",
		"Consumes 30 of 63 Charges on use",
		"Currently has 63 Charges",
		"--------",
		"Grants immunity to Ignite",
		"--------",
		"Requirements: Level 60",
		"--------",
		"Item Level: 76",
		"--------",
		"Recovers 297 Life when used",
		"58% increased Charges",
	}, "\n")
	local charm = Parser.parse(CHARM)
	Mods.annotate(charm)
	-- The charm's own actions are properties, line by line, even though the block also holds a modifier.
	H.check("capture: the charm's actions are properties",
		charm.properties["Lasts 3 Seconds"] ~= nil
			and charm.properties["Recovers 297 Life when used"] ~= nil
			and charm.properties["Consumes 30 of 63 Charges on use"] ~= nil)
	H.eq("capture: the charm's real modifier is not swallowed as a property",
		charm.properties["58% increased Charges"], nil)
	H.eq("capture: and it is counted as a modifier line", #(charm.explicitMods or { }), 1)
	H.eq("capture: the charm's base is found", charm.baseType, "Dousing Charm")

	-- With one line unrecognised the split is unknown, so NO slot rule may be applied.
	local charmAdvice = Advisor.analyze(charm, league)
	H.eq("capture: no slot rule is applied to an unknown split", charmAdvice.ruleId, nil)
	local charmCodes = { }
	for _, note in ipairs(charmAdvice.notes or { }) do
		charmCodes[note.code] = true
	end
	H.eq("capture: and the panel explains why no step is offered",
		charmCodes.split_unknown_no_rule, true)
	local offeredRegal = false
	for _, plan in ipairs(charmAdvice.plans or { }) do
		for _, step in ipairs(plan.steps or { }) do
			if step.id == "regal" then
				offeredRegal = true
			end
		end
	end
	H.eq("capture: a rarity upgrade is not offered for a charm whose slots are unknown",
		offeredRegal, false)

	-- The customer's charm had two more things wrong on the card, both about claims made from text:
	-- the panel said the crafted slot was taken, and it said no affixes were free.
	local charmState = Coach.state(charm, CHARM)
	-- "(augmented)" marks a modifier whose VALUE was changed, not a crafted modifier. Reading it as one
	-- claimed a crafted slot the charm does not have.
	H.eq("capture: a value marker is not a crafted modifier", charmState.craftedAnchorUsed, false)
	-- The split is unknown, so the number of free slots is unknown too; modCount counts modifier LINES
	-- including the charm's own property lines, and using it here announced a full item.
	H.eq("capture: the slots are not claimed as known", charmState.slotsKnown, false)
	local charmReport = Coach.report(charm, charmAdvice, CHARM)
	local warningIds = { }
	for _, warning in ipairs(charmReport.warnings or { }) do
		warningIds[warning.id] = true
	end
	H.eq("capture: the charm is not told it has no free affixes", warningIds.no_room, nil)
	H.eq("capture: and it is not told the crafted slot is taken", warningIds.crafted_used, nil)
	-- The one step that does not depend on the slot count is the value reroll, so that is the step.
	H.eq("capture: an item with values but no known split is offered the value reroll",
		charmReport.step.currency, "Divine Orb")
end