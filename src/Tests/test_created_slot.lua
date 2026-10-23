-- The created-modifier limit: one since 0.5.0, two with Astrid's Creativity.
--
-- This is the change that breaks the most older guides. Auditing all fourteen sources
-- (docs/mentor-research.md) found six whose centrepiece craft stacks several guaranteed modifiers - an essence
-- plus socketed runes, or two or three essences in a row. Since 0.5.0 an item holds ONE created modifier
-- (essence, alloy or rune), so those crafts cannot be reproduced, and the mentor has to say so instead of
-- helping a player waste the currency.
--
-- The one documented exception is Astrid's Creativity, "Can have 1 additional Crafted Modifier", which a
-- 0.5-era guide uses to run two guaranteed essences. The limit is therefore not a constant: it is read from
-- the item, and an item that paid for the slot must not be told a second modifier will not fit.
return function()
	local H = require("Tests.harness")
	local Coach = require("Craft.Coach")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local league = require("Data.league_0_5_5")

	local function stateOf(text)
		local item = Parser.parse(text)
		Mods.annotate(item)
		return item, Coach.state(item, text)
	end

	local function warningIds(state, item, text)
		local ids = { }
		for _, warning in ipairs(Coach.warnings(item, text, state) or { }) do
			ids[tostring(warning.id)] = true
		end
		return ids
	end

	-- The rune exists in the data: the mentor must not invent the exception. The rune table is grouped by slot
	-- (Data/runes.lua: { bySlot = ..., stats = ... }), so it is searched through rather than indexed.
	local rune = nil
	local ok, runes = pcall(require, "Data.runes")
	if ok and type(runes) == "table" then
		local function search(node, depth)
			if rune ~= nil or type(node) ~= "table" or depth > 4 then return end
			for _, value in pairs(node) do
				if type(value) == "table" and value.name == "Astrid's Creativity" then
					rune = value
					return
				end
				if type(value) == "table" then search(value, depth + 1) end
			end
		end
		search(runes, 1)
	end
	H.check("created slot: Astrid's Creativity exists in the data", rune ~= nil)
	if rune then
		local found = false
		for _, line in ipairs(rune.texts or { }) do
			if tostring(line):lower():find("additional crafted modifier", 1, true) then found = true end
		end
		H.check("created slot: and it grants an additional crafted modifier", found,
			table.concat(rune.texts or { }, " | "))
	end

	-- An item with one created modifier and no exception: the slot is full.
	local PLAIN = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Crafted Helm", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
		'{ Suffix Modifier "of the Craft" (Tier: 1) }', "+15% to Fire Resistance (crafted)",
	}, "\n")
	local plainItem, plainState = stateOf(PLAIN)
	H.eq("created slot: one created modifier is seen", plainState.craftedAnchorUsed, true)
	H.eq("created slot: and counted", plainState.createdModifierCount, 1)
	H.eq("created slot: the allowance is one by default", plainState.createdSlots, 1)
	local plainWarnings = warningIds(plainState, plainItem, PLAIN)
	H.eq("created slot: a full slot is reported", plainWarnings.crafted_used, true)

	-- The same item WITH Astrid's Creativity: a second created modifier is legal.
	local WITH_RUNE = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Crafted Helm", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
		'{ Suffix Modifier "of the Craft" (Tier: 1) }', "+15% to Fire Resistance (crafted)",
		'{ Rune Modifier "Astrid\'s Creativity" }', "Can have 1 additional Crafted Modifier",
	}, "\n")
	local runeItem, runeState = stateOf(WITH_RUNE)
	H.eq("created slot: the rune raises the allowance", runeState.createdSlots, 2)
	local runeWarnings = warningIds(runeState, runeItem, WITH_RUNE)
	H.eq("created slot: the item is not told its slot is full", runeWarnings.crafted_used, nil)

	-- An item with no created modifier at all: nothing to warn about, and the slot is still worth spending.
	local EMPTY = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Clean Helm", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
	}, "\n")
	local emptyItem, emptyState = stateOf(EMPTY)
	H.eq("created slot: nothing created yet", emptyState.craftedAnchorUsed, false)
	H.eq("created slot: and the count is zero", emptyState.createdModifierCount, 0)
	local emptyWarnings = warningIds(emptyState, emptyItem, EMPTY)
	H.eq("created slot: no full-slot warning", emptyWarnings.crafted_used, nil)
	H.eq("created slot: the free slot is pointed out", emptyWarnings.essence_slot_free, true)
end
