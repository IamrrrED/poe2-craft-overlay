--- Remembers the item between crafting steps, so the next advice can depend on what actually rolled.
--
-- The whole point of the step loop is that step two is not step one: the player acts, the item
-- changes, and the assistant has to look again. That needs a memory of the item as it was before
-- the action, and a comparison with the item as it is now.
local Memory = { }

local PATH = "craft_memory.lua"

-- Written above every state file. It is not data and not a source file: it is the previous capture, kept only
-- so the next advice can tell what actually changed. It used to be tracked by git, which meant every test run
-- dirtied the tree and a commit could carry one player's item into the repository.
local HEADER = "-- GENERATED at runtime by Craft/Memory.lua. Safe to delete; it is the previous capture, not data.\n"

--- Text of one modifier, whatever shape the engine handed over.
-- Modifiers arrive as plain strings in some paths and as tables in others, so both are accepted:
-- guessing one shape and being wrong is what broke the coach twice.
local function modText(entry)
	if type(entry) == "string" then
		return entry
	end
	if type(entry) == "table" then
		return tostring(entry.text or entry.line or entry.value or entry.mod or entry.name or "")
	end
	return ""
end

--- The numbers inside one modifier line, as text, so a value change is visible.
--
-- Comparing modifier TEXT alone made a Divine Orb invisible: it rerolls values and leaves the modifier
-- set alone, so "nothing changed" was reported and the same step was offered again and again. The
-- values are part of what the item is now.
-- @param entry modifier table or string
-- @return string like "58,12" ("" when the line carries no number)
local function valuesOf(entry)
	local text = modText(entry)
	local numbers = { }
	if type(entry) == "table" and type(entry.values) == "table" then
		for _, value in ipairs(entry.values) do
			numbers[#numbers + 1] = tostring(value)
		end
	end
	if #numbers == 0 then
		for number in tostring(text):gmatch("%-?%d+%.?%d*") do
			numbers[#numbers + 1] = number
		end
	end
	return table.concat(numbers, ",")
end

--- Quality as a remembered line, so the comparison can see it move.
--
-- Quality is not part of any modifier line: it sits on the item as its own number. Without this line a
-- quality currency looked like it did nothing, so the coach kept reporting "nothing changed" and offered
-- the same step again and again - which is exactly what the customer hit with an Armourer's Scrap on a
-- helmet: the quality was rising and the card kept saying nothing had happened.
-- @param item parsed item
-- @return string or nil when the item states no quality
local function qualityLine(item)
	local quality = (item or { }).quality
	if quality == nil then
		return nil
	end
	return "quality: " .. tostring(quality)
end

--- Every modifier of the item, in a stable order, as plain text.
--
-- Each line carries its numbers as well, because the advice loop needs to tell "the modifier did not
-- change" from "the value changed". The item's own quality is one of those lines.
function Memory.mods(item)
	local item_ = item or { }
	local out = { }
	for _, field in ipairs({ "implicitMods", "explicitMods", "craftedMods", "desecratedMods", "runeMods", "enchantMods" }) do
		local list = item_[field]
		if type(list) == "table" then
			for _, entry in ipairs(list) do
				local text = modText(entry)
				if text ~= "" then
					out[#out + 1] = text .. " [" .. valuesOf(entry) .. "]"
				end
			end
		elseif type(list) == "string" and list ~= "" then
			for line in list:gmatch("[^\r\n]+") do
				if line:gsub("%s", "") ~= "" then
					out[#out + 1] = line .. " [" .. valuesOf(line) .. "]"
				end
			end
		end
	end
	local quality = qualityLine(item)
	if quality then
		out[#out + 1] = quality
	end
	table.sort(out)
	return out
end

--- All the numbers in the item's own text, in order, as one string.
--
-- Not part of the fingerprint, on purpose. Putting the values there looked right and was wrong: a value
-- change then changed the fingerprint, so the item stopped being recognised as the SAME item and every
-- capture was treated as a first look - the step loop lost its memory exactly when a value reroll made
-- it matter. Identity is what the item IS; changes are what the comparison is for.
-- @return string like "1327,10,75,58,31"
local function textValues(item)
	local raw = type((item or { }).raw) == "string" and item.raw or ""
	local numbers = { }
	for number in raw:gmatch("%-?%d+%.?%d*") do
		numbers[#numbers + 1] = number
	end
	return table.concat(numbers, ",")
end

--- What the item is, regardless of what was done to it: the same base stays the same item.
-- Two captures are the same item when this matches; otherwise the player moved to another item and
-- the remembered steps no longer apply.
function Memory.fingerprint(item)
	local item_ = item or { }
	return table.concat({
		-- Format marker: this file's shape changed, so an older memory is treated as a different item
		-- rather than compared against the new fields.
		"v2",
		tostring(item_.itemClass or ""),
		tostring(item_.baseType or ""),
		tostring(item_.name or ""),
		tostring(item_.itemLevel or ""),
		-- Quality is NOT part of identity, on purpose: it is something the player changes while working
		-- on the same item, so putting it here made a quality currency look like a different item - the
		-- loop lost its memory exactly when it mattered. It is compared instead, as one of Memory.mods.
	}, "|")
end

--- The readable form of a remembered modifier: the text without the values annotation.
--
-- Memory.mods appends "[58,12]" so a value-only change is visible to the comparison, and the item's
-- quality is one of the lines. The card shows these lines to the player, so the annotation is stripped
-- and a bare quality line is turned into something a person can read.
local function readable(text)
	local stripped = tostring(text):gsub("%s*%[[%d%.,%-%s]*%]$", "")
	local quality = stripped:match("^quality:%s*(%d+)$")
	if quality then
		-- English, because the remembered lines are a fingerprint shared by both languages: a display
		-- string that changed with the panel's language would break "is this the same item" comparisons.
		-- Mcp/api.lua turns this one line into the panel's language for the card.
		return "Quality: " .. quality .. "%"
	end
	return stripped
end

--- Modifiers that appeared, disappeared, or stayed.
function Memory.compare(before, after)
	local beforeSet, afterSet = { }, { }
	for _, text in ipairs(before or { }) do beforeSet[text] = true end
	for _, text in ipairs(after or { }) do afterSet[text] = true end
	local added, removed, same = { }, { }, 0
	for _, text in ipairs(after or { }) do
		if beforeSet[text] then
			same = same + 1
		else
			added[#added + 1] = readable(text)
		end
	end
	for _, text in ipairs(before or { }) do
		if not afterSet[text] then
			removed[#removed + 1] = readable(text)
		end
	end
	return { added = added, removed = removed, same = same }
end

--- Reads the memory written by the previous capture. Returns nil when there is none.
function Memory.load()
	local file = io.open(PATH, "r")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	local chunk = loadstring(content)
	if not chunk then
		return nil
	end
	local ok, saved = pcall(chunk)
	if not ok or type(saved) ~= "table" then
		return nil
	end
	return saved
end

--- Stores the item as it is now, together with the step that was recommended for it.
function Memory.save(fingerprint, mods, step)
	local file = io.open(PATH, "w")
	if not file then
		return false
	end
	file:write(HEADER)
	file:write("return {\n")
	file:write(string.format("\tfingerprint = %q,\n", tostring(fingerprint or "")))
	file:write("\tmods = {\n")
	for _, text in ipairs(mods or { }) do
		file:write(string.format("\t\t%q,\n", text))
	end
	file:write("\t},\n")
	file:write(string.format("\tstep = %q,\n", tostring((step or { }).currency or "")))
	file:write(string.format("\tstepIndex = %s,\n", tostring(tonumber((step or { }).index) or 1)))
	file:write(string.format("\tstepTitle = %q,\n", tostring((step or { }).title or "")))
	file:write(string.format("\tat = %q,\n", os.date("%Y-%m-%d %H:%M:%S")))
	file:write("}\n")
	file:close()
	return true
end

--- Forgets the remembered item: used when the player moved to another one.
function Memory.clear()
	local file = io.open(PATH, "w")
	if file then
		file:write(HEADER)
		file:write("return nil\n")
		file:close()
	end
end

--- The comparison the coach needs: same item or a new one, and what changed since last time.
function Memory.review(item, step)
	local now = {
		fingerprint = Memory.fingerprint(item),
		mods = Memory.mods(item),
	}
	local saved = Memory.load()
	local review = { sameItem = false, changes = nil, previousStep = nil }
	if saved and saved.fingerprint == now.fingerprint then
		review.sameItem = true
		review.previousStep = saved.step or ""
		review.previousStepTitle = saved.stepTitle or ""
		review.previousStepIndex = tonumber(saved.stepIndex) or 1
		review.changes = Memory.compare(saved.mods or { }, now.mods)
		review.verdict = (function()
			local changes = review.changes
			if #changes.added == 0 and #changes.removed == 0 then
				return "nothing"
			end
			if #changes.added > #changes.removed then
				return "progress"
			end
			if #changes.removed > #changes.added then
				return "loss"
			end
			return "swap"
		end)()
	end
	-- "First look" means the craft starts here: either nothing was remembered, or the player moved to
	-- another item, in which case the remembered steps no longer apply to what is in hand.
	review.first = (saved == nil) or (not review.sameItem)
	-- Either way the item is remembered as it is now, so the next capture compares against this one.
	Memory.save(now.fingerprint, now.mods, step)
	return review
end

return Memory