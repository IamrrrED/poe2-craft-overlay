-- PoE2 Craft Overlay : Craft/GenesisTree.lua
-- The Genesis Tree as a set of plans, not a paragraph.
--
-- Why this is an advisor and not a data entry. The tree answers a question a beginner actually asks - "how do
-- I get the catalyst I need?" - and the answer has a shape: which Wombgift to put in which womb, which nodes
-- to allocate, and how many births it takes on average. Since 0.5.0 catalysts no longer drop from monsters, so
-- without this the mentor could not explain where jewellery quality comes from at all.
--
-- Every number here is a published chance (basicknowledge.xyz/poe2/craft/genesis-tree, quoting the 0.5.0
-- notes), and the attempts are 1/chance - arithmetic on those numbers, not a guess. Where the source states an
-- ordering rather than a number (the 10%-then-5% for a Refined Breach Ring), the two rolls are multiplied and
-- said to be two rolls.
local GenesisTree = { }

--- A goal is what the player wants OUT of the tree.
-- `chance` is the probability that one birth produces it.
GenesisTree.GOALS = {
	{
		id = "catalyst_any",
		title = "Любой катализатор (для качества украшений)",
		titleEn = "Any catalyst (for jewellery quality)",
		womb = "currency",
		wombgift = "Lavish Wombgift",
		chanceKey = "catalystChance",
		nodes = { "Catalyst Chance (15%)", "Can only Birth Catalysts — чтобы валюта была только катализатором" },
		nodesEn = { "Catalyst Chance (15%)", "Can only Birth Catalysts - so the currency is catalysts only" },
		why = "Катализаторы с 0.5.0 не падают с монстров: только дерево. Один бросок на предмет валюты, "
			.. "шанс катализатора 15% — поэтому искать КОНКРЕТНЫЙ катализатор дорого, а не «какой-нибудь» дёшево. "
			.. "Есть и вторая нода: 30% на ДОПОЛНИТЕЛЬНЫЙ катализатор того же типа, она снижает число рождений, "
			.. "но не меняет шанс нужного типа.",
		whyEn = "Since 0.5.0 catalysts no longer drop from monsters: the tree only. One roll per currency "
			.. "item, a 15% catalyst chance - so hunting a SPECIFIC catalyst is expensive, while hunting "
			.. "\"any\" one is cheap. There is a second node as well: 30% for an EXTRA catalyst of the same "
			.. "type; it cuts the number of births but does not change the chance of the type you need.",
		risk = "катализатор случайный: какой именно — не выбирается, кроме как запретами в нодах",
		riskEn = "the catalyst is random: which one is not chosen, except through bans in the nodes",
	},
	{
		id = "catalyst_refined",
		title = "Refined-катализатор (для ювелирки)",
		titleEn = "Refined catalyst (for jewels)",
		womb = "currency",
		wombgift = "Lavish Wombgift",
		chanceKey = "refinedCatalystChance",
		nodes = { "Jewel Catalyst Chance (4%)", "Enhanced Creation (10%)" },
		why = "Refined-катализаторы идут через ВТОРОЙ бросок, поэтому их шанс 4%, а не 15%. Это самая дорогая "
			.. "цель в дереве и причина, почему ювелирное качество дороже обычного.",
		whyEn = "Refined catalysts go through a SECOND roll, so their chance is 4%, not 15%. This is the "
			.. "most expensive goal in the tree and the reason jewel quality costs more than ordinary quality.",
		risk = "два броска подряд: даже при удаче первого можно не получить Refined",
		riskEn = "two rolls in a row: a lucky first roll can still miss Refined",
	},
	{
		id = "ring",
		title = "Кольцо",
		titleEn = "Ring",
		womb = "ring",
		wombgift = "Signet Wombgift",
		chance = 1.0,
		nodes = {},
		why = "Signet Wombgift в кольцевую утробу даёт кольцо всегда — редкость и моды случайны. Ноды "
			.. "смещают, какие именно кольца выпадают.",
		whyEn = "Signet Wombgift in the ring womb always produces a ring - rarity and modifiers are random. "
			.. "Nodes bias which rings come out.",
		risk = "содержимое случайное: это способ получить базу, а не нужные моды",
		riskEn = "the contents are random: this is a way to get a base, not the modifiers you need",
	},
	{
		id = "breach_ring",
		title = "Breach Ring (база с потолком качества 40%)",
		titleEn = "Breach Ring (base with a 40% quality cap)",
		womb = "ring",
		wombgift = "Signet Wombgift",
		-- 10% of birthed items are Breach Rings.
		chanceKey = "breachRingChance",
		nodes = {},
		why = "Breach Ring можно найти и обычным дропом, но у него есть имплисит «Maximum Quality is 40%», "
			.. "поэтому он и есть правильная база для катализаторов.",
		whyEn = "A Breach Ring can also be found as an ordinary drop, but it carries the implicit "
			.. "\"Maximum Quality is 40%\", which is why it is the right base for catalysts.",
		risk = "10% — это шанс на предмет, а не гарантия; дешевле купить, если цена базы ниже стоимости рождений",
		riskEn = "10% is a chance per item, not a guarantee; buying is cheaper when the base price is below "
			.. "the cost of the births",
	},
	{
		id = "refined_breach_ring",
		title = "Refined Breach Ring (потолок 45%)",
		titleEn = "Refined Breach Ring (45% cap)",
		womb = "ring",
		wombgift = "Signet Wombgift",
		-- Two rolls: 10% to be a Breach Ring, then 5% to be Refined instead.
		chanceKey = "refinedBreachRing",
		nodes = {},
		why = "Самый дорогой результат дерева: 10% что предмет вообще Breach Ring, затем 5% что он Refined. "
			.. "Никаким другим путём его не получить — только из дерева.",
		whyEn = "The most expensive result in the tree: 10% that the item is a Breach Ring at all, then 5% "
			.. "that it is Refined. There is no other route to it - the tree only.",
		risk = "два броска: 0.5% на рождение, то есть в среднем две сотни рождений",
		riskEn = "two rolls: 0.5% per birth, that is two hundred births on average",
	},
	{
		id = "amulet",
		title = "Амулет",
		titleEn = "Amulet",
		womb = "amulet",
		wombgift = "Ornate Wombgift",
		chance = 1.0,
		nodes = {},
		why = "Ornate Wombgift в утробу амулетов даёт амулет всегда; редкость и моды случайны.",
		whyEn = "Ornate Wombgift in the amulet womb always produces an amulet; rarity and modifiers are random.",
		risk = "содержимое случайное",
		riskEn = "the contents are random",
	},
	{
		id = "belt",
		title = "Пояс",
		titleEn = "Belt",
		womb = "belt",
		wombgift = "Banded Wombgift",
		chance = 1.0,
		nodes = {},
		why = "Banded Wombgift в утробу поясов даёт пояс всегда; редкость и моды случайны.",
		whyEn = "Banded Wombgift in the belt womb always produces a belt; rarity and modifiers are random.",
		risk = "содержимое случайное",
		riskEn = "the contents are random",
	},
	{
		id = "breachstone",
		title = "Бречстоун",
		titleEn = "Breachstone",
		womb = "breachstone",
		wombgift = "Revelatory Wombgift",
		chance = 1.0,
		nodes = {},
		why = "Revelatory Wombgift даёт бречстоун — это про вход в Breach-босса, а не про крафт снаряжения.",
		whyEn = "Revelatory Wombgift gives a Breachstone - that is about entering the Breach boss, not about "
			.. "crafting gear.",
		risk = "к крафту предметов отношения не имеет",
		riskEn = "it has nothing to do with crafting items",
	},
}

--- The probability that one birth yields the goal.
-- @param goal a GOALS entry
-- @param ruleset league table (carries the chances)
-- @return number in (0, 1]
function GenesisTree.chanceOf(goal, ruleset)
	if tonumber(goal.chance) then
		return goal.chance
	end
	local tree = (ruleset or { }).genesisTree or { }
	if goal.chanceKey == "refinedBreachRing" then
		-- Stated as two rolls in the source: 10% to be a Breach Ring, then 5% to be Refined.
		local ring = tonumber(tree.breachRingChance) or 0
		local refined = tonumber(tree.refinedBreachRingChance) or 0
		return ring * refined
	end
	return tonumber(tree[goal.chanceKey]) or 0
end

--- The plan for one goal.
-- @param goalId a GOALS id
-- @param ruleset league table
-- @return table|nil { goal, wombgift, chance, expectedBirths, steps, note } or nil for an unknown goal
function GenesisTree.plan(goalId, ruleset)
	local goal = nil
	for _, entry in ipairs(GenesisTree.GOALS) do
		if entry.id == tostring(goalId or "") then goal = entry end
	end
	if not goal then
		return nil
	end
	local chance = GenesisTree.chanceOf(goal, ruleset)
	local expected = chance > 0 and math.floor((1 / chance) * 100 + 0.5) / 100 or nil
	local steps = {
		{
			action = "Собрать Wombgift и Hiveblood",
			actionEn = "Gather a Wombgift and Hiveblood",
			what = "оба падают с Breach-монстров: Hiveblood тратится на активацию, Wombgift — на рождение",
			whatEn = "both drop from Breach monsters: Hiveblood is spent on activation, the Wombgift on the birth",
			risk = "без Hiveblood дерево не запустится, даже если Wombgift есть",
			riskEn = "without Hiveblood the tree does not start, even with a Wombgift in hand",
		},
		{
			action = "Выделить ноды под эту цель",
			actionEn = "Allocate the nodes for this goal",
			what = #goal.nodes > 0 and table.concat(goal.nodes, "; ") or "для этой цели ноды не нужны",
			whatEn = #goal.nodes > 0 and table.concat(goal.nodesEn or goal.nodes, "; ")
				or "no nodes are needed for this goal",
			-- Passives on the tree can be freely refunded and reallocated, so this is NOT a commitment.
			-- Saying otherwise would have made a beginner afraid to try the setup at all.
			risk = "ничего не теряете: пассивные ноды дерева снимаются и ставятся заново бесплатно",
			riskEn = "nothing is lost: tree passives are removed and reallocated for free",
		},
		{
			action = "Вложить " .. goal.wombgift,
			actionEn = "Insert " .. goal.wombgift,
			what = "в утробу «" .. goal.womb .. "»",
			whatEn = "into the womb: " .. goal.womb,
			risk = goal.risk or "результат случайный",
			riskEn = goal.riskEn or "the result is random",
		},
	}
	if expected and expected > 1 then
		steps[#steps + 1] = {
			action = "Повторять",
			actionEn = "Repeat",
			what = string.format("в среднем %.1f рождения на одну цель (шанс %.0f%%)",
				expected, chance * 100),
			whatEn = string.format("on average %.1f births per goal (%.0f%% chance)",
				expected, chance * 100),
			risk = "это среднее, а не гарантия: половина игроков получит раньше, половина позже",
			riskEn = "this is an average, not a guarantee: half the players get it sooner, half later",
		}
	end
	return {
		goal = goal.id,
		title = goal.title,
		titleEn = goal.titleEn or goal.title,
		wombgift = goal.wombgift,
		womb = goal.womb,
		chance = chance,
		expectedBirths = expected,
		steps = steps,
		why = goal.why,
		whyEn = goal.whyEn or goal.why,
	}
end

--- Every goal with its numbers, for a reference list.
function GenesisTree.overview(ruleset)
	local out = { }
	for _, goal in ipairs(GenesisTree.GOALS) do
		local chance = GenesisTree.chanceOf(goal, ruleset)
		out[#out + 1] = {
			id = goal.id,
			title = goal.title,
			titleEn = goal.titleEn or goal.title,
			wombgift = goal.wombgift,
			chance = chance,
			expectedBirths = chance > 0 and math.floor((1 / chance) * 100 + 0.5) / 100 or nil,
		}
	end
	return out
end

return GenesisTree
