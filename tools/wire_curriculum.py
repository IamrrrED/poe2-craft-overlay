"""Wire the Curriculum module into the API payload and the syntax guards."""

import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

api_path = os.path.join(ROOT, "src", "Mcp", "api.lua")
with io.open(api_path, encoding="utf-8") as handle:
    api = handle.read()

anchor = 'local Techniques = require("Craft.Techniques")'
if "Craft.Curriculum" not in api:
    if anchor not in api:
        raise SystemExit("techniques require not found")
    api = api.replace(anchor, anchor + '\nlocal Curriculum = require("Craft.Curriculum")', 1)
    print("api: required Curriculum")

# The course rides along with the methods payload: it needs the advice, which toolMethods already has.
marker = "\t\ttechniques = Techniques.forItem(item),"
if "Curriculum.forItem(item" not in api:
    if marker not in api:
        raise SystemExit("techniques payload marker not found")
    api = api.replace(
        marker,
        marker
        + "\n\t\t-- The mentor's course, with this item as the state: each lesson says whether the item"
        + "\n\t\t-- already demonstrates the point, so the panel can skip what the player knows."
        + "\n\t\tcurriculum = Curriculum.forItem(item, advice),",
        1)
    print("api: attached the curriculum")

with io.open(api_path, "w", encoding="utf-8", newline="") as handle:
    handle.write(api)

GUARD_ANCHOR = '"Craft/Techniques.lua",'
for relative in ("src/Launch.lua", "src/Tests/runner.lua"):
    path = os.path.join(ROOT, relative)
    with io.open(path, encoding="utf-8") as handle:
        text = handle.read()
    if "Craft/Curriculum.lua" in text:
        print(relative, "already lists Curriculum")
        continue
    if GUARD_ANCHOR not in text:
        print(relative, "anchor missing")
        continue
    text = text.replace(GUARD_ANCHOR, GUARD_ANCHOR + ' "Craft/Curriculum.lua",', 1)
    with io.open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print(relative, "listed Curriculum")

print("done")
