"""Never send Cyrillic modifier text to the trade site.

The trade site's stats are English. A Russian client produces lines like "#% увеличение Evasion", which resolve
to nothing - so the search matches zero items, the ladder walks all four rungs, and the hourly budget is spent
learning nothing. The query translates each line first and drops the ones that stay non-Latin.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = os.path.join(ROOT, "src", "Mcp", "api.lua")

with io.open(API, encoding="utf-8") as handle:
    text = handle.read()

old = '\t\t\t\tmods[#mods + 1] = { text = stat, min = minimum, side = side }'
new = (
    '\t\t\t\t-- The trade site only knows English stat names. A Russian line resolves to nothing, so the\n'
    '\t\t\t\t-- search would burn all four ladder rungs and the hourly budget to learn that. Translate\n'
    '\t\t\t\t-- first; if the line stays non-Latin, drop it rather than send junk.\n'
    '\t\t\t\tif stat:find("[\\128-\\255]") then\n'
    '\t\t\t\t\tlocal translated = nil\n'
    '\t\t\t\t\tlocal ok, value = pcall(Ru.toEnglish, stat)\n'
    '\t\t\t\t\tif ok and type(value) == "string" and value ~= "" then translated = value end\n'
    '\t\t\t\t\tif translated then\n'
    '\t\t\t\t\t\tstat = translated:gsub("%-?%d+%.?%d*", "#"):gsub("^%+", "")\n'
    '\t\t\t\t\tend\n'
    '\t\t\t\tend\n'
    '\t\t\t\tif not stat:find("[\\128-\\255]") then\n'
    '\t\t\t\t\tmods[#mods + 1] = { text = stat, min = minimum, side = side }\n'
    '\t\t\t\tend'
)

if old in text:
    text = text.replace(old, new, 1)
    with io.open(API, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print("latin guard added")
elif "only knows English stat names" in text:
    print("already present")
else:
    print("ANCHOR MISS")
