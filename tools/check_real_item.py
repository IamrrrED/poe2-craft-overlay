"""Check the two fixes against the customer's real amulet, then leave the file as it was."""

import io
import os
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBE = os.path.join(ROOT, "src", "Tests", "test_zz_real.lua")
RUNNER = os.path.join(ROOT, "src", "Tests", "runner.lua")

probe = r'''
return function()
	local Api = require("Mcp.api")
	local f = io.open("zz_real.txt", "w")
	local text = io.open("last_item.txt", "r"):read("*a")
	local analysis = Api.call("analyze_item", { item_text = text })
	local cob = analysis and analysis.craftOrBuy
	f:write("hasCost: " .. tostring(cob and cob.hasCost) .. "\n")
	f:write("fullItem: " .. tostring(cob and cob.fullItem) .. "\n")
	f:write("fullNote: " .. tostring(cob and cob.fullNote) .. "\n")
	local mq = Api.call("market_query", { item_text = text })
	f:write("mods sent to trade: " .. #((mq or {}).mods or {}) .. "\n")
	for _, m in ipairs((mq or {}).mods or {}) do
		f:write("  " .. tostring(m.text) .. "  min=" .. tostring(m.min) .. "\n")
	end
	f:close()
end
'''

with io.open(PROBE, "w", encoding="utf-8", newline="") as handle:
    handle.write(probe)

with io.open(RUNNER, encoding="utf-8") as handle:
    runner = handle.read()
runner = runner.replace('\t"Tests.test_second_source",', '\t"Tests.test_zz_real",\n\t"Tests.test_second_source",', 1)
with io.open(RUNNER, "w", encoding="utf-8", newline="") as handle:
    handle.write(runner)

subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", os.path.join(ROOT, "tests.ps1")],
               cwd=ROOT, capture_output=True)

with io.open(os.path.join(ROOT, "src", "zz_real.txt"), encoding="utf-8", errors="replace") as handle:
    print(handle.read())

os.remove(PROBE)
with io.open(RUNNER, encoding="utf-8") as handle:
    runner = handle.read()
runner = runner.replace('\t"Tests.test_zz_real",\n', "")
with io.open(RUNNER, "w", encoding="utf-8", newline="") as handle:
    handle.write(runner)
os.remove(os.path.join(ROOT, "src", "zz_real.txt"))
print("cleaned up")
