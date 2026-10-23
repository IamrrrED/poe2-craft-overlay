-- The two gaps the poe2db cross-check turned up: Hinekora's Lock and waystones.
--
-- Both were listed on poe2db for 0.5.5 and both were absent from our ruleset, so the helper was silent about a
-- currency that lets you check a slam before paying, and about the one item type where Chaos IS a full reroll.
return function()
	local H = require("Tests.harness")
	local league = require("Data.league_0_5_5")
	local Lesson = require("Craft.Lesson")
	local Techniques = require("Craft.Techniques")
	local Claims = require("Craft.Claims")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")

	-- 1. Hinekora's Lock: a currency that previews the next one without applying it.
	local hinekora = (league.currencies or { }).hinekora
	H.check("poe2db: Hinekora's Lock is in the ruleset", hinekora ~= nil)
	if hinekora then
		H.eq("poe2db: it is named correctly", hinekora.en, "Hinekora's Lock")
		H.eq("poe2db: it is a preview, not a modifier", hinekora.preview, true)
		H.eq("poe2db: it adds nothing by itself", tonumber(hinekora.adds), 0)
		H.eq("poe2db: and removes nothing", tonumber(hinekora.removes), 0)
		H.check("poe2db: its text says it foresees the next currency",
			tostring(hinekora.effectEn):find("foresee", 1, true) ~= nil, tostring(hinekora.effectEn))
		-- The ability is lost on any other change, which is why it is used right before a spend.
		H.check("poe2db: and that modifying the item cancels it",
			tostring(hinekora.effectEn):find("removes the ability", 1, true) ~= nil)
	end

	-- It teaches something, so it needs a lesson, and that lesson must be reachable by the display name.
	local lesson = Lesson.forName("Hinekora's Lock")
	H.check("poe2db: the lock has a lesson", lesson ~= nil)
	if lesson then
		H.check("poe2db: which is about checking before paying",
			tostring(lesson.text):lower():find("не применяет", 1, true) ~= nil
				or tostring(lesson.title):lower():find("прежде чем", 1, true) ~= nil,
			tostring(lesson.title))
	end

	-- And a technique, offered only where a slam is actually possible.
	local TECHNIQUE_ITEM = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "T", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "A" (Tier: 1) }', "+35 to maximum Mana",
	}, "\n")
	local item = Parser.parse(TECHNIQUE_ITEM)
	Mods.annotate(item)
	local offered = false
	for _, technique in ipairs(Techniques.forItem(item)) do
		if technique.id == "preview_before_slam" then offered = true end
	end
	H.eq("poe2db: the lock technique is offered on a rare with room", offered, true)

	local FULL = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "T", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "A" (Tier: 1) }', "+35 to maximum Mana",
		'{ Prefix Modifier "B" (Tier: 1) }', "+20 to Strength",
		'{ Prefix Modifier "C" (Tier: 1) }', "+20 to Dexterity",
		'{ Suffix Modifier "D" (Tier: 1) }', "+40% to Fire Resistance",
		'{ Suffix Modifier "E" (Tier: 1) }', "+40% to Cold Resistance",
		'{ Suffix Modifier "F" (Tier: 1) }', "+40% to Lightning Resistance",
	}, "\n")
	local fullItem = Parser.parse(FULL)
	Mods.annotate(fullItem)
	local offeredOnFull = false
	for _, technique in ipairs(Techniques.forItem(fullItem)) do
		if technique.id == "preview_before_slam" then offeredOnFull = true end
	end
	H.eq("poe2db: and not on a full item, where nothing can be slammed", offeredOnFull, false)

	-- 2. Waystones: the one place Chaos rerolls the whole set.
	local waystones = league.waystones
	H.check("poe2db: the waystone block exists", type(waystones) == "table")
	H.eq("poe2db: chaos is the reroll currency", waystones.crafting.rerollCurrency, "chaos")
	H.eq("poe2db: and it replaces the whole set", waystones.crafting.replacesAll, true)
	H.check("poe2db: the mod pools are recorded", #(waystones.modPools or { }) >= 2,
		tostring(#(waystones.modPools or { })))
	-- The four steering omens, and that each names the family it forbids.
	H.eq("poe2db: four steering omens", #(waystones.steeringOmens or { }), 4)
	for _, omen in ipairs(waystones.steeringOmens or { }) do
		H.check("poe2db: a steering omen exists in the ruleset (" .. tostring(omen.omen) .. ")",
			(league.omens or { })[omen.omen] ~= nil, tostring(omen.omen))
		H.check("poe2db: and forbids a family (" .. tostring(omen.omen) .. ")",
			type(omen.excludes) == "string" and omen.excludes ~= "")
	end
	-- The resist penalty table is the game's own and must stay ordered.
	local tiers = waystones.tierResistPenalty or { }
	H.check("poe2db: the resist penalty table is present", #tiers >= 6, tostring(#tiers))
	for index = 2, #tiers do
		H.check("poe2db: the penalty table ascends in level",
			tiers[index].level > tiers[index - 1].level,
			tostring(tiers[index].level) .. " vs " .. tostring(tiers[index - 1].level))
	end

	-- And the claim that says it, because "no full reroll" is exactly the sort of rule a beginner over-learns.
	local claim = Claims.answer("На вейстоуне chaos перекатывает всё?")
	H.eq("poe2db: the waystone claim is recognised", claim.id, "waystone_chaos_rerolls_all")
	H.eq("poe2db: and marked true", claim.verdict, "true")
end
