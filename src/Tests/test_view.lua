-- PoE2 Craft Overlay : Tests/test_view.lua
-- Display decisions (detail levels, collapsible sections) and panel placement. Both
-- are pure functions precisely so they can be checked without a renderer.

local View = require("Core.view")
local util = require("Core.util")

return function(H)
	-- Detail levels: clamped, cycled, and each level enables the right amount of text.
	-- How many league options a detail level lists: level 3 means "everything".
	H.eq("view: compact detail lists one option", View.optionLimit(1), 1)
	H.eq("view: normal detail lists three options", View.optionLimit(2), 3)
	H.eq("view: detailed level lists every option", View.optionLimit(3) > 100, true)
	H.eq("view: default detail level", View.DEFAULT_DETAIL, 2)
	H.eq("view: level below range clamped", View.clampDetail(0), 1)
	H.eq("view: level above range clamped", View.clampDetail(99), 3)
	H.eq("view: junk level falls back to default", View.clampDetail("nonsense"), 2)

	H.eq("view: cycle compact -> normal", View.cycleDetail(1), 2)
	H.eq("view: cycle normal -> detailed", View.cycleDetail(2), 3)
	H.eq("view: cycle detailed -> compact", View.cycleDetail(3), 1)

	H.eq("view: compact hides the effect text", View.showEffect(1), false)
	H.eq("view: normal shows the effect text", View.showEffect(2), true)
	H.eq("view: normal hides tips", View.showHints(2), false)
	H.eq("view: detailed shows tips", View.showHints(3), true)
	H.eq("view: normal shows the single best chance", View.showTopChance(2), true)
	H.eq("view: normal hides the full odds list", View.showOdds(2), false)
	H.eq("view: detailed shows the full odds list", View.showOdds(3), true)

	H.eq("view: compact level name", View.detailNameKey(1), "detailCompact")
	H.eq("view: detailed level name", View.detailNameKey(3), "detailDetailed")

	-- Sections: bulky blocks start collapsed so the overlay stays small.
	local defaults = View.sectionsFor(nil)
	H.eq("view: omens collapsed by default", defaults.omens, false)
	H.eq("view: mod tiers shown by default", defaults.modTiers, true)
	H.eq("view: notes shown by default", defaults.notes, true)

	local custom = View.sectionsFor({ omens = true, modTiers = false })
	H.eq("view: explicit omen state honoured", custom.omens, true)
	H.eq("view: explicit mod tier state honoured", custom.modTiers, false)
	H.eq("view: unspecified section keeps its default", custom.notes, true)

	local toggled = View.toggleSection({ omens = false }, "omens")
	H.eq("view: toggle flips a section", toggled, true)
	H.eq("view: toggle is visible through sectionVisible",
		View.sectionVisible({ omens = true }, "omens"), true)

	-- Index stepping for hotkey-driven cycling (font variants use this).
	H.eq("view: step forward", View.nextVariantIndex(1, 5, 1), 2)
	H.eq("view: step wraps forward", View.nextVariantIndex(5, 5, 1), 1)
	H.eq("view: step backward", View.nextVariantIndex(3, 5, -1), 2)
	H.eq("view: backward wraps", View.nextVariantIndex(1, 5, -1), 5)
	H.eq("view: works for larger jumps", View.nextVariantIndex(4, 5, -6), 3)
	H.eq("view: empty list yields zero", View.nextVariantIndex(1, 0, 1), 0)

	-- Collapsible blocks: the panel's groups all fold, each with a marker and hotkey.
	local blocks = View.blocks(nil)
	H.eq("view: four collapsible blocks", #blocks, 4)
	H.eq("view: first block is the item", blocks[1].key, "item")
	H.eq("view: second block is the plans", blocks[2].key, "plans")
	H.eq("view: third block is the league methods", blocks[3].key, "league")
	H.eq("view: fourth block is the notes", blocks[4].key, "notes")
	H.eq("view: item block starts expanded", blocks[1].expanded, true)
	H.eq("view: league block starts collapsed", blocks[3].expanded, false)
	H.eq("view: every block has a label key", (function()
		for _, block in ipairs(blocks) do
			if type(block.labelKey) ~= "string" or type(block.hotkey) ~= "string" then
				return false
			end
		end
		return true
	end)(), true)
	H.eq("view: expanded marker", View.blockMarker(true), "[-]")
	H.eq("view: collapsed marker", View.blockMarker(false), "[+]")
	local folded = View.blocks({ item = false, league = true })
	H.eq("view: collapsing the item block", folded[1].expanded, false)
	H.eq("view: expanding the league block", folded[3].expanded, true)

	-- Click hit-testing: the row under the cursor can be found, edges included.
	local rows = { { size = 10 }, { size = 20, block = "plans" }, { size = 10 } }
	H.eq("view: first row hit", View.rowAt(rows, 0, 0, 7), 1)
	H.eq("view: row boundary belongs to the next row", View.rowAt(rows, 17, 0, 7), 2)
	H.eq("view: header row is found", rows[View.rowAt(rows, 20, 0, 7)].block, "plans")
	H.eq("view: last row hit", View.rowAt(rows, 53, 0, 7), 3)
	H.eq("view: below the last row is nothing", View.rowAt(rows, 200, 0, 7), nil)

	-- Text scale: clamped, rounded, never below the readability floor.
	H.eq("view: scale clamps low", View.clampTextScale(0.2), View.MIN_TEXT_SCALE)
	H.eq("view: scale clamps high", View.clampTextScale(9), View.MAX_TEXT_SCALE)
	H.eq("view: junk scale falls back to 1", View.clampTextScale("nope"), 1)
	H.eq("view: size unchanged at 100%", View.scaledSize(12, 1), 12)
	H.eq("view: size scales down", View.scaledSize(16, 0.75), 12)
	H.eq("view: size scales up", View.scaledSize(10, 1.5), 15)
	H.eq("view: size never below the floor", View.scaledSize(11, View.MIN_TEXT_SCALE), View.MIN_TEXT_SIZE)

	-- Panel placement: centred when it fits, clamped so it never leaves the screen.
	local x, y = util.centerPosition(2560, 1440, 700, 900)
	H.eq("view: centre x", x, 930)
	H.eq("view: centre y", y, 270)

	local cx, cy = util.centerPosition(2560, 1440, 700, 900, 8)
	H.eq("view: margin does not move a fitting panel", cx, 930)
	H.eq("view: margin does not move a fitting panel vertically", cy, 270)

	local sx, sy = util.centerPosition(600, 400, 700, 900, 8)
	H.eq("view: oversized panel clamps to the margin", sx, 8)
	H.eq("view: oversized panel clamps vertically", sy, 8)

	-- A panel taller than the screen is pinned to the margin instead of going negative.
	local tx, ty = util.centerPosition(1000, 600, 700, 700, 10)
	H.eq("view: panel taller than the screen clamps", ty, 10)
	H.eq("view: that panel stays horizontally centred", tx, 150)

	local bx, by = util.centerPosition(1000, 800, 700, 700, 10)
	H.eq("view: panel that fits keeps its centre", by, 50)
	H.eq("view: panel narrower than the screen stays centred", bx, 150)
end

