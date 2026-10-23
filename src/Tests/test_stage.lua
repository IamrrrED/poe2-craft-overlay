-- The stage gate: what a beginner is told to spend, and what he is told to save.
--
-- Every guide analysed in docs/mentor-research.md says the same thing: campaign gear gets Transmute,
-- Augment and Regal, and Exalted/Chaos/Divine/Vaal wait. The overlay used to offer whatever was possible,
-- so a low-level player was advised to spend an Exalted Orb on boots he would replace in two acts.
return function()
	local H = require("Tests.harness")
	local Stage = require("Craft.Stage")
	local Api = require("Mcp.api")

	-- The stage comes from the item, which is the only thing the engine can prove.
	H.eq("stage: a low item level is the campaign", Stage.forItemLevel(20), "campaign")
	H.eq("stage: item level 49 is still the campaign", Stage.forItemLevel(49), "campaign")
	H.eq("stage: item level 50 is early endgame", Stage.forItemLevel(50), "early")
	H.eq("stage: item level 74 is still early", Stage.forItemLevel(74), "early")
	H.eq("stage: item level 75 is endgame", Stage.forItemLevel(75), "endgame")
	H.eq("stage: an unknown level never restricts", Stage.forItemLevel(nil), "endgame")

	-- What each stage may spend.
	H.eq("stage: the campaign may transmute", Stage.allows("campaign", "transmutation"), true)
	H.eq("stage: the campaign may augment", Stage.allows("campaign", "augmentation"), true)
	H.eq("stage: the campaign may regal", Stage.allows("campaign", "regal"), true)
	H.eq("stage: the campaign may use an essence", Stage.allows("campaign", "essence"), true)
	H.eq("stage: the campaign may use a rune", Stage.allows("campaign", "rune"), true)
	H.eq("stage: the campaign may raise quality", Stage.allows("campaign", "scrap"), true)
	-- The expensive ones are the point of the whole rule.
	H.eq("stage: the campaign saves its exalted orbs", Stage.allows("campaign", "exalted"), false)
	H.eq("stage: the campaign saves its chaos orbs", Stage.allows("campaign", "chaos"), false)
	H.eq("stage: the campaign saves its divine orbs", Stage.allows("campaign", "divine"), false)
	H.eq("stage: the campaign saves its vaal orbs", Stage.allows("campaign", "vaal"), false)
	H.eq("stage: the campaign saves its annulments", Stage.allows("campaign", "annulment"), false)
	-- Early endgame opens the additive work but not the irreversible one.
	H.eq("stage: early endgame may exalt", Stage.allows("early", "exalted"), true)
	H.eq("stage: early endgame may chaos a bad mod", Stage.allows("early", "chaos"), true)
	H.eq("stage: early endgame still saves its vaal orbs", Stage.allows("early", "vaal"), false)
	H.eq("stage: early endgame still saves its divine orbs", Stage.allows("early", "divine"), false)
	-- Endgame allows everything.
	H.eq("stage: endgame may vaal", Stage.allows("endgame", "vaal"), true)
	H.eq("stage: endgame may divine", Stage.allows("endgame", "divine"), true)

	-- A refused method says WHY, and points at the stage rather than at a rule id.
	local allowed, reason = Stage.allows("campaign", "exalted")
	H.eq("stage: a refusal is a boolean", type(allowed), "boolean")
	H.check("stage: the refusal is explained in words", type(reason) == "string" and #reason > 20,
		tostring(reason))

	-- A low-level capture must carry the gate, and an endgame one must not restrict anything.
	local LOW = table.concat({
		"Item Class: Boots", "Rarity: Rare", "Campaign Boots", "Rawhide Boots", "--------",
		"Item Level: 40", "--------",
		'{ Prefix Modifier "Runner" (Tier: 2) }', "20% increased Movement Speed",
	}, "\n")
	local low = assert(Api.call("methods", { item_text = LOW }))
	H.eq("stage: a level-40 capture is the campaign", low.stage.id, "campaign")
	H.eq("stage: and its item level is the reason", low.stage.fromItemLevel, "campaign")
	H.check("stage: the stage explains itself", type(low.stage.description) == "string"
		and #low.stage.description > 20, tostring(low.stage.description))
	local lowExalted, lowRegal = nil, nil
	for _, group in ipairs(low.groups or { }) do
		for _, row in ipairs(group.methods or { }) do
			if row.currencyId == "exalted" then lowExalted = row end
			if row.currencyId == "scrap" then lowRegal = row end
		end
	end
	H.check("stage: the exalted method is present but refused",
		lowExalted ~= nil and lowExalted.allowedAtStage == false)
	H.check("stage: with the reason attached",
		lowExalted and type(lowExalted.stageNote) == "string" and #lowExalted.stageNote > 20,
		tostring(lowExalted and lowExalted.stageNote))
	H.check("stage: while quality stays allowed",
		lowRegal == nil or lowRegal.allowedAtStage == true)

	local HIGH = (LOW:gsub("Item Level: 40", "Item Level: 80"))
	local high = assert(Api.call("methods", { item_text = HIGH }))
	H.eq("stage: a level-80 capture is endgame", high.stage.id, "endgame")
	for _, group in ipairs(high.groups or { }) do
		for _, row in ipairs(group.methods or { }) do
			H.eq("stage: nothing is refused at endgame (" .. tostring(row.title) .. ")",
				row.allowedAtStage, true)
		end
	end
end
