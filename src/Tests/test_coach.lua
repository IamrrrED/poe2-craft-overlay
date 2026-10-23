-- The coach decides what the beginner does next, so it is worth testing like any other logic:
-- a wrong step costs real currency.
return function()
	local H = require("Tests.harness")
	local Coach = require("Craft.Coach")
	local Parser = require("Item.Parser")

	local CORRUPTED = table.concat({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		"+118 to maximum Life",
		"--------",
		"Corrupted",
	}, "\n")

	-- The Russian client writes the state line in its own words, and a state line that is not
	-- recognised is not cosmetic: the item then looks modifiable and the panel advises currency that
	-- the game will refuse. A sanctified item is the dangerous case - the Omen of Sanctification
	-- randomises and multiplies the values once, and after that most methods of crafting refuse it.
	local SANCTIFIED_RU = table.concat({
		"Класс предмета: Скипетры",
		"Редкость: Редкий",
		"Разрушительное проклятие",
		"Гремящий скипетр",
		"--------",
		"Качество: +20%",
		"--------",
		"Уровень предмета: 80",
		"--------",
		'{ Префикс "Изобилующий" (Уровень: 5) }',
		"43% увеличение духа",
		'{ Суффикс "хирурга" (Уровень: 1) }',
		"+190 к максимуму маны",
		"--------",
		"Освящено",
	}, "\n")
	local sanctified = Parser.parse(SANCTIFIED_RU)
	H.eq("coach: a Russian sanctified item is recognised", sanctified.flags.sanctified, true)
	H.eq("coach: and is not modifiable", sanctified.isModifiable, false)
	local sanctifiedAdvice = require("Craft.Advisor").analyze(sanctified, require("Data.league_0_5_5"))
	H.eq("coach: the locked rule is chosen for it", sanctifiedAdvice.ruleId, "locked")
	local sanctifiedReport = Coach.report(sanctified, sanctifiedAdvice, SANCTIFIED_RU)
	H.eq("coach: no currency is offered for it", sanctifiedReport.step.currency, nil)
	H.eq("coach: and the card says the craft is over",
		sanctifiedReport.step.title:find("заверш", 1, true) ~= nil, true)
	H.eq("coach: the card says modifiers cannot be changed", sanctifiedReport.state.modifiable, false)

	local OPEN = table.concat({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		"+118 to maximum Life",
	}, "\n")

	local LOW = table.concat({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Low Thing",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 20",
		"--------",
		"+11 to maximum Life",
	}, "\n")

	local state = Coach.state(Parser.parse(CORRUPTED), CORRUPTED)
	H.eq("coach: corruption is read from the text", state.corrupted, true)
	H.eq("coach: item level is read", state.itemLevel, 82)
	local report = Coach.report(Parser.parse(CORRUPTED), { }, CORRUPTED)
	H.eq("coach: a corrupted item has no next step", report.step.currency, nil)
	H.eq("coach: and says the craft is over", report.step.title:find("заверш", 1, true) ~= nil, true)
	local hasCorruptionWarning = false
	for _, warning in ipairs(report.warnings) do
		if warning.id == "corrupted" then hasCorruptionWarning = true end
	end
	H.eq("coach: corruption is warned about", hasCorruptionWarning, true)

	local lowReport = Coach.report(Parser.parse(LOW), { }, LOW)
	local lowWarned = false
	for _, warning in ipairs(lowReport.warnings) do
		if warning.id == "low_ilvl" then lowWarned = true end
	end
	H.eq("coach: a low item level is warned about", lowWarned, true)

	-- A plan-driven step must carry both outcome branches: the next move depends on what rolled.
	local advice = {
		plans = {
			{ id = "anchors", reason = "Поставьте якорь эссенцией.", steps = {
				{ en = "Essence of the Body", count = 1, effect = "Adds maximum life" },
				{ en = "Exalted Orb", count = 2, effect = "Fills the open affixes" },
			} },
		},
	}
	local planned = Coach.report(Parser.parse(OPEN), advice, OPEN)
	H.eq("coach: the plan supplies the step", planned.step.currency, "Essence of the Body")
	H.eq("coach: the step explains why", #tostring(planned.step.why) > 5, true)
	H.eq("coach: the success branch is present", type(planned.step.ifSuccess), "string")
	H.eq("coach: the success branch names the next currency", planned.step.ifSuccess:find("Exalted Orb", 1, true) ~= nil, true)
	H.eq("coach: the failure branch is present", type(planned.step.ifFail), "string")
	H.eq("coach: the loop reminder is present", planned.step.after:find("Ctrl+Q", 1, true) ~= nil, true)
	H.eq("coach: open slots are counted", planned.state.openSlots >= 1, true)

	-- A full rare whose modifiers did NOT all classify. This mirrors a real capture (a body armour
	-- whose "+270 to Stun Threshold" line the matcher does not know): before the fix the advisor
	-- reasoned from three recognised prefixes and offered an Exalted Orb for an item with no room at
	-- all, and the panel showed that step. A rule that needs the affix count must stay out of the way
	-- when the count is unknown, so the item falls through to the full-item rule, which swaps a
	-- modifier instead of adding one.
	local Advisor = require("Craft.Advisor")
	local league = require("Data.league_0_5_5")
	local FULL_UNKNOWN = table.concat({
		"Item Class: Body Armours",
		"Rarity: Rare",
		"Chimeric Reflection",
		"Vile Robe",
		"--------",
		"Item Level: 80",
		"--------",
		'{ Prefix Modifier "Steadfast" (Tier: 1) - Energy Shield }',
		"104(101-110)% increased Energy Shield",
		'{ Prefix Modifier "Pontiffs" (Tier: 2) - Energy Shield }',
		"+23(21-25) to maximum Energy Shield",
		"34(33-38)% increased Energy Shield",
		'{ Desecrated Prefix Modifier "Marquess" (Tier: 5) }',
		"+44(43-46) to Spirit",
		'{ Suffix Modifier "of the Obsidian Hide" (Tier: 1) }',
		"+270(254-304) to Stun Threshold",
		'{ Suffix Modifier "of Ice" (Tier: 2) - Elemental, Cold, Resistance }',
		"+36(36-40)% to Cold Resistance",
		'{ Crafted Suffix Modifier "of the Essence" }',
		"49(40-50)% reduced Extra Damage from Critical Hits",
	}, "\n")

	local fullItem = Parser.parse(FULL_UNKNOWN)
	local fullAdvice = Advisor.analyze(fullItem, league)
	-- The game's own annotations name each modifier's side, so this item is classified even though
	-- the dictionary does not know every line: three prefixes, three suffixes, no room left.
	H.eq("coach: the sides come from the game's own annotations", fullItem.prefixCount, 3)
	H.eq("coach: and for the suffixes too", fullItem.suffixCount, 3)
	H.eq("coach: so the split is known", fullItem.affixSplitComplete, true)
	H.eq("coach: the full-item rule is chosen", fullAdvice.ruleId, "rare_full")
	H.eq("coach: the plan swaps a modifier instead of adding one",
		(fullAdvice.plans[1].steps[1] or { }).en ~= "Exalted Orb", true)
	local fullReport = Coach.report(fullItem, fullAdvice, FULL_UNKNOWN)
	H.eq("coach: no Exalted Orb is offered for a full item", fullReport.step.currency ~= "Exalted Orb", true)
	H.eq("coach: and the card says there is no room", fullReport.state.openSlots, 0)

	-- The other half of the same bug: an item with free slots must keep offering "add a modifier".
	-- When a line went unread the split was declared unknown and the advisor switched to removal
	-- advice on an item that still had room.
	local OPEN_RARE = table.concat({
		"Item Class: Helmets",
		"Rarity: Rare",
		"Chimeric Visage",
		"Vile Mask",
		"--------",
		"Item Level: 80",
		"--------",
		'{ Prefix Modifier "Steadfast" (Tier: 1) - Energy Shield }',
		"104(101-110)% increased Energy Shield",
		'{ Suffix Modifier "of Ice" (Tier: 2) - Elemental, Cold, Resistance }',
		"+36(36-40)% to Cold Resistance",
		'{ Suffix Modifier "of the Essence" (Tier: 1) }',
		"49(40-50)% reduced Extra Damage from Critical Hits",
	}, "\n")
	local openItem = Parser.parse(OPEN_RARE)
	local openAdvice = Advisor.analyze(openItem, league)
	H.eq("coach: a half-filled item is recognised as open", openItem.prefixCount, 1)
	H.eq("coach: with two suffixes taken", openItem.suffixCount, 2)
	H.eq("coach: the open-affix rule is chosen", openAdvice.ruleId, "rare_open_affix")
	-- The plan begins with the quality step now (it is put inside the plan so the index-based coach can
	-- see it), so the rule's own step is found by id rather than by position.
	local function stepById(advice, id)
		for _, step in ipairs((advice.plans[1] or { }).steps or { }) do
			if step.id == id then
				return step
			end
		end
		return nil
	end
	H.eq("coach: the step adds a modifier", (stepById(openAdvice, "exalted") or { }).en, "Exalted Orb")
	-- Quality closes the craft out before the irreversible step, by the customer's rule: modifiers first,
	-- then quality, then Vaal. Leading with quality offered a Scrap while a slot was still open.
	H.eq("coach: the modifier step comes first",
		(openAdvice.plans[1].steps[1] or { }).id, "exalted")
	-- The minimal plan closes with quality; Vaal is the MAX plan's last step, because a one-way step is not
	-- the follow-up to a single move.
	local openSteps = openAdvice.plans[1].steps
	H.eq("coach: and quality closes the minimal plan", (openSteps[#openSteps] or { }).id, "scrap")
	local openMax = openAdvice.plans[2].steps
	H.eq("coach: Vaal is the last step of the maximum plan", (openMax[#openMax] or { }).id, "vaal")
	-- Quality comes AFTER the value reroll, by the customer's rule: it multiplies the item's numbers, so it
	-- is worth most once those numbers are final.
	H.eq("coach: with the value reroll before quality", (openMax[#openMax - 2] or { }).id, "divine")
	H.eq("coach: and quality right after it", (openMax[#openMax - 1] or { }).id, "scrap")
	local minimalVaal = false
	for _, step in ipairs(openSteps) do
		if step.id == "vaal" then minimalVaal = true end
	end
	H.eq("coach: the minimal plan never offers Vaal", minimalVaal, false)

	-- The Russian socket label has to be translated. When it is missed the socket line is read as a
	-- modifier, which makes the split look incomplete and silently switches off slot advice.
	local Ru = require("Item.Ru")
	local RU_HELMET = table.concat({
		"Класс предмета: Шлемы",
		"Редкость: Редкий",
		"Символический бастион",
		"Чародейская тиара",
		"--------",
		"Качество: +20% (augmented)",
		"--------",
		"Гнезда: S S ",
		"--------",
		"Уровень предмета: 80",
		"--------",
		'{ Префикс "Непоколебимое" (Уровень: 1) — Энергетический щит }',
		"125(101-110)% увеличение энергетического щита",
		'{ Суффикс "льда" (Уровень: 2) — Стихийный, Холод, Сопротивление }',
		"+18(36-40)% к сопротивлению хаосу",
	}, "\n")
	local translated = Ru.toEnglish(RU_HELMET) or RU_HELMET
	H.eq("coach: the Russian socket label is translated",
		translated:find("Sockets:", 1, true) ~= nil, true)
	local ruItem = Parser.parse(translated)
	H.eq("coach: the sockets are read, not counted as a modifier", #(ruItem.sockets or { }), 2)
	local ruAdvice = Advisor.analyze(ruItem, league)
	H.eq("coach: the Russian item keeps its split", ruItem.affixSplitComplete, true)
	H.eq("coach: and still has room, so the step adds a modifier",
		(stepById(ruAdvice, "exalted") or { }).en, "Exalted Orb")

	-- Quality is a separate number, not an affix slot, and it scales the item's own base stats. A
	-- Magic flask whose two affixes are both taken and which has no quality at all must be offered
	-- quality FIRST - the customer's case: the panel went straight to a rarity upgrade instead.
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
	local flaskItem = Parser.parse(MAGIC_FLASK)
	local flaskAdvice = Advisor.analyze(flaskItem, league)
	H.eq("coach: a flask with no quality gets a quality step",
		(flaskAdvice.qualityStep or { }).en, "Glassblower's Bauble")
	local flaskReport = Coach.report(flaskItem, flaskAdvice, MAGIC_FLASK)
	-- A full Magic item is upgraded, not polished: Regal adds a third modifier while the Bauble only
	-- raises quality on a two-mod item that still has room to become Rare. Quality is inserted AFTER
	-- the step that changes the modifier set, which is the order the whole advisor uses.
	H.eq("coach: the card offers the rarity upgrade first, not quality",
		flaskReport.step.currency, "Regal Orb")
	H.eq("coach: the title says the rarity upgrade",
		flaskReport.step.title:find("Regal", 1, true) ~= nil, true)

	-- Each class has its own quality currency, and an item already at 20% gets no such step.
	local ARMOUR = table.concat({
		"Item Class: Body Armours",
		"Rarity: Rare",
		"Chimeric Reflection",
		"Vile Robe",
		"--------",
		"Quality: +20% (augmented)",
		"Energy Shield: 601 (augmented)",
		"--------",
		"Item Level: 80",
		"--------",
		'{ Prefix Modifier "Steadfast" (Tier: 1) - Energy Shield }',
		"104(101-110)% increased Energy Shield",
	}, "\n")
	local armourItem = Parser.parse(ARMOUR)
	H.eq("coach: quality is read from the item", armourItem.quality, 20)
	H.eq("coach: an item at full quality is offered the value reroll instead",
		(Advisor.analyze(armourItem, league).qualityStep or { }).en, "Divine Orb")

	local NO_QUALITY_ARMOUR = (ARMOUR:gsub("Quality: %+20%% %(augmented%)\n", ""))
	local scrapItem = Parser.parse(NO_QUALITY_ARMOUR)
	H.eq("coach: armour without quality asks for scrap",
		(Advisor.analyze(scrapItem, league).qualityStep or { }).en, "Armourer's Scrap")

	-- Rings, amulets and jewels are the exception: they take a catalyst, and a catalyst covers one
	-- modifier tag only. When one of the modifiers on the item clearly matches a catalyst's tag the
	-- step names it; when nothing matches it says only that a catalyst is needed, rather than naming
	-- the wrong one and sending the player to raise quality on a modifier they do not want.
	local RING = table.concat({
		"Item Class: Rings",
		"Rarity: Rare",
		"Doom Loop",
		"Gold Ring",
		"--------",
		"Requirements: Level 48",
		"--------",
		"Item Level: 78",
		"--------",
		'{ Prefix Modifier "Merciless" (Tier: 3) }',
		"Adds 12 to 21 Physical Damage to Attacks",
		'{ Suffix Modifier "of the Prism" (Tier: 2) }',
		"+28% to Fire Resistance",
	}, "\n")
	local ringStep = (Advisor.analyze(Parser.parse(RING), league).qualityStep or { })
	H.check("coach: a ring is offered a catalyst, not a class currency",
		ringStep.en ~= nil and ringStep.en:find("Catalyst", 1, true) ~= nil, tostring(ringStep.en))
	-- The ring matches several tags at once, and the step has to list them all rather than pick one:
	-- a catalyst covers a single tag, so naming only one would send the player at the wrong modifier.
	H.check("coach: every matching catalyst is offered", #(ringStep.catalysts or { }) >= 2,
		tostring(#(ringStep.catalysts or { })))
	local listed = table.concat(ringStep.catalysts or { }, ", ")
	H.check("coach: the physical catalyst is among them", listed:find("Carapace", 1, true) ~= nil, listed)
	H.check("coach: the fire catalyst is among them", listed:find("Xoph", 1, true) ~= nil, listed)

	local ODD_RING = table.concat({
		"Item Class: Rings",
		"Rarity: Rare",
		"Doom Loop",
		"Gold Ring",
		"--------",
		"Item Level: 78",
		"--------",
		'{ Suffix Modifier "of the Whelpling" (Tier: 2) }',
		"Grants Level 12 Haste Skill",
	}, "\n")
	local oddStep = (Advisor.analyze(Parser.parse(ODD_RING), league).qualityStep or { })
	H.eq("coach: with no match the step stays generic, it does not guess",
		oddStep.en, "Quality currency")
	H.eq("coach: and lists no catalysts", #(oddStep.catalysts or { }), 0)

	-- A jewel takes the Refined catalysts, so the plain ones must not be offered for it.
	local JEWEL = table.concat({
		"Item Class: Jewels",
		"Rarity: Rare",
		"Entropy Shard",
		"Ruby",
		"--------",
		"Item Level: 80",
		"--------",
		"Adds 14 to 22 Fire Damage to Attacks",
	}, "\n")
	local jewelStep = (Advisor.analyze(Parser.parse(JEWEL), league).qualityStep or { })
	H.check("coach: a jewel gets a Refined catalyst",
		jewelStep.en ~= nil and jewelStep.en:find("Refined", 1, true) ~= nil, tostring(jewelStep.en))

	-- Quality at the cap: the only thing left that improves what the item already has is a Divine Orb,
	-- which rerolls the values without touching the modifier set. This is the flask the customer
	-- showed - +20% quality, both mods in place - and the panel used to offer a rarity upgrade.
	local QUALITY_FLASK = table.concat({
		"Item Class: Life Flasks",
		"Rarity: Magic",
		"Seething Perfect Mana Flask of the Surgeon",
		"--------",
		"Quality: +20% (augmented)",
		"Recovers 372 Mana over 3 Seconds",
		"Consumes 10 of 75 Charges on use",
		"Currently has 75 Charges",
		"--------",
		"Requirements: Level 60",
		"--------",
		"Item Level: 65",
		"--------",
		'{ Prefix Modifier "Seething" (Tier: 3) }',
		"30% of Recovery applied Instantly",
		'{ Suffix Modifier "of the Surgeon" (Tier: 1) }',
		"35(31-35)% Chance to gain a Charge when you Kill an Enemy",
	}, "\n")
	local qualityFlask = Parser.parse(QUALITY_FLASK)
	H.eq("coach: the flask's quality is read", qualityFlask.quality, 20)
	local qualityAdvice = Advisor.analyze(qualityFlask, league)
	H.eq("coach: at full quality the step is a Divine Orb",
		(qualityAdvice.qualityStep or { }).en, "Divine Orb")
	local qualityReport = Coach.report(qualityFlask, qualityAdvice, QUALITY_FLASK)
	-- Even at the quality cap, the rarity upgrade comes first: it ADDS a modifier, while Divine only
	-- rerolls the numbers of the two that are there. Rerolling before the set is final wastes the orb.
	H.eq("coach: the rarity upgrade is offered before the value reroll",
		qualityReport.step.currency, "Regal Orb")

	-- A full Magic item is NOT finished. This test used to assert the opposite - that no rarity upgrade
	-- can add anything - which contradicted our own currency table (regal.adds = 1), the poe2db type
	-- name CurrencyUpgradeMagicToRare, and the 0.4 walkthrough that does Transmutation -> Augmentation
	-- -> Regal on a two-mod item. The cap rises with the rarity, so Regal always has room on Magic.
	local FULL_MAGIC = table.concat({
		"Item Class: Life Flasks",
		"Rarity: Magic",
		"Abundant Transcendent Life Flask of the Surgeon",
		"--------",
		"Recovers 1327 Life over 4 Seconds",
		"Consumes 10 of 75 Charges on use",
		"--------",
		"Requirements: Level 50",
		"--------",
		"Item Level: 54",
		"--------",
		'{ Prefix Modifier "Abundant" (Tier: 5) }',
		"58% increased Recovery Amount",
		'{ Suffix Modifier "of the Surgeon" (Tier: 1) }',
		"31% Chance to gain a Charge when you Kill an Enemy",
	}, "\n")
	local fullMagic = Parser.parse(FULL_MAGIC)
	local fullAdvice = Advisor.analyze(fullMagic, league)
	H.eq("coach: a full Magic item gets its own rule", fullAdvice.ruleId, "magic_full")
	H.check("coach: and the panel says why nothing can be added", fullAdvice.blockerEn ~= nil)
	local offeredRegal = false
	for _, plan in ipairs(fullAdvice.plans) do
		for _, step in ipairs(plan.steps or { }) do
			if step.id == "regal" then
				offeredRegal = true
			end
		end
	end
	H.eq("coach: a rarity upgrade IS offered for a full Magic item", offeredRegal, true)
	-- Regal is the first step of the plan, and the index-based coach shows it first.
	H.eq("coach: the first step of the plan is the rarity upgrade",
		(fullAdvice.plans[1].steps[1] or { }).id, "regal")
	H.eq("coach: and the card offers it", Coach.report(fullMagic, fullAdvice, FULL_MAGIC).step.currency,
		"Regal Orb")

	-- The same flask when the engine cannot resolve a modifier line. The split is then unknown, so no
	-- slot rule may be applied - but quality does not depend on the slot count, and the customer's flask
	-- with no quality was told to spend a Divine Orb instead of a Bauble. A Divine cannot raise quality.
	local UNRESOLVED = table.concat({
		"Item Class: Life Flasks",
		"Rarity: Magic",
		"Abundant Transcendent Life Flask of the Surgeon",
		"Transcendent Life Flask",
		"--------",
		"Recovers 1327 Life over 4 Seconds",
		"Consumes 10 of 75 Charges on use",
		"Currently has 75 Charges",
		"--------",
		"Requirements: Level 50",
		"--------",
		"Item Level: 54",
		"--------",
		"58% increased Recovery Amount",
		"31% Chance to gain a Charge when you Kill an Enemy",
	}, "\n")
	local unresolvedItem = Parser.parse(UNRESOLVED)
	local unresolvedAdvice = Advisor.analyze(unresolvedItem, league)
	H.eq("coach: an unresolved modifier leaves the split unknown",
		unresolvedItem.affixSplitComplete, false)
	H.eq("coach: and no rule is applied", unresolvedAdvice.ruleId, nil)
	H.eq("coach: but quality is still the step, not a value reroll",
		(unresolvedAdvice.qualityStep or { }).en, "Glassblower's Bauble")
	H.eq("coach: and the card offers the Bauble",
		Coach.report(unresolvedItem, unresolvedAdvice, UNRESOLVED).step.currency, "Glassblower's Bauble")

	-- With the quality already at the cap and the split unknown there is nothing to raise, so the value
	-- reroll is the honest answer.
	local CAPPED_UNRESOLVED = (UNRESOLVED:gsub("Recovers 1327 Life over 4 Seconds",
		"Quality: +20% (augmented)\nRecovers 1372 Life over 4 Seconds"))
	local cappedUnresolved = Parser.parse(CAPPED_UNRESOLVED)
	local cappedUnresolvedAdvice = Advisor.analyze(cappedUnresolved, league)
	H.eq("coach: at the cap with an unknown split the step is the value reroll",
		Coach.report(cappedUnresolved, cappedUnresolvedAdvice, CAPPED_UNRESOLVED).step.currency, "Divine Orb")

	-- At the quality cap the step is the value reroll. Coach.step is used with an explicit memory rather
	-- than Coach.report: report WRITES the shared memory file, so two similar fixtures in one file
	-- inherit each other's remembered step and the second answer depends on the first test.
	local CAPPED = (FULL_MAGIC:gsub("Recovers 1327 Life over 4 Seconds",
		"Quality: +20% (augmented)\nRecovers 1372 Life over 4 Seconds"))
	local cappedItem = Parser.parse(CAPPED)
	local cappedAdvice = Advisor.analyze(cappedItem, league)
	H.eq("coach: the capped flask keeps the full-Magic rule", cappedAdvice.ruleId, "magic_full")
	local cappedState = Coach.state(cappedItem, CAPPED)
	local cappedStep = Coach.step(cappedItem, cappedAdvice, cappedState, nil)
	-- The rarity upgrade still comes first at the quality cap: it ADDS a modifier, while the value reroll
	-- only changes the numbers of the two the flask already carries.
	H.eq("coach: at the cap the step is still the rarity upgrade",
		cappedStep and cappedStep.currency, "Regal Orb")
	-- The step loop: once the rarity upgrade is applied the item is Rare, so the next look moves on
	-- instead of offering the same orb again.
	local afterQuality = Coach.step(cappedItem, cappedAdvice, cappedState, {
		sameItem = true,
		previousStepIndex = 1,
		verdict = "progress",
	})
	H.eq("coach: after the quality step comes the value reroll",
		afterQuality and afterQuality.currency, "Divine Orb")
	-- Stepping PAST the end of the plan must not repeat the last step. On this item that means the value
	-- reroll, which is the step that still works when nothing else does - not the last step of the plan
	-- over and over, which is what produced an endless Divine loop for the customer.
	local far = Coach.state(cappedItem, CAPPED)
	local pastEnd = Coach.step(cappedItem, cappedAdvice, far, {
		sameItem = true,
		previousStepIndex = 9,
		verdict = "progress",
	})
	H.check("coach: stepping past the plan does not repeat the last step",
		pastEnd ~= nil and pastEnd.currency == "Divine Orb", tostring(pastEnd and pastEnd.currency))

	-- Instilling is Delirium, not flask work and not desecration: three Liquid Emotions in a fixed
	-- order grant an amulet one notable passive, and the same emotions in another order can be a
	-- different notable. It has to be offered on amulets and Waystones only, and it must say that an
	-- already instilled item would be overwritten rather than silently re-instilled.
	local AMULET = table.concat({
		"Item Class: Amulets",
		"Rarity: Rare",
		"Rapture Beads",
		"Stellar Amulet",
		"--------",
		"Requirements: Level 52",
		"--------",
		"Item Level: 79",
		"--------",
		'{ Prefix Modifier "Substantial" (Tier: 2) }',
		"+38 to maximum Life",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }',
		"+45% to all Elemental Resistances",
	}, "\n")
	local function instilOption(itemText)
		local report = Advisor.analyze(Parser.parse(itemText), league)
		for _, entry in ipairs(report.omenOptions or { }) do
			if entry.kind == "instil" then
				return entry
			end
		end
		return nil
	end
	local amuletOption = instilOption(AMULET)
	H.check("coach: an amulet is offered instilling", amuletOption ~= nil)
	H.eq("coach: instilling on an amulet is about the notable", amuletOption.slot, "amulet")
	H.eq("coach: the option knows the emotion catalogue size", amuletOption.emotions, 26)
	H.contains("coach: and says a fixed order is needed", amuletOption.why, "fixed order")
	H.contains("coach: and says where it is done", amuletOption.why, "instilling station")

	local INSTILLED = (AMULET:gsub("Item Level: 79", "Item Level: 79\n--------\nInstilled"))
	local instilledOption = instilOption(INSTILLED)
	H.check("coach: an already instilled amulet is still offered the step", instilledOption ~= nil)
	H.eq("coach: but the step says it would be replaced", instilledOption.alreadyInstilled, true)

	-- Instruments of another slot must not get it: Liquid Emotions do not instil gloves.
	local GLOVES = table.concat({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		"+120 to maximum Life",
	}, "\n")
	H.eq("coach: gloves are never offered instilling", instilOption(GLOVES), nil)

	-- The reforge ladder decides what an emotion is worth: three of one emotion become one of the next
	-- rung up, so the order is data worth checking. The ten-rung ladder does not include the Potent set,
	-- which is a separate (rarer) family for the strongest anoints, or the Ancient set.
	local ladder = { }
	local potent, ancient = 0, 0
	for _, emotion in ipairs(league.liquidEmotions or { }) do
		if emotion.tier == "ancient" then
			ancient = ancient + 1
		elseif emotion.tier == "potent" then
			potent = potent + 1
		else
			ladder[emotion.ladder] = emotion.en
		end
	end
	H.eq("coach: the emotion ladder has ten rungs", (function()
		local count = 0
		for _ in pairs(ladder) do count = count + 1 end
		return count
	end)(), 10)
	H.eq("coach: the ladder starts at Diluted Ire", ladder[1], "Diluted Liquid Ire")
	H.eq("coach: and ends at Concentrated Suffering", ladder[10], "Concentrated Liquid Suffering")
	H.eq("coach: no rung is empty", (function()
		for rung = 1, 10 do
			if not ladder[rung] then return false end
		end
		return true
	end)(), true)
	H.eq("coach: three Potent emotions sit outside the ladder", potent, 3)
	H.eq("coach: and so do thirteen Ancient ones", ancient, 13)
	H.eq("coach: the whole catalogue is 26 emotions", #(league.liquidEmotions or { }), 26)
end