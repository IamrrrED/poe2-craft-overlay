-- Runs a real item through the engine's own pipeline and saves the answer.
--
-- This is the reference the JavaScript port is measured against: the same item, the same engine call
-- that the overlay used before the rewrite (the MCP tool), captured as JSON so the numbers can be
-- compared outside instead of being taken on trust.

local json = require("Mcp.json")

local CANDIDATES = { "app/data/", "../app/data/", "../../app/data/" }

local function writeOut(name, value)
	for _, prefix in ipairs(CANDIDATES) do
		local file = io.open(prefix .. name .. ".json", "w")
		if file then
			file:write(json.encode(value))
			file:close()
			return true
		end
	end
	return false
end

local function readItem()
	local files = {
		"../samples/ru_gloves.txt",
		"../samples/rare_gloves.txt",
		"../app/craft-history.json",
	}
	for _, path in ipairs(files) do
		local file = io.open(path, "r")
		if file then
			local content = file:read("*a")
			file:close()
			if path:find("craft%-history") then
				-- The history is a list of captures; the last one is the current state of the craft.
				local ok, list = pcall(json.decode, content)
				if ok and type(list) == "table" and list[#list] and list[#list].raw then
					return list[#list].raw, path
				end
			else
				return content, path
			end
		end
	end
	return nil, nil
end

return function()
	local itemText, source = readItem()
	if not itemText then
		writeOut("mcp-report", "mcp: no item to analyse")
		print("mcp: no item to analyse")
		return true
	end

	local api = require("Mcp.api")
	local result = { source = source, calls = {} }

	for _, tool in ipairs({ "analyze_item", "craft_step" }) do
		local ok, answer = pcall(api.call, tool, { item_text = itemText })
		result.calls[#result.calls + 1] = {
			tool = tool,
			ok = ok,
			answer = ok and answer or tostring(answer),
		}
	end

	writeOut("mcp-sample", result)
	writeOut("mcp-report", "mcp: analysed " .. tostring(source))
	print("mcp: analysed " .. tostring(source))
	return true
end
