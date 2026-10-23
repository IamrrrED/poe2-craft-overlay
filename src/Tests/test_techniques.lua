-- Advanced techniques: sequences an experienced crafter knows, offered only when their state applies.
--
-- Taken from reading the actual guides (docs/mentor-research.md): Fubgun's 221k-view jewel video shows the
-- "third suffix" trick - a jewel holds two suffixes, so a third pushes the side over cap and a Chaos Orb can
-- only ever hit the prefix, making the suffix side unbrickable. No rule in the table derives that from the
-- data; it has to be curated, and it has to be offered only when it is true of the item.
return function()
	local H = require("Tests.harness")
	local Techniques = require("Craft.Techniques")
	local Api = require("Mcp.api")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")

	-- Every technique is complete: a precondition, a reason, steps with what and risk, and a source.
	local list = Techniques.LIST
	H.check("techniques: the list is not empty", #list >= 3, tostring(#list))
	local ids = { }
	for _, technique in ipairs(list) do
		H.check("techniques: an entry has an id", type(technique.id) == "string" and technique.id ~= "")
		H.eq("techniques: the id is unique (" .. tostring(technique.id) .. ")", ids[technique.id], nil)
		ids[technique.id] = true
		H.eq("techniques: it has a precondition (" .. technique.id .. ")", type(technique.when), "function")
		H.check("techniques: it explains why (" .. technique.id .. ")",
			type(technique.why) == "string" and #technique.why > 60, tostring(technique.why and #technique.why))
		H.check("techniques: it has steps (" .. technique.id .. ")",
			type(technique.steps) == "table" and #technique.steps >= 2)
		for _, step in ipairs(technique.steps) do
			H.check("techniques: a step says what (" .. technique.id .. ")",
				type(step.action) == "string" and step.action ~= ""
					and type(step.what) == "string" and step.what ~= "")
			-- A sequence without the downside is trivia, and trivia costs currency.
			H.check("techniques: a step names the risk (" .. technique.id .. ")",
				type(step.risk) == "string" and step.risk ~= "")
		end
		H.check("techniques: it names its source (" .. technique.id .. ")",
			type(technique.source) == "string" and #technique.source > 10)
		-- Every technique states which patch it came from and what was checked about it. The guides these come
		-- from are from two different eras, and a beginner cannot tell that from a video - so the age of the
		-- claim has to travel with the claim.
		H.check("techniques: it says which patch it holds for (" .. technique.id .. ")",
			type(technique.leagueNote) == "string" and #technique.leagueNote > 60,
			tostring(technique.leagueNote and #technique.leagueNote))
	end

	-- A jewel with THREE suffixes is the state the trick needs: the suffix side is over cap.
	-- A Rare jewel holds 2/2 by default; the third suffix slot exists only because Potent Liquid of Contempt
	-- added it, which the item states as "+1 Suffix Modifier allowed". The fixture includes that line, because
	-- a jewel with three suffixes and no such modifier is not a state the game can produce.
	local JEWEL = table.concat({
		"Item Class: Jewels", "Rarity: Rare", "Test Jewel", "Sapphire", "--------",
		"Item Level: 82", "--------",
		'{ Prefix Modifier "A" (Tier: 1) }', "+20% to Critical Damage Bonus",
		'{ Prefix Modifier "B" (Tier: 1) }', "+15% increased Attack Damage",
		'{ Suffix Modifier "E" (Tier: 1) }', "+1 Suffix Modifier allowed",
		'{ Suffix Modifier "C" (Tier: 1) }', "+18% to Critical Hit Chance",
		'{ Suffix Modifier "D" (Tier: 1) }', "12% increased Attack Speed",
	}, "\n")
	local item = Parser.parse(JEWEL)
	Mods.annotate(item)
	H.eq("techniques: the jewel is a jewel", tostring(item.itemClass):lower(), "jewels")
	-- The bought "+1 Suffix Modifier allowed" is itself one of the suffix affixes, so the parser does not count
	-- it among the real suffixes; what it does is raise the cap. Two real suffixes plus the bought slot fill
	-- the three-suffix side, and that is the state the technique needs.
	H.eq("techniques: two real suffixes are counted", item.suffixCount, 2)
	H.eq("techniques: the base caps are two and two", item.affixCaps.base.prefixes, 2)
	H.eq("techniques: the bought slot raises the suffix cap", item.affixCaps.suffixes, 3)
	local jewelTechniques = Techniques.forItem(item)
	local ids2 = { }
	for _, technique in ipairs(jewelTechniques) do
		ids2[technique.id] = true
	end
	H.eq("techniques: the suffix-cap trick is offered on this jewel", ids2.jewel_suffix_cap, true)
	H.eq("techniques: the slot-upgrade rule applies to jewels too", ids2.jewel_slot_upgrade, true)

	-- The same trick must NOT be offered on an ordinary item: its precondition is the over-cap suffix side.
	local HELMET = "Item Class: Helmets\nRarity: Rare\nT\nCharming Tiara\n--------\nItem Level: 80\n--------\n+35 to maximum Mana\n"
	local helmet = Parser.parse(HELMET)
	Mods.annotate(helmet)
	local helmetIds = { }
	for _, technique in ipairs(Techniques.forItem(helmet)) do
		helmetIds[technique.id] = true
	end
	H.eq("techniques: the jewel trick is not offered on a helmet", helmetIds.jewel_suffix_cap, nil)
	H.eq("techniques: but the tag hunt is, on a rare with room", helmetIds.homogenising_tag_hunt, true)

	-- A jewel with only two suffixes has NOT reached the state yet: the trick needs the third one.
	local TWO = table.concat({
		"Item Class: Jewels", "Rarity: Rare", "Test Jewel", "Sapphire", "--------",
		"Item Level: 82", "--------",
		'{ Prefix Modifier "A" (Tier: 1) }', "+20% to Critical Damage Bonus",
		'{ Suffix Modifier "C" (Tier: 1) }', "+18% to Critical Hit Chance",
		'{ Suffix Modifier "D" (Tier: 1) }', "12% increased Attack Speed",
	}, "\n")
	local twoItem = Parser.parse(TWO)
	Mods.annotate(twoItem)
	H.eq("techniques: the two-suffix jewel really has two", twoItem.suffixCount, 2)
	local twoIds = { }
	for _, technique in ipairs(Techniques.forItem(twoItem)) do
		twoIds[technique.id] = true
	end
	H.eq("techniques: two suffixes is not yet the trick state", twoIds.jewel_suffix_cap, nil)

	-- The jewel caps, and the extra slot that makes the trick possible: base 2/2, plus the emotion's +1 on
	-- the suffix side. Both numbers matter - the base is what a jewel starts with, and the third suffix slot
	-- exists only because the item says so.
	H.eq("techniques: a rare jewel caps suffixes at two", item.affixCaps.base.suffixes, 2)
	H.eq("techniques: and prefixes at two", item.affixCaps.base.prefixes, 2)
	H.eq("techniques: with the emotion the suffix cap becomes three", item.affixCaps.suffixes, 3)
	-- A jewel with the same suffixes but WITHOUT the emotion's modifier is not a legal state, and the trick
	-- must not be offered on it: there the third suffix could not have been added at all.
	local NO_EMOTION = table.concat({
		"Item Class: Jewels", "Rarity: Rare", "Test Jewel", "Sapphire", "--------",
		"Item Level: 82", "--------",
		'{ Prefix Modifier "A" (Tier: 1) }', "+20% to Critical Damage Bonus",
		'{ Suffix Modifier "C" (Tier: 1) }', "+18% to Critical Hit Chance",
		'{ Suffix Modifier "D" (Tier: 1) }', "12% increased Attack Speed",
		'{ Suffix Modifier "E" (Tier: 1) }', "+10% increased Elemental Damage",
	}, "\n")
	local noEmotion = Parser.parse(NO_EMOTION)
	Mods.annotate(noEmotion)
	local noEmotionIds = { }
	for _, technique in ipairs(Techniques.forItem(noEmotion)) do
		noEmotionIds[technique.id] = true
	end
	H.eq("techniques: no emotion, no trick - the state cannot exist",
		noEmotionIds.jewel_suffix_cap, nil)

	-- The payload carries them, so the panel can show them without another call.
	local payload = assert(Api.call("methods", { item_text = JEWEL }))
	H.check("techniques: the methods payload carries them", type(payload.techniques) == "table")
	H.eq("techniques: and the jewel trick is among them", #payload.techniques >= 2, true)
	local found = nil
	for _, technique in ipairs(payload.techniques or { }) do
		if technique.id == "jewel_suffix_cap" then found = technique end
	end
	H.check("techniques: with its steps in the payload", found ~= nil and #(found.steps or { }) >= 2)
end
