-- The panel shows the item as the game does: its properties and its modifiers, nothing else.
return function()
local H = require("Tests.harness")
local Lines = require("Item.Lines")

local ITEM = table.concat({
	"Класс предмета: Шлемы",
	"Редкость: Редкий",
	"Имя предмета",
	"Чародейская тиара",
	"--------",
	"Качество: +20% (augmented)",
	"Энергетический щит: 218 (augmented)",
	"--------",
	"Требуется: Уровень 70, 99 Инт",
	"--------",
	'{ Расколотое Суффикс "разрушения" (Уровень: 1) — Урон }',
	"38(35-39)% увеличение урона",
	'{ Префикс "Синеватый" (Уровень: 1) — Мана }',
	"+190(150-164) к максимуму маны",
	"--------",
	"«Даже перед лицом зимы жизнь нашла лазейку.»",
	"Пополняется у колодцев или по мере убийства монстров.",
	"--------",
	"Осквернено",
}, "\n")

local split = Lines.split(ITEM)

H.eq("lines: three properties of the item", #split.properties, 3)
H.eq("lines: quality comes first", split.properties[1].label, "Качество")
H.eq("lines: quality keeps its value", split.properties[1].value, "+20% (augmented)")
H.eq("lines: the defence value is a property, not a modifier", split.properties[2].label, "Энергетический щит")
H.eq("lines: requirements are shown as the game shows them", split.properties[3].label, "Требуется")
H.eq("lines: only the two real modifiers are listed", #split.mods, 2)
H.eq("lines: the rolled value is shown, not the range", split.mods[1].text, "38% увеличение урона")
H.eq("lines: a fractured modifier is marked", split.mods[1].fractured, true)
H.eq("lines: an ordinary modifier is not marked", split.mods[2].fractured, false)
H.eq("lines: the second modifier keeps its plus", split.mods[2].text, "+190 к максимуму маны")
H.eq("lines: corruption is a flag, not a line", split.flags.corrupted, true)
H.eq("lines: the name comes from the client's text", split.header.name, "Имя предмета")
H.eq("lines: the base comes from the client's text", split.header.base, "Чародейская тиара")
H.eq("lines: the class block adds nothing", split.properties[1].label ~= "Класс предмета", true)
end
