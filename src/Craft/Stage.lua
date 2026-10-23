-- PoE2 Craft Overlay : Craft/Stage.lua
-- What stage of the game the player is at, and therefore which methods are worth offering.
--
-- Why this exists. Every serious guide says the same thing and the videos say it too: during the campaign you
-- use Transmutation, Augmentation and Regal, and you SAVE Exalted, Chaos, Divine and Vaal for endgame - not
-- because they are bad, but because campaign gear is replaced within a few levels. The overlay used to offer
-- whatever was possible, so a level-40 player was told to spend an Exalted Orb on boots he would replace in
-- Act 5. That is the single most expensive piece of beginner advice, and it is the one thing every guide
-- agrees on.
--
-- The stage is a judgement, so it is made from what the item itself proves (its item level) and only then
-- from the player's own choice, which can override it.
local Stage = { }

--- The three stages, cheapest first.
Stage.ORDER = { "campaign", "early", "endgame" }

Stage.LABELS = {
	campaign = "Кампания (до карт)",
	early = "Ранний эндгейм",
	endgame = "Эндгейм",
}

-- English twins. Kept next to the Russian ones so a stage cannot be named in one language and described
-- in the other; Mcp/api.lua picks one pair for the whole card.
Stage.LABELS_EN = {
	campaign = "Campaign (before maps)",
	early = "Early endgame",
	endgame = "Endgame",
}

-- The "do not spend this yet" sentence, per language and stage, split from the label so the two parts
-- cannot drift apart (the label is used on its own elsewhere).
Stage.NOT_ALLOWED = {
	ru = ": на этой стадии этот способ не тратят — предмет будет заменён раньше, чем окупится.",
	en = ": this method is not spent at this stage - the item is replaced before it pays for itself.",
}

Stage.DESCRIBE = {
	ru = {
		endgame = ": можно всё, включая необратимое — но только на предмете, который вы оставите.",
		campaign = ": Transmute/Augment/Regal, эссенции и руны. Exalted, Chaos, Divine и Vaal — копить.",
		early = ": добавка Exalted и точечный Chaos уже имеют смысл; Divine — только на предмет, который останется.",
	},
	en = {
		endgame = ": everything is allowed, including the irreversible - but only on an item you will keep.",
		campaign = ": Transmute/Augment/Regal, essences and runes. Save Exalted, Chaos, Divine and Vaal.",
		early = ": an Exalted top-up and a targeted Chaos already make sense; Divine only on an item that stays.",
	},
}

--- The two words a caller needs for one stage, in one language.
-- @param stage stage id
-- @param lang "ru" (default) or "en"
function Stage.words(stage, lang)
	local key = (lang == "en") and "en" or "ru"
	return Stage[key == "en" and "LABELS_EN" or "LABELS"][stage] or tostring(stage or "?"),
		Stage.DESCRIBE[key]
end

--- Which currencies each stage is allowed to spend on a craft that is not yet worth much.
--
-- The rule is not "cheap currency only": it is "do not spend what a replacement item would cost". An Exalted
-- Orb during the campaign is usually worth more than the boots it is spent on, which is exactly what the
-- guides warn about. Chaos and Divine are in the same class: they are for an item you intend to keep.
Stage.ALLOWED = {
	campaign = {
		transmutation = true, greater_transmutation = true,
		augmentation = true, greater_augmentation = true,
		regal = true, greater_regal = true,
		alchemy = true,
		quality = true, whetstone = true, scrap = true, etcher = true, bauble = true, prism = true,
		-- An essence is allowed: a guaranteed mod on a keepable base is the cheapest real upgrade, and
		-- essences are the one "control" layer a beginner should learn early.
		essence = true,
		-- Runes and the socket currency are free, deterministic and never wasted.
		rune = true,
	},
	early = {
		transmutation = true, greater_transmutation = true,
		augmentation = true, greater_augmentation = true,
		regal = true, greater_regal = true,
		alchemy = true,
		exalted = true, greater_exalted = true,
		essence = true, rune = true,
		quality = true, whetstone = true, scrap = true, etcher = true, bauble = true, prism = true,
		annulment = true,
		-- Chaos starts here: it is the tool for fixing one bad modifier on an item worth keeping.
		chaos = true,
	},
	endgame = {
		-- Everything, including the irreversible ones.
		all = true,
	},
}

--- The stage an item level suggests, when the player has not said where he is.
-- @param itemLevel item level of the captured item
-- @return stage id
function Stage.forItemLevel(itemLevel)
	local level = tonumber(itemLevel) or 0
	if level <= 0 then
		return "endgame" -- unknown: never restrict on a guess
	end
	-- Campaign gear is roughly below the map tier; endgame starts once the item level is high enough for
	-- the top tiers of the modifiers that matter (the guides use 60-70 as the boundary).
	if level < 50 then
		return "campaign"
	end
	if level < 75 then
		return "early"
	end
	return "endgame"
end

--- Can this stage spend this currency or method at all?
-- @param stage stage id, or nil to allow everything
-- @param method currency id or method name
-- @return allowed, reason (reason only when not allowed)
function Stage.allows(stage, method)
	local allowed = Stage.ALLOWED[stage]
	if not allowed or allowed.all then
		return true
	end
	local key = tostring(method or "")
	if allowed[key] then
		return true
	end
	-- The engine names some things by their full title ("Exalted Orb", "Arcanum's Essence"). Falling back
	-- to a substring keeps this list in one place instead of duplicating every spelling in the ruleset.
	local lowered = key:lower()
	if lowered:find("transmutation", 1, true) and allowed.transmutation then return true end
	if lowered:find("augmentation", 1, true) and allowed.augmentation then return true end
	if lowered:find("regal", 1, true) and allowed.regal then return true end
	if lowered:find("essence", 1, true) and allowed.essence then return true end
	if lowered:find("rune", 1, true) and allowed.rune then return true end
	return false, (Stage.LABELS[stage] or stage or "?") .. Stage.NOT_ALLOWED.ru
end

--- The same refusal as Stage.allows, in English.
-- Callers that answer in another language use this instead of translating the sentence themselves.
function Stage.refusalEn(stage)
	return (Stage.LABELS_EN[stage] or tostring(stage or "?")) .. Stage.NOT_ALLOWED.en
end

--- Currencies that are irreversible, or that cost more than the item is worth at this stage.
function Stage.isSaveForLater(stage, method)
	if Stage.allows(stage, method) then
		return false
	end
	return true
end

--- One line for the panel: what the stage is and what it forbids.
-- @param stage stage id
-- @param lang language code
-- @return string
function Stage.describe(stage, lang)
	local key = (lang == "en") and "en" or "ru"
	local labels = (key == "en") and Stage.LABELS_EN or Stage.LABELS
	local label = labels[stage] or tostring(stage or "?")
	return label .. Stage.DESCRIBE[key][stage]
end

return Stage
