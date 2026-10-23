"""Prefer the game's annotation side over the builder's type when asking the trade site."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = os.path.join(ROOT, "src", "Mcp", "api.lua")

with io.open(API, encoding="utf-8") as handle:
    text = handle.read()

old = (
    '\t\t\t\tlocal side = (type(mod) == "table" and mod.mod and mod.mod.type)\n'
    '\t\t\t\t\tand string.lower(tostring(mod.mod.type)) or ""'
)
new = (
    '\t\t\t\t-- The annotation the game prints above the line is the authority on the side; the resolved\n'
    '\t\t\t\t-- table only supplies the tier and disagrees on some modifiers. A wrong side would make the\n'
    '\t\t\t\t-- market search price one prefix and one suffix as if they were the other way round.\n'
    '\t\t\t\tlocal sideSource = type(mod) == "table" and (mod.side or (mod.mod and mod.mod.type)) or nil\n'
    '\t\t\t\tlocal side = sideSource and string.lower(tostring(sideSource)) or ""'
)

if old in text:
    text = text.replace(old, new, 1)
    with io.open(API, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print("market side fixed")
elif "sideSource" in text:
    print("already fixed")
else:
    print("ANCHOR MISS")
