-- PoE2 Craft Overlay : Tests/test_stash_tabs.lua
-- The stash tab table has to stay truthful: a regular tab is a grid whose cells can be computed, a specialised tab is
-- one slot per item type and must never be read as a grid. Getting that wrong silently reads the gap between two
-- currency slots and reports "empty".
local H = require("Tests.harness")
local Tabs = require("Data.stash_tabs")

return function(h)
	H.check("stash: the table has regular tabs", #Tabs.regular >= 2, tostring(#Tabs.regular))
	H.check("stash: the table has specialised tabs", #Tabs.specialised >= 8, tostring(#Tabs.specialised))

	-- A basic tab is 12x12, a quad is 24x24: these are the game's numbers, not ours.
	local byId = { }
	for _, tab in ipairs(Tabs.regular) do
		byId[tab.id] = tab
	end
	H.eq("stash: a normal tab is 12x12", byId.normal.rows .. "x" .. byId.normal.cols, "12x12")
	H.eq("stash: a quad tab is 24x24", byId.quad.rows .. "x" .. byId.quad.cols, "24x24")

	-- 144 cells over a 600x600 grid at 50 px pitch: centres at 25, 75, ... and never on a border.
	local cells = Tabs.cellCentres(100, 200, 600, 600, 12, 12)
	H.eq("stash: a 12x12 grid has 144 cells", #cells, 144)
	H.eq("stash: the first centre is half a cell inside", cells[1].x .. "," .. cells[1].y, "125,225")
	local last = cells[#cells]
	H.eq("stash: the last centre is half a cell inside the far edge", last.x .. "," .. last.y, "675,775")
	local unique = true
	local seenPositions = { }
	for _, cell in ipairs(cells) do
		local key = cell.x .. ":" .. cell.y
		if seenPositions[key] then
			unique = false
		end
		seenPositions[key] = true
	end
	H.check("stash: no two cells share a centre", unique, "duplicates")
	H.check("stash: every centre is inside the grid", cells[1].x > 100 and last.x < 700 and last.y < 800,
		cells[1].x .. ".." .. last.x)

	-- A degenerate rectangle must give no cells rather than a crash or a division by zero.
	H.eq("stash: an empty rectangle gives no cells", #Tabs.cellCentres(0, 0, 0, 0, 12, 12), 0)
	H.eq("stash: a zero column count gives no cells", #Tabs.cellCentres(0, 0, 100, 100, 0, 12), 0)

	-- Reading mode is the promise that specialised tabs are not treated as grids.
	H.eq("stash: a normal tab is read as a grid", Tabs.readingMode("normal"), "grid")
	H.eq("stash: a quad tab is read as a grid", Tabs.readingMode("quad"), "grid")
	H.eq("stash: a currency tab is read by slots", Tabs.readingMode("currency"), "slots")
	H.eq("stash: an essence tab is read by slots", Tabs.readingMode("essence"), "slots")
	H.eq("stash: an unknown tab is read by slots, not as a grid", Tabs.readingMode("mystery"), "slots")

	-- Bilingual labels, like everywhere else in the data.
	for _, tab in ipairs(Tabs.specialised) do
		H.check("stash: " .. tostring(tab.id) .. " has both names",
			(tab.ru or "") ~= "" and (tab.en or "") ~= "", tostring(tab.en))
		H.check("stash: " .. tostring(tab.id) .. " has no Russian in the English note",
			not (tab.noteEn or ""):find("[\208-\209][\128-\191]"), tostring(tab.noteEn))
	end
end
