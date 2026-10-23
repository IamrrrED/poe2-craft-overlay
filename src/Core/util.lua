-- PoE2 Craft Overlay : Core/util.lua
-- Small dependency-free helpers shared by every module.
-- Pure Lua 5.1 / LuaJIT compatible (no engine APIs), so it is testable headless.

local util = { }

function util.trim(s)
	if s == nil then return nil end
	return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function util.startsWith(s, prefix)
	return tostring(s):sub(1, #prefix) == prefix
end

--- Split raw text into trimmed, non-empty lines.
function util.splitLines(text)
	local lines = { }
	for line in tostring(text):gmatch("[^\r\n]+") do
		line = util.trim(line)
		if line ~= "" then
			lines[#lines + 1] = line
		end
	end
	return lines
end

function util.upper(s)
	return tostring(s):upper()
end

--- Extract the first balanced parenthetical group at the end of a line.
-- Returns the line with the group removed plus the group's inner text.
function util.popTrailingTag(line)
	local body, tag = tostring(line):match("^(.-)%s*%(([^%(%)]*)%)%s*$")
	if body then
		return util.trim(body), util.trim(tag)
	end
	return util.trim(line), nil
end

--- Extract every "(a-b)" numeric range from a line.
-- Returns the cleaned line plus a list of { min, max } pairs.
function util.extractRanges(line)
	local ranges = { }
	local cleaned = tostring(line):gsub("%((%-?%d+%.?%d*)%s*%-%s*(%-?%d+%.?%d*)%)", function(a, b)
		ranges[#ranges + 1] = { min = tonumber(a), max = tonumber(b) }
		return ""
	end)
	return util.trim(cleaned), ranges
end

--- First number found in a string ("+20%" -> 20, "1.2" -> 1.2).
function util.firstNumber(s)
	return tonumber(tostring(s):match("(%-?%d+%.?%d*)"))
end

function util.numberOrNil(v)
	if type(v) == "number" then return v end
	return tonumber(tostring(v):match("(%-?%d+%.?%d*)"))
end

function util.round(n, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(n * mult + 0.5) / mult
end

function util.deepCopy(t)
	if type(t) ~= "table" then return t end
	local out = { }
	for k, v in pairs(t) do
		out[k] = util.deepCopy(v)
	end
	return out
end

function util.count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

function util.sortedKeys(t)
	local keys = { }
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

function util.fileExists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

function util.readFile(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	return data
end

function util.writeFile(path, data)
	local f = io.open(path, "wb")
	if not f then return false end
	f:write(data)
	f:close()
	return true
end

function util.removeFile(path)
	return os.remove(path) ~= nil
end

--- Position a w x h box in the centre of a screen, clamped so it never leaves it.
-- Pure maths, so the overlay's placement can be tested without a renderer.
function util.centerPosition(screenW, screenH, w, h, margin)
	margin = margin or 0
	local x = math.floor((screenW - w) / 2)
	local y = math.floor((screenH - h) / 2)
	if x < margin then x = margin end
	if y < margin then y = margin end
	if x + w > screenW - margin then
		x = math.max(margin, screenW - w - margin)
	end
	if y + h > screenH - margin then
		y = math.max(margin, screenH - h - margin)
	end
	return x, y
end

--- UTF-8 aware display width (Cyrillic and box-drawing count as one column).
-- Lua 5.1 has no utf8 library; the engine ships lua-utf8 as a module, so guard it.
function util.displayWidth(s)
	s = tostring(s)
	local utf8lib = rawget(_G, "utf8")
	if utf8lib and utf8lib.codes then
		local n = 0
		for _ in utf8lib.codes(s) do
			n = n + 1
		end
		return n
	end
	return #s
end

return util
