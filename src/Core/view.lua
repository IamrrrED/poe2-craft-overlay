-- PoE2 Craft Overlay : Core/view.lua
-- Pure display decisions: how much of the advice is expanded, and which optional
-- sections are shown. Kept separate from Launch.lua so it can be tested headless,
-- and so "collapse the crafting method into a block" is a data decision, not a
-- tangle of conditionals inside the drawing code.

local view = { }

-- Detail levels, cycled by the detail hotkey:
--   1 compact  - one line per step: currency name, cost, nothing else
--   2 normal   - + short effect description and the single best roll chance
--   3 detailed - + tips, warnings and the full roll-chance list
view.MIN_DETAIL = 1
view.MAX_DETAIL = 3
view.DEFAULT_DETAIL = 2

--- Section toggles and their defaults. Bulky sections start collapsed so the overlay
-- does not cover half the screen; the footer shows the keys that expand them.
-- Collapsible panel blocks, in the order they are drawn. Each block has a header with
-- a [+]/[-] marker; the marker is clickable in interactive mode (F9) and every block
-- also has a hotkey, so the panel can be folded without a mouse.
view.BLOCKS = { "item", "plans", "league", "notes" }

view.BLOCK_LABEL = {
	item = "sectionItem",
	plans = "sectionPlans",
	league = "sectionOmens",
	notes = "sectionNotes",
}

view.BLOCK_HOTKEY = {
	item = "toggleItem",
	plans = "togglePlans",
	league = "toggleOmens",
	notes = "toggleNotes",
}

-- Section state and its defaults. The bulky league-methods block starts collapsed so
-- the overlay does not cover half the screen.
view.DEFAULT_SECTIONS = {
	item = true,       -- rarity, class, base, item level, affixes
	modTiers = true,   -- per-modifier tier lines inside the item block
	plans = true,      -- MIN / MAX crafting plans
	league = false,    -- omens, desecration and essence crafts
	notes = true,      -- parser/advisor notes
	omens = false,     -- legacy alias of `league`
}

function view.clampDetail(level)
	level = tonumber(level) or view.DEFAULT_DETAIL
	if level < view.MIN_DETAIL then
		return view.MIN_DETAIL
	end
	if level > view.MAX_DETAIL then
		return view.MAX_DETAIL
	end
	return level
end

--- Cycle the detail level (used by the detail hotkey).
function view.cycleDetail(level)
	local next_ = view.clampDetail(level) + 1
	if next_ > view.MAX_DETAIL then
		next_ = view.MIN_DETAIL
	end
	return next_
end

function view.showEffect(level)
	return view.clampDetail(level) >= 2
end

function view.showTopChance(level)
	return view.clampDetail(level) >= 2
end

function view.showOdds(level)
	return view.clampDetail(level) >= 3
end

function view.showHints(level)
	return view.clampDetail(level) >= 3
end

--- Normalized section state (missing keys fall back to the defaults).
-- The legacy `omens` key mirrors `league`, so a config that only sets one of them
-- still behaves as expected.
function view.sectionsFor(sections)
	local out = { }
	for key, default in pairs(view.DEFAULT_SECTIONS) do
		if sections and sections[key] ~= nil then
			out[key] = sections[key] and true or false
		else
			out[key] = default
		end
	end
	if sections then
		if sections.league ~= nil and sections.omens == nil then
			out.omens = sections.league and true or false
		elseif sections.omens ~= nil and sections.league == nil then
			out.league = sections.omens and true or false
		end
	end
	return out
end

--- How many league crafting options the panel lists at a detail level.
-- Level 3 is the "show me everything" level, so it lists every option; the lower levels
-- stay short, which is what keeps the overlay small during play.
function view.optionLimit(detail)
	if detail >= 3 then
		return math.huge
	end
	if detail <= 1 then
		return 1
	end
	return 3
end

--- Toggle one section, returning the new value.
function view.toggleSection(sections, key)
	local current = view.sectionsFor(sections)
	current[key] = not current[key]
	return current[key]
end

--- Is a section visible?
function view.sectionVisible(sections, key)
	local state = view.sectionsFor(sections)
	if key == "omens" then
		return state.league == true
	end
	if key == "league" then
		return state.league == true
	end
	return state[key] == true
end

--- Marker drawn in front of a block header: expanded or collapsed.
function view.blockMarker(expanded)
	return expanded and "[-]" or "[+]"
end

--- All blocks with their label key, hotkey and expansion state, in draw order.
function view.blocks(sections)
	local state = view.sectionsFor(sections)
	local list = { }
	for _, key in ipairs(view.BLOCKS) do
		list[#list + 1] = {
			key = key,
			labelKey = view.BLOCK_LABEL[key],
			hotkey = view.BLOCK_HOTKEY[key],
			expanded = state[key] == true,
		}
	end
	return list
end

--- Row index under a Y coordinate, used for click-to-collapse.
-- @param rows list of { size = number } in draw order
-- @param y coordinate to test (same units the rows are drawn in)
-- @param originY y of the first row
-- @param spacing extra pixels added to each row's size
-- @return index or nil
function view.rowAt(rows, y, originY, spacing)
	local cursor = originY or 0
	spacing = spacing or 7
	for index, row in ipairs(rows) do
		local height = (row.size or 12) + spacing
		if y >= cursor and y < cursor + height then
			return index
		end
		cursor = cursor + height
	end
	return nil
end

--- Human-readable detail level name key (localised by the caller).
function view.detailNameKey(level)
	local names = { "detailCompact", "detailNormal", "detailDetailed" }
	return names[view.clampDetail(level)] or "detailNormal"
end

--- Wrap-around index stepping, used when cycling font variants (and anything else
-- that is a list the user pages through with a hotkey).
function view.nextVariantIndex(currentIndex, count, step)
	if count <= 0 then
		return 0
	end
	local index = (currentIndex or 1) + (step or 1)
	while index > count do
		index = index - count
	end
	while index < 1 do
		index = index + count
	end
	return index
end

-- Text scale bounds. Below ~70% Cyrillic stops being readable at 1080p and above
-- 150% the panel covers too much of the game.
view.MIN_TEXT_SCALE = 0.70
view.MAX_TEXT_SCALE = 1.60
view.MIN_TEXT_SIZE = 9

--- Clamp a text scale into the allowed range (also used to sanitise saved prefs).
function view.clampTextScale(scale)
	scale = tonumber(scale) or 1
	if scale < view.MIN_TEXT_SCALE then
		return view.MIN_TEXT_SCALE
	end
	if scale > view.MAX_TEXT_SCALE then
		return view.MAX_TEXT_SCALE
	end
	return scale
end

--- Apply the text scale to a font size, keeping a readable minimum.
function view.scaledSize(size, scale)
	local scaled = (tonumber(size) or 12) * view.clampTextScale(scale)
	return math.max(view.MIN_TEXT_SIZE, math.floor(scaled + 0.5))
end

return view
