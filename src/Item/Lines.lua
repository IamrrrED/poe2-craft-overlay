--- The item's own lines, ready for the panel to draw.
--
-- The rules were worked out against real items while the site showed them. The text the client
-- itself copied is the source, because it is already in the player's language and the engine's
-- parsed form is not. The header block (class, rarity, name, base) is skipped, a "label: value"
-- line is a property of the item rather than a modifier, quoted flavour and full sentences are
-- dropped, and a rolled value is printed without the range it could have rolled from.
local Lines = { }

--- Labels that describe the item itself, not a modifier of it.
local META = {
	"Уровень предмета", "Гнезда", "Размещение предмета", "Прочность", "Цена", "Стоимость",
	"Класс предмета", "Редкость",
	"Item Class", "Rarity", "Item Level", "Sockets", "Stack Size", "Note",
}

--- Lua strings are bytes, so a check has to compare the whole prefix, not one character.
local function startsWith(line, prefix)
	return line:sub(1, #prefix) == prefix
end

local function endsWith(line, suffix)
	return #line >= #suffix and line:sub(-#suffix) == suffix
end

local function isMeta(line)
	for _, label in ipairs(META) do
		if startsWith(line, label) then
			return true
		end
	end
	return false
end

--- "69(68-79)% increased …" reads as "69% increased …": the range is not what rolled.
local function withoutRange(text)
	return (text:gsub("%s*%([%d%.,]+%s*%-%s*[%d%.,]+%)", ""))
end

--- "Качество: +20%" becomes a label and a value, so the panel can colour them separately.
local function asProperty(line)
	local found = line:find(":", 1, true)
	if not found then
		return nil
	end
	local label = line:sub(1, found - 1)
	local value = line:sub(found + 1)
	-- Byte counts, not characters: Cyrillic takes two bytes each, so the limit is doubled.
	if #label == 0 or #label > 68 then
		return nil
	end
	return { label = label, value = (value:gsub("^%s+", "")) }
end

--- Split the client's item text into what the panel should show.
-- @return { properties = { {label, value} }, mods = { { text, fractured } }, flags = { corrupted, sanctified } }
function Lines.split(rawText)
	local properties, mods = { }, { }
	-- The header block is the class, the rarity, the name and the base, in the client's own
	-- language: the parsed item is English, so the name has to come from here to be shown as
	-- the player sees it.
	local header = { }
	local flags = { corrupted = false, sanctified = false }
	local pastHeader, inFlavour, fracturedNext = false, false, false

	for line in tostring(rawText or ""):gmatch("[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then
			if line:match("^%-%-%-+$") then
				pastHeader = true
			elseif not pastHeader and not startsWith(line, "Редкость") and not startsWith(line, "Rarity")
				and not startsWith(line, "Класс предмета") and not startsWith(line, "Item Class") then
				if not header.name then
					header.name = line
				elseif not header.base then
					header.base = line
				end
			elseif inFlavour then
				if endsWith(line, "»") then
					inFlavour = false
				end
			elseif startsWith(line, "«") then
				inFlavour = not endsWith(line, "»")
			elseif startsWith(line, "{") then
				-- A braced header announces the modifier that follows and says what kind it is. Only the
				-- Russian word was matched, so on an English client a fractured modifier was shown as an
				-- ordinary one - and its "cannot be removed" property silently disappeared from the card.
				fracturedNext = line:find("Расколотое", 1, true) ~= nil
					or line:find("Fractured", 1, true) ~= nil
			elseif pastHeader then
				-- Both languages, and both spellings of the Russian word: this decides what the card
				-- shows about the item, and a flag missed here was shown as a normal modifier line
				-- instead of the state it is.
				if line == "Осквернено" or line == "Corrupted" then
					flags.corrupted = true
				elseif line == "Освящено" or line == "Освещено" or line == "Sanctified" then
					flags.sanctified = true
				elseif line == "Расколотый предмет" or line == "Fractured Item" then
					-- The item's own state line, not a modifier: it was listed as an unrecognised
					-- modifier and reached an English card as a Russian bullet.
					flags.fractured = true
				elseif isMeta(line) then
					-- conditions of the item, not properties of it
				elseif endsWith(line, ".") and not line:find("%d") then
					-- a full sentence from the description block
				else
					local property = asProperty(line)
					if property then
						properties[#properties + 1] = property
					else
						mods[#mods + 1] = { text = withoutRange(line), fractured = fracturedNext }
					end
					fracturedNext = false
				end
			end
		end
	end

	return { header = header, properties = properties, mods = mods, flags = flags }
end

return Lines