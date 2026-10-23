-- PoE2 Craft Overlay : Tests/item_corpus.lua
-- GENERATED FILE - do not edit by hand (tools/build_item_corpus.py).
--
-- Every item fixture the tests already use, deduplicated: the language parity test runs ALL of them
-- through the engine in both languages, because each item class takes its own branch and a branch
-- nobody exercises is where a Russian-only string survives.
return {
	-- from test_advisor.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
]],
	-- from test_advisor.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
4% increased maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
+30 to Strength
]],
	-- from test_advisor.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
--------
Corrupted
]],
	-- from test_advisor.lua
	[[
Item Class: Bows
Rarity: Normal
Composite Bow
--------
Item Level: 55
]],
	-- from test_advisor.lua
	[[
Item Class: Body Armours
Rarity: Unique
Widowhail
Ornate Quiver
--------
Item Level: 70
--------
+50 to maximum Life
]],
	-- from test_advisor.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
4% increased maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
]],
	-- from test_advisor.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
+45% to Fire Resistance
+38% to Cold Resistance
+30 to Strength
]],
	-- from test_capture.lua
	[[
Item Class: Waystones
Rarity: Rare
Waystone (Tier 15)
--------
Waystone Tier: 15
--------
Item Level: 79
--------
Monsters deal 20% increased Damage
]],
	-- from test_capture.lua
	[[
Item Class: Tablets
Rarity: Rare
Breach Tablet
--------
Item Level: 80
--------
Breaches in Map contain an additional Rare Monster
]],
	-- from test_capture.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
]],
	-- from test_capture.lua
	[[
Item Class: Charms
Rarity: Magic
Evergreen Dousing Charm of Plenty
Dousing Charm
--------
Lasts 3 Seconds
Consumes 30 of 63 Charges on use
Currently has 63 Charges
--------
Grants immunity to Ignite
--------
Requirements: Level 60
--------
Item Level: 76
--------
Recovers 297 Life when used
58% increased Charges
]],
	-- from test_coach.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+118 to maximum Life
--------
Corrupted
]],
	-- from test_coach.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+118 to maximum Life
]],
	-- from test_coach.lua
	[[
Item Class: Gloves
Rarity: Rare
Low Thing
Blacksteel Gauntlets
--------
Item Level: 20
--------
+11 to maximum Life
]],
	-- from test_coach.lua
	[[
Item Class: Jewels
Rarity: Rare
Entropy Shard
Ruby
--------
Item Level: 80
--------
Adds 14 to 22 Fire Damage to Attacks
]],
	-- from test_coach.lua
	[[
Item Class: Life Flasks
Rarity: Magic
Abundant Transcendent Life Flask of the Surgeon
Transcendent Life Flask
--------
Recovers 1327 Life over 4 Seconds
Consumes 10 of 75 Charges on use
Currently has 75 Charges
--------
Requirements: Level 50
--------
Item Level: 54
--------
58% increased Recovery Amount
31% Chance to gain a Charge when you Kill an Enemy
]],
	-- from test_essences.lua
	[[
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
]],
	-- from test_language.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Quality: +20% (augmented)
Armour: 412 (augmented)
--------
Requirements:
Level: 78
Str: 100
--------
Item Level: 82
--------
+30 to Strength (implicit)
--------
+118 to maximum Life
+44% to Fire Resistance
--------
]],
	-- from test_language.lua
	[[
Класс предмета: Шлемы
Редкость: Волшебный
Маска парии моржа
--------
Уклонение: 137
Энергетический щит: 43
--------
Требуется: Уровень 54, 42 Ловк, 42 Инт
--------
Уровень предмета: 65
--------
{ Суффикс "моржа" (Уровень: 4) — Стихийный, Холод, Сопротивление }
+30(26-30)% к сопротивлению холоду
]],
	-- from test_mcp.lua
	[[
Item Class: Waystones
Rarity: Rare
Waystone (Tier 15)
--------
Item Level: 79
--------
Monsters deal 20% increased Damage
]],
	-- from test_mods.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
Utterly Unknown Modifier Line
]],
	-- from test_mods.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Item Level: 82
--------
+45% to Fire Resistance
+38% to Cold Resistance
+30 to Strength
+35 to Dexterity
]],
	-- from test_mods.lua
	[[
Item Class: Amulets
Rarity: Rare
Rapture Beads
Stellar Amulet
--------
+1 Prefix Modifier allowed
-1 Suffix Modifier allowed
--------
Item Level: 79
--------
{ Prefix Modifier "Substantial" (Tier: 1) }
+38 to maximum Life
{ Prefix Modifier "Heated" (Tier: 1) }
+40 to maximum Mana
{ Suffix Modifier "of the Prism" (Tier: 1) }
+42% to Fire Resistance
{ Suffix Modifier "of the Ice" (Tier: 1) }
+38% to Cold Resistance
]],
	-- from test_mods.lua
	[[
Item Class: Jewels
Rarity: Rare
Entropy Shard
Ruby
--------
Item Level: 80
--------
{ Suffix Modifier "of the Craft" (Tier: 1) }
-1 Prefix Modifier allowed
{ Prefix Modifier "Heated" (Tier: 1) }
+18% to Fire Resistance
{ Suffix Modifier "of the Ice" (Tier: 1) }
+12 to Strength
]],
	-- from test_mods.lua
	[[
Item Class: Gloves
Rarity: Rare
Andvarius' Hide
Blacksteel Gauntlets
--------
Item Level: 82
--------
+20 to maximum Life
]],
	-- from test_ocr.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
Quality: +20% (augmented)
Evasion Rating: 296 (augmented)
+118 to maximum Life
+44% to Fire Resistance
+37% to Cold Resistance
Item Level: 82
]],
	-- from test_omens.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
4% increased maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
]],
	-- from test_omens.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+120 to maximum Life
+22 to maximum Mana
4% increased maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
+30 to Strength
]],
	-- from test_omens.lua
	[[
Item Class: Boots
Rarity: Magic
Runed Slippers of the Whelpling
--------
Item Level: 65
--------
+25% to Movement Speed (crafted)
]],
	-- from test_omens.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
Item Level: 82
--------
+30 to Strength (implicit)
--------
+120 to maximum Life
+45% to Fire Resistance
]],
	-- from test_parser.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Expert Vaal Gauntlets
--------
Quality: +20% (augmented)
Armour: 320 (augmented)
--------
Requirements:
Level: 78
Str: 100
--------
Sockets: S S
--------
Item Level: 82
--------
+30 to Strength (implicit)
--------
+120 to maximum Life
+45% to Fire Resistance
+38% to Cold Resistance
--------
Corrupted
]],
	-- from test_parser.lua
	[[
Item Class: Boots
Rarity: Magic
Runed Slippers of the Whelpling
--------
Quality: +12% (augmented)
Evasion Rating: 210 (augmented)
--------
Item Level: 65
--------
+25% to Movement Speed
+35 to maximum Life
]],
	-- from test_parser.lua
	[[
Item Class: Bows
Rarity: Normal
Composite Bow
--------
Physical Damage: 20-38
Critical Hit Chance: 5.00%
Attacks per Second: 1.20
--------
Item Level: 62
]],
	-- from test_parser.lua
	[[
Item Class: Rings
Rarity: Rare
Rune Knot
Gold Ring
--------
Item Level: 75
--------
+(30-40) to Strength
+(50-70) to maximum Life
--------
Corrupted
Twice Corrupted
]],
	-- from test_parser.lua
	[[
Item Class: Helmets
Rarity: Rare
Gloom Visage
Expert Plated Helm
--------
Item Level: 80
--------
+25 to Strength
--------
+90 to maximum Life
+40% to Fire Resistance
]],
	-- from test_ru.lua
	[[
Класс предмета: Амулеты
Редкость: Волшебный
Маркизский Алый амулет дракона
--------
Требуется: Уровень 36
--------
Уровень предмета: 79
--------
{ Собственное свойство — Здоровье }
Регенерация 3(2-4) здоровья в секунду
--------
{ Префикс "Маркизский" (Уровень: 2) }
+18(15-20) к ловкости
--------
{ Суффикс "дракона" (Уровень: 3) }
+24(20-30)% к сопротивлению огню
]],
	-- from test_runes.lua
	[[
Item Class: Wands
Rarity: Rare
Doom Bite
Attuned Wand
--------
Item Level: 82
--------
Adds 10 to 20 Fire Damage
+30 to maximum Mana
+20% to Fire Resistance
]],
	-- from test_runes.lua
	[[
Item Class: Body Armours
Rarity: Rare
Chimeric Reflection
Vile Robe
--------
Sockets: S S
--------
Item Level: 80
--------
+120 to maximum Life
]],
	-- from test_runes.lua
	[[
Item Class: Body Armours
Rarity: Rare
Chimeric Reflection
Vile Robe
--------
Sockets: S
--------
Item Level: 80
--------
Rune: Body Rune
--------
+120 to maximum Life
]],
	-- from test_runes.lua
	[[
Item Class: Gloves
Rarity: Rare
Doom Grip
Blacksteel Gauntlets
--------
--------
Item Level: 82
--------
Rune: Body Rune
--------
+120 to maximum Life
]],
}
