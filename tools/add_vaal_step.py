"""Keep the Vaal Orb out of the minimal plan.

The customer asked for Vaal in the plan, last - it is the step after which nothing can be done. The first
version put it in BOTH plans, which made it the immediate follow-up to a single reroll on the minimal path:
a one-way, item-destroying step reached in one move. Vaal now belongs to the maximum plan only, where it is
the last step after the modifiers are settled, while the minimal plan stays the safe path.

Run this after any rule edit that adds a plan list, so the rule holds for every rule.
"""

import re

PATH = "src/Data/league_0_5_5.lua"

with open(PATH, "r", encoding="utf-8") as handle:
    lines = handle.readlines()

removed = []
added = []

for index, line in enumerate(lines):
    match = re.match(r"^(\t{3}(min|max) = \{)(.*?)(\},)\s*$", line)
    if not match:
        continue
    head, which, body, tail = match.group(1), match.group(2), match.group(3), match.group(4)
    has_vaal = re.search(r'"vaal"', body) is not None
    if which == "min" and has_vaal:
        # Drop it, and tidy the trailing comma when it was the last entry.
        body = re.sub(r',?\s*"vaal"\s*,?', ',', body)
        body = re.sub(r",\s*,", ",", body).rstrip()
        if body.endswith(","):
            body = body[:-1]
        lines[index] = head + body + " " + tail + "\n"
        removed.append(index + 1)
    elif which == "max" and not has_vaal and body.strip() != "":
        code = body.rstrip()
        if not code.endswith(","):
            code = code + ","
        lines[index] = head + code + ' "vaal" ' + tail + "\n"
        added.append(index + 1)

with open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.writelines(lines)

print("vaal removed from min lines:", ", ".join(str(number) for number in removed))
print("vaal added to max lines:", ", ".join(str(number) for number in added))
