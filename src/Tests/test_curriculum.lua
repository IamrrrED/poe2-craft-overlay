-- The mentor's course: an order of lessons, each checked against the item in hand.
--
-- The analysed guides all teach in one order (read the item, base and ilvl, cheap Magic tier, lock what is
-- good, control instead of gamble, know when to stop) and each point is shown on the viewer's own item. The
-- course follows the item, so a lesson the item already demonstrates is marked as understood instead of being
-- repeated.
return function()
	local H = require("Tests.harness")
	local Curriculum = require("Craft.Curriculum")
	local Api = require("Mcp.api")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local Advisor = require("Craft.Advisor")
	local league = require("Data.league_0_5_5")

	-- Every lesson is complete and teachable.
	local lessons = Curriculum.LESSONS
	H.check("curriculum: the course has lessons", #lessons >= 6, tostring(#lessons))
	local ids = { }
	for _, lesson in ipairs(lessons) do
		H.check("curriculum: a lesson has an id", type(lesson.id) == "string" and lesson.id ~= "")
		H.eq("curriculum: the id is unique (" .. tostring(lesson.id) .. ")", ids[lesson.id], nil)
		ids[lesson.id] = true
		H.check("curriculum: it has a title (" .. lesson.id .. ")",
			type(lesson.title) == "string" and #lesson.title > 15, tostring(lesson.title))
		-- A lesson that fits in a line cannot teach; this also catches a placeholder.
		H.check("curriculum: it explains itself (" .. lesson.id .. ")",
			type(lesson.text) == "string" and #lesson.text > 90, tostring(#lesson.text))
		H.eq("curriculum: it has a check (" .. lesson.id .. ")", type(lesson.check), "function")
	end

	-- The course runs on a real item: the lessons apply, and the ones the item already demonstrates are done.
	local HELMET = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Symbolic Bastion", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
		'{ Suffix Modifier "of the Prism" (Tier: 1) }', "+18% to Chaos Resistance",
	}, "\n")
	local item = Parser.parse(HELMET)
	Mods.annotate(item)
	local advice = Advisor.analyze(item, league)
	local course = Curriculum.forItem(item, advice)
	H.check("curriculum: the course applies to a real rare", #course >= 4, tostring(#course))
	for _, lesson in ipairs(course) do
		H.eq("curriculum: a lesson has a done flag (" .. lesson.id .. ")", type(lesson.done), "boolean")
	end
	local byId = { }
	for _, lesson in ipairs(course) do
		byId[lesson.id] = lesson
	end
	-- Reading the item is understood on any item whose split the engine could determine.
	H.eq("curriculum: reading the item counts as done", byId.read_item.done, true)
	H.eq("curriculum: base and ilvl count as done", byId.base_and_ilvl.done, true)
	-- A RARE item does not teach the Magic-tier lesson by being `done` - that lesson is about Magic items.
	H.eq("curriculum: the cheap-tier lesson does not apply to a rare",
		byId.cheap_tier and byId.cheap_tier.done or nil, nil)
	-- Irreversible-last is a rule that holds on any RARE, so it reads as understood.
	H.eq("curriculum: the irreversible lesson reads as understood on a rare",
		byId.irreversible_last and byId.irreversible_last.done, true)

	local progress = Curriculum.progress(item, advice)
	H.check("curriculum: progress counts the lessons", progress.total == #course, tostring(progress.total))
	H.check("curriculum: and the done ones", progress.done >= 2, tostring(progress.done))
	H.check("curriculum: it points at the next lesson", progress.nextLesson ~= nil
		or progress.done == progress.total)
	if progress.nextLesson then
		H.eq("curriculum: the next lesson is not already done", progress.nextLesson.done, false)
	end

	-- A Magic item gets the Magic-tier lesson, because that is the state it is in.
	local MAGIC = table.concat({
		"Item Class: Helmets", "Rarity: Magic", "Test", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Runner" (Tier: 2) }', "20% increased Movement Speed",
	}, "\n")
	local magic = Parser.parse(MAGIC)
	Mods.annotate(magic)
	local magicCourse = Curriculum.forItem(magic, Advisor.analyze(magic, league))
	local magicIds = { }
	for _, lesson in ipairs(magicCourse) do
		magicIds[lesson.id] = lesson
	end
	H.check("curriculum: a magic item gets the cheap-tier lesson", magicIds.cheap_tier ~= nil)
	-- On a Magic item the cheap tier IS the state, so the lesson reads as demonstrated. That is the point of
	-- the check: the course tells a beginner what his item already proves, not what he has read.
	H.eq("curriculum: and the item demonstrates it", magicIds.cheap_tier.done, true)
	-- The irreversible lesson is about a Rare being finished, so a Magic item does not get it.
	local magicIdsList = { }
	for _, lesson in ipairs(magicCourse) do
		magicIdsList[lesson.id] = true
	end
	H.check("curriculum: a magic item is not taught the rare-only lesson yet",
		magicIdsList.irreversible_last == nil or magicIds.irreversible_last.done == false)

	-- The payload carries the course, so the panel shows it without another call.
	local payload = assert(Api.call("methods", { item_text = HELMET }))
	H.check("curriculum: the payload carries the course", type(payload.curriculum) == "table")
	H.check("curriculum: with lessons in it", #(payload.curriculum or { }) >= 4)
	H.check("curriculum: and a byId lookup still works", Curriculum.byId("read_item") ~= nil)
	H.eq("curriculum: an unknown lesson is not invented", Curriculum.byId("nope"), nil)
end
