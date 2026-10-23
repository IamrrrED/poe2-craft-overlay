-- Closing the last four items from the poe2db cross-check.
--
-- None of them changes a crafting decision - two are gem-socket items, one duplicates a finished item, one
-- identifies - so they are recorded where they cannot be mistaken for a way to change an item's modifiers, and
-- the five Sagas are marked so the advice never offers one for a piece of gear.
return function()
	local H = require("Tests.harness")
	local league = require("Data.league_0_5_5")

	-- 1. The five Sagas: on poe2db's Omen page, and the only omens we were missing (45 + 5 = 50).
	local SAGAS = {
		"Aldur's Saga", "Medved's Saga", "Vorana's Saga", "Uhtred's Saga", "Olroth's Saga",
	}
	local byName = { }
	for _, omen in pairs(league.omens or { }) do byName[omen.en or ""] = omen end
	for _, name in ipairs(SAGAS) do
		local omen = byName[name]
		H.check("poe2db: " .. name .. " is recorded", omen ~= nil)
		if omen then
			H.eq("poe2db: " .. name .. " is marked as not item crafting", omen.notItemCrafting, true)
			-- It targets a Logbook, not an orb: `applies` is reserved for the currency an omen steers, and a
			-- Saga steers none, so putting "logbook" there would have broken the integrity check that every
			-- omen's `applies` names a real currency.
			H.eq("poe2db: " .. name .. " targets a logbook", omen.target, "logbook")
			H.eq("poe2db: " .. name .. " steers no orb", omen.applies, nil)
			H.check("poe2db: " .. name .. " carries its effect text",
				type(omen.effectEn) == "string" and #omen.effectEn > 40, tostring(omen.effectEn))
		end
	end
	-- Every Saga guarantees or shapes a Logbook, so none may be described as an Exalted/Chaos omen.
	for _, name in ipairs(SAGAS) do
		H.check("poe2db: " .. name .. " is not applied to an orb",
			byName[name] and byName[name].applies == nil)
	end

	-- 2. The four extra currencies poe2db lists, in a table that the methods picker does not read.
	local others = league.otherCurrencies or { }
	H.check("poe2db: the extra currencies are recorded", #others >= 5, tostring(#others))
	local otherNames = { }
	for _, entry in ipairs(others) do
		otherNames[entry.en] = entry
		H.check("poe2db: an extra currency has an effect (" .. tostring(entry.en) .. ")",
			type(entry.effectEn) == "string" and #entry.effectEn > 15, tostring(entry.effectEn))
		H.eq("poe2db: and is not called a crafting method (" .. tostring(entry.en) .. ")",
			entry.crafting, false)
	end
	H.check("poe2db: Mirror of Kalandra is recorded", otherNames["Mirror of Kalandra"] ~= nil)
	H.check("poe2db: Scroll of Wisdom is recorded", otherNames["Scroll of Wisdom"] ~= nil)
	for _, orb in ipairs({ "Lesser Jeweller's Orb", "Greater Jeweller's Orb", "Perfect Jeweller's Orb" }) do
		H.check("poe2db: " .. orb .. " is recorded", otherNames[orb] ~= nil)
		if otherNames[orb] then
			H.eq("poe2db: " .. orb .. " targets a skill gem", otherNames[orb].target, "skill gem")
		end
	end

	-- And they must NOT be in the currency table, or the picker would offer them as ways to modify an item.
	for _, entry in ipairs(others) do
		for id, currency in pairs(league.currencies or { }) do
			H.check("poe2db: " .. tostring(entry.en) .. " is not a craft method",
				currency.en ~= entry.en, tostring(id))
		end
	end

	-- 3. The shards were already recorded; this pins that they still are, since the gap list mentioned them.
	local shards = league.shards or { }
	H.check("poe2db: the shard table is present", #shards >= 3, tostring(#shards))
	local shardNames = { }
	for _, shard in ipairs(shards) do shardNames[shard.en] = true end
	for _, name in ipairs({ "Artificer's Shard", "Regal Shard", "Transmutation Shard", "Chance Shard" }) do
		H.eq("poe2db: " .. name .. " is recorded", shardNames[name], true)
	end

	-- 4. Omen coverage against the page's own total: 50 there, 45 ours plus the 5 Sagas here.
	local total = 0
	for _ in pairs(league.omens or { }) do total = total + 1 end
	H.check("poe2db: the omen set now covers the page", total >= 50, tostring(total))
end
