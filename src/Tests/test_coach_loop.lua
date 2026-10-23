-- The step loop: what the assistant says depends on what happened between two captures.
return function()
	local H = require("Tests.harness")
	local Coach = require("Craft.Coach")
	local Memory = require("Craft.Memory")

	local advice = { plans = { { id = "plan", reason = "По плану.", steps = {
		{ name = "Exalted Orb", count = 1 },
		{ name = "Chaos Orb", count = 1 },
		{ name = "Divine Orb", count = 1 },
	} } } }

	local function item(mods, extra)
		local base = {
			itemClass = "Gloves", baseType = "Blacksteel Gauntlets", name = "Doom Grip",
			itemLevel = 82, rarity = "RARE", modCount = #mods + 1, explicitMods = mods, isModifiable = true,
		}
		for key, value in pairs(extra or { }) do base[key] = value end
		return base
	end

	Memory.clear()

	local first = Coach.report(item({ "+118 to maximum Life" }), advice, "")
	H.eq("loop: the first look is not a known item", first.review.sameItem, false)
	H.eq("loop: the first look starts the plan", first.step.currency, "Exalted Orb")
	H.eq("loop: the first look is remembered", first.review.first, true)

	local progress = Coach.report(item({ "+118 to maximum Life", "+45% to Fire Resistance" }), advice, "")
	H.eq("loop: an added modifier is progress", progress.review.verdict, "progress")
	H.eq("loop: progress moves to the next step", progress.step.currency, "Chaos Orb")
	H.eq("loop: progress says what was added", (progress.review.changes.added or { })[1], "+45% to Fire Resistance")

	local nothing = Coach.report(item({ "+118 to maximum Life", "+45% to Fire Resistance" }), advice, "")
	H.eq("loop: no change is nothing", nothing.review.verdict, "nothing")
	H.eq("loop: nothing repeats the step", nothing.step.currency, "Chaos Orb")
	H.eq("loop: nothing explains why it may not have applied", nothing.step.why:find("не изменил", 1, true) ~= nil, true)
	H.eq("loop: nothing is honest about the group rule", nothing.step.why:find("группу", 1, true) ~= nil, true)

	-- A swap needs one modifier gone and another arrived: set the memory to [Life, Fire] first.
	Memory.save(Memory.fingerprint(item({ "+118 to maximum Life", "+45% to Fire Resistance" })),
		Memory.mods(item({ "+118 to maximum Life", "+45% to Fire Resistance" })), { currency = "Chaos Orb", index = 2 })
	local loss = Coach.report(item({ "+118 to maximum Life" }), advice, "")
	H.eq("loop: a lost modifier is a loss", loss.review.verdict, "loss")
	H.eq("loop: loss steps back in the plan", loss.step.currency, "Exalted Orb")
	H.eq("loop: loss warns before adding more", loss.step.why:find("восстанов", 1, true) ~= nil, true)

	Memory.save(Memory.fingerprint(item({ "+118 to maximum Life", "+45% to Fire Resistance" })),
		Memory.mods(item({ "+118 to maximum Life", "+45% to Fire Resistance" })), { currency = "Chaos Orb", index = 2 })
	local swap = Coach.report(item({ "+118 to maximum Life", "+30 to Strength" }), advice, "")
	H.eq("loop: a replaced modifier is a swap", swap.review.verdict, "swap")
	H.eq("loop: swap names the retry tools", swap.step.why:find("Whittling", 1, true) ~= nil, true)

	local other = Coach.report({
		itemClass = "Boots", baseType = "Expert Vaal Greaves", name = "Other Boots",
		itemLevel = 80, rarity = "RARE", modCount = 1, explicitMods = { "+50 to maximum Life" },
	}, advice, "")
	H.eq("loop: another item is a new craft", other.review.sameItem, false)
	H.eq("loop: and starts from the first step", other.step.currency, "Exalted Orb")
	H.eq("loop: the other item is remembered on its own", (require("Craft.Memory").load() or { }).step, "Exalted Orb")

	Memory.clear()
end