-- PoE2 Craft Overlay : Tests/test_recipes.lua
-- The routes are data, and this file is the contract that keeps them honest:
--   * every step names a rule, and that rule must have passed the consensus bar;
--   * C7 (greater exaltation + homogenising) must appear NOWHERE, because one confirmation against three
--     contradictions is not evidence enough to advise on;
--   * a route matches by class and item level, and the specific route comes before the generic one;
--   * the English answer carries its own twins and no Russian.
local H = require("Tests.harness")
local Recipes = require("Data.recipes")

-- C6 (the "same tag" technique) is deliberately absent: the omen is not obtainable in a 0.5 league, so the
-- method is not offered at all and no route may stand on it.
local CONFIRMED = { C1 = true, C2 = true, C3 = true, C4 = true, C5 = true, C8 = true }

local GLOVES = table.concat({
	"Item Class: Gloves", "Rarity: Rare", "Test", "Siren Scale Gloves", "--------",
	"Item Level: 82", "--------", "120% increased Energy Shield",
}, "\n")

local LOW = table.concat({
	"Item Class: Gloves", "Rarity: Rare", "Test", "Siren Scale Gloves", "--------",
	"Item Level: 20", "--------", "12% increased Energy Shield",
}, "\n")

return function(h)
	-- 1. The data itself: no unconfirmed rule anywhere, C7 in particular.
	local badRules, unknownRule = { }, { }
	for _, recipe in ipairs(Recipes.recipes or { }) do
		for _, id in ipairs(Recipes.ruleIdsOf(recipe)) do
			if not CONFIRMED[id] then
				badRules[#badRules + 1] = tostring(recipe.id) .. ":" .. tostring(id)
			end
		end
		for _, rule in pairs(recipe.rules or { }) do
			if not CONFIRMED[rule] then
				unknownRule[#unknownRule + 1] = tostring(recipe.id)
			end
		end
	end
	H.check("recipes: every step stands on a confirmed rule", #badRules == 0, table.concat(badRules, ", "))
	H.check("recipes: C7 is never used as a basis for advice", #badRules == 0
		and table.concat(badRules, ","):find("C7", 1, true) == nil, table.concat(badRules, ","))
	H.check("recipes: the routes name their rules at all",
		#(Recipes.recipes or { }) > 0 and #Recipes.ruleIdsOf(Recipes.recipes[1]) > 0, "no rules")

	-- 2. Matching: the specific route (gloves, ilvl 78+) comes before the generic one.
	local matched = Recipes.forItem({ itemClass = "Gloves", itemLevel = 82 })
	H.check("recipes: gloves at ilvl 82 match a route", #matched >= 1, tostring(#matched))
	if #matched > 0 then
		H.eq("recipes: and the specific route is first", matched[1].id, "es_res_armour")
		for index = 2, #matched do
			H.check("recipes: the generic routes come after (" .. tostring(matched[index].id) .. ")",
				#matched[index].classes == 0, tostring(#matched[index].classes))
		end
	end

	-- A low item level must not receive a route whose floor is 78.
	local lowMatched = Recipes.forItem({ itemClass = "Gloves", itemLevel = 20 })
	for _, route in ipairs(lowMatched) do
		H.check("recipes: " .. tostring(route.id) .. " respects its item level floor",
			(tonumber(route.minIlvl) or 0) <= 20, tostring(route.minIlvl))
	end

	-- 3. Every route is readable in both languages: a goal, ordered steps, a stop rule.
	for _, recipe in ipairs(Recipes.recipes or { }) do
		H.check("recipes: " .. tostring(recipe.id) .. " has a goal in both languages",
			(recipe.goal or "") ~= "" and (recipe.goalEn or "") ~= "", tostring(recipe.goalEn))
		H.check("recipes: " .. tostring(recipe.id) .. " has a stop rule in both languages",
			(recipe.stopRule or "") ~= "" and (recipe.stopRuleEn or "") ~= "", tostring(recipe.stopRuleEn))
		H.check("recipes: " .. tostring(recipe.id) .. " has three steps", #(recipe.steps or { }) == 3,
			tostring(#(recipe.steps or { })))
		for _, step in ipairs(recipe.steps or { }) do
			H.check("recipes: " .. tostring(recipe.id) .. " step " .. tostring(step.n) .. " is bilingual",
				(step.action or "") ~= "" and (step.actionEn or "") ~= "", tostring(step.actionEn))
			H.check("recipes: " .. tostring(recipe.id) .. " step " .. tostring(step.n) .. " has no Russian in English",
				not (step.actionEn or ""):find("[\208-\209][\128-\191]"), tostring(step.actionEn))
		end
	end

	-- 4. And through the engine, the same routes reach the card.
	local Api = require("Mcp.api")
	local card = Api.call("craft_step", { item_text = GLOVES, lang = "ru" })
	H.check("recipes: the card carries the route", type(card.routes) == "table" and #card.routes >= 1,
		tostring(card.routes and #card.routes))
	if type(card.routes) == "table" and #card.routes >= 1 then
		H.eq("recipes: and it is the specific one", card.routes[1].id, "es_res_armour")
	end
	local english = Api.call("craft_step", { item_text = GLOVES, lang = "en" })
	local englishRoute = type(english.routes) == "table" and english.routes[1] or { }
	H.check("recipes: the English card carries its own goal", (englishRoute.goal or "") ~= "",
		tostring(englishRoute.goal))
	H.check("recipes: with no Russian in it", not (englishRoute.goal or ""):find("[\208-\209][\128-\191]"),
		tostring(englishRoute.goal))
-- 5. The state check: the two slots are limits, and the card must say so before a step is taken.
	local noSlots = Recipes.stateNotes({ craftedAnchorUsed = false, desecratedAnchorUsed = false })
	H.eq("state: a clean item is told the two slots are separate", #noSlots, 1)
	H.check("state: and the note names the compatibility", (noSlots[1].text or ""):find("совместимы", 1, true) ~= nil,
		tostring(noSlots[1] and noSlots[1].text))

	local desecrated = Recipes.stateNotes({ craftedAnchorUsed = false, desecratedAnchorUsed = true })
	H.eq("state: a desecrated item gets one note", #desecrated, 1)
	H.check("state: naming the single desecration slot",
		(desecrated[1].text or ""):find("одна на предмет", 1, true) ~= nil, tostring(desecrated[1].text))
	H.check("state: and the way out of it",
		(desecrated[1].text or ""):find("Предзнаменование света", 1, true) ~= nil, tostring(desecrated[1].text))

	local crafted = Recipes.stateNotes({ craftedAnchorUsed = true, desecratedAnchorUsed = false })
	H.check("state: a crafted modifier is a replacement, not a second slot",
		(crafted[1].text or ""):find("ЗАМЕНИТ", 1, true) ~= nil, tostring(crafted[1].text))

	local both = Recipes.stateNotes({ craftedAnchorUsed = true, desecratedAnchorUsed = true })
	H.eq("state: with both slots taken there are two notes", #both, 2)

	-- The English twins exist and hold no Russian, like everywhere else.
	for _, note in ipairs(both) do
		H.check("state: the note is bilingual", (note.textEn or "") ~= "", tostring(note.textEn))
		H.check("state: with no Russian in English", not (note.textEn or ""):find("[\208-\209][\128-\191]"),
			tostring(note.textEn))
	end

	-- And the payload carries them: the card is where the player reads it.
	local stateCard = Api.call("craft_step", { item_text = GLOVES, lang = "ru" })
	H.check("state: the card carries the notes", type(stateCard.stateNotes) == "table" and #stateCard.stateNotes >= 1,
		tostring(stateCard.stateNotes and #stateCard.stateNotes))

	-- 6. The live capture that exposed this: a Russian client prints "Класс предмета: Обувь" for sandals, and the
	-- dictionary knew only "Сапоги". Without the class fix no footwear item could ever reach its route.
	local BOOTS_RU = table.concat({
		"Класс предмета: Обувь", "Редкость: Редкий", "Победная поступь", "Сандалии хранителя песков", "--------",
		"Уровень предмета: 84", "--------",
		'{ Префикс "Горечавковая" (Уровень: 2) — Мана }', "+104(90-104) к максимуму маны",
	}, "\n")
	local bootsCard = Api.call("craft_step", { item_text = BOOTS_RU, lang = "ru", goal = "es" })
	local bootsRoute = nil
	for _, route in ipairs((bootsCard or { }).routes or { }) do
		if route.id == "es_res_armour" then
			bootsRoute = route
		end
	end
	H.check("recipes: a Russian footwear item reaches the armour route", bootsRoute ~= nil,
		tostring(bootsCard and #(bootsCard.routes or { })))
	if bootsRoute then
		H.check("recipes: and the route speaks Russian", (bootsRoute.goal or ""):find("энергощита", 1, true) ~= nil,
			tostring(bootsRoute.goal))
	end
	-- An unknown base must NOT be guessed into a specific slot.
	H.check("recipes: an unknown base gets no specific class",
		Recipes.classFromBase("Mysterious Thing") == nil,
		tostring(Recipes.classFromBase("Mysterious Thing")))
-- 7. The class comes from the base table's spawn tags, not from a dictionary of printed names. This walks the
	-- whole corpus and proves it: every base the table tags as boots/gloves/helmet/body/shield/weapon must resolve
	-- to the class our routes speak. A regression here silently degrades advice for a whole item class.
	local Bases = require("Item.Bases")
	local table_ = require("Data.bases")
	local seen, wrong, unmapped = 0, { }, { }
	for base, tags in pairs(table_.tags or { }) do
		seen = seen + 1
		local class = Recipes.classFromTags(base)
		local got = tostring(tags)
		local expected = nil
		if got:find("boots", 1, true) then expected = "boots"
		elseif got:find("gloves", 1, true) then expected = "gloves"
		elseif got:find("body_armour", 1, true) then expected = "body armours"
		elseif got:find("helmet", 1, true) then expected = "helmets"
		elseif got:find("shield", 1, true) then expected = "shields"
		-- "crossbow" contains "bow", so the narrower tag has to be tested first - the test itself had this wrong
		-- and reported nine crossbows as mismatched while the code was right.
		elseif got:find("crossbow", 1, true) then expected = "crossbows"
		elseif got:find("bow", 1, true) then expected = "bows"
		elseif got:find("sceptre", 1, true) then expected = "sceptres"
		elseif got:find("wand", 1, true) then expected = "wands"
		elseif got:find("spear", 1, true) then expected = "spears"
		end
		if expected and class ~= expected then
			wrong[#wrong + 1] = base .. ": " .. tostring(class) .. " != " .. expected
		end
		if expected == nil and class == nil and (got:find("weapon", 1, true) or got:find("armour", 1, true)) then
			unmapped[#unmapped + 1] = base .. " [" .. got .. "]"
		end
	end
	H.check("recipes: the class corpus was actually read", seen > 1000, tostring(seen))
	H.check("recipes: no tagged base resolves to the wrong class", #wrong == 0,
		table.concat(wrong, "; "):sub(1, 300))
	H.check("recipes: an armour or weapon base always resolves to some class", #unmapped == 0,
		tostring(#unmapped) .. " без класса: " .. table.concat(unmapped, "; "):sub(1, 300))
end
