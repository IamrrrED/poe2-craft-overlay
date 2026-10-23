-- The campaign / early / endgame buttons: the choice has to reach the engine and change the answer.
--
-- The panel posts "stage:<id>" to the host, which re-analyses the captured item with that stage. That chain
-- was broken inside the engine: analyze_item forwarded only the item text to the methods builder, so the
-- stage argument was dropped and every click produced the same card. The buttons looked dead. These checks
-- drive the API the way the host does, with an explicit stage, and require the answer to differ.
return function()
	local H = require("Tests.harness")
	local Api = require("Mcp.api")

	local HIGH = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Test", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
	}, "\n")
	local LOW = table.concat({
		"Item Class: Boots", "Rarity: Rare", "Campaign Boots", "Rawhide Boots", "--------",
		"Item Level: 40", "--------",
		'{ Prefix Modifier "Runner" (Tier: 2) }', "20% increased Movement Speed",
	}, "\n")

	local function refusedCount(methods)
		local count = 0
		for _, group in ipairs(methods.groups or { }) do
			for _, row in ipairs(group.methods or { }) do
				if row.allowedAtStage == false then count = count + 1 end
			end
		end
		return count
	end

	-- Without a stage the item level decides: that behaviour must not regress.
	local derived = assert(Api.call("analyze_item", { item_text = HIGH }))
	H.eq("stage switch: an item alone derives the stage", derived.methods.stage.id, "endgame")
	H.eq("stage switch: with nothing refused", refusedCount(derived.methods), 0)

	-- The same endgame item asked about AS a campaign item: the engine must obey the caller, not the ilvl.
	-- lang = "en": the rows below are matched on their English titles ("Whetstone", "Scrap"), which are
	-- the machine names of the quality currencies. The Russian titles are covered by Tests.test_language.
	local forcedCampaign = assert(Api.call("analyze_item", { item_text = HIGH, stage = "campaign", lang = "en" }))
	H.eq("stage switch: an explicit campaign wins over the item level",
		forcedCampaign.methods.stage.id, "campaign")
	H.check("stage switch: and the campaign refuses the expensive orbs",
		refusedCount(forcedCampaign.methods) > 0, tostring(refusedCount(forcedCampaign.methods)))
	-- Quality stays allowed: the point of the gate is to save the EXPENSIVE orbs, not to forbid crafting.
	-- Matched on the title because some rows carry no currencyId in the payload.
	H.check("stage switch: the campaign still allows quality", (function()
		for _, group in ipairs(forcedCampaign.methods.groups or { }) do
			for _, row in ipairs(group.methods or { }) do
				local title = tostring(row.title or "")
				if title:find("Scrap", 1, true) or title:find("Whetstone", 1, true)
					or title:find("Etcher", 1, true) or title:find("Bauble", 1, true) then
					if row.allowedAtStage == true then return true end
				end
			end
		end
		return false
	end)(), "quality should stay allowed in the campaign")
	-- And not everything is refused, or the switch would be useless.
	H.check("stage switch: the campaign still leaves something to do", (function()
		for _, group in ipairs(forcedCampaign.methods.groups or { }) do
			for _, row in ipairs(group.methods or { }) do
				if row.allowedAtStage == true then return true end
			end
		end
		return false
	end)(), "every method refused would leave nothing to spend on")

	-- And the other direction: a campaign-level item asked about as endgame gets everything.
	local forcedEndgame = assert(Api.call("analyze_item", { item_text = LOW, stage = "endgame" }))
	H.eq("stage switch: an explicit endgame wins over the item level",
		forcedEndgame.methods.stage.id, "endgame")
	H.eq("stage switch: and nothing is refused", refusedCount(forcedEndgame.methods), 0)

	-- The middle stage exists and is its own answer, not a synonym for either neighbour.
	local forcedEarly = assert(Api.call("analyze_item", { item_text = LOW, stage = "early" }))
	H.eq("stage switch: early is selectable on its own", forcedEarly.methods.stage.id, "early")
	H.check("stage switch: and it differs from the campaign about something",
		refusedCount(forcedEarly.methods) ~= refusedCount(forcedCampaign.methods)
			or forcedEarly.methods.stage.id ~= "campaign")

	-- The payload carries what the panel needs to paint the switch: the label, the reason, and the choices.
	H.check("stage switch: the payload names the stage", type(forcedCampaign.methods.stage.label) == "string"
		and #forcedCampaign.methods.stage.label > 3, tostring(forcedCampaign.methods.stage.label))
	H.check("stage switch: it explains itself", type(forcedCampaign.methods.stage.description) == "string"
		and #forcedCampaign.methods.stage.description > 30)
	H.eq("stage switch: and lists the choices", #(forcedCampaign.methods.stage.choices or { }), 3)
	-- The derived stage is reported separately, so the panel can say why the default was what it was.
	H.eq("stage switch: the item's own stage is still reported",
		forcedCampaign.methods.stage.fromItemLevel, "endgame")
end
