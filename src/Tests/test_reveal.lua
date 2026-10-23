-- PoE2 Craft Overlay : Tests/test_reveal.lua
-- Parity check for the desecration reveal model.
--
-- Item/Mods.revealChance is a port of the community implementation in
-- poe2-crafting-mcp (crafting/desecration.py). Tests/reveal_reference.lua holds values
-- produced by running *that* function over a grid of pool sizes and target counts, so
-- this test fails if either side drifts - which is the point of committing the numbers.

local Mods = require("Item.Mods")
local reference = require("Tests.reveal_reference")

return function(H)
	H.eq("reveal: reference table present", #(reference.rows or { }) >= 40, true)
	H.contains("reveal: reference names its source", reference.source, "poe2-crafting-mcp")

	local mismatches = { }
	for _, row in ipairs(reference.rows) do
		local actual = Mods.revealChance(row.poolSize, row.targetCount, row.draws, row.echoes)
		if math.abs(actual - row.expected) > 1e-9 then
			mismatches[#mismatches + 1] = string.format(
				"pool=%d targets=%d echoes=%s: ours %.9f, theirs %.9f",
				row.poolSize, row.targetCount, tostring(row.echoes), actual, row.expected)
		end
	end
	H.check("reveal: every reference row reproduced", #mismatches == 0,
		table.concat(mismatches, "; "))

	-- The shapes that matter in practice.
	H.eq("reveal: 3 of 12 for one target is 25%", Mods.revealChance(12, 1, 3, false), 0.25)
	H.eq("reveal: echoes square the miss chance",
		math.abs(Mods.revealChance(12, 1, 3, true) - (1 - 0.75 * 0.75)) < 1e-12, true)
	H.eq("reveal: empty pool yields nothing", Mods.revealChance(0, 1, 3, false), 0)
	H.eq("reveal: no targets yields nothing", Mods.revealChance(10, 0, 3, false), 0)
	H.eq("reveal: target covering the pool is certain", Mods.revealChance(4, 4, 3, false), 1)
	H.eq("reveal: pool smaller than the draw is certain", Mods.revealChance(2, 1, 3, false), 1)
	H.eq("reveal: zero draws yields nothing", Mods.revealChance(10, 1, 0, false), 0)
	H.eq("reveal: more targets raises the chance",
		Mods.revealChance(12, 3, 3, false) > Mods.revealChance(12, 1, 3, false), true)

	-- Attaching to a real pool: the desecration pool carries its own reveal numbers.
	local pool = Mods.desecrationPool(82, { "gloves", "armour", "default" })
	H.eq("reveal: desecration pool built", pool ~= nil and pool.tierCount > 0, true)
	Mods.attachReveal(pool)
	H.eq("reveal: pool reports its size", pool.reveal.poolSize, pool.tierCount)
	H.eq("reveal: pool reports three draws", pool.reveal.draws, 3)
	local group = pool.groups[1]
	H.eq("reveal: group carries a reveal chance", type(group.revealChance), "number")
	local expected = Mods.revealChance(pool.tierCount, group.tierCount, 3, false)
	H.eq("reveal: group chance matches the pool maths",
		math.abs(group.revealChance - expected) < 1e-12, true)
	H.eq("reveal: reveal chance exceeds the plain weighted share for a single-tier group",
		group.tierCount > 1 or group.revealChance >= group.chance / 100, true)
end
