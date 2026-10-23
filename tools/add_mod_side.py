"""Send the modifier side with the market query, so loosening keeps one prefix and one suffix."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = os.path.join(ROOT, "src", "Mcp", "api.lua")

with io.open(API, encoding="utf-8") as handle:
    text = handle.read()

old = "\t\t\t\tmods[#mods + 1] = { text = stat, min = minimum }"
new = (
    "\t\t\t\t-- The side travels too. When the search has to loosen it keeps one prefix and one suffix,\n"
    "\t\t\t\t-- because the first two lines may both come from the same side and the price would then\n"
    "\t\t\t\t-- describe a different item.\n"
    "\t\t\t\tlocal side = (type(mod) == \"table\" and mod.mod and mod.mod.type)\n"
    "\t\t\t\t\tand string.lower(tostring(mod.mod.type)) or \"\"\n"
    "\t\t\t\tmods[#mods + 1] = { text = stat, min = minimum, side = side }"
)

if old in text:
    text = text.replace(old, new, 1)
    with io.open(API, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print("side added")
elif "mod.side" in text or "The side travels too" in text:
    print("already added")
else:
    print("ANCHOR MISS")
