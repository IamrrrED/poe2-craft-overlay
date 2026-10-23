-- PoE2 Craft Overlay : Data/league_0_5_5.lua
-- Crafting ruleset for the live Path of Exile 2 league (0.5.5 "Forbidden Rites").
--
-- IMPORTANT
-- This file is data, not code: edit it as leagues change. Every entry carries a
-- `status` field:
--   "core"       - long-standing PoE2 currency behaviour, safe to rely on
--   "league"     - introduced or changed by a specific patch, see `source`
--   "unverified" - plausible but NOT confirmed by an official source yet; the
--                  overlay prints a warning marker for these, and they are the
--                  first thing to correct after a patch.
--
-- Machine-readable combat fields used by the probability engine:
--   adds         - how many random modifiers the currency adds
--   removes      - how many modifiers it removes
--   minModLevel  - minimum modifier level floor (Greater / Perfect tiers)
--   side         - "any" | "prefix" | "suffix" (which side it can add to)
-- Costs are qualitative tiers (low/medium/high/veryhigh): real prices are
-- league- and time-dependent and are deliberately not hardcoded.
--
-- Russian fields (`effect`, `why`, `blocker`, `glossary`) feed the Russian panel
-- and the console log; English fields (`effectEn`, ...) the English panel. Names
-- The overlay is English only; `en` is the name that is shown.
-- searched for on the internet.

return {
	league = "0.5.5 Forbidden Rites",
	leagueShort = "0.5.5",
	updated = "2026-10",
	sources = {
		"https://www.pathofexile.com/forum/view-thread/4000864", -- official 0.5.5 patch notes
		"https://domistae.github.io/poe2-leveling/poe2_crafting_codex.html", -- crafting codex (community)
		"https://timesaver.gg/blog/poe2-omens-guide", -- omen list (community)
		"https://poe2db.tw/us/", -- datamined database
	},

	currencies = {
		transmutation = {
			en = "Orb of Transmutation", effectEn = "Turns a Normal item Magic with one modifier.",
			cost = "low", status = "core", adds = 1, removes = 0, minModLevel = 0, side = "any",
		},
		greater_transmutation = {
			en = "Greater Orb of Transmutation", effectEn = "As Transmutation, with a minimum modifier level of 44.",
			cost = "medium", status = "league", adds = 1, removes = 0, minModLevel = 44, side = "any",
			},
		perfect_transmutation = {
			en = "Perfect Orb of Transmutation", effectEn = "As Transmutation, with a minimum modifier level of 70.",
			cost = "high", status = "league", adds = 1, removes = 0, minModLevel = 70, side = "any",
		},
		augmentation = {
			en = "Orb of Augmentation", effectEn = "Adds one modifier to a Magic item (Magic caps at one prefix and one suffix).",
			cost = "low", status = "core", adds = 1, removes = 0, minModLevel = 0, side = "any",
		},
		greater_augmentation = {
			en = "Greater Orb of Augmentation", effectEn = "As Augmentation, with a minimum modifier level of 44.",
			cost = "medium", status = "league", adds = 1, removes = 0, minModLevel = 44, side = "any",
		},
		perfect_augmentation = {
			en = "Perfect Orb of Augmentation", effectEn = "As Augmentation, with a minimum modifier level of 70.",
			cost = "high", status = "league", adds = 1, removes = 0, minModLevel = 70, side = "any",
		},
		regal = {
			en = "Regal Orb", effectEn = "Upgrades a Magic item to Rare and adds one modifier.",
			cost = "low", status = "core", adds = 1, removes = 0, minModLevel = 0, side = "any",
		},
		greater_regal = {
			en = "Greater Regal Orb", effectEn = "As Regal, with a minimum modifier level of 35.",
			cost = "medium", status = "league", adds = 1, removes = 0, minModLevel = 35, side = "any",
		},
		perfect_regal = {
			en = "Perfect Regal Orb", effectEn = "As Regal, with a minimum modifier level of 50.",
			cost = "high", status = "league", adds = 1, removes = 0, minModLevel = 50, side = "any",
		},
		exalted = {
			en = "Exalted Orb", effectEn = "Adds one random modifier to a Rare item (max 3 prefixes + 3 suffixes).",
			cost = "medium", status = "core", adds = 1, removes = 0, minModLevel = 0, side = "any",
		},
		greater_exalted = {
			en = "Greater Exalted Orb", effectEn = "As Exalted, with a minimum modifier level of 35 - cuts the junk tiers.",
			cost = "high", status = "league", adds = 1, removes = 0, minModLevel = 35, side = "any",
			},
		perfect_exalted = {
			en = "Perfect Exalted Orb", effectEn = "As Exalted, with a minimum modifier level of 50 - the final slam.",
			cost = "veryhigh", status = "league", adds = 1, removes = 0, minModLevel = 50, side = "any",
		},
		hinekora = {
			en = "Hinekora's Lock",
			-- Listed on poe2db's currency tab (0.5.5). It does not change the item by itself: it shows what
			-- the next currency WOULD do, and the ability is lost if the item is modified in any other way.
			-- That makes it the only way to check a slam before paying for it, which is the behaviour the
			-- mentor teaches - so it is modelled even though it neither adds nor removes a modifier.
			effectEn = "Lets an item foresee the result of the next Currency item used on it. Modifying the "
				.. "item in any way removes the ability to foresee.",
			cost = "high", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
			preview = true,
		},
		chaos = {
			en = "Chaos Orb", effectEn = "Removes one random modifier and adds a new one (Rare items).",
			cost = "medium", status = "core", adds = 1, removes = 1, minModLevel = 0, side = "any",
		},
		greater_chaos = {
			en = "Greater Chaos Orb", effectEn = "As Chaos, with a minimum modifier level of 35.",
			cost = "high", status = "league", adds = 1, removes = 1, minModLevel = 35, side = "any",
		},
		perfect_chaos = {
			en = "Perfect Chaos Orb", effectEn = "As Chaos, with a minimum modifier level of 50.",
			cost = "veryhigh", status = "league", adds = 1, removes = 1, minModLevel = 50, side = "any",
		},
		divine = {
			en = "Divine Orb", effectEn = "Rerolls the numeric values of existing modifiers; the modifier set is unchanged.",
			cost = "medium", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		annulment = {
			en = "Orb of Annulment", effectEn = "Removes one random modifier. Risky: it can strip the modifier you need.",
			cost = "medium", status = "core", adds = 0, removes = 1, minModLevel = 0, side = "none",
		},
		fracturing = {
			en = "Fracturing Orb", effectEn = "Locks one random modifier in place; it can no longer be modified.",
			cost = "high", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		vaal = {
			en = "Vaal Orb", effectEn = "Corrupts the item: adds a corrupted implicit, an extra socket or another effect (possibly bricking it). No further changes.",
			-- One-way, and it can REMOVE what the craft was built for, which is why the plan puts it last,
			-- after quality: nothing can be done to the item afterwards. The warning travels with the step
			-- so it is read at the moment the player is about to use it, not only in the pitfalls list.
			cost = "low", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
			-- Four outcomes, equal chance (poewiki, Vaal Orb): a corruption implicit that REPLACES the existing
			-- one, a socket going non-white, a reroll into a rare with six random affixes, or nothing. A
			-- warning that says "can brick" does not convey that one attempt in four destroys the craft.
			warningEn = "One-way. Equipment has FOUR equal outcomes, 25% each: a corruption implicit (it "
				.. "REPLACES the existing implicit), a socket turning non-white, the item becoming rare with SIX "
				.. "random affixes (the craft is gone), or no change. One attempt in four destroys the result.",
			warning = "Необратимо. У снаряжения ЧЕТЫРЕ равных исхода по 25 %: осквернённый имплисит (он "
				.. "ЗАМЕНИТ существующий), цвет сокета станет не белым, предмет станет редким с ШЕСТЬЮ "
				.. "случайными модами — крафт пропадает, — либо ничего не изменится. Одна попытка из четырёх "
				.. "уничтожает результат.",
		},
		alchemy = {
			en = "Orb of Alchemy", effectEn = "Upgrades a Normal item straight to Rare with several modifiers (typically 4).",
			cost = "low", status = "core", adds = 4, removes = 0, minModLevel = 0, side = "any",
		},
		chance = {
			en = "Orb of Chance", effectEn = "Upgrades a Normal item into a random Unique of the same class - or destroys it.",
			cost = "medium", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		-- Quality is a separate number, not an affix slot, and it scales the item's own base stats: a
		-- flask's recovery, a weapon's physical damage, armour's defences. Each item class has its own
		-- currency, and quality is worth raising BEFORE expensive modifiers - that is why the panel
		-- offers it as the very first step. It used to have a single "Quality currency" entry, so the
		-- advice could not name the item the player actually has to use.
		quality = {
			en = "Quality currency", effectEn = "Raises item quality (scales base stats). Do this BEFORE expensive modifiers.",
			cost = "low", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		whetstone = {
			en = "Blacksmith's Whetstone", effectEn = "Raises the quality of martial weapons: 1% more local physical damage per 1% quality.",
			cost = "low", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		scrap = {
			en = "Armourer's Scrap", effectEn = "Raises the quality of armour: 1% more defences (armour, evasion, energy shield) per 1%.",
			cost = "low", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		etcher = {
			en = "Arcanist's Etcher", effectEn = "Raises the quality of wands, staves and sceptres: 1% quality per 1%, which improves the socketed skill.",
			cost = "low", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		bauble = {
			en = "Glassblower's Bauble", effectEn = "Raises the quality of a flask: 1% more recovery per 1% quality.",
			cost = "low", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		prism = {
			en = "Gemcutter's Prism", effectEn = "Raises the quality of a skill or support gem; always exactly 5%.",
			cost = "low", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		essence = {
			en = "Essence", effectEn = "Guarantees one specific modifier. Occupies the item's single crafted-modifier slot.",
			cost = "medium", status = "core", adds = 1, removes = 0, minModLevel = 0, side = "any",
			guaranteed = true,
		},
		perfect_essence = {
			en = "Perfect Essence", effectEn = "Guarantees the modifier at the highest available mod level. Also uses the crafted-mod slot.",
			cost = "high", status = "core", adds = 1, removes = 0, minModLevel = 0, side = "any",
			guaranteed = true,
		},
		omen = {
			en = "Omen", effectEn = "Rewrites the rules of the next matching currency (e.g. adds only a suffix).",
			cost = "high", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
		bone = {
			en = "Desecration Bone", effectEn = "Adds a hidden desecrated modifier; you pick one of three at the Well of Souls.",
			cost = "medium", status = "league", adds = 1, removes = 0, minModLevel = 0, side = "any",
			},
		alloy = {
			en = "Runic Alloy", effectEn = "Removes a random modifier and adds one exclusive to that alloy. Uses the crafted-mod slot.",
			cost = "high", status = "league", adds = 1, removes = 1, minModLevel = 0, side = "any",
			guaranteed = true,
			},
		rune = {
			en = "Rune / Runeforging", effectEn = "A rune goes into a socket for a fixed modifier; meta-runes unlock new mod pools for normal crafting.",
			cost = "low", status = "league", adds = 0, removes = 0, minModLevel = 0, side = "none",
			source = "0.5 Runes of Aldur: Verisium, Runic Ward, 13 Ancient runes, meta-runes, fluxes.",
		},
		quality = {
			en = "Quality currency", effectEn = "Raises item quality (scales base stats). Do this BEFORE expensive modifiers.",
			cost = "low", status = "core", adds = 0, removes = 0, minModLevel = 0, side = "none",
		},
	},

	-- Omens.
	-- An omen does not act on the item itself: it rewrites the rules of the next
	-- matching currency. Machine-readable behaviour fields:
	--   applies  - which currency it modifies (currency id)
	--   side     - "prefix" | "suffix": the modified currency may only touch that side
	--   removal  - "lowest" | "prefix" | "suffix" | "random": what a removal step hits
	--   count    - how many modifiers the modified currency handles (default 1)
	--   guarantee/noDestroy/reroll - special outcomes
	omens = {
		whittling = {
			en = "Omen of Whittling", effectEn = "The next Chaos Orb removes the lowest-level modifier instead of a random one.",
			applies = "chaos", removal = "lowest", cost = "veryhigh", status = "core",
			},
		sinistral_erasure = {
			en = "Omen of Sinistral Erasure", effectEn = "The next Chaos Orb removes only a prefix.",
			applies = "chaos", removal = "prefix", cost = "veryhigh", status = "core",
		},
		dextral_erasure = {
			en = "Omen of Dextral Erasure", effectEn = "The next Chaos Orb removes only a suffix.",
			applies = "chaos", removal = "suffix", cost = "veryhigh", status = "core",
		},
		greater_exaltation = {
			en = "Omen of Greater Exaltation", effectEn = "The next Exalted Orb adds two modifiers instead of one.",
			applies = "exalted", count = 2, cost = "high", status = "core",
		},
		sinistral_exaltation = {
			en = "Omen of Sinistral Exaltation", effectEn = "The next Exalted Orb adds only a prefix.",
			applies = "exalted", side = "prefix", cost = "high", status = "core",
		},
		dextral_exaltation = {
			en = "Omen of Dextral Exaltation", effectEn = "The next Exalted Orb adds only a suffix.",
			applies = "exalted", side = "suffix", cost = "high", status = "core",
		},
		homogenising_exaltation = {
			en = "Omen of Homogenising Exaltation",
			-- Corrected against the official 0.4.0 notes: "Omen of Homogenising Exaltation and the Omen of
			-- Homogenising Coronation have been disabled from dropping. Existing items are still functional."
			-- So it is NOT unobtainable - it is a currency-exchange item now, and the technique it enables
			-- (guaranteeing a modifier of a tag the item already has) still works. Our old wording said
			-- "not obtainable in league" and would have hidden one of the strongest methods in the game.
			effectEn = "The next Exalted Orb adds a modifier sharing a TAG with one already on the item. "
				.. "No longer drops (0.4): obtainable through the currency exchange, still functional.",
			applies = "exalted", sameTypeAs = true, cost = "high", status = "removed",
			-- The technique only works when the wanted family is the ONLY one the exalt can roll on the
			-- chosen side; otherwise the tags of the other side come into play (verified in a real craft).
			deterministicWhenAlone = true,
		},
		catalysing_exaltation = {
			en = "Omen of Catalysing Exaltation", effectEn = "The next Exalted Orb biases the added modifier toward the catalyst's tag (exact bias undocumented).",
			applies = "exalted", bias = "catalyst", cost = "high", status = "unverified",
		},
		greater_annulment = {
			en = "Omen of Greater Annulment", effectEn = "The next Orb of Annulment removes two modifiers.",
			applies = "annulment", count = 2, cost = "high", status = "core",
		},
		sinistral_annulment = {
			en = "Omen of Sinistral Annulment", effectEn = "The next Orb of Annulment removes only a prefix.",
			applies = "annulment", removal = "prefix", cost = "high", status = "core",
		},
		dextral_annulment = {
			en = "Omen of Dextral Annulment", effectEn = "The next Orb of Annulment removes only a suffix.",
			applies = "annulment", removal = "suffix", cost = "high", status = "core",
		},
		sinistral_coronation = {
			en = "Omen of Sinistral Coronation", effectEn = "The next Regal Orb adds only a prefix.",
			applies = "regal", side = "prefix", cost = "medium", status = "core",
		},
		dextral_coronation = {
			en = "Omen of Dextral Coronation", effectEn = "The next Regal Orb adds only a suffix.",
			applies = "regal", side = "suffix", cost = "medium", status = "core",
		},
		omen_of_chance = {
			en = "Omen of Chance", effectEn = "The next Orb of Chance will not destroy the item.",
			applies = "chance", noDestroy = true, cost = "medium", status = "core",
		},
		omen_of_the_ancients = {
			en = "Omen of the Ancients", effectEn = "The next Orb of Chance is guaranteed to upgrade the item to a random Unique of the same class.",
			applies = "chance", guarantee = "unique", cost = "veryhigh", status = "league",
		},
		blessed = {
			en = "Omen of the Blessed", effectEn = "The next Divine Orb rerolls implicit modifiers only.",
			applies = "divine", reroll = "implicits", cost = "medium", status = "core",
		},
		sinistral_necromancy = {
			en = "Omen of Sinistral Necromancy", effectEn = "The desecration affects the prefix side.",
			applies = "bone", side = "prefix", cost = "high", status = "league",
		},
		dextral_necromancy = {
			en = "Omen of Dextral Necromancy", effectEn = "The desecration affects the suffix side.",
			applies = "bone", side = "suffix", cost = "high", status = "league",
		},
		-- The crafting omens the game has and this file used to be missing entirely. The coach already
		-- advised "Annulment with Omen of Light" while the item was not in the ruleset at all, so the
		-- panel named something the engine did not know. Status "league" marks the ones whose exact
		-- wording comes from third party catalogues rather than the official patch notes.
		omen_of_light = {
			en = "Omen of Light", effectEn = "The next Orb of Annulment removes only a desecrated modifier - the way to take back a bad desecration without losing the rest.",
			applies = "annulment", removal = "desecrated", cost = "high", status = "league",
		},
		-- The five "Saga" items sit on poe2db's Omen page and were the only entries missing from our set
		-- (45 + 5 = the page's 50). They are NOT item-crafting omens: they shape the next Expedition Logbook,
		-- so they are recorded for completeness and marked so the advice never offers them for a piece of gear.
		aldurs_saga = {
			en = "Aldur's Saga", effectEn = "The next Logbook adds special modifiers to revealed Grand Expedition areas.",
			target = "logbook", cost = "high", status = "league", notItemCrafting = true,
		},
		medveds_saga = {
			en = "Medved's Saga", effectEn = "The next Logbook guarantees a Medved encounter in the revealed Biome.",
			target = "logbook", cost = "high", status = "league", notItemCrafting = true,
		},
		voranas_saga = {
			en = "Vorana's Saga", effectEn = "The next Logbook guarantees a Vorana encounter in the revealed Biome.",
			target = "logbook", cost = "high", status = "league", notItemCrafting = true,
		},
		uhtreds_saga = {
			en = "Uhtred's Saga", effectEn = "The next Logbook guarantees an Uhtred encounter in the revealed Biome.",
			target = "logbook", cost = "high", status = "league", notItemCrafting = true,
		},
		olroths_saga = {
			en = "Olroth's Saga", effectEn = "The next Logbook guarantees an Olroth encounter in the revealed Biome.",
			target = "logbook", cost = "high", status = "league", notItemCrafting = true,
		},
		omen_of_sanctification = {
			en = "Omen of Sanctification", effectEn = "The next Divine Orb used on a Rare item sanctifies it: every modifier value is multiplied once by 0.78-1.22. The item cannot be crafted further.",
			applies = "divine", sanctifies = true, cost = "veryhigh", status = "league",
		},
		sinistral_alchemy = {
			en = "Omen of Sinistral Alchemy", effectEn = "The next Orb of Alchemy rolls the maximum number of prefixes.",
			applies = "alchemy", side = "prefix", maximum = true, cost = "high", status = "league",
		},
		dextral_alchemy = {
			en = "Omen of Dextral Alchemy", effectEn = "The next Orb of Alchemy rolls the maximum number of suffixes.",
			applies = "alchemy", side = "suffix", maximum = true, cost = "high", status = "league",
		},
		sinistral_crystallisation = {
			en = "Omen of Sinistral Crystallisation", effectEn = "The next Perfect or Corrupted Essence removes only a prefix before applying its guaranteed modifier.",
			applies = "perfect_essence", removal = "prefix", cost = "high", status = "league",
		},
		dextral_crystallisation = {
			en = "Omen of Dextral Crystallisation", effectEn = "The next Perfect or Corrupted Essence removes only a suffix before applying its guaranteed modifier.",
			applies = "perfect_essence", removal = "suffix", cost = "high", status = "league",
		},
		homogenising_coronation = {
			en = "Omen of Homogenising Coronation",
			-- Same correction as its Exalted twin: disabled from DROPPING, and the official notes say existing
			-- items still work. It lives on the currency exchange now, which is not the same as unobtainable.
			effectEn = "The next Regal Orb adds a modifier sharing a TAG with one already on the item. "
				.. "No longer drops (0.5.0): obtainable through the currency exchange, still functional.",
			applies = "regal", sameTypeAs = true, cost = "high", status = "removed",
		},
		abyssal_echoes = {
			en = "Omen of Abyssal Echoes", effectEn = "One reroll of the three modifiers offered when a desecrated modifier is revealed at the Well of Souls.",
			applies = "bone", reroll = "reveal", cost = "high", status = "league",
		},
		the_blackblooded = {
			en = "Omen of the Blackblooded", effectEn = "The next desecration of a weapon or jewellery guarantees a random Kurgal modifier.",
			applies = "bone", lich = "kurgal", slots = { "weapon", "jewellery" }, cost = "high", status = "league",
		},
		the_liege = {
			en = "Omen of the Liege", effectEn = "The next desecration of a weapon or jewellery guarantees a random Amanamu modifier.",
			applies = "bone", lich = "amanamu", slots = { "weapon", "jewellery" }, cost = "high", status = "league",
		},
		the_sovereign = {
			en = "Omen of the Sovereign", effectEn = "The next desecration of a weapon or jewellery guarantees a random Ulaman modifier.",
			applies = "bone", lich = "ulaman", slots = { "weapon", "jewellery" }, cost = "high", status = "league",
		},
		-- Utility omens: they change nothing about a currency, so they carry no `applies` and are marked
		-- `utility`. They are here so that every omen the game has is named in the ruleset with what it
		-- actually does - otherwise the panel can advise one the engine has never heard of.
		amelioration = {
			en = "Omen of Amelioration", effectEn = "Prevents 75% of the experience lost on death.",
			utility = true, cost = "medium", status = "league",
		},
		answered_prayers = {
			en = "Omen of Answered Prayers", effectEn = "The next Shrine grants an additional effect.",
			utility = true, cost = "medium", status = "league",
		},
		bartering = {
			en = "Omen of Bartering", effectEn = "The next item sold to a vendor is mispriced in your favour.",
			utility = true, cost = "medium", status = "league",
		},
		gambling = {
			en = "Omen of Gambling", effectEn = "The next gamble has a 50% chance to cost no gold and not consume the omen.",
			utility = true, cost = "medium", status = "league",
		},
		refreshment = {
			en = "Omen of Refreshment", effectEn = "Refills flask and charm charges when you reach Low Life.",
			utility = true, cost = "medium", status = "league",
		},
		resurgence = {
			en = "Omen of Resurgence", effectEn = "Restores life, mana and energy shield when you reach Low Life.",
			utility = true, cost = "medium", status = "league",
		},
		reinforcements = {
			en = "Omen of Reinforcements", effectEn = "The next Rogue Exile is joined by an ally.",
			utility = true, cost = "low", status = "league",
		},
		secret_compartments = {
			en = "Omen of Secret Compartments", effectEn = "The next Strongbox can be opened a second time.",
			utility = true, cost = "medium", status = "league",
		},
		the_hunt = {
			en = "Omen of the Hunt", effectEn = "The next Possessed monster releases its Azmeri Spirit. 0.5.5 reworded the description without changing the effect.",
			utility = true, cost = "medium", status = "league",
		},
		chaotic_effectiveness = {
			en = "Omen of Chaotic Effectiveness", effectEn = "The next Chaos Orb on a Waystone rolls modifiers that do not grant Monster Effectiveness.",
			applies = "chaos", waystone = true, excludes = "effectiveness", cost = "medium", status = "league",
		},
		chaotic_monsters = {
			en = "Omen of Chaotic Monsters", effectEn = "The next Chaos Orb on a Waystone rolls modifiers that do not grant Monster Rarity.",
			applies = "chaos", waystone = true, excludes = "monster rarity", cost = "medium", status = "league",
		},
		chaotic_quantity = {
			en = "Omen of Chaotic Quantity", effectEn = "The next Chaos Orb on a Waystone rolls modifiers that do not grant Pack Size.",
			applies = "chaos", waystone = true, excludes = "pack size", cost = "medium", status = "league",
		},
		chaotic_rarity = {
			en = "Omen of Chaotic Rarity", effectEn = "The next Chaos Orb on a Waystone rolls modifiers that do not grant Item Rarity.",
			applies = "chaos", waystone = true, excludes = "item rarity", cost = "medium", status = "league",
		},
		putrefaction = {
			en = "Omen of Putrefaction",
			-- Confirmed by two sources, and it is an explicit EXCEPTION to the one-desecrated-modifier rule
			-- rather than a contradiction of it: it replaces every modifier, leaves up to six unrevealed ones
			-- and corrupts the item. Our note used to call it contradictory AND unconfirmed - wrong twice.
			effectEn = "The next desecration replaces every modifier on the item, creating up to six unrevealed modifiers and corrupting it. An explicit exception to the one-desecrated-modifier limit.",
			applies = "bone", replacesAll = true, corrupts = true, cost = "veryhigh", status = "league",
		},
		recombination = {
			en = "Omen of Recombination", effectEn = "Not obtainable since 0.5.0: the Recombinator was removed and existing copies were deleted. Kept here so the name is not mistaken for a live method.",
			utility = true, cost = "unknown", status = "unverified",
		},
		omen_of_corruption = {
			en = "Omen of Corruption", effectEn = "Vaal Orb always produces a change (no 'nothing happens' outcome). Removed from league drops; Standard-only copies remain.",
			applies = "vaal", alwaysChanges = true, cost = "unknown", status = "unverified",
		},
	},

	-- Ordered rules; the first match supplies the plan.
	-- Alloys (Verisium): 13 of them, each adds a modifier from its own pool. PoB data has
	-- the modifiers themselves (affix "Verisium" / "of the Stars", weight 0) but no
	-- alloy -> modifier mapping, so the panel lists the pool and says outright that the
	-- odds cannot be computed.
	alloys = {
		{ en = "Runic Alloy", },
		{ en = "Adaptive Alloy", },
		{ en = "Protective Alloy", },
		{ en = "Expansive Alloy", },
		{ en = "Swift Alloy", },
		{ en = "Cyclonic Alloy", },
		{ en = "Prismatic Alloy", },
		{ en = "Mystic Alloy", },
		{ en = "Sovereign Alloy", },
		{ en = "Celestial Alloy", },
		{ en = "Transcendent Alloy", },
		{ en = "The Runebinder's Alloy", },
		{ en = "The Runefather's Alloy", },
	},

	-- Desecration / the Well of Souls: what the player actually applies to open a reveal.
	--
	-- The panel used to say only "a bone" (Advisor.lua), which tells the player nothing: the bone
	-- decides WHICH item classes can be desecrated, and its grade decides how good the offered
	-- modifier can be. From the public catalogue (poe2ref, timesaver):
	--   slot  - which items the bone fits: weapon (weapons and quivers), armour (helmet, body,
	--           gloves, boots, shield), jewellery (amulet, ring, belt), jewel, waystone
	--   grade - Gnawed only fits items up to item level 64 (campaign), Preserved fits any item,
	--           Ancient fits any item AND guarantees a modifier level of at least 40
	-- One desecrated modifier per item, and if all six affixes are taken a random one is removed
	-- first. Altered Collarbone comes from the Genesis Tree and can roll otherworldly modifiers.
	-- Desecration itself: what the bone does, and the two thresholds that decide whether it is worth doing.
	-- Sources: basicknowledge.xyz/poe2/craft/abyss, poe2wiki. Applied with a bone on a rare; the result is
	-- unrevealed and chosen 1 of 3 at the Well of Souls in Act 2.
	desecration = {
		appliedWith = "preserved bone",
		revealedAt = "Колодец Душ (Well of Souls), хаб Акта 2",
		revealedAtEn = "Well of Souls, Act 2 hub",
		choices = 3,
		-- Above this item level at least one of the three options is a modifier that normally cannot roll.
		offPoolFromItemLevel = 65,
		-- 0.5.0: a desecrated modifier no longer counts as crafted, and the item holds one of them.
		maxDesecrated = 1,
		dropsFrom = "Abyssal Troves и Abyssal Depths",
		dropsFromEn = "Abyssal Troves and Abyssal Depths",
		-- Abyss omens stopped dropping in low areas in 0.5.0, which is why they are endgame-priced.
		omenDropLevel = 65,
	},	bones = {
		{ en = "Gnawed Jawbone", slot = "weapon", grade = "gnawed", maxItemLevel = 64, },
		{ en = "Preserved Jawbone", slot = "weapon", grade = "preserved", },
		{ en = "Ancient Jawbone", slot = "weapon", grade = "ancient", minModLevel = 40, },
		{ en = "Gnawed Rib", slot = "armour", grade = "gnawed", maxItemLevel = 64, },
		{ en = "Preserved Rib", slot = "armour", grade = "preserved", },
		{ en = "Ancient Rib", slot = "armour", grade = "ancient", minModLevel = 40, },
		{ en = "Gnawed Collarbone", slot = "jewellery", grade = "gnawed", maxItemLevel = 64, },
		{ en = "Preserved Collarbone", slot = "jewellery", grade = "preserved", },
		{ en = "Ancient Collarbone", slot = "jewellery", grade = "ancient", minModLevel = 40, },
		{ en = "Preserved Cranium", slot = "jewel", grade = "preserved", },
		{ en = "Preserved Vertebrae", slot = "waystone", grade = "preserved", },
		{ en = "Altered Collarbone", slot = "jewellery", grade = "preserved", altered = true,
			detail = "From the Genesis Tree (Breach); can roll otherworldly modifiers." },
	},
	-- The three liches whose modifier pools the Well of Souls offers, and the omens that force one.
	desecrationLiches = {
		{ id = "ulaman", en = "Ulaman", omens = { "the_sovereign" }, mods = 66, },
		{ id = "amanamu", en = "Amanamu", omens = { "the_liege" }, mods = 70, },
		{ id = "kurgal", en = "Kurgal", omens = { "the_blackblooded" }, mods = 63, },
	},

	-- Quality beyond the five class currencies: catalysts, for rings, amulets and jewels only.
	--
	-- A catalyst raises the quality of one modifier tag and REPLACES any quality of another tag, so
	-- the choice matters. Caps: a plain ring or amulet 20%, a Breach Ring 40%, a Refined Breach Ring
	-- 45%. Since 0.5.0 catalysts no longer drop from monsters - the Genesis Tree (Breach) is the
	-- source. "Refined" versions are the jewels' variant.
	catalysts = {
		{ en = "Adaptive Catalyst", tag = "adaptive" },
		{ en = "Carapace Catalyst", tag = "physical" },
		{ en = "Chayula's Catalyst", tag = "chaos" },
		{ en = "Esh's Catalyst", tag = "lightning" },
		{ en = "Flesh Catalyst", tag = "life" },
		{ en = "Necrotic Catalyst", tag = "minion" },
		{ en = "Neural Catalyst", tag = "mana" },
		{ en = "Reaver Catalyst", tag = "attack" },
		{ en = "Sibilant Catalyst", tag = "spell" },
		{ en = "Skittering Catalyst", tag = "speed" },
		{ en = "Tul's Catalyst", tag = "cold" },
		{ en = "Uul-Netol's Catalyst", tag = "defence" },
		{ en = "Xoph's Catalyst", tag = "fire" },
		{ en = "Refined Adaptive Catalyst", tag = "adaptive", refined = true },
		{ en = "Refined Carapace Catalyst", tag = "physical", refined = true },
		{ en = "Refined Chayula's Catalyst", tag = "chaos", refined = true },
		{ en = "Refined Esh's Catalyst", tag = "lightning", refined = true },
		{ en = "Refined Flesh Catalyst", tag = "life", refined = true },
		{ en = "Refined Necrotic Catalyst", tag = "minion", refined = true },
		{ en = "Refined Neural Catalyst", tag = "mana", refined = true },
		{ en = "Refined Reaver Catalyst", tag = "attack", refined = true },
		{ en = "Refined Sibilant Catalyst", tag = "spell", refined = true },
		{ en = "Refined Skittering Catalyst", tag = "speed", refined = true },
		{ en = "Refined Tul's Catalyst", tag = "cold", refined = true },
		{ en = "Refined Uul-Netol's Catalyst", tag = "defence", refined = true },
		{ en = "Refined Xoph's Catalyst", tag = "fire", refined = true },
	},
	-- The four Vaal Infusers: they add a corrupted enchantment to one kind of item and require the
	-- item to be at 20% quality or better.
	-- Liquid Emotions (Delirium). I called these flask consumables once and that was wrong, so the facts
	-- are spelled out: they are combined at the instilling station to anoint an AMULET with one notable
	-- passive from the tree, three emotions in a fixed order (a different order can be a different
	-- notable), or applied to a Waystone as a reward modifier. They are not quality currency and they are
	-- not desecration bones, which is the easy mix-up - the names read like liquids.
	--
	-- The ten-rung ladder: three of one emotion reforge into one of the next rung up at the Reforging
	-- Bench (3 Ire -> 1 Guilt -> ... -> 1 Suffering), which is why the rarity order below matters when
	-- advising what to spend. "Diluted" and "Concentrated" are NOT tiers of the same thing, they are
	-- parts of names: the ladder is Ire, Guilt, Greed, Paranoia, Envy, Disgust, Despair, Fear, Isolation,
	-- Suffering, where the first three are Diluted, the middle four plain and the last three Concentrated.
	-- A tenth "Potent" set exists above them for the strongest anoints (one of them, Zarokh's Gift, grants
	-- a jewel socket instead of a stat). 26 names in total, counting the Ancient set.
	liquidEmotions = {
		{ en = "Diluted Liquid Ire", tier = "diluted", ladder = 1 },
		{ en = "Diluted Liquid Guilt", tier = "diluted", ladder = 2 },
		{ en = "Diluted Liquid Greed", tier = "diluted", ladder = 3 },
		{ en = "Liquid Paranoia", tier = "base", ladder = 4 },
		{ en = "Liquid Envy", tier = "base", ladder = 5 },
		{ en = "Liquid Disgust", tier = "base", ladder = 6 },
		{ en = "Liquid Despair", tier = "base", ladder = 7 },
		{ en = "Concentrated Liquid Fear", tier = "concentrated", ladder = 8 },
		{ en = "Concentrated Liquid Isolation", tier = "concentrated", ladder = 9 },
		{ en = "Concentrated Liquid Suffering", tier = "concentrated", ladder = 10 },
		{ en = "Potent Liquid Melancholy", tier = "potent" },
		{ en = "Potent Liquid Ferocity", tier = "potent" },
		{ en = "Potent Liquid Contempt", tier = "potent" },
		{ en = "Ancient Diluted Liquid Ire", tier = "ancient", ladder = 1 },
		{ en = "Ancient Diluted Liquid Guilt", tier = "ancient", ladder = 2 },
		{ en = "Ancient Diluted Liquid Greed", tier = "ancient", ladder = 3 },
		{ en = "Ancient Liquid Paranoia", tier = "ancient", ladder = 4 },
		{ en = "Ancient Liquid Envy", tier = "ancient", ladder = 5 },
		{ en = "Ancient Liquid Disgust", tier = "ancient", ladder = 6 },
		{ en = "Ancient Liquid Despair", tier = "ancient", ladder = 7 },
		{ en = "Ancient Concentrated Liquid Fear", tier = "ancient", ladder = 8 },
		{ en = "Ancient Concentrated Liquid Isolation", tier = "ancient", ladder = 9 },
		{ en = "Ancient Concentrated Liquid Suffering", tier = "ancient", ladder = 10 },
		{ en = "Ancient Potent Liquid Melancholy", tier = "ancient" },
		{ en = "Ancient Potent Liquid Ferocity", tier = "ancient" },
		{ en = "Ancient Potent Liquid Contempt", tier = "ancient" },
	},
	liquidEmotionsNote = "Instilling works on an amulet (three emotions in a fixed order grant one notable) or on a Waystone (a reward modifier). Three of one emotion reforge into one of the next rung up. The Ancient set is for Rare Time-Lost Jewels and does not instil amulets or Waystones.",
	-- Catalysts raise the quality of a ring, amulet or jewel, and they cover one modifier tag each -
	-- the choice of catalyst decides which modifiers get the quality. A catalyst replaces quality of
	-- another tag rather than stacking with it. Caps: ring or amulet 20%, Breach Ring 40%, Refined
	-- Breach Ring 45%; jewels take the Refined versions. (The table itself is defined above, next to
	-- the desecration bones, and mirrors the game's 26 catalyst names.)
	catalystsNote = "A catalyst raises the quality of the modifier tag it covers and replaces quality of another tag; ring or amulet caps at 20%, Breach Ring at 40%, Refined Breach Ring at 45%.",
	-- Essences our generated table is missing: it comes from PoB's Essence.lua, which has 81 of the
	-- game's 82. Essence of the Abyss is the one it does not carry, and it matters for desecration -
	-- it removes a random modifier and applies Mark of the Abyssal Lord, which the next desecration
	-- replaces with a desecrated modifier.
	missingEssences = {
		{ en = "Essence of the Abyss", text = "Removes a random modifier and applies Mark of the Abyssal Lord; the next desecration replaces that mark with a desecrated modifier." },
	},
	vaalInfusers = {
		{ en = "Vaal Armourer's Infuser", slot = "armour", raisesTo = 30, corruptRisk = true },
		{ en = "Vaal Blacksmith's Infuser", slot = "weapon", raisesTo = 30, corruptRisk = true },
		{ en = "Vaal Arcanist's Infuser", slot = "caster weapon", raisesTo = 30, corruptRisk = true },
		{ en = "Vaal Catalysing Infuser", slot = "jewellery", raisesTo = 30, corruptRisk = true },
	},

	-- The Genesis Tree: a whole crafting line that 0.5.0 created and that we had none of.
	-- It lives in The Monastery of the Keepers, consumes Wombgifts and Hiveblood (both from Breach monsters),
	-- and the NODES decide what comes out - which is why it cannot be reduced to "a currency drops".
	-- The line that matters most: since 0.5.0 catalysts no longer drop from monsters at all, so this is the
	-- only way to get the quality that jewellery and jewels need.
	-- Source: the official 0.5.0 notes as quoted by basicknowledge.xyz/poe2/craft/genesis-tree.
	genesisTree = {
		location = "Монастырь Хранителей (The Monastery of the Keepers), к югу от начала Атласа",
		locationEn = "The Monastery of the Keepers, south of the Atlas start",
		consumes = { "Wombgift", "Hiveblood" },
		produces = "кольца, амулеты, пояса и валюту; какие именно — решают ноды дерева",
		producesEn = "rings, amulets, belts and currency; the tree's nodes decide which",
		wombgifts = {
			{ en = "Lavish Wombgift", produces = "currency", producesRu = "валюту" },
			{ en = "Signet Wombgift", produces = "ring", producesRu = "кольцо" },
			{ en = "Ornate Wombgift", produces = "amulet", producesRu = "амулет" },
			{ en = "Banded Wombgift", produces = "belt", producesRu = "пояс" },
			{ en = "Revelatory Wombgift", produces = "breachstone", producesRu = "бреечстоун" },
		},
		-- The odds that matter for a crafter, and the reason one specific catalyst is hard to target.
		-- Confirmed by three independent sources (poe2wiki, fextralife, basicknowledge).
		catalystChance = 0.15,
		-- A second node: the chance to birth an EXTRA catalyst of the same type.
		duplicateCatalystChance = 0.30,
		refinedCatalystChance = 0.04,
		enhancedCreationChance = 0.10,
		breachRingChance = 0.10,
		refinedBreachRingChance = 0.05,
		-- Passives that change what a womb produces, and therefore change a crafting decision. A SUBSET on
		-- purpose: the tree carries dozens per womb and a full dump would be unreadable. Source: poewiki
		-- "The_Genesis_Tree", fetched 2026-10-20. Passives are freely refundable, so nothing here is a
		-- one-way choice.
		wombPassives = {
			{
				womb = "equipment",
				nodes = {
					{ name = "Modifier Tier Rating", kind = "small", effectEn = "+20 to Modifier Tier Rating",
						effectRu = "+20 к рейтингу тира модов" },
					{ name = "Divine Rolls", kind = "small",
						effectEn = "Values of random modifiers are rolled an additional time, keeping the best",
						effectRu = "Числа случайных модов перебрасываются ещё раз, берётся лучшее" },
					{ name = "Solid Cysts", kind = "notable",
						effectEn = "33% chance to be Fractured",
						effectRu = "33 % шанс, что предмет выйдет расколотым" },
					{ name = "Severing", kind = "notable",
						effectEn = "The lowest level Modifier is removed",
						effectRu = "Снимается мод с наименьшим уровнем" },
					{ name = "Arterial Mesh", kind = "notable",
						effectEn = "Sockets and Links rolled +50 times, keeping the best",
						effectRu = "Сокеты и связи перебрасываются +50 раз, берётся лучшее" },
					{ name = "Forsaken Soul", kind = "notable",
						effectEn = "Parent of the three 'reduced <type> modifier chance' passives",
						effectRu = "Родитель трёх пассивок «меньше модов <типа>»" },
					{ name = "Devoted Soul", kind = "notable",
						effectEn = "Parent of the 'increased <type> modifier chance' passives",
						effectRu = "Родитель пассивок «больше модов <типа>»" },
					{ name = "Increased Resistance Modifier Chance", kind = "notable",
						effectEn = "300% increased chance for Resistance Modifiers",
						effectRu = "300 % к шансу модов сопротивлений" },
					{ name = "Increased Life Modifier Chance", kind = "notable",
						effectEn = "300% increased chance for Life Modifiers",
						effectRu = "300 % к шансу модов здоровья" },
				},
			},
			{
				womb = "currency",
				nodes = {
					{ name = "Prodigal Offspring", kind = "notable",
						effectEn = "25% chance to birth 3 extra currency, 3% for 10",
						effectRu = "25 % шанс на 3 дополнительные валюты, 3 % — на 10" },
					{ name = "Fertile Genesis", kind = "notable",
						effectEn = "Currency is rolled an additional time, keeping the rarest outcome",
						effectRu = "Валюта перебрасывается ещё раз, берётся самый редкий исход" },
					{ name = "Wild Growth", kind = "notable",
						effectEn = "2% chance for birthed currency to drop as a full stack",
						effectRu = "2 % шанс, что валюта выйдет полным стеком" },
					{ name = "Mutation Cultivation", kind = "notable",
						effectEn = "25% extra currency; 100% increased chance for Graft Implants and Foulborn",
						effectRu = "25 % к дополнительной валюте; вдвое выше шанс имплантов и Foulborn" },
				},
			},
			{
				womb = "unique",
				nodes = {
					{ name = "Recessive Genes", kind = "notable",
						effectEn = "Uniques are rolled an additional time, keeping the rarest outcome - biases to T3/T4",
						effectRu = "Уникалка перебрасывается ещё раз, берётся редчайший исход — уклон к T3/T4" },
					{ name = "Cleansed of Impurity", kind = "notable",
						effectEn = "Birthed uniques have 100% reduced chance to be Foulborn",
						effectRu = "Осквернённая (Foulborn) версия не выпадет" },
					{ name = "Foulborn Gluttony", kind = "notable",
						effectEn = "30% chance for an extra item; +30% chance to be Foulborn",
						effectRu = "30 % шанс на лишний предмет; +30 % к шансу Foulborn" },
				},
			},
		},
		wombPassivesSource = "poewiki The_Genesis_Tree, снято 2026-10-20; это подмножество, а не весь список",
		wombPassivesSourceEn = "poewiki The_Genesis_Tree, fetched 2026-10-20; a subset, not the whole list",
		notes = {
			"С 0.5.0 катализаторы НЕ падают с монстров. Единственный источник — Genesis Tree.",
			"Выход не выбирается: его смещают ноды (шанс катализатора, запрет типов, «только катализаторы»).",
			"Refined-катализаторы (на ювелирку) проходят ДВА броска, поэтому заметно реже обычных.",
			"Три одинаковых катализатора продаются в один случайный.",
			"Breach Ring падает и так, а Refined Breach Ring — только из дерева: 10 %, затем 5 %.",
		},
		notesEn = {
			"Since 0.5.0 catalysts do NOT drop from monsters. The Genesis Tree is the only source.",
			"The output is not chosen: the nodes bias it (catalyst chance, forbidden types, 'catalysts only').",
			"Refined catalysts (for jewels) pass through TWO rolls, so they are noticeably rarer than ordinary ones.",
			"Three identical catalysts reforge into one random catalyst.",
			"A Breach Ring drops anyway; a Refined Breach Ring comes only from the tree: 10%, then 5%.",
		},
	},

	-- Currency that poe2db lists on its currency tab and that we had not recorded. Kept OUT of `currencies`
	-- on purpose: that table drives the methods picker, and none of these is a way to change an item's
	-- modifiers. Recording them closes the cross-check without teaching a beginner that a Scroll of Wisdom is
	-- a crafting method.
	otherCurrencies = {
		{
			en = "Mirror of Kalandra", effectEn = "Creates a copy of an item.",
			why = "дублирует готовый предмет; к изменению модов отношения не имеет",
			whyEn = "duplicates a finished item; nothing to do with changing modifiers",
			crafting = false,
		},
		{
			en = "Scroll of Wisdom", effectEn = "Identifies an item.",
			why = "опознание, а не крафт",
			whyEn = "identification, not crafting",
			crafting = false,
		},
		{
			en = "Lesser Jeweller's Orb", effectEn = "Sets a Skill Gem to have 3 Support Gem Sockets.",
			why = "сокеты КАМНЯ умения, не аффиксы предмета", crafting = false, target = "skill gem",
			whyEn = "sockets of a SKILL GEM, not the item's affixes",
		},
		{
			en = "Greater Jeweller's Orb", effectEn = "Sets a Skill Gem to have 4 Support Gem Sockets.",
			why = "сокеты КАМНЯ умения, не аффиксы предмета", crafting = false, target = "skill gem",
			whyEn = "sockets of a SKILL GEM, not the item's affixes",
		},
		{
			en = "Perfect Jeweller's Orb", effectEn = "Sets a Skill Gem to have 5 Support Gem Sockets.",
			why = "сокеты КАМНЯ умения; с 0.5.0 заметно реже", crafting = false, target = "skill gem",
			whyEn = "sockets of a SKILL GEM; noticeably rarer since 0.5.0",
		},
	},

	-- Quality above the ordinary 20%: every route, with what it costs. Kept as data because the panel used to
	-- hardcode 20 as "the cap" and told a 35% Breach Ring its quality was already maximal.
	-- Sources: poe2wiki (Vaal Infuser, Breach Ring), basicknowledge.xyz/poe2/craft/quality and /craft/breach.
	quality = {
		defaultMax = 20,
		-- Ordinary currency (scraps, whetstones, etchers, baubles, prisms, catalysts) cannot pass the default.
		ordinaryCurrencyCap = 20,
		infuserMax = 30,
		routes = {
			{
				id = "vaal_infuser",
				label = "Vaal-инфьюзер (Vaal Armourer's / Blacksmith's / Arcanist's / Catalysing)",
				labelEn = "Vaal Infuser (Vaal Armourer's / Blacksmith's / Arcanist's / Catalysing)",
				from = 20, to = 30,
				cost = "с шансом осквернить предмет: осквернённый предмет больше нельзя крафтить",
				costEn = "with a chance to corrupt the item: a corrupted item can no longer be crafted",
				applies = "броня, боевое и кастерское оружие, украшения",
				appliesEn = "armour, martial and caster weapons, jewellery",
			},
			{
				id = "breach_ring",
				label = "База Breach Ring: имплисит «Maximum Quality is 40%»",
				labelEn = "Breach Ring base: implicit 'Maximum Quality is 40%'",
				from = 20, to = 40,
				cost = "сама база дороже обычного кольца",
				costEn = "the base itself is more expensive than an ordinary ring",
				applies = "кольца",
				appliesEn = "rings",
			},
			{
				id = "refined_breach_ring",
				label = "База Refined Breach Ring: имплисит на +25% к максимуму",
				labelEn = "Refined Breach Ring base: implicit for +25% to the maximum",
				from = 20, to = 45,
				cost = "сама база; максимум среди всех баз",
				costEn = "the base itself; the highest ceiling of any base",
				applies = "кольца",
				appliesEn = "rings",
			},
			{
				id = "essence_of_the_breach",
				label = "Essence of the Breach: гарантированный мод «+20% to Maximum Quality»",
				labelEn = "Essence of the Breach: guaranteed '+20% to Maximum Quality' modifier",
				from = 20, to = 40,
				cost = "занимает единственный созданный слот предмета (с 0.5.0)",
				costEn = "uses the item's single crafted slot (since 0.5.0)",
				applies = "кольца и амулеты: даёт обычной базе потолок 40%",
				appliesEn = "rings and amulets: gives an ordinary base a 40% ceiling",
			},
			{
				id = "high_level_drop",
				label = "Дроп в областях высокого уровня: предмет может выпасть сразу с качеством до 30%",
				labelEn = "Drops in high-level areas: an item can drop with up to 30% quality",
				from = 20, to = 30,
				cost = "не управляется, только находится",
				costEn = "not controlled, only found",
				applies = "случайные предметы",
				appliesEn = "random items",
			},
		},
		-- Bases whose own implicit raises the quality ceiling. Kept by BASE NAME so the mentor can answer
		-- "which base should I buy" before the item is in hand - reading it from a captured item only helps
		-- after the purchase, which is exactly too late for the decision that costs money.
		baseCaps = {
			["Breach Ring"] = 40,
			["Refined Breach Ring"] = 45,
		},
		note = "Качество не занимает аффикс. У оружия оно даёт «more» к БАЗОВОМУ физическому урону, поэтому "
			.. "добавленный элементальный урон качеством не усиливается. У катализаторов своя система: один "
			.. "тип качества, каждый следующий катализатор заменяет предыдущий.",
		noteEn = "Quality does not take an affix. On a weapon it gives 'more' to BASE physical damage, so "
			.. "added elemental damage is not increased by quality. Catalysts are their own system: one "
			.. "quality type, and every further catalyst replaces the previous one.",
	},
	-- The four named Orbs of Sacrifice (0.5.4): they improve a corrupted enchantment at the cost of
	-- one random explicit modifier, and they work on twice-corrupted items too.
	orbsOfSacrifice = {
		{ en = "Kopec's Orb of Sacrifice", source = "Atziri" },
		{ en = "Yaomac's Orb of Sacrifice", source = "Atziri" },
		{ en = "Kamasa's Orb of Sacrifice", source = "Atziri" },
		{ en = "Yugul's Orb of Sacrifice", source = "Atziri" },
	},

	-- Runeforging's Ancient Runes, the Warding Runes and the Soul Cores now live in Data/runes.lua: the
	-- extractor used to drop them (its slot regex was anchored on one indentation, so 139 of the
	-- source's 305 runes never came through) and they were hand-written here as a stopgap. The extractor
	-- reads the table by brace depth now, so runes.lua carries all 305 runes across 21 slots and these
	-- hand-written copies are gone.

	-- Shards: the pieces that add a socket or a currency. They are the last names from the game's list
	-- that the overlay did not know at all. Artificer's Shards add a socket (ten of them at the salvage
	-- bench); the other three are the shard side of Transmutation, Regal and Chance.
	shards = {
		{ en = "Artificer's Shard", makes = "Artificer's Orb", text = "Ten shards make an Artificer's Orb, which adds an Augment Socket to an item." },
		{ en = "Transmutation Shard", makes = "Orb of Transmutation", text = "Shards of the Orb of Transmutation." },
		{ en = "Regal Shard", makes = "Regal Orb", text = "Shards of the Regal Orb." },
		{ en = "Chance Shard", makes = "Orb of Chance", text = "Shards of the Orb of Chance." },
	},

	-- Waystones (the endgame maps): tiers 1 to 16 and nothing else - the item is literally written
	-- "Waystone (Tier 15)", there is no base name, which is why nothing in our base table matched them.
	--
	-- The modifier pool is NOT in our data. Path of Building carries the stat descriptions for waystone
	-- modifiers but no spawn weights, and the trade API publishes only item names, so the panel cannot
	-- compute odds for a waystone the way it does for gear. What it can do is the mechanics:
	--   rolling   - a currency that rerolls modifiers works on a waystone; the tiers are not quality
	--   omens     - the four Chaotic omens exclude a reward type instead of guaranteeing it (0.5.0)
	--   instilling- a Liquid Emotion adds a reward modifier (rarity, rare monsters)
	--   corrupting- Vaal can move the tier by one, and T15 -> T16 happens ONLY this way
	waystones = {
		minTier = 1,
		maxTier = 16,
		-- Only a corruption can make a tier 16, which is why a tier 15 is worth keeping.
		tier16FromCorruption = true,
		modsInData = false,
		modsNote = "waystone modifier weights are not in Path of Building or the trade API, so the odds "
			.. "for a waystone are not computed here",
		-- Waystones are the ONE place where Chaos is a full reroll. The Omen of Chaotic ... records say it
		-- plainly: "your next Chaos Orb will replace all Modifiers on a [Waystone]". On equipment Chaos removes
		-- one random modifier and adds one; here it replaces the whole set, and the omens steer the result by
		-- forbidding one family. A mentor that taught "no full reroll" without this exception would be wrong
		-- for the item type endgame players craft most.
		-- Source: poe2db Waystones (0.5.5): Waystones Mods /107, Desecrated Waystone Mods /19, Omen of Chaotic
		-- texts.
		crafting = {
			rerollCurrency = "chaos",
			replacesAll = true,
			note = "На вейстоуне Chaos Orb заменяет ВСЕ моды, а не один. Это единственный предмет, где "
				.. "существует полный реролл.",
			noteEn = "On a Waystone the Chaos Orb replaces ALL modifiers, not one. It is the only item "
				.. "where a full reroll exists.",
		},
		-- Tier sets the monster level; the resist penalty is the game's own table.
		tierResistPenalty = {
			{ level = 1, penalty = 0 }, { level = 16, penalty = -10 }, { level = 33, penalty = -20 },
			{ level = 45, penalty = -30 }, { level = 54, penalty = -40 }, { level = 60, penalty = -50 },
			{ level = 65, penalty = -60 },
		},
		modPools = {
			{ id = "waystone", mods = 107 },
			{ id = "desecrated_waystone", mods = 19 },
		},
		-- The four omens that steer a waystone reroll by forbidding one family of modifiers.
		steeringOmens = {
			{ omen = "chaotic_rarity", excludes = "Item Rarity" },
			{ omen = "chaotic_quantity", excludes = "Pack Size" },
			{ omen = "chaotic_monsters", excludes = "Monster Rarity" },
			{ omen = "chaotic_effectiveness", excludes = "Monster Effectiveness" },
		},
	},

	-- Reforging Bench ("3-to-1"). Two different things share the name and both matter:
	--   upgrade - three of the same family member become one of the NEXT rung: runes (Lesser -> Normal ->
	--             Greater, same rune type), Liquid Emotions along the ten-rung ladder, Essences to a
	--             better tier (0.3.0 made this deterministic instead of random), catalysts into a random
	--             catalyst;
	--   recycle - three items of the same base type and the same rarity become one new item of that base
	--             with its modifiers rolled again. Three rares that each carry three modifiers can come
	--             back as an unidentified rare with four, which is the reason to do it at all.
	-- Conditions that decide whether the bench will accept the items:
	--   same base type and same rarity; uniques must also be the same unique
	--   corrupted and mirrored items cannot be reforged; a SANCTIFIED item can (checked against the
	--   project's own source, since we treat sanctified as unmodifiable everywhere else)
	--   Ancient Liquid Emotions do not reforge at all
	-- The panel cannot see the player's stash, so it states the rule and what the bench would take rather
	-- than counting items it cannot count.
	reforging = {
		requiredCount = 3,
		upgradeFamilies = {
			{ family = "runes", from = { "Lesser", "base" }, to = { "base", "Greater" },
				detail = "Three runes of the SAME rune become one of the next tier: 3 Lesser -> 1 base, 3 base -> 1 Greater." },
			{ family = "liquidEmotions", ladder = true,
				detail = "Three emotions of one rung become one of the next rung, up the ten-rung ladder. Ancient emotions do not reforge." },
			{ family = "essences", detail = "Three essences of a type become one of a better tier (deterministic since 0.3.0)." },
			{ family = "catalysts", detail = "Three catalysts become one random catalyst." },
		},
		recycleFamilies = {
			{ family = "gear", detail = "Same base type and same rarity; the result is that base with the modifiers rolled again." },
			{ family = "flasks", detail = "As gear: same base and rarity." },
			{ family = "jewels", detail = "As gear: same base (Ruby, Emerald, ...) and rarity." },
		},
		refuses = { corrupted = true, mirrored = true },
		allows = { sanctified = true },
		upgradesThreeModRares = true,
		note = "The bench works on three items at a time and the overlay cannot see your stash, so this is the rule rather than a count.",
	},

	-- Augment Sockets. A rune, soul core, idol or abyssal eye goes into a socket and applies ONE fixed
	-- modifier, which is why socket advice is about FIT rather than odds - the chance is 100% by
	-- definition. The item text prints the sockets as "Sockets: S S" (one letter per empty socket).
	--
	-- Capacity is what the base starts with; an Artificer's Orb adds one (ten Artificer's Shards at the
	-- salvage bench make it) and a Vaal Orb can add one beyond the cap while corrupting the item. What
	-- is already socketed is printed as "Rune: ...", and a socketed augment cannot be taken back out -
	-- only overwritten, which destroys the old one (Orb of Extraction destroys the item to return it).
	sockets = {
		capacity = {
			["body armour"] = 2,
			["two hand weapon"] = 2,
			["one hand weapon"] = 1,
			["helmet"] = 1,
			["gloves"] = 1,
			["boots"] = 1,
			["shield"] = 1,
			["buckler"] = 1,
			["focus"] = 1,
		},
		defaultCapacity = 1,
		artificerOrbAdds = 1,
		vaalOrbCanExceed = 1,
		removable = false,
		note = "A socketed augment cannot be removed, only overwritten - which destroys it.",
	},

	-- Mechanics and where their numbers come from: the official patch notes plus the PoB
	-- data files the weights are read from. Printed in the panel and in the README.
	sources = {
		{
			id = "weights",
			label = "Modifier weights",
			detail = "Path of Building PoE2: Data/ModItem.lua, ModVeiled.lua, ModRunes.lua (spawn weights), extracted by tools/extract_mods.py",
			url = "https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2",
		},
		{
			id = "league",
			label = "League 0.5.5 Forbidden Rites",
			detail = "official patch notes: omens, desecration, essences, runes, alloys",
			url = "https://www.pathofexile.com/forum/view-thread/4000864",
		},
		{
			id = "essences",
			label = "Essences",
			detail = "PoB Data/Essence.lua: guaranteed modifier per item class",
			url = "https://www.pathofexile.com/forum/view-thread/4000864",
		},
		{
			id = "runes",
			label = "Runes and soul cores",
			detail = "PoB Data/ModRunes.lua: guaranteed modifier per slot, per-item limit",
			url = "https://www.pathofexile.com/forum/view-thread/4000864",
		},
		{
			id = "runeforging",
			label = "Runeforging",
			detail = "PoB Data/VerisiumCrafts.lua: base types upgraded to Runeforged / Runemastered",
			url = "https://www.pathofexile.com/forum/view-thread/4000864",
		},
		{
			id = "desecration",
			label = "Desecration",
			detail = "PoB Data/ModVeiled.lua: pool tagged breach_desecration",
			url = "https://www.pathofexile.com/forum/view-thread/4000864",
		},
		{
			id = "codex",
			label = "Crafting codex (community)",
			detail = "community reference for league crafting routes",
			url = "https://domistae.github.io/poe2-leveling/poe2_crafting_codex.html",
		},
		{
			id = "omens_guide",
			label = "Omen list (community)",
			detail = "community list of omens and their effects",
			url = "https://timesaver.gg/blog/poe2-omens-guide",
		},
	},

	-- Ordered rules; the first match supplies the plan.
	rules = {
		{
			id = "locked",
			when = { anyFlag = { "corrupted", "sanctified", "mirrored" } },
			min = {},
			max = {},
			blockerEn = "Corrupted / sanctified / mirrored: modifiers cannot be changed. At most a Divine Orb reroll, if applicable.",
		},
		{
			id = "normal_base",
			when = { rarity = "NORMAL" },
			-- No quality entry here: the quality step is added by the advisor, for the item's own class
			-- currency, and placed after the modifier steps. Keeping the old "quality" placeholder in the
			-- list put it in front of the transmutation, which is the opposite of that order.
			min = { "transmutation" },
			max = { "transmutation", "augmentation", "essence", "regal", "greater_exalted", "greater_exalted", "vaal" },
			why = {
				min = "Дешёвый вход: волшебный предмет с одним модом как заготовка, дальше качество и остальное.",
				max = "Полный путь: Трансмутация → Аугментация → Эссенция на ключевой мод → Регал → добивка Экзальтами, затем качество.",
			},
			whyEn = {
				min = "Cheap entry: Magic with one mod as the crafting base, then quality and the rest.",
				max = "Full path: Magic -> Augmentation -> Essence for the key mod -> Regal -> Exalted fills, then quality.",
			},
		},
		{
			id = "magic_one_mod",
			when = { rarity = "MAGIC", maxAffixes = 1 },
			min = { "augmentation", "regal" },
			max = { "essence", "augmentation", "regal", "greater_exalted", "greater_exalted", "vaal" },
			why = {
				min = "Дёшево добить волшебный предмет до двух модов, затем поднять до редкого.",
				max = "Закрепить ключевой мод Эссенцией, пока предмет ещё волшебный, затем добить Экзальтами.",
			},
			whyEn = {
				min = "Cheaply fill Magic to two mods, then upgrade to Rare.",
				max = "Lock the key mod with an Essence while still Magic, then fill with Exalted orbs.",
			},
		},
		{
			-- A Magic item holds one prefix and one suffix. With both taken it is still NOT finished: a Regal
			-- Orb lifts the item to Rare and adds a third modifier while keeping the two that are there, because
			-- the cap rises with the rarity. The rule used to say the opposite - "Regal finds no room", "Regal
			-- would change nothing" - and planned no steps at all, so every full Magic item was told it was
			-- finished and offered quality instead. That is one of the most common states in the game: any
			-- two-mod base worth keeping.
			id = "magic_full",
			when = { rarity = "MAGIC", maxAffixes = 2, minAffixes = 2 },
			min = { "regal" },
			max = { "regal", "greater_exalted", "greater_exalted", "vaal" },
			blocker = "Оба аффикса волшебного предмета заняты, но предмет не закончен: Regal поднимет его до редкого и добавит "
				.. "третий мод, сохранив оба имеющихся.",
			blockerEn = "Both affixes of a Magic item are taken, but the item is not finished: a Regal Orb "
				.. "lifts it to Rare and adds a third modifier, keeping both that are already there.",
			why = {
				min = "У волшебного предмета заняты префикс и суффикс — добавить в них нечего. Regal поднимает редкость до редкой "
					.. "и добавляет третий мод, НЕ снимая первые два: это единственный шаг, который здесь строго "
					.. "улучшает предмет. Качество при этом не теряется и его можно добрать позже.",
				max = "Regal, затем добить открытые слоты Exalted и закрыть качеством; Vaal — последним и только "
					.. "если готовы потерять предмет.",
			},
			whyEn = {
				min = "Both a prefix and a suffix are taken, so nothing can be added to them. A Regal Orb raises "
					.. "the rarity to Rare and adds a third modifier WITHOUT removing the first two: it is the one "
					.. "move here that strictly improves the item. Quality is not lost and can be added later.",
				max = "Regal, then fill the open slots with Exalted, and close with quality; Vaal last, and only "
					.. "if you are willing to lose the item.",
			},
		},
		{
			id = "magic_two_mods",
			-- Only when the split is actually KNOWN. A Magic item's next step depends entirely on
			-- whether a slot is free, and for flasks and charms the plain Ctrl+C text often carries no
			-- prefix/suffix annotations, so a modifier can stay unrecognised. Applying this rule anyway
			-- is what told the customer to use a Regal Orb on a charm whose slots the engine could not
			-- see. With the split unknown, no rule is applied and the panel says so instead.
			when = { rarity = "MAGIC", requireSplit = true },
			min = { "regal" },
			max = { "essence", "regal", "greater_exalted", "greater_exalted", "greater_exalted", "vaal" },
			why = {
				min = "Волшебный предмет с двумя модами: Регал поднимет до редкого и добавит третий, сохранив оба.",
				max = "Эссенция на ключевой мод, затем Регал и добивка Экзальтами.",
			},
			whyEn = {
				min = "A single Regal Orb gives you a Rare item with three mods.",
				max = "If one mod is junk, an Essence overwrites it during the upgrade, then fill the remaining slots.",
			},
		},
		{
			-- Reachable only because Data/mods.lua classifies affixes: without it the
			-- overlay cannot know that only suffixes remain open.
			id = "rare_prefixes_full",
			when = { rarity = "RARE", maxOpenPrefixes = 0, minOpenSuffixes = 1 },
			min = { "exalted" },
			max = { "greater_exalted", "greater_exalted", "divine", "vaal" },
			why = {
				min = "Все три префикса заняты: следующая валюта может добавить только суффикс, так что терять нечего.",
				max = "Заполнить суффиксы Greater/Perfect Exalted, затем подстроить числа Divine.",
			},
			whyEn = {
				min = "All three prefixes are taken: the next orb can only add a suffix, so nothing can be lost.",
				max = "Fill the suffix slots with Greater/Perfect Exalted, then tune values with Divine.",
			},
		},
		{
			id = "rare_suffixes_full",
			when = { rarity = "RARE", maxOpenSuffixes = 0, minOpenPrefixes = 1 },
			min = { "exalted" },
			max = { "greater_exalted", "greater_exalted", "divine", "vaal" },
			why = {
				min = "Все суффиксы заняты: следующая валюта может добавить только префикс.",
				max = "Заполнить префиксы Greater/Perfect Exalted, затем подстроить числа Divine.",
			},
			whyEn = {
				min = "All suffixes are taken: the next orb can only add a prefix.",
				max = "Fill the prefix slots with Greater/Perfect Exalted, then Divine.",
			},
		},
		{
			id = "rare_open_affix",
			when = { rarity = "RARE", maxAffixes = 5 },
			min = { "exalted" },
			max = { "greater_exalted", "greater_exalted", "divine", "vaal" },
			why = {
				min = "Слот свободен — один Экзальт добавит мод, не рискуя уже имеющимися.",
				max = "Greater/Perfect Exalted поднимают минимальный уровень модов, затем Divine подстраивает числа.",
			},
			whyEn = {
				min = "A slot is open - one Exalted Orb adds a mod without risking the existing ones.",
				max = "Greater/Perfect Exalted raise the minimum mod level, then Divine tunes the values.",
			},
		},
		{
			id = "rare_full",
			-- "No free slots" has to mean that. This rule used to match ANY rare item, and because it sits
			-- after the slot-aware rules it acted as the catch-all for every rare that did not match them -
			-- including an item with an open suffix when its split came out wrong upstream (the sceptre: a
			-- chaos reroll advised on a five-modifier item that still had room). The affix count is now
			-- part of the condition, so a full item is required rather than assumed.
			when = { rarity = "RARE", minAffixes = 6, maxAffixes = 6 },
			min = { "chaos" },
			max = { "omen", "chaos", "divine", "vaal" },
			why = {
				min = "Все шесть модов заняты: добавить некуда. Chaos — самый дешёвый шаг, но он снимает "
					.. "СЛУЧАЙНЫЙ мод: может уйти лучший. Чтобы заменить именно слабый, нужен Omen of Whittling — "
					.. "с ним снимается мод худшего тира. Если моды устраивают, ничего не трогайте и поднимите "
					.. "качество — это дешевле.",
				max = "Omen of Whittling отбирает худший мод, Chaos заменяет его, Divine подстраивает числа, "
					.. "качество добавляется в конце; Vaal — последним и необратимо.",
			},
			whyEn = {
				min = "No free slots. Chaos is the cheap move, but it removes a RANDOM modifier - it can take "
					.. "your best one. To replace a specific weak affix you need the Omen of Whittling. If the "
					.. "modifiers are fine, leaving them alone and raising quality is cheaper.",
				max = "The Omen of Whittling picks the worst-tier modifier, Chaos replaces it, Divine tunes the "
					.. "values, quality closes; Vaal last and irreversible.",
			},
		},
		{
			id = "unique",
			when = { rarity = "UNIQUE" },
			min = { "quality", "divine" },
			max = { "quality", "divine", "rune", "vaal" },
			why = {
				min = "Уникальные предметы нельзя крафтить модами: только качество и переброс чисел Divine.",
				max = "Качество + Divine на хорошие числа + руны в сокеты.",
			},
			whyEn = {
				min = "Uniques cannot be crafted with modifiers: quality and a Divine reroll only.",
				max = "Quality + Divine for good rolls + runes into sockets.",
			},
		},
	},


	glossaryEn = {
		quality = "Quality first: it multiplies base numbers, and once mods are on you cannot recompute them.",
		essence = "An Essence is the only way to GUARANTEE a specific mod - pick it for the stat your build needs.",
		greater_exalted = "Greater/Perfect orbs cost more but raise the added mod's minimum level - that is the 'max' route.",
		omen = "Omens are expensive; use them only when the item is already nearly perfect.",
		divine = "A Divine Orb changes mod values, not the mod set - it is the last step, not the first.",
		alloy = "An alloy shares the item's single crafted-mod slot with essences: you pick exactly one route.",
	},

}
