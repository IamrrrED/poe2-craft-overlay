-- The panel is Russian, so the explanation must arrive in Russian.
--
-- Three separate layers each preferred English: the advisor chose the English reason over the Russian one,
-- the coach attached a remembered verdict to a step it did not describe, and the tool layer rebuilt plans with
-- `title = plan.titleEn or plan.title`. Fixing one of them only moved the problem down a layer, which is why
-- this test checks the answer a player actually receives, through the API, on a Russian item.
return function()
	local H = require("Tests.harness")
	local Api = require("Mcp.api")

	local WAND_RU = table.concat({
		"Класс предмета: Жезлы",
		"Редкость: Волшебный",
		"Зачарованный жезл",
		"Жезл",
		"--------",
		"Требуется: Уровень 28, 23 Инт",
		"--------",
		"Уровень предмета: 79",
		"--------",
		'{ Префикс "Напевный" (Уровень: 1) }',
		"46% увеличение урона от чар",
		'{ Суффикс "Бездны" (Уровень: 1) }',
		"+3 к уровню всех камней умений чар хаоса",
	}, "\n")

	local payload = assert(Api.call("craft_step", { item_text = WAND_RU }))
	local step = payload.step or { }
	local why = tostring(step.why or "")
	local title = tostring(step.title or "")

	H.check("ru: the step has an explanation", #why > 20, why)
	-- Cyrillic bytes live in the 0xD0-0xD1 range in UTF-8. A Latin explanation has none.
	H.check("ru: the explanation is in Russian", why:find("[\208-\209]") ~= nil, why)
	H.check("ru: and the title is too", title:find("[\208-\209]") ~= nil, title)
	-- The specific defect: a full Magic item was told nothing could be added, in English.
	H.eq("ru: the Magic item is upgraded, not declared finished", step.currency, "Regal Orb")
	-- The currency is named in Russian now (the language gate maps bare English currency adjectives to their
	-- official Russian names), so the assertion checks the Russian name and that the English one is gone.
	H.check("ru: the explanation names the rarity upgrade in Russian",
		why:find("Сфера царей", 1, true) ~= nil and why:find("Regal", 1, true) == nil, why)
	H.check("ru: and does not claim nothing can be added",
		why:find("no currency adds another modifier", 1, true) == nil, why)
end
