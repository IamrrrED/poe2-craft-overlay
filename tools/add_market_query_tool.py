"""Add the market_query tool: turn a captured item into a trade search spec.

The Lua engine parses the item, so it - not the Node script - decides what the base is and which modifiers to
match. Parsing in two languages is how the two sides drift apart.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = os.path.join(ROOT, "src", "Mcp", "api.lua")

with io.open(API, encoding="utf-8") as handle:
    text = handle.read()

if 'name == "market_query"' in text:
    print("already present")
    raise SystemExit(0)

anchor = '\telseif name == "craft_or_buy" then'
if anchor not in text:
    raise SystemExit("craft_or_buy anchor not found")

block = (
    '\telseif name == "market_query" then\n'
    '\t\t-- The market half of craft-vs-buy: what to ASK the trade site, built from the parsed item. The\n'
    '\t\t-- trade stat text wants numbers blanked to "#" and no leading plus, and the minimum is the roll the\n'
    '\t\t-- item actually has - comparing against a worse item would understate what it is worth.\n'
    '\t\tlocal itemText = args and args.item_text\n'
    '\t\tif type(itemText) ~= "string" or itemText == "" then\n'
    '\t\t\treturn nil, "item_text is required"\n'
    '\t\tend\n'
    '\t\tlocal parsed, parseErr = parseItem(itemText)\n'
    '\t\tif not parsed then\n'
    '\t\t\treturn nil, parseErr or "the item could not be parsed"\n'
    '\t\tend\n'
    '\t\tlocal base = tostring(parsed.baseType or "")\n'
    '\t\tif base == "" then\n'
    '\t\t\treturn nil, "the item has no base type, so it cannot be looked up"\n'
    '\t\tend\n'
    '\t\tlocal mods = { }\n'
    '\t\tfor _, mod in ipairs(parsed.explicitMods or { }) do\n'
    '\t\t\tlocal line = type(mod) == "table" and (mod.text or "") or mod\n'
    '\t\t\tif type(line) == "string" and line ~= "" and line:sub(1, 1) ~= "{" then\n'
    '\t\t\t\t-- "37% increased Energy Shield" -> "#% increased Energy Shield"\n'
    '\t\t\t\tlocal stat = line:gsub("%-?%d+%.?%d*", "#")\n'
    '\t\t\t\tstat = stat:gsub("^%+", "")\n'
    '\t\t\t\t-- The item\'s own lowest number becomes the floor for the search.\n'
    '\t\t\t\tlocal minimum = nil\n'
    '\t\t\t\tfor number in line:gmatch("(%-?%d+%.?%d*)") do\n'
    '\t\t\t\t\tlocal value = tonumber(number)\n'
    '\t\t\t\t\tif value and (minimum == nil or value < minimum) then minimum = value end\n'
    '\t\t\t\tend\n'
    '\t\t\t\tmods[#mods + 1] = { text = stat, min = minimum }\n'
    '\t\t\tend\n'
    '\t\tend\n'
    '\t\tif #mods == 0 then\n'
    '\t\t\treturn nil, "the item has no explicit modifiers to match"\n'
    '\t\tend\n'
    '\t\treturn {\n'
    '\t\t\tbase = base,\n'
    '\t\t\tleague = (ruleset() or { }).league,\n'
    '\t\t\tmods = mods,\n'
    '\t\t\tnote = "Запрос к трейду: та же база и те же моды, с минимумом по текущему роллу.",\n'
    '\t\t}, nil\n'
)

text = text.replace(anchor, block + anchor, 1)
with io.open(API, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("market_query added")
