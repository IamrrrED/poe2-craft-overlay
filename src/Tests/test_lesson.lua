-- The lesson behind a step: the principle, not just this action.
--
-- The guides analysed in docs/mentor-research.md teach by stating the rule once and showing it in action.
-- The overlay used to show only the action, so a player learned nothing that transferred to the next item.
-- A lesson also guards against the fabrications found in SEO guides: it is written from rules the engine
-- enforces, so it cannot claim what the data does not do.
return function()
	local H = require("Tests.harness")
	local Lesson = require("Craft.Lesson")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Advisor = require("Craft.Advisor")
	local Coach = require("Craft.Coach")
	local league = require("Data.league_0_5_5")

	-- Every currency the coach can recommend must have a lesson: a missing one is a silent hole in the
	-- teaching, because the card then shows a bare instruction.
	local CURRENCIES = {
		"transmutation", "augmentation", "regal", "alchemy", "exalted", "greater_exalted",
		"perfect_exalted", "chaos", "greater_chaos", "perfect_chaos", "annulment", "divine", "vaal",
		"quality", "whetstone", "scrap", "etcher", "bauble", "prism",
	}
	for _, id in ipairs(CURRENCIES) do
		local lesson = Lesson.reasonFor({ id = id })
		H.check("lesson: " .. id .. " has a lesson", lesson ~= nil)
		if lesson then
			H.check("lesson: " .. id .. " names the rule", type(lesson.title) == "string" and #lesson.title > 8,
				tostring(lesson.title))
			-- A lesson that fits in one line cannot teach a principle; this also catches a placeholder.
			H.check("lesson: " .. id .. " explains it", type(lesson.text) == "string" and #lesson.text > 80,
				tostring(#lesson.text))
		end
	end

	-- And every kind the picker groups by, for steps whose currency has no lesson of its own.
	for _, kind in ipairs({ "add", "replace", "improve", "free", "risky" }) do
		local lesson = Lesson.reasonFor({ id = "unknown_currency", kind = kind })
		H.check("lesson: the " .. kind .. " kind has a lesson", lesson ~= nil)
	end

	-- Nothing to say about a step that is not a table, or about a currency nobody wrote a rule for: the
	-- card must fall back to its own text instead of inventing one.
	H.eq("lesson: a missing step has no lesson", Lesson.reasonFor(nil), nil)
	H.eq("lesson: an unknown currency has no lesson", Lesson.reasonFor({ id = "not_a_currency" }), nil)

	-- The name map and the lesson table must not drift apart: a REAL currency with a lesson but no name entry
	-- is unreachable from a step that only carries the display name, which is how the lesson silently
	-- disappeared for some branches. `quality` is exempt on purpose: it is not one currency but a family
	-- (scrap, whetstone, etcher, bauble, prism, each mapped by its own name), and it is reached through a
	-- step's id rather than through a display name.
	local mappedIds = { }
	for name, id in pairs(Lesson.NAME_TO_ID) do
		H.check("lesson: the name map points at a real lesson (" .. name .. ")",
			Lesson.BY_CURRENCY[id] ~= nil, tostring(id))
		mappedIds[id] = name
	end
	for id in pairs(Lesson.BY_CURRENCY) do
		if (league.currencies or { })[id] ~= nil then
			H.check("lesson: every real currency's lesson is reachable by name (" .. id .. ")",
				mappedIds[id] ~= nil, tostring(id))
		end
	end
	H.check("lesson: the name map is not empty", next(Lesson.NAME_TO_ID) ~= nil)
	-- A step that carries only the display name still finds its lesson: that is the path the card uses for the
	-- branches whose step table has no id.
	local byName = Lesson.forName("Exalted Orb")
	H.check("lesson: a display name resolves to its lesson", byName ~= nil)
	H.eq("lesson: and it is the exalted lesson", byName and byName, Lesson.BY_CURRENCY.exalted)
	H.eq("lesson: an unknown name falls back to the kind", Lesson.forName("Nonsense Orb", "add"),
		Lesson.BY_KIND.add)
	H.eq("lesson: an unknown name with no kind has no lesson", Lesson.forName("Nonsense Orb"), nil)

	-- The step card actually carries the lesson for this item, which is how the missing-branch bug surfaced.
	local HELMET = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Symbolic Bastion", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }', "+18% to Chaos Resistance",
	}, "\n")
	local item = Parser.parse(HELMET)
	Mods.annotate(item)
	local advice = Advisor.analyze(item, league)
	local step = Coach.step(item, advice, Coach.state(item, HELMET), nil)
	H.eq("lesson: the recommended step is an exalted orb", step.currency, "Exalted Orb")
	H.check("lesson: the card carries a lesson title", type(step.lessonTitle) == "string"
		and #step.lessonTitle > 8, tostring(step.lessonTitle))
	H.check("lesson: and the lesson itself", type(step.lesson) == "string" and #step.lesson > 80,
		tostring(step.lesson and #step.lesson))
	-- The lesson must not be a copy of the step's own "why": one explains the action, the other the rule.
	H.check("lesson: it is not the step's why repeated", step.lesson ~= step.why)
end
