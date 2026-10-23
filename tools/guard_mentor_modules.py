"""List every mentor module in the two syntax-guard lists.

Launch.lua and Tests/runner.lua both carry the list of engine files that must compile before a run; a file that
is missing from it is invisible to that guard. This keeps the two lists in step as the mentor adds modules.
"""

import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

MODULES = [
    '"Craft/Stage.lua"', '"Craft/Lesson.lua"', '"Craft/Claims.lua"',
    '"Craft/Techniques.lua"', '"Craft/Curriculum.lua"', '"Craft/CraftOrBuy.lua"',
]
ANCHOR = '"Item/Reforging.lua",'

for relative in ("src/Launch.lua", "src/Tests/runner.lua"):
    path = os.path.join(ROOT, relative)
    with io.open(path, encoding="utf-8") as handle:
        text = handle.read()

    added = []
    for module in MODULES:
        if module in text:
            continue
        if ANCHOR not in text:
            print("anchor missing in", relative)
            break
        text = text.replace(ANCHOR, ANCHOR + " " + module, 1)
        added.append(module)

    if added:
        with io.open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        print(relative, "added:", ", ".join(added))
    else:
        print(relative, "already complete")

    for module in MODULES:
        print("  ", module, "->", module in text)
