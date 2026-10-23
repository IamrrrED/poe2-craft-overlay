"""Was the old snapshot systematically wrong? Count entries sitting at the exalted rate."""

import re
import subprocess

pattern = re.compile(r'\["([^"]+)"\]\s*=\s*([0-9.]+)')

old_text = subprocess.run(
    ["git", "show", "HEAD:poe2craft/src/Data/prices.lua"],
    cwd="..", capture_output=True,
).stdout.decode("utf-8", "replace")

rows = {name: float(value) for name, value in pattern.findall(old_text)}
exalted = rows.get("Exalted Orb")
near = [name for name, value in rows.items() if exalted and abs(value - exalted) / exalted < 0.01]

print("old Exalted Orb =", exalted)
print("entries priced within 1% of the exalted rate:", len(near), "of", len(rows))
print("examples:", ", ".join(sorted(near)[:8]))

# The same question for the fresh file.
with open("src/Data/prices.lua", encoding="utf-8") as handle:
    fresh_text = handle.read()
fresh = {name: float(value) for name, value in pattern.findall(fresh_text)}
fresh_exalted = fresh.get("Exalted Orb")
fresh_near = [n for n, v in fresh.items() if fresh_exalted and abs(v - fresh_exalted) / fresh_exalted < 0.01]
print("fresh entries at the exalted rate:", len(fresh_near), "of", len(fresh))
print("examples:", ", ".join(sorted(fresh_near)[:8]))
