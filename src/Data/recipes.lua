-- PoE2 Craft Overlay : Data/recipes.lua
-- Routes built ONLY from rules that survived the consensus bar, and every step names the rule it stands on.
--
-- Why a file and not prose: the panel used to show one step plus everything known about it, and a player who
-- wanted a plan had to assemble it from seven blocks. A route is the opposite - a goal, three steps and the
-- point where you stop - and it is data, so a step cannot appear without a rule behind it.
--
-- The rules are tagged C1..C8 and defined once below. They come from docs/craft-consensus-0.5.md:
--   * six claims passed (>=5 independent confirmations, 0 contradictions),
--   * C8 came from the official 0.5.0 patch notes,
--   * C7 was excluded (1 for, 3 against) and therefore appears NOWHERE in this file - the test enforces it.
local Recipes = {
	version = "0.5",

	--- The rules, short, with where each one comes from. `verified` is the consensus verdict, not an opinion.
	rules = {
		C1 = {
			text = "Один crafted-мод на предмет; эссенции считаются crafted",
			textEn = "One crafted modifier per item; essences count as crafted",
			verified = true,
			source = "патчноуты 0.5.0 + stratlore + switchblade + 5 видео",
		},
		C2 = {
			text = "Великое возвышение: следующий exalt даёт два мода",
			textEn = "Greater Exaltation: the next exalt adds two modifiers",
			verified = true,
			source = "патчноуты + вики оменов + poe2db + 8 видео",
		},
		C3 = {
			text = "Некромантия левши/правши форсирует сторону дезекрации",
			textEn = "Sinistral/Dextral Necromancy forces the desecration side",
			verified = true,
			source = "вики оменов + poe2craft + 10 видео",
		},
		C4 = {
			text = "Дезекрацию нельзя фракнуть: с ней шанс фрактуры 1/3 вместо 1/4",
			textEn = "A desecrated modifier cannot be fractured: with one the fracture odds are 1/3 not 1/4",
			verified = true,
			source = "poe2wiki (Fracturing Orb) + timesaver + poe2fun + 2 видео",
		},
		C5 = {
			text = "Предзнаменование света + отмена снимает дезекрацию; отголоски Бездны перебрасывают витрину",
			textEn = "Omen of Light + annul removes the desecration; Abyssal Echoes rerolls the reveal",
			verified = true,
			source = "вики оменов + poe2craft + 9 видео",
		},
		C8 = {
			text = "Дезекрация — отдельный слот: одна на предмет, не crafted",
			textEn = "Desecration is its own slot: one per item, not crafted",
			verified = true,
			source = "патчноуты 0.5.0",
		},
		-- C7 is deliberately absent: 1 confirmation, 3 contradictions. See the consensus document.
	},

	--- Routes. `classes` matches the item's class name as the game prints it, lowercased.
	recipes = {
		{
			id = "es_res_armour",
			goal = "Три префикса энергощита + три сопротивления (шлем, перчатки, нагрудник)",
			goalEn = "Three energy-shield prefixes plus three resistances (helmet, gloves, body armour)",
			classes = { "helmets", "gloves", "body armours", "boots", "shields" },
			minIlvl = 78,
			steps = {
				{
					n = 1,
					action = "Одна эссенция на энергощит: она делает предмет редким и даёт префикс",
					actionEn = "One energy-shield essence: it makes the item rare and adds a prefix",
					rules = { "C1" },
				},
				{
					n = 2,
					action = "Предзнаменование некромантии левши + ребро: дезекрация уходит в префикс (гибрид энергощит/жизнь)",
					actionEn = "Sinistral Necromancy + rib: the desecration lands as a prefix (hybrid ES/life)",
					rules = { "C3", "C8" },
				},
				{
					n = 3,
					action = "Великое возвышение + возвышение правши: два мода, оба в суффиксы — добиваем сопротивления",
					actionEn = "Greater Exaltation + Dextral Exaltation: two modifiers, both suffixes - finish the resistances",
					rules = { "C2" },
				},
			},
			stopRule = "Стоп: два префикса энергощита + гибрид, и три сопротивления. Плохой показ — не конец: "
				.. "Omen of Light + annul, затем дезекрация заново",
			stopRuleEn = "Stop: two ES prefixes plus the hybrid, and three resistances. A bad reveal is not the end: "
				.. "Omen of Light + annul, then desecrate again",
			stopRules = { "C5", "C8" },
		},
		{
			id = "fracture_weapon",
			goal = "Оружие с зафракнутым ключевым модом и добитыми модами вокруг",
			goalEn = "A weapon with the key modifier fractured and the rest finished around it",
			classes = { "bows", "crossbows", "quarterstaves", "wands", "sceptres", "two hand maces",
				"one hand maces", "spears", "staves" },
			minIlvl = 0,
			steps = {
				{
					n = 1,
					action = "Сначала добиваем предмет до 3 обычных модов, затем дезекрация (один слот)",
					actionEn = "First build the item to 3 normal modifiers, then desecrate (one slot)",
					rules = { "C8" },
				},
				{
					n = 2,
					action = "Фрактура: дезекрация в розыгрыш не входит, поэтому шанс 1 из 3, а не 1 из 4",
					actionEn = "Fracture: the desecration is not in the draw, so it is 1 in 3, not 1 in 4",
					rules = { "C4" },
				},
				{
					n = 3,
					action = "Остальное добиваем возвышениями; великое возвышение = два мода за один",
					actionEn = "Finish the rest with exalt slams; Greater Exaltation means two modifiers per orb",
					rules = { "C1", "C2" },
				},
			},
			stopRule = "Стоп: зафракнут ключевой мод и закрыты нужные префиксы/суффиксы. Провал фрактуры — новый базис",
			stopRuleEn = "Stop: the key modifier is fractured and the wanted prefixes/suffixes are closed. "
				.. "A failed fracture means a new base",
			stopRules = { "C4" },
		},
		{
			id = "desecration_reroll",
			goal = "Дожать нужный дезекрация-мод, не теряя предмет",
			goalEn = "Land the needed desecrated modifier without losing the item",
			classes = {},
			minIlvl = 0,
			steps = {
				{
					n = 1,
					action = "Дезекрация с нужной стороны (левши — префикс, правши — суффикс)",
					actionEn = "Desecrate on the wanted side (Sinistral for prefix, Dextral for suffix)",
					rules = { "C3", "C8" },
				},
				{
					n = 2,
					action = "Плохой показ: Предзнаменование света + аннулирование снимает дезекрацию точечно",
					actionEn = "Bad reveal: Omen of Light + annul removes the desecration on purpose",
					rules = { "C5" },
				},
				{
					n = 3,
					action = "Предзнаменование отголосков Бездны перебрасывает витрину, затем повторная дезекрация",
					actionEn = "Abyssal Echoes rerolls the reveal, then desecrate again",
					rules = { "C5", "C8" },
				},
			},
			stopRule = "Стоп: выпал нужный мод, или откат стоит дороже базиса — тогда новый базис, не спор со случаем",
			stopRuleEn = "Stop: the wanted modifier landed, or the reroll costs more than the base - then a new "
				.. "base, not a fight with RNG",
			stopRules = { "C5" },
		},
	},
}

--- Routes that apply to this item, most specific first.
--
-- Matching is deliberately crude and explainable: the item's class (as the game prints it) must be in the
-- route's class list, and the item level must reach its floor. A route with an empty class list applies to any
-- item - those are the "any item" techniques, not recipes for a specific slot.
-- @param item parsed item (needs .class and .itemLevel)
-- @return array of routes
function Recipes.forItem(item)
	local found = { }
	if type(item) ~= "table" then
		return found
	end
	-- The parser keeps the class as `itemClass` ("Gloves", "Body Armours"); the base name is the fallback,
	-- because a route about "a weapon" should still match when the header names the base only.
	local class = tostring(item.itemClass or item.class or ""):lower()
	if class == "" then
		class = tostring(item.baseType or ""):lower()
	end
	local level = tonumber(item.itemLevel) or 0
	for _, recipe in ipairs(Recipes.recipes) do
		local applies = #recipe.classes == 0
		for _, wanted in ipairs(recipe.classes) do
			if class:find(wanted, 1, true) then
				applies = true
				break
			end
		end
		if applies and level >= (tonumber(recipe.minIlvl) or 0) then
			found[#found + 1] = recipe
		end
	end
	return found
end

--- Every rule id a route uses, in order. Used by the test that keeps C7 out.
function Recipes.ruleIdsOf(recipe)
	local ids = { }
	for _, step in ipairs((recipe or { }).steps or { }) do
		for _, id in ipairs(step.rules or { }) do
			ids[#ids + 1] = id
		end
	end
	for _, id in ipairs((recipe or { }).stopRules or { }) do
		ids[#ids + 1] = id
	end
	return ids
end

--- What the item's own state forbids, said before any step is taken.
--
-- The consensus rules C1 and C8 are limits, not techniques: an item has ONE crafted slot and ONE desecrated
-- slot. A route that keeps proposing an essence on an item whose crafted slot is taken, or a second
-- desecration, is telling the player to waste currency - and the two slots are separate, which is the
-- useful half of the rule ("essence and desecration do stack").
-- @param state the state table from the coach report
-- @return array of { text = russian, textEn = english }
function Recipes.stateNotes(state)
	local notes = { }
	if type(state) ~= "table" then
		return notes
	end
	if state.desecratedAnchorUsed then
		notes[#notes + 1] = {
			text = "Осквернённый слот уже занят: дезекрация одна на предмет (C8). Второй не будет — сначала "
				.. "Предзнаменование света + отмена, затем дезекрация заново.",
			textEn = "The desecrated slot is already taken: one per item (C8). A second one will not happen - "
				.. "Omen of Light + annul first, then desecrate again.",
		}
	end
	if state.craftedAnchorUsed then
		notes[#notes + 1] = {
			text = "Созданный мод уже стоит: эссенция его ЗАМЕНИТ, а не добавится второй (C1).",
			textEn = "A crafted modifier is already there: an essence will REPLACE it, not add a second one (C1).",
		}
	end
	if not state.craftedAnchorUsed and not state.desecratedAnchorUsed then
		notes[#notes + 1] = {
			text = "Созданный и осквернённый — разные слоты: эссенция и дезекрация совместимы (C8).",
			textEn = "Crafted and desecrated are different slots: an essence and a desecration do stack (C8).",
		}
	end
	return notes
end

return Recipes