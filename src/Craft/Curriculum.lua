-- PoE2 Craft Overlay : Craft/Curriculum.lua
-- The mentor's course: an order of lessons, each tied to a fact about the item in hand.
--
-- Why a course and not a list of rules. The guides analysed in docs/mentor-research.md all teach in the same
-- order - read the item, check the base and item level, use the cheap Magic tier, lock what is good, control
-- instead of gamble, know when to stop - and each step is shown ON THE VIEWER'S OWN ITEM. A pile of rules
-- gives a beginner the answer to "what now" and nothing for "why", which is why the overlay was useful once
-- and forgotten after the item was sold.
--
-- A lesson here has a CHECK: something the engine can verify about the item, so the course can say "this one
-- you already understand" instead of making the player read what he knows. No progress is stored: the item in
-- hand is the state, and the course follows it.
local Curriculum = { }

--- The course, in teaching order.
--- Each entry:
--   id      stable name
--   title   what the player learns
--   text    the lesson itself
--   check   function(item, advice) -> true when this lesson's fact is visible on the item
--   needs   what the item must be for the lesson to make sense (rarity etc.)
Curriculum.LESSONS = {
	{
		id = "read_item",
		title = "Прочитать предмет: префиксы, суффиксы, свободные слоты",
		text = "Первое, что делает опытный крафтер, — считает, сколько сторон занято и сколько открыто. Префикс "
			.. "и суффикс — разные стороны, и от них зависит, что вообще можно добавить. Пока это не прочитано, "
			.. "любой совет — угадывание.",
		check = function(item)
			return item.affixSplitComplete == true
		end,
	},
	{
		id = "base_and_ilvl",
		title = "База и уровень предмета решают, какой тир вообще возможен",
		text = "Уровень предмета ограничивает максимальный тир мода: на низком уровне предмета лучший тир просто не выпадет, "
			.. "сколько ни плати. База задаёт, какие семейства модов вообще доступны. Это проверяют ДО первой "
			.. "валюты, потому что отменить это нельзя.",
		check = function(item)
			return (tonumber(item.itemLevel) or 0) > 0 and item.baseType ~= nil
		end,
	},
	{
		id = "cheap_tier",
		title = "Волшебная ступень — единственный «перекат»",
		text = "Полного реролла в PoE 2 нет. Пока предмет волшебный, плохой старт выбрасывают и начинают заново — это "
			.. "дёшево. После Regal предмет редкий, и каждый следующий шаг уже стоит денег.",
		check = function(item)
			return tostring(item.rarity or ""):upper() == "MAGIC"
				or tostring(item.rarity or ""):upper() == "NORMAL"
		end,
	},
	{
		id = "lock_good",
		title = "Regal только когда оба мода волшебного предмета годятся",
		text = "Regal поднимает до редкого и сохраняет оба мода, добавляя третий случайный. Поэтому его применяют, "
			.. "когда терять нечего: оба мода уже хороши. Слать Regal на мусор — способ заплатить за редкий мусор.",
		check = function(item)
			return tostring(item.rarity or ""):upper() == "MAGIC"
		end,
	},
	{
		id = "control_not_gamble",
		title = "Управление вместо рулетки: эссенция, руна, омен",
		text = "Эссенция ставит гарантированный мод. Руна — бесплатный гарантированный мод в сокет. Омен "
			.. "направляет следующую валюту: сторона, самый слабый мод, два мода сразу. Это дороже ставки, но "
			.. "это единственный способ получить нужное, а не надеяться.",
		check = function(item, advice)
			for _, option in ipairs((advice and advice.omenOptions) or { }) do
				if option.deterministic or option.kind == "essence" or option.kind == "rune" then
					return true
				end
			end
			return false
		end,
	},
	{
		id = "stop_point",
		title = "Точка остановки: крафт против покупки",
		text = "Перед каждым дорогим шагом считают, во что обойдётся крафт и сколько стоит готовый предмет. Если "
			.. "крафт дороже — его не начинают. Второе: заранее решают, какое состояние считается «достаточно "
			.. "хорошим», иначе вложение не заканчивается.",
		check = function(item, advice)
			-- This lesson is relevant once there is a priced way to spend on the item.
			for _, plan in ipairs((advice and advice.plans) or { }) do
				for _, step in ipairs(plan.steps or { }) do
					if step.cost == "high" or step.cost == "veryhigh" then
						return true
					end
				end
			end
			return false
		end,
	},
	{
		id = "irreversible_last",
		title = "Необратимое — последним",
		text = "Vaal и освящение закрывают предмет для крафта навсегда. Их делают, когда результат уже "
			.. "устраивает, и никогда — на предмете, который ещё собираются доделывать.",
		check = function(item)
			return tostring(item.rarity or ""):upper() == "RARE"
		end,
	},
}

--- The course in English, keyed by lesson id.
--
-- Kept as one block rather than a "titleEn" twin inside every Russian block: the lessons are long
-- paragraphs with line continuation, and a twin inline made each one hard to read. A lesson id without
-- an entry here is a failing assertion in Tests.test_language, so nothing can be forgotten silently.
Curriculum.EN = {
	read_item = {
		title = "Read the item: prefixes, suffixes, free slots",
		text = "The first thing an experienced crafter does is count how many sides are taken and how "
			.. "many are open. Prefix and suffix are different sides, and they decide what can be added "
			.. "at all. Until this is read, any advice is a guess.",
	},
	base_and_ilvl = {
		title = "The base and the item level decide which tier is possible at all",
		text = "The item level caps the highest modifier tier: on a low ilvl the top tier simply will not "
			.. "roll, however much is paid. The base decides which modifier families are available at all. "
			.. "This is checked BEFORE the first currency, because it cannot be undone.",
	},
	cheap_tier = {
		title = "The cheap Magic stage is the only reroll there is",
		text = "There is no full reroll in PoE 2. While the item is Magic, a bad start is thrown away and "
			.. "begun again, and that is cheap. After Regal the item is Rare, and every further step costs "
			.. "money.",
	},
	lock_good = {
		title = "Regal only when both Magic modifiers are worth keeping",
		text = "Regal raises the item to Rare and keeps both modifiers, adding a third one at random. So it "
			.. "is used when there is nothing to lose: both modifiers are already good. Sending Regal at "
			.. "junk is a way to pay for a rare piece of junk.",
	},
	control_not_gamble = {
		title = "Control instead of roulette: essence, rune, omen",
		text = "An essence sets a guaranteed modifier. A rune is a free guaranteed modifier in a socket. An "
			.. "omen steers the next currency: the side, the weakest modifier, two modifiers at once. It "
			.. "costs more than a bet, but it is the only way to get what is needed instead of hoping.",
	},
	stop_point = {
		title = "The stopping point: crafting against buying",
		text = "Before every expensive step, count what the craft will cost and what the finished item "
			.. "costs. If crafting is dearer, it is not started. Second: decide in advance which state "
			.. "counts as good enough, or the investment never ends.",
	},
	irreversible_last = {
		title = "The irreversible ones go last",
		text = "Vaal and sanctification close the item to crafting for good. They are done when the result "
			.. "already satisfies, and never on an item that is still being finished.",
	},
}

--- Lessons that apply to this item, and which of them the item already demonstrates.
-- @param item parsed item
-- @param advice advisor result (may be nil: the checks that need it are skipped)
-- @return list of { id, title, text, done }
function Curriculum.forItem(item, advice)
	local out = { }
	for _, lesson in ipairs(Curriculum.LESSONS) do
		local ready = true
		if item == nil then
			ready = false
		elseif lesson.needs then
			ready = lesson.needs(item, advice) ~= false
		end
		if ready then
			local ok, done = pcall(lesson.check, item, advice)
			local english = Curriculum.EN[lesson.id] or { }
			out[#out + 1] = {
				id = lesson.id,
				title = lesson.title,
				titleEn = english.title,
				text = lesson.text,
				textEn = english.text,
				done = ok and done == true,
			}
		end
	end
	return out
end

--- How far along the course the player is on this item.
-- @return { total, done, nextLesson }
function Curriculum.progress(item, advice)
	local lessons = Curriculum.forItem(item, advice)
	local done, nextLesson = 0, nil
	for _, lesson in ipairs(lessons) do
		if lesson.done then
			done = done + 1
		elseif nextLesson == nil then
			nextLesson = lesson
		end
	end
	return { total = #lessons, done = done, nextLesson = nextLesson }
end

--- One lesson by id, for the reference list and tests.
function Curriculum.byId(id)
	for _, lesson in ipairs(Curriculum.LESSONS) do
		if lesson.id == id then
			return lesson
		end
	end
	return nil
end

return Curriculum
