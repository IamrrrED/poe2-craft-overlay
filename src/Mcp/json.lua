-- PoE2 Craft Overlay : Mcp/json.lua
-- Minimal JSON encoder/decoder for the MCP bridge.
--
-- The overlay runs inside the SimpleGraphic/LuaJIT host, and the MCP server (Node)
-- talks to it through files: the request arrives as a Lua table, the answer leaves as
-- JSON. Encoding is therefore mandatory, decoding is only needed by the tests (and is
-- handy when a request is written as JSON), so both live here.
--
-- Deliberately dependency-free: the host ships dkjson, but relying on a library that
-- may or may not be on this host's package path would make the bridge fragile.

local json = { }

local escapes = {
	['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
	["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escapeChar(char)
	return escapes[char] or string.format("\\u%04x", char:byte())
end

local function encodeString(value)
	-- Control characters and the quote/backslash pair are escaped; UTF-8 passes
	-- through untouched, which keeps the output valid JSON.
	return '"' .. value:gsub('[%z\1-\31\\"]', escapeChar) .. '"'
end

local function encodeNumber(value)
	if value ~= value or value == math.huge or value == -math.huge then
		return "null"
	end
	if math.floor(value) == value and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	return string.format("%.6f", value)
end

--- Encode a Lua value as JSON. Arrays are tables with consecutive integer keys.
-- An empty table encodes as [] because Lua cannot tell an empty array from an empty
-- object; that is the right shape for the payloads this bridge produces (empty lists of
-- groups, plans, sources), and the JavaScript side never needs the other case.
-- @param value any
-- @param indent optional pretty-printing indent (nil = compact)
function json.encode(value, indent)
	local function isArray(tbl)
		local count = 0
		for key in pairs(tbl) do
			if type(key) ~= "number" then
				return false
			end
			count = count + 1
		end
		return count == #tbl
	end

	local function encode(current, depth)
		local kind = type(current)
		if current == nil then
			return "null"
		elseif kind == "boolean" then
			return current and "true" or "false"
		elseif kind == "number" then
			return encodeNumber(current)
		elseif kind == "string" then
			return encodeString(current)
		elseif kind ~= "table" then
			return encodeString(tostring(current))
		end

		local newline, pad, padInner = "", "", ""
		if indent then
			newline = "\n"
			pad = string.rep(indent, depth + 1)
			padInner = string.rep(indent, depth)
		end

		local parts = { }
		if isArray(current) then
			for index = 1, #current do
				parts[#parts + 1] = pad .. encode(current[index], depth + 1)
			end
			if #parts == 0 then
				return "[]"
			end
			return "[" .. newline .. table.concat(parts, "," .. newline) .. newline .. padInner .. "]"
		end

		local keys = { }
		for key in pairs(current) do
			keys[#keys + 1] = key
		end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, key in ipairs(keys) do
			parts[#parts + 1] = pad .. encodeString(tostring(key)) .. ":" .. (indent and " " or "")
				.. encode(current[key], depth + 1)
		end
		if #parts == 0 then
			return "{}"
		end
		return "{" .. newline .. table.concat(parts, "," .. newline) .. newline .. padInner .. "}"
	end

	return encode(value, 0)
end

--- Decode a JSON document. Returns the value, or nil plus an error message.
function json.decode(text)
	local position = 1
	local source = tostring(text)

	local function skipSpace()
		while position <= #source do
			local char = source:sub(position, position)
			if char == " " or char == "\t" or char == "\n" or char == "\r" then
				position = position + 1
			else
				break
			end
		end
	end

	local parseValue

	local function parseString()
		position = position + 1 -- opening quote
		local out = { }
		while position <= #source do
			local char = source:sub(position, position)
			if char == '"' then
				position = position + 1
				return table.concat(out)
			elseif char == "\\" then
				local nextChar = source:sub(position + 1, position + 1)
				if nextChar == "u" then
					local hex = source:sub(position + 2, position + 5)
					local code = tonumber(hex, 16)
					if not code then
						return nil, "bad \\u escape"
					end
					-- Encode the codepoint as UTF-8.
					if code < 0x80 then
						out[#out + 1] = string.char(code)
					elseif code < 0x800 then
						out[#out + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
					else
						out[#out + 1] = string.char(0xE0 + math.floor(code / 4096),
							0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
					end
					position = position + 6
				else
					local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
						['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
					out[#out + 1] = map[nextChar] or nextChar
					position = position + 2
				end
			else
				out[#out + 1] = char
				position = position + 1
			end
		end
		return nil, "unterminated string"
	end

	local function parseNumber()
		local start = position
		while position <= #source and source:sub(position, position):match("[%d%.eE%+%-]") do
			position = position + 1
		end
		local value = tonumber(source:sub(start, position - 1))
		if not value then
			return nil, "bad number"
		end
		return value
	end

	local function parseArray()
		position = position + 1 -- [
		local out = { }
		skipSpace()
		if source:sub(position, position) == "]" then
			position = position + 1
			return out
		end
		while true do
			local value, err = parseValue()
			if err then return nil, err end
			out[#out + 1] = value
			skipSpace()
			local char = source:sub(position, position)
			if char == "," then
				position = position + 1
				skipSpace()
			elseif char == "]" then
				position = position + 1
				return out
			else
				return nil, "expected , or ] in array"
			end
		end
	end

	local function parseObject()
		position = position + 1 -- {
		local out = { }
		skipSpace()
		if source:sub(position, position) == "}" then
			position = position + 1
			return out
		end
		while true do
			skipSpace()
			if source:sub(position, position) ~= '"' then
				return nil, "expected key string in object"
			end
			local key, keyErr = parseString()
			if keyErr then return nil, keyErr end
			skipSpace()
			if source:sub(position, position) ~= ":" then
				return nil, "expected : after key"
			end
			position = position + 1
			skipSpace()
			local value, err = parseValue()
			if err then return nil, err end
			out[key] = value
			skipSpace()
			local char = source:sub(position, position)
			if char == "," then
				position = position + 1
			elseif char == "}" then
				position = position + 1
				return out
			else
				return nil, "expected , or } in object"
			end
		end
	end

	parseValue = function()
		skipSpace()
		local char = source:sub(position, position)
		if char == "{" then
			return parseObject()
		elseif char == "[" then
			return parseArray()
		elseif char == '"' then
			return parseString()
		elseif char == "t" and source:sub(position, position + 3) == "true" then
			position = position + 4
			return true
		elseif char == "f" and source:sub(position, position + 4) == "false" then
			position = position + 5
			return false
		elseif char == "n" and source:sub(position, position + 3) == "null" then
			position = position + 4
			return nil
		elseif char == "" then
			return nil, "unexpected end of input"
		end
		return parseNumber()
	end

	local value, err = parseValue()
	if err then
		return nil, err
	end
	skipSpace()
	if position <= #source then
		return nil, "trailing data at position " .. position
	end
	return value
end

return json
