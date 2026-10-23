-- PoE2 Craft Overlay : Tests/harness.lua
-- Minimal assertion harness: no external dependencies, works on Lua 5.1 / LuaJIT.

local H = { }
H.results = { }

function H.check(label, condition, detail)
	H.results[#H.results + 1] = {
		label = label,
		ok = condition and true or false,
		detail = detail,
	}
	return condition and true or false
end

function H.eq(label, actual, expected)
	local ok = actual == expected
	return H.check(label, ok, ok and nil or string.format("expected %s, got %s",
		tostring(expected), tostring(actual)))
end

function H.contains(label, haystack, needle)
	local ok = tostring(haystack):find(needle, 1, true) ~= nil
	return H.check(label, ok, ok and nil or string.format("text does not contain %q", tostring(needle)))
end

function H.notContains(label, haystack, needle)
	local ok = tostring(haystack):find(needle, 1, true) == nil
	return H.check(label, ok, ok and nil or string.format("text unexpectedly contains %q", tostring(needle)))
end

function H.summary()
	local passed, failed = 0, 0
	local lines = { }
	for _, r in ipairs(H.results) do
		if r.ok then
			passed = passed + 1
			lines[#lines + 1] = "PASS  " .. r.label
		else
			failed = failed + 1
			lines[#lines + 1] = "FAIL  " .. r.label .. (r.detail and ("  <- " .. r.detail) or "")
		end
	end
	lines[#lines + 1] = string.format("TOTAL: %d passed, %d failed, %d total", passed, failed, passed + failed)
	return passed, failed, table.concat(lines, "\n")
end

return H
