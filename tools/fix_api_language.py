"""Stop the API from preferring English when it rebuilds plans and options.

The advisor was fixed to prefer Russian, but the tool layer assembles its own plan and option tables and there
the English field still won: `title = plan.titleEn or plan.title`. So the panel received Russian plans from the
advisor and English text from the layer above it. Only the preferred (Russian) slots are touched - the explicit
`titleEn` fields are meant to hold the English text and must stay as they are.
"""

import io
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Mcp", "api.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

# Only plain keys: title / why / reason. `titleEn` and friends are the English slots and stay untouched.
pattern = re.compile(r"(?<![A-Za-z])(title|why|reason|blocker)\s*=\s*([A-Za-z_.]+)\.\1En\s+or\s+\2\.\1(?!\w)")

count = 0
def swap(match):
    global count
    count += 1
    key, owner = match.group(1), match.group(2)
    return f"{key} = {owner}.{key} or {owner}.{key}En"

text = pattern.sub(swap, text)
print("swapped:", count)

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)

# Report what remains, so nothing is silently left English-first.
leftovers = [
    (number, line.strip())
    for number, line in enumerate(text.splitlines(), 1)
    if re.search(r"(?<![A-Za-z])(title|why|reason)\s*=\s*\w+\.\1En\s+or", line)
]
print("remaining English-first:", len(leftovers))
for number, line in leftovers[:10]:
    print(" ", number, line)
