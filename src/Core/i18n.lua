-- PoE2 Craft Overlay : Core/i18n.lua
-- The host renders text with PoB's bitmap fonts (Fontin / Liberation), which carry no
-- Cyrillic glyphs: non-ASCII bytes come out as "[u0431][u0432]..." placeholders.
-- Therefore:
--   * the on-screen panel uses ASCII-only strings (see Launch.lua and the *En fields),
--   * logs, console dumps and last_advice.txt stay in Russian (plain UTF-8 files).
--
-- Notes are therefore emitted as *codes* with parameters and localised at render time,
-- instead of being baked in as one language's sentence.

local i18n = { }

--- Russian plural form for a count: 1 мод / 2 мода / 5 модов.
--
-- A Russian sentence cannot be built by gluing "%d мод(ов)" together: the noun AND the verb have to agree
-- with the number, and "3 мод(ов)" is what a translation looks like when nobody checked. These are the
-- standard three forms; the caller picks the word, this picks the form.
-- @param count number
-- @param one string form for 1, 21, 31 ...
-- @param few string form for 2-4, 22-24 ...
-- @param many string form for 0, 5-20, 25-30 ...
function i18n.plural(count, one, few, many)
	local number = math.floor(math.abs(tonumber(count) or 0))
	local last = number % 10
	local lastTwo = number % 100
	if last == 1 and lastTwo ~= 11 then
		return one
	end
	if last >= 2 and last <= 4 and not (lastTwo >= 12 and lastTwo <= 14) then
		return few
	end
	return many
end

local NOTES = {
	empty_input = {
		en = "empty item text",
		ru = "пустой текст предмета",
	},
	no_rarity_header = {
		en = "no 'Rarity:' header found; parsed as headerless text",
		ru = "строка «Редкость:» не найдена; текст разобран как разметка без заголовка",
	},
	no_name = {
		en = "item name not found",
		ru = "имя предмета не найдено",
	},
	no_base = {
		en = "base type not found (expected two lines: name and base)",
		ru = "строка базы не найдена (ожидались две строки: имя и база)",
	},
	unparsed_property = {
		en = "unrecognised property line: %s",
		ru = "неопознанная строка свойства: %s",
	},
	suspected_implicit = {
		en = "%d untagged mod(s) may be implicits - use the advanced copy for certainty",
			-- A function, because the noun and the verb must agree with the number: "1 мод ... может", "3 мода ...
		-- могут". The English sentence is fine as a plain string.
		ru = function(count)
			local number = math.floor(math.abs(tonumber(count) or 0))
			local noun = i18n.plural(number, "мод", "мода", "модов")
			local verb = (number % 10 == 1 and number % 100 ~= 11) and "может быть имплиситом"
				or "могут быть имплиситами"
			return string.format("%d %s без тега %s — для точности используйте расширенное копирование",
				number, noun, verb)
		end,
	},
	low_item_level = {
		en = "item level %d is low: top mod tiers are out of reach, costly currency will not pay off",
		ru = "уровень предмета %d низкий: топовые тиры недостижимы, дорогая валюта не окупится",
	},
	corrupted_check = {
		en = "item is corrupted - verify the chosen step is still applicable",
		ru = "предмет осквернён — проверьте, что выбранный шаг ещё применим",
	},
	full_affixes = {
		en = "all 6 affix slots are taken: free a slot first (Chaos/Annulment), then add",
		ru = "все 6 слотов аффиксов заняты: сначала освободите слот (Chaos/Annulment), потом добавляйте",
	},
	no_rule = {
		en = "no rule matches this item state - add one to the league ruleset",
		ru = "ни одно правило не подходит под состояние предмета — добавьте его в свод лиги",
	},
	pool_missing = {
		en = "%s: the modifier pool for this item class is not in our data (waystones, tablets and relics are absent from Path of Building), so the affix split is unknown and no slot rule is applied",
		ru = "%s: пула модов для этого класса предметов нет в наших данных (Waystone, Tablet и Relic отсутствуют в Path of Building), поэтому деление на префиксы и суффиксы неизвестно и правило по слотам не применяется",
	},
	prefixes_full = {
		en = "all prefixes are taken: the next currency can only add a suffix (%d suffix slot(s) open)",
		ru = "все префиксы заняты: следующая валюта может добавить только суффикс (свободно суффиксов: %d)",
	},
	suffixes_full = {
		en = "all suffixes are taken: the next currency can only add a prefix (%d prefix slot(s) open)",
		ru = "все суффиксы заняты: следующая валюта может добавить только префикс (свободно префиксов: %d)",
	},
	tier_estimated = {
		en = "tier estimated from item level (value matched no range) for %d mod(s)",
			ru = function(count)
			local number = math.floor(math.abs(tonumber(count) or 0))
			-- After "у" the genitive singular goes with 1 and the genitive plural with everything else.
			return string.format("тир оценён по уровню предмета (значение не попало в диапазон) у %d %s",
				number, i18n.plural(number, "мода", "модов", "модов"))
		end,
	},
	affix_split_unknown = {
		en = "%d modifier(s) unrecognised: prefix/suffix split unknown, slot-based rules are skipped",
		ru = "не опознано модов: %d — деление на префиксы и суффиксы неизвестно, правила по слотам пропущены",
	},
	split_unknown_no_rule = {
		en = "%d modifier(s) unrecognised, so how many prefix and suffix slots are free is unknown - no step is offered, because every step here depends on that; copy the item with the game's advanced copy (Ctrl+C on the item) so the annotations come with it",
		ru = "не опознано модов: %d, поэтому неизвестно, сколько слотов префиксов и суффиксов свободно — шаг не предлагается, потому что здесь от этого зависит всё; скопируйте предмет расширенным копированием игры (Ctrl+C по предмету), чтобы пришли аннотации",
	},
	affix_split_inconsistent = {
		en = "%d prefix(es) and %d suffix(es) recognised - impossible for %s, so a line was misread; slot advice is disabled",
		ru = "распознано префиксов: %d, суффиксов: %d — для %s это невозможно, значит строка прочитана неверно; советы по слотам отключены",
	},
	crafted_slot_taken = {
		en = "the item already carries a crafted modifier (%d): 0.5 allows only one, so an essence or alloy replaces it - pick one route",
		ru = "на предмете уже есть созданный мод (%d): в 0.5 разрешён только один, поэтому эссенция или сплав его заменят — выберите один путь",
	},
}

--- Format a note code in the requested language.
-- @param code string key of NOTES
-- @param params table|nil positional values for string.format
-- @param lang "ru"|"en"
function i18n.note(code, params, lang)
	local entry = NOTES[code]
	if not entry then
		return tostring(code)
	end
	-- The requested language first, English as the fallback: a code without a translation must still read
	-- as a sentence rather than as its own name.
	local template = entry[lang] or entry.en
	-- An entry may be a function instead of a format string: Russian needs the noun and the verb to agree
	-- with the number, which string.format cannot do by itself.
	if type(template) == "function" then
		local ok, text = pcall(template, unpack(params or { }))
		if ok and text then
			return text
		end
		return tostring(code)
	end
	if params then
		local ok, text = pcall(string.format, template, unpack(params))
		if ok then return text end
	end
	return template
end

--- Render a note table (from the parser or the advisor).
function i18n.notes(noteList, lang)
	local out = { }
	for _, note in ipairs(noteList or { }) do
		if type(note) == "table" and note.code then
			out[#out + 1] = i18n.note(note.code, note.params, lang)
		else
			out[#out + 1] = tostring(note)
		end
	end
	return out
end

--- True when the string can be drawn with the shipped fonts.
function i18n.isAscii(s)
	return tostring(s):find("[\128-\255]") == nil
end

--- Replace bytes the bitmap fonts cannot draw, keeping the layout readable.
function i18n.asciiSafe(s)
	return (tostring(s):gsub("[\128-\255]", "?"))
end

return i18n
