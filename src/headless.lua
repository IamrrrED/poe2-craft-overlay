-- Headless entry point: the same serving protocol as Launch.lua, with no host at all.
-- Nothing here draws, so this runs on plain LuaJIT and the process has no windows.
package.path = package.path .. ";./?.lua;./?/init.lua"

-- Lines is one of this project's own modules (src/Item/Lines.lua), not a host function: Launch.lua
-- loads it as a global and api.lua calls Lines.split(text), which returns properties, mods and
-- flags. Requiring it here is what the host-side launcher effectively did.
Lines = require("Item.Lines")
local util = require("Core.util")
local json = require("Mcp.json")
local Mcp  = require("Mcp.api")

local handled = nil
local attempts = 0

local function serveOnce()
    local content = util.readFile("mcp_serve_request.lua")
    if not content or content == handled then return false end
    local payload
    local okLoad, request = pcall(function()
        local chunk = loadstring(content, "@mcp_serve_request.lua")
        return chunk and chunk()
    end)
    if not okLoad or type(request) ~= "table" then
        -- The panel may still be writing the file: a partially written request cannot be parsed, and
        -- marking it handled here would drop it for good. Retry on the next round instead, and only give
        -- up after a few tries so a genuinely broken file cannot make the panel wait for its timeout.
        attempts = (attempts or 0) + 1
        if attempts < 4 then
            return false
        end
        handled = content
        payload = { ok = false, error = "the serving request was not a table" }
    else
        local tool = tostring(request.tool or "")
        local okCall, result, callErr = pcall(Mcp.call, tool, request.args or { })
        if not okCall then      payload = { ok = false, tool = tool, error = tostring(result) }
        elseif callErr then     payload = { ok = false, tool = tool, error = callErr }
        else                    payload = { ok = true,  tool = tool, result = result } end
    end
    handled = content
    attempts = 0
    util.writeFile("mcp_serve_response.json", json.encode(payload))
    return true
end

local function sleepMs(ms)
    local stop = os.clock() + ms / 1000
    while os.clock() < stop do end
end

-- Errors are written down, never swallowed: a silent pcall here once hid a failing request and left
-- the panel with no answer and no explanation.
while true do
    local ok, err = pcall(serveOnce)
    if not ok then
        util.writeFile("headless_error.txt", tostring(err) .. "\n")
    end
    sleepMs(25)
end
