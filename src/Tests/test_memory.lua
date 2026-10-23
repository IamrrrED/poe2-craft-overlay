-- The memory is what makes step two depend on step one, so it is tested like the coach itself.
return function()
	local H = require("Tests.harness")
	local Memory = require("Craft.Memory")

	-- Both shapes of modifier data are accepted: strings and tables.
	local first = {
		itemClass = "Gloves", baseType = "Blacksteel Gauntlets", name = "Doom Grip", itemLevel = 82,
		explicitMods = { "+118 to maximum Life" },
		implicitMods = { { text = "+30 to Strength" } },
	}
	local second = {
		itemClass = "Gloves", baseType = "Blacksteel Gauntlets", name = "Doom Grip", itemLevel = 82,
		explicitMods = { "+118 to maximum Life", "+44% to Fire Resistance" },
		implicitMods = { { text = "+30 to Strength" } },
	}
	local other = {
		itemClass = "Boots", baseType = "Expert Vaal Greaves", name = "Some Boots", itemLevel = 80,
		explicitMods = { "+50 to maximum Life" },
	}

	H.eq("memory: the same item has the same fingerprint", Memory.fingerprint(first), Memory.fingerprint(second))
	H.eq("memory: another item does not", Memory.fingerprint(first) ~= Memory.fingerprint(other), true)
	H.eq("memory: modifiers are collected from both shapes", #Memory.mods(first), 2)
	H.eq("memory: the table shape is read", Memory.mods(first)[1] ~= nil, true)

	local changes = Memory.compare(Memory.mods(first), Memory.mods(second))
	H.eq("memory: an added modifier is seen", #changes.added, 1)
	H.eq("memory: the added modifier is named", changes.added[1], "+44% to Fire Resistance")
	H.eq("memory: nothing is reported as removed", #changes.removed, 0)
	H.eq("memory: unchanged modifiers are counted", changes.same, 2)

	local lost = Memory.compare(Memory.mods(second), Memory.mods(first))
	H.eq("memory: a removed modifier is seen", #lost.removed, 1)

	-- The memory survives a round trip through its file.
	Memory.save(Memory.fingerprint(second), Memory.mods(second), { currency = "Exalted Orb", title = "Следующий шаг: Exalted Orb" })
	local saved = Memory.load()
	H.eq("memory: the fingerprint is stored", saved.fingerprint, Memory.fingerprint(second))
	H.eq("memory: the step is stored", saved.step, "Exalted Orb")
	H.eq("memory: the modifiers are stored", #saved.mods, 3)

	-- Same item: the review compares. Another item: it does not, and the old steps are forgotten.
	Memory.save(Memory.fingerprint(first), Memory.mods(first), { currency = "Exalted Orb" })
	local sameReview = Memory.review(second, { currency = "Chaos Orb" })
	H.eq("memory: the same item is recognised", sameReview.sameItem, true)
	H.eq("memory: progress is reported when a modifier appeared", sameReview.verdict, "progress")
	H.eq("memory: the previous step is remembered", sameReview.previousStep, "Exalted Orb")

	local newReview = Memory.review(other, { currency = "Transmutation" })
	H.eq("memory: another item is not the same", newReview.sameItem, false)
	H.eq("memory: a new item carries no changes", newReview.changes, nil)
	H.eq("memory: and is treated as the first look", newReview.first, true)

	local unchanged = Memory.review(other, { currency = "Transmutation" })
	H.eq("memory: the second look at it is the same item", unchanged.sameItem, true)
	H.eq("memory: nothing changed is reported as such", unchanged.verdict, "nothing")

	Memory.clear()
	H.eq("memory: clearing removes the memory", Memory.load(), nil)
end