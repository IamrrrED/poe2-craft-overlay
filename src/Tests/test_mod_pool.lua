-- PoE2 Craft Overlay : Tests/test_mod_pool.lua
-- The modifier pool shown in "показать всё" has to be true to what can actually roll:
--   * a group the item already carries must not appear again (the game will not roll it twice);
--   * chances are shares of the roll weight, so each side should add up to ~100 %;
--   * the "wanted" list is ordered by the goal, and says nothing about price;
--   * an English reply carries no Russian family names and vice versa.
local H = require("Tests.harness")
local Parser = require("Item.Parser")
local Mods = require("Item.Mods")
local ModPool = require("Craft.ModPool")

local GLOVES = table.concat({
	"Item Class: Gloves", "Rarity: Rare", "Test", "Expert Vaal Gauntlets", "--------",
	"Item Level: 82", "--------",
	'{ Prefix Modifier "Ruin" (Tier: 3) }', "+85 to maximum Energy Shield",
}, "\n")

return function(h)
	local item = Parser.parse(GLOVES)
	Mods.annotate(item)
	local hasRussian = function(text) return tostring(text or ""):find("[\208-\209][\128-\191]") ~= nil end

	do
		local dbg = io.open("probe_pool.txt", "w")
		local resPool = ModPool.forItem(item, { goal = "res" })
		if dbg then
			for index, entry in ipairs(resPool.wanted or { }) do
				dbg:write(index, ") ", tostring(entry.family), " boost=", tostring(entry.boost),
					" score=", string.format("%.2f", entry.score or 0), " chance=", string.format("%.2f", entry.chance or 0),
					" | ", tostring(entry.bestText), "\n")
			end
			dbg:close()
		end
	end
	local pool = ModPool.forItem(item, { goal = "es" })
	H.check("modPool: the item gets a pool at all", type(pool.sides) == "table")
	H.check("modPool: prefixes exist", #((pool.sides.prefix or { }).groups or { }) > 0,
		tostring(#((pool.sides.prefix or { }).groups or { })))
	H.check("modPool: suffixes exist", #((pool.sides.suffix or { }).groups or { }) > 0,
		tostring(#((pool.sides.suffix or { }).groups or { })))

	-- Chances are percentages of the same total, so each side has to close at about 100.
	for _, side in ipairs({ "prefix", "suffix" }) do
		local sum = 0
		for _, group in ipairs(pool.sides[side].groups or { }) do
			sum = sum + (tonumber(group.chance) or 0)
			H.check("modPool: " .. side .. " entry has a text", (group.bestText or "") ~= "", tostring(group.bestText))
			H.check("modPool: " .. side .. " entry has a tier",
				(tonumber(group.bestTier) or 0) >= 1, tostring(group.bestTier))
			H.check("modPool: " .. side .. " entry names a family", (group.family or "") ~= "", tostring(group.family))
		end
		H.check("modPool: " .. side .. " chances add up to about 100 %",
			sum > 95 and sum < 105, string.format("%s %.2f", side, sum))
	end

	-- The energy-shield prefix carried by the item must not be offered again.
	local esOffered = 0
	for _, group in ipairs(pool.sides.prefix.groups or { }) do
		if (group.bestText or ""):lower():find("energy shield", 1, true) then
			esOffered = esOffered + 1
		end
	end
	H.eq("modPool: a modifier the item already has is not offered again", esOffered, 0)

	-- Goals change the order of the headline, not the pool. A given base need not be able to roll every family
	-- (these gloves, for one, cannot roll resistances at all), so the assertion is about the rule the code
	-- promises: the headline is ordered by how much the goal wants an entry, and a wanted family opens it.
	local damagePool = ModPool.forItem(item, { goal = "damage" })
	local wanted = damagePool.wanted or { }
	H.check("modPool: the wanted list is not empty for a goal", #wanted > 0, tostring(#wanted))
	local ordered = true
	for index = 2, #wanted do
		if (wanted[index].boost or 1) > (wanted[index - 1].boost or 1) then
			ordered = false
		end
	end
	H.check("modPool: the headline is ordered by how much the goal wants it", ordered, "boost order")
	H.check("modPool: a damage goal opens with a family it wants",
		((wanted[1] or { }).boost or 1) > 1, tostring((wanted[1] or { }).boost))
	H.check("modPool: the wanted list survives an absent goal", #(ModPool.forItem(item, { }).wanted or { }) > 0,
		tostring(#(ModPool.forItem(item, { }).wanted or { })))

	-- Price is not invented: the slot exists and says it was not checked.
	H.check("modPool: price is marked as not checked", pool.price and pool.price.checked == false)
	H.check("modPool: and says so in Russian", (pool.price.noteRu or ""):find("не проверялась", 1, true) ~= nil,
		tostring(pool.price.noteRu))
	H.check("modPool: and in English", not hasRussian(pool.price.noteEn), tostring(pool.price.noteEn))

	-- One name per reply, chosen before the payload is built: an empty label would silently fall back to the id.
	H.check("modPool: family labels carry a name", (pool.families[1].name or "") ~= "",
		tostring(pool.families[1].name))
	local russianNames = 0
	for _, family in ipairs(pool.families) do
		if hasRussian(family.name) then
			russianNames = russianNames + 1
		end
	end
	H.check("modPool: a Russian pool names its families in Russian", russianNames > 0, tostring(russianNames))

	-- And the card carries it, with the right language on each side.
	local Api = require("Mcp.api")
	local ruCard = Api.call("craft_step", { item_text = GLOVES, lang = "ru", goal = "es" })
	H.check("modPool: the Russian card carries the pool", ruCard.modPool and ruCard.modPool.sides ~= nil)
	local enCard = Api.call("craft_step", { item_text = GLOVES, lang = "en", goal = "es" })
	local leaked = 0
	for _, family in ipairs((enCard.modPool or { }).families or { }) do
		if hasRussian(family.nameEn) or hasRussian(family.nameRu) then
			leaked = leaked + 1
		end
	end
	H.eq("modPool: no Russian family name reaches the English card", leaked, 0)
end
