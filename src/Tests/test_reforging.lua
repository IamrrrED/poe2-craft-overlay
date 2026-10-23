-- PoE2 Craft Overlay : Tests/test_reforging.lua
-- The Reforging Bench ("3-to-1"). The bench takes three items and the overlay sees one, so what is
-- tested here is the DECISION - whether the bench would take this item, whether it upgrades or recycles
-- it, and what the reason to use it is - never a claim about items the player owns.
return function()
	local H = require("Tests.harness")
	local Parser = require("Item.Parser")
	local Reforging = require("Item.Reforging")
	local league = require("Data.league_0_5_5")

	local function item(lines)
		return Parser.parse(table.concat(lines, "\n"))
	end

	local RARE_GLOVES = item({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		'{ Prefix Modifier "Substantial" (Tier: 1) }',
		"+120 to maximum Life",
		'{ Prefix Modifier "Heated" (Tier: 1) }',
		"+40 to maximum Mana",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }',
		"+45% to Fire Resistance",
	})
	-- The decision depends on the item being CLASSIFIED, so the split is asserted before it is used:
	-- a fixture whose modifiers do not resolve would silently test the wrong branch.
	require("Item.Mods").annotate(RARE_GLOVES)
	H.eq("reforging: the fixture is classified", RARE_GLOVES.affixSplitComplete, true)
	H.eq("reforging: with three affixes", (RARE_GLOVES.prefixCount + RARE_GLOVES.suffixCount), 3)

	-- The rules themselves, as data.
	local rules = league.reforging or { }
	H.eq("reforging: the bench takes three items", rules.requiredCount, 3)
	H.eq("reforging: it refuses corrupted items", (rules.refuses or { }).corrupted, true)
	H.eq("reforging: and mirrored ones", (rules.refuses or { }).mirrored, true)
	-- Sanctified is the one state the bench accepts even though every currency refuses it.
	H.eq("reforging: but a sanctified item may be reforged", (rules.allows or { }).sanctified, true)
	H.eq("reforging: three three-modifier rares are the exception worth using it for",
		rules.upgradesThreeModRares, true)

	-- Ordinary gear is recycled, not upgraded, and the three-modifier rare is the reason to do it.
	local allowed, reason = Reforging.allows(RARE_GLOVES, league)
	H.eq("reforging: ordinary gear is accepted", allowed, true)
	H.eq("reforging: with no special reason", reason, nil)
	H.eq("reforging: and it is a recycle, not an upgrade", (Reforging.mode(RARE_GLOVES, league)), "recycle")
	local why = Reforging.whyFor(RARE_GLOVES, league)
	H.check("reforging: the reason names the four-modifier result",
		why ~= nil and why:find("four", 1, true) ~= nil, tostring(why))

	-- A weak rare gets the honest answer instead: the bench rerolls, it does not improve.
	local WEAK = item({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		'{ Prefix Modifier "Substantial" (Tier: 1) }',
		"+20 to maximum Life",
	})
	local weakWhy = Reforging.whyFor(WEAK, league)
	H.check("reforging: a nearly empty rare is described as reuse, not improvement",
		weakWhy ~= nil and weakWhy:find("rolled again", 1, true) ~= nil, tostring(weakWhy))

	-- Corrupted and mirrored items are refused; that is the whole point of checking.
	local CORRUPTED = item({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		"Corrupted",
		"--------",
		"+120 to maximum Life",
	})
	local corruptedAllowed, corruptedReason = Reforging.allows(CORRUPTED, league)
	H.eq("reforging: a corrupted item is refused", corruptedAllowed, false)
	H.eq("reforging: and the reason is named", corruptedReason, "corrupted")
	H.eq("reforging: a refused item gets no advice", (Reforging.whyFor(CORRUPTED, league)), nil)

	local SANCTIFIED = item({
		"Item Class: Gloves",
		"Rarity: Rare",
		"Doom Grip",
		"Blacksteel Gauntlets",
		"--------",
		"Item Level: 82",
		"--------",
		"Sanctified",
		"--------",
		"{ Prefix Modifier \"Substantial\" (Tier: 1) }",
		"+120 to maximum Life",
	})
	local sanctifiedAllowed, sanctifiedReason = Reforging.allows(SANCTIFIED, league)
	H.eq("reforging: a sanctified item is accepted", sanctifiedAllowed, true)
	H.eq("reforging: and flagged as such", sanctifiedReason, "sanctified")

	-- The upgrade families are the other half: runes, emotions, essences, catalysts.
	local RUNE = item({
		"Item Class: Runes",
		"Rarity: Currency",
		"Lesser Body Rune",
	})
	H.eq("reforging: a rune is upgraded", (Reforging.mode(RUNE, league)), "upgrade")
	local runeWhy = Reforging.whyFor(RUNE, league)
	H.check("reforging: and the rune ladder is stated",
		runeWhy ~= nil and runeWhy:find("Lesser", 1, true) ~= nil, tostring(runeWhy))
	H.check("reforging: the emotion ladder is in the ruleset",
		(Reforging.upgradeFor("liquidEmotions", league) or ""):find("Ancient", 1, true) ~= nil)
	H.check("reforging: the essence rule is in the ruleset",
		(Reforging.upgradeFor("essences", league) or ""):find("better tier", 1, true) ~= nil)

	-- A flask is recycled like gear; that distinction is what the panel shows.
	local FLASK = item({
		"Item Class: Life Flasks",
		"Rarity: Magic",
		"Abundant Transcendent Life Flask of the Surgeon",
		"--------",
		"Recovers 1327 Life over 4 Seconds",
		"--------",
		"Item Level: 54",
	})
	H.eq("reforging: a flask is recycled", (Reforging.mode(FLASK, league)), "recycle")
	H.eq("reforging: an unknown class gets no answer", (Reforging.mode(item({
		"Item Class: Waystones",
		"Rarity: Rare",
		"Waystone (Tier 15)",
	}), league)), nil)
end
