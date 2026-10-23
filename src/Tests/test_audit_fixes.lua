-- Fixes that came out of auditing 32 videos against 0.5.5.
--
-- Each check here corresponds to something a guide in docs/mentor-research.md does that the helper used to get
-- wrong or did not model at all. They are grouped together because they share one origin: the videos were read
-- and compared with the ruleset, not because someone guessed at edge cases.
return function()
	local H = require("Tests.harness")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Lines = require("Item.Lines")
	local Techniques = require("Craft.Techniques")

	-- 1. Fractured modifiers. The game announces them in the annotation line above the modifier, in English or
	-- Russian. Only the Russian word was recognised, so on an English client a fractured modifier looked like
	-- an ordinary one and its "cannot be removed" property vanished from the card.
	local EN = table.concat({
		"Item Class: Gloves", "Rarity: Rare", "Test", "Expert Vaal Gauntlets", "--------",
		"Item Level: 82", "--------",
		'{ Fractured Prefix Modifier "Ruin" (Tier: 2) }', "+85 to maximum Energy Shield",
	}, "\n")
	local enLines = Lines.split(EN)
	local enFractured = 0
	for _, mod in ipairs(enLines.mods or { }) do
		if mod.fractured then enFractured = enFractured + 1 end
	end
	H.eq("audit: an English fractured modifier is marked", enFractured, 1)

	local RU = table.concat({
		"Класс предмета: Перчатки", "Редкость: Редкий", "Тест", "Перчатки из чешуи сирены", "--------",
		"Уровень предмета: 82", "--------",
		'{ Расколотое Префикс "Руина" (Уровень: 2) }', "+85 к максимуму энергетического щита",
	}, "\n")
	local ruLines = Lines.split(RU)
	local ruFractured = 0
	for _, mod in ipairs(ruLines.mods or { }) do
		if mod.fractured then ruFractured = ruFractured + 1 end
	end
	H.eq("audit: the Russian one still is", ruFractured, 1)

	-- 2. The desecration technique needs a fractured modifier, and it used to look for a field the parser never
	-- fills - so it could never fire. It now reads the copied text, which is where the game states it.
	local FRACTURED = table.concat({
		"Item Class: Gloves", "Rarity: Rare", "Test", "Expert Vaal Gauntlets", "--------",
		"Item Level: 82", "--------",
		'{ Fractured Prefix Modifier "Ruin" (Tier: 2) }', "+85 to maximum Energy Shield",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }', "+20% to Chaos Resistance",
	}, "\n")
	local fracturedItem = Parser.parse(FRACTURED)
	Mods.annotate(fracturedItem)
	local fractIds = { }
	for _, technique in ipairs(Techniques.forItem(fracturedItem)) do
		fractIds[technique.id] = true
	end
	H.eq("audit: the fracture-desecration loop is offered on a fractured item",
		fractIds.desecration_wash, true)

	local PLAIN = table.concat({
		"Item Class: Gloves", "Rarity: Rare", "Test", "Expert Vaal Gauntlets", "--------",
		"Item Level: 82", "--------",
		'{ Prefix Modifier "Ruin" (Tier: 2) }', "+85 to maximum Energy Shield",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }', "+20% to Chaos Resistance",
	}, "\n")
	local plainItem = Parser.parse(PLAIN)
	Mods.annotate(plainItem)
	local plainIds = { }
	for _, technique in ipairs(Techniques.forItem(plainItem)) do
		plainIds[technique.id] = true
	end
	H.eq("audit: and not on an item without one", plainIds.desecration_wash, nil)

	-- 3. Quality above the ordinary ceiling. 20% is the limit of the ordinary scrabs and whetstones, not of the
	-- item: several 0.5-era guides push to 30, 40 and 50 with infusers, a Breach essence and catalysts, and the
	-- old wording told a 30% item its quality was already at the cap.
	local QUAL = table.concat({
		"Item Class: Crossbows", "Rarity: Rare", "Test", "Expert Siege Crossbow", "--------",
		"Quality: +30%", "Physical Damage: 100-200", "--------", "Item Level: 82", "--------",
		'{ Prefix Modifier "A" (Tier: 1) }', "+50 to maximum Life",
	}, "\n")
	local qualityItem = Parser.parse(QUAL)
	Mods.annotate(qualityItem)
	H.eq("audit: quality above twenty survives parsing", tonumber(qualityItem.quality), 30)
end
