-- PoE2 Craft Overlay : Core/strings.lua
-- Every user-visible interface string, English only.
--
-- The panel used to be bilingual (Russian with the English name in brackets). Russian
-- was removed on request: the official localisation only covers part of the item and
-- modifier pool (1536 of 1769 base types, 518 of 687 modifier texts), which made the
-- output a mix of two languages. There is no language switch any more, and the helper
-- functions that used to take a `lang` argument keep their signature so call sites do
-- not need to change - they simply ignore it and return English.

local Strings = { }

-- Kept for call sites that still pass a language around; always English.
-- Default is English; the panel follows the game client's language, which is detected from the
-- item text the game itself copies (see Item/Ru.lua) and applied by the launcher.
Strings.lang = "en"

local UI = {
	appTitle = "PoE2 Craft Overlay",
	leagueLabel = "league %s",
	howTo = "How to use:",
	howTo1 = "1. Hover an item in game (inventory, crafting bench, trade window).",
	howTo2 = "2. Press %s - the overlay sends Ctrl+C to the game and reads the clipboard.",
	howTo3 = "3. MIN (lowest budget) and MAX (best result) plans appear below.",
	howTo4 = "%s demo item, %s clickable window, %s quit.",
	sectionItem = "--- Item ---",
	sectionPlans = "--- Plans ---",
	sectionOmens = "--- League crafting methods ---",
	sectionNotes = "--- Notes ---",
	essenceLine = "guaranteed: %s (T%d, mod level %d) - %d%%",
	runeLine = "guaranteed: %s - %d%%, limit %d per item%s",
	runeLevel = ", requires level %d",
	modLevelShort = "mod level",
	runeType = {
		Rune = "Rune",
		SoulCore = "Soul core",
		Idol = "Idol",
		AbyssalEye = "Abyssal eye",
		CongealedMist = "Congealed mist",
	},
	alloyTitle = "Alloys (Verisium): modifier pool",
	alloyNote = "alloy modifiers carry zero spawn weight in PoB data, so their odds are not computable - only the pool is shown",
	alloyList = "Alloys: %s",
	runeforgingLine = "Runeforging: %s turns into %s",
	sourcesTitle = "Data sources:",
	sourceLine = "* %s - %s (%s)",
	omenAtLeastOnce = "at least one of %d rolls: %.2f%% (single roll %.2f%%)",
	omenRemoves = "removes: %s (mod level %d)",
	omenRemovesSide = "removes only a %s; %.1f%% chance to hit the right modifier",
	omenOddsUnknown = "odds not shown",
	omenNoOdds = "odds not computed: PoB carries no weights for this pool",
	-- Jewellery quality: a catalyst covers one modifier tag, so the panel lists the catalysts that
	-- match a modifier the item already has and leaves the choice to the player.
	catalystShortlist = "matching catalysts: %s",
	-- Instilling, from Liquid Emotions. The recipe lives in the game, not in our data.
	instilHow = "%d Liquid Emotions exist; a recipe is three of them in a fixed order, and the current combinations are shown in game by holding Alt over the notable",
	instilAlready = "this item is already instilled: instilling again replaces the notable and spends the emotions (%d in the catalogue)",
	-- Waystones.
	waystoneTierRule = "tier %d: a currency rerolls the modifiers, and tier 16 exists only by corrupting a tier 15",
	waystoneNoTier = "the tier is printed on the item; a currency rerolls the modifiers",
	-- Short on purpose: the price sits in the panel's right-hand column, and the long wording
	-- used to stretch that column across half the panel.
	stepPrice = "price %.2f %s / CoE",
	revealLine = "reveal: %d of %d eligible mods are offered, so the best group appears in %.2f%% of reveals (%.2f%% with Abyssal Echoes)",
	noSteps = "(no steps)",
	tipLabel = "tip: ",
	chancesHeader = "chances (%d eligible tiers, %s%s):",
	chancesSideBoth = "both sides",
	chancesSidePrefix = "prefixes",
	chancesSideSuffix = "suffixes",
	chancesFloor = ", min mod level %d",
	removalLine = "removal: %.1f%% per modifier (%d mods on the item)",
	rollPoolLine = "Random roll pool on %s: %d mod groups, average best tier T%.1f, T1 reachable in %d (%.0f%%)",
	noRule = "no rule",
	truncated = "... (list truncated)",
	footer = "%s capture | %s panel | %s demo | %s click | %s quit",
	footerSections = "%s (%s) | %s item | %s plans | %s league",
	footerFont = "^%s/%s/%s font | ^%s/%s/%s size",
	blockCollapsed = "collapsed (%s to expand)",
	detailCompact = "compact",
	detailNormal = "normal",
	detailDetailed = "detailed",
	statusDetail = "Detail level: %s",
	statusSectionOn = "Section expanded: %s",
	statusSectionOff = "Section collapsed: %s",
	sectionMods = "modifier tiers",
	sectionNotesShort = "notes",
	omitted = "collapsed: %s (%s)",
	statusHover = "Hover an item in game and press %s",
	statusSummary = "%s | rule: %s | mods: %d",
	statusParseFail = "Could not parse the item (%s)",
	statusCleared = "Cleared. Hover an item and press %s",
	statusNoGameWindow = "Game window not found: copy the item yourself (Ctrl+C), then press %s",
	statusClipboardEmpty = "Clipboard is empty - the item was not copied",
	statusGrabbing = "Reading the item picture (%s)...",
	statusOcrEmpty = "Could not read the tooltip; copied the item instead - check the local site",
	statusDemoMissing = "Demo item not found: %s",
	statusClickable = "Clickable mode: drag the window, %s to restore the overlay",
	statusOverlay = "Overlay mode (clicks pass through)",
	statusError = "ERROR: %s",
	statusOverlayWindowMissing = "Overlay window not found; styling skipped",
	statusFont = "Font: %s (%d of %d) - %s next, %s previous, %s save",
	statusFontSaved = "Font saved: %s",
	statusFontNoVariants = "No glyph atlases found: build them with tools/build_fonts.ps1",
	statusSpacing = "Letter spacing: %d%% (%s tighter, %s looser)",
	statusTextScale = "Text scale: %d%% (%s smaller, %s larger)",
}

-- Russian interface strings for the panel. Only the keys listed here are translated; every other
-- key falls back to English, so the table can grow one label at a time without touching the rest.
-- The glyph atlases carry Cyrillic (see Core/font.lua), so these can be drawn as they are.
local UI_RU = {
	sectionItem = "Предмет",
	sectionPlans = "План крафта",
	sectionOmens = "Омены и десакрация",
	sectionNotes = "Заметки",
	statusOverlay = "Режим оверлея (клики проходят сквозь)",
	statusClickable = "Режим кликов: тяни окно, %s — вернуть оверлей",
	statusClipboardEmpty = "Буфер обмена пуст — предмет не скопирован",
	statusGrabbing = "Читаю картинку предмета (%s)...",
	statusError = "ОШИБКА: %s",
}

--- Interface string by key, with optional printf-style arguments.
-- `lang` == "ru" takes the Russian table where it has the key and falls back to English otherwise.
function Strings.t(lang, key, ...)
	local text = (lang == "ru" and UI_RU[key]) or UI[key]
	if text == nil then
		return tostring(key)
	end
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, text, ...)
		if ok then
			return formatted
		end
	end
	return text
end

--- Name of a game object. Russian was removed, so the English name is returned.
function Strings.name(lang, ruName, enName)
	if enName and enName ~= "" then
		return tostring(enName)
	end
	return tostring(ruName or "")
end

--- Game label as displayed: item properties and other short labels.
-- The engine keeps everything English internally, because the parser translates the Russian client
-- text into English on the way in. A Russian panel therefore needs the opposite direction, and that
-- dictionary is generated by inverting the parser's own pairs (tools/build_display_ru.py), so the
-- two directions cannot drift apart. Labels it does not cover are shown as they are.
function Strings.displayLabel(text, lang)
	if (lang or Strings.lang) ~= "ru" then
		return tostring(text or "")
	end
	local ok, data = pcall(require, "Data.display_ru")
	if ok and type(data) == "table" and type(data.labels) == "table" then
		return data.labels[text] or tostring(text or "")
	end
	return tostring(text or "")
end

--- Modifier line as displayed. Modifier texts are always shown in English, which is
-- exactly what the game and the trade site use.
function Strings.modText(text, lang)
	return tostring(text)
end

--- Modifier line for the panel: the English text.
function Strings.modName(text, lang)
	return tostring(text)
end

--- Game term (item class, rarity, flag). English only.
function Strings.term(kind, text, lang)
	return tostring(text or "")
end

--- Base type name. English only.
function Strings.baseName(name, lang)
	return tostring(name or "")
end

--- Rune / soul-core type name, still mapped for readability ("SoulCore" -> "Soul core").
function Strings.runeType(typeKey, lang)
	local key = tostring(typeKey)
	return UI.runeType[key] or key
end

--- All keys defined by the single interface table (used by tests).
function Strings.keys()
	local keys = { }
	for key in pairs(UI) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

return Strings
