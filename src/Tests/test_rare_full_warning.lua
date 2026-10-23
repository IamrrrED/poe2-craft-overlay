-- A full rare gets told the truth about Chaos: it removes a RANDOM modifier.
--
-- Chaos is the cheapest step on a six-mod item - about one chaos against ten for a Divine - so it stays in the
-- minimal plan. But it does not let you choose which affix goes, and on a good item that roll can take the best
-- one. The explanation used to say "swaps a modifier", which reads as if the choice is yours. Targeted removal
-- needs the Omen of Whittling, and a player who never hears that will learn it the expensive way.
return function()
	local H = require("Tests.harness")
	local Api = require("Mcp.api")

	local FULL_RARE_RU = table.concat({
		"Класс предмета: Амулеты",
		"Редкость: Редкий",
		"Медальон",
		"Лазурный амулет",
		"--------",
		"Уровень предмета: 83",
		"--------",
		'{ Префикс "Выносливый" (Уровень: 1) }',
		"+123 к максимуму здоровья",
		'{ Префикс "Маревый" (Уровень: 3) }',
		"37% увеличение уклонения",
		'{ Префикс "Неприступный" (Уровень: 1) }',
		"47% увеличение максимума энергетического щита",
		'{ Суффикс "стежков" (Уровень: 3) }',
		"16% полученного урона восполняется в виде здоровья",
		'{ Суффикс "таланта" (Уровень: 3) }',
		"19% повышение скорости сотворения чар",
		'{ Суффикс "переливов" (Уровень: 1) }',
		"+17% к сопротивлению всем стихиям",
	}, "\n")

	local payload = assert(Api.call("craft_step", { item_text = FULL_RARE_RU }))
	local step = payload.step or { }
	local why = tostring(step.why or "")

	H.check("rare_full: the explanation exists", #why > 40, why)
	H.check("rare_full: it is in Russian", why:find("[\208-\209]") ~= nil, why)
	-- The two facts a player must not learn the expensive way.
	H.check("rare_full: it says the removal is random",
		why:find("СЛУЧАЙНЫЙ", 1, true) ~= nil or why:find("случайн", 1, true) ~= nil, why)
	H.check("rare_full: and names the omen for targeted removal",
		why:find("Whittling", 1, true) ~= nil, why)
	-- Chaos stays the cheap step: the plan economics are unchanged.
	H.eq("rare_full: the cheap step is still Chaos", step.currency, "Chaos Orb")
end
