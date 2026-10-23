"""List every rule with its English explanation, so the Russian ones can be written from the real text."""

import io
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Data", "league_0_5_5.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

# Each rule block runs from its id to the next id (or the end of the rules table).
ids = [(m.group(1), m.start()) for m in re.finditer(r'\bid = "([a-z_]+)",\n\t+when', text)]

for index, (rule_id, start) in enumerate(ids):
    end = ids[index + 1][1] if index + 1 < len(ids) else len(text)
    block = text[start:end]
    has_ru = "why = {" in block
    print(("RU " if has_ru else "EN "), rule_id)
    if not has_ru and "whyEn = {" in block:
        body = block[block.find("whyEn = {") + len("whyEn = {"):]
        cut = body.find("\n\t\t\t},")
        body = body[:cut] if cut != -1 else body[:900]
        for line in body.splitlines():
            stripped = line.strip()
            if stripped:
                print("      ", stripped)
