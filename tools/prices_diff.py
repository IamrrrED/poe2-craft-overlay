"""How far did prices move in two weeks? Compare the committed snapshot with the fresh one."""

import io
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Data", "prices.lua")

pattern = re.compile(r'\["([^"]+)"\]\s*=\s*([0-9.]+)')


def read_prices(text):
    return {name: float(value) for name, value in pattern.findall(text)}


with io.open(PATH, encoding="utf-8") as handle:
    fresh_text = handle.read()
fresh = read_prices(fresh_text)

old_result = subprocess.run(
    ["git", "show", "HEAD:poe2craft/src/Data/prices.lua"],
    cwd=os.path.dirname(ROOT), capture_output=True,
)
old = read_prices(old_result.stdout.decode("utf-8", "replace"))

print(f"old entries: {len(old)}   fresh entries: {len(fresh)}")

# Currencies the crafting methods actually use, plus the biggest movers overall.
WATCHED = [
    "Divine Orb", "Exalted Orb", "Greater Exalted Orb", "Perfect Exalted Orb",
    "Regal Orb", "Chaos Orb", "Orb of Annulment", "Orb of Alchemy",
    "Transmutation Orb", "Augmentation Orb", "Vaal Orb",
    "Arcanist's Etcher", "Glassblower's Bauble", "Gemcutter's Prism",
    "Fracturing Orb", "Omen of Whittling", "Omen of Light",
]

print("\n=== watched ===")
for name in WATCHED:
    before, after = old.get(name), fresh.get(name)
    if before is None or after is None:
        print(f"  {name:<26} old={before} new={after}")
        continue
    if before <= 0:
        continue
    change = (after - before) / before * 100
    print(f"  {name:<26} {before:>10.4f} -> {after:>10.4f}   {change:+7.1f}%")

movers = []
for name, after in fresh.items():
    before = old.get(name)
    if not before or before <= 0 or after <= 0:
        continue
    movers.append((abs((after - before) / before), name, before, after))

movers.sort(reverse=True)
print("\n=== biggest moves (priced above 0.05 chaos either side) ===")
shown = 0
for magnitude, name, before, after in movers:
    if max(before, after) < 0.05:
        continue
    print(f"  {name:<34} {before:>9.3f} -> {after:>9.3f}   {(after - before) / before * 100:+7.0f}%")
    shown += 1
    if shown >= 12:
        break
