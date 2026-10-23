"""Wire the Techniques module into the API payload and the syntax guards.

Written as a file because the shell keeps mangling the quoting of Lua string literals.
"""

import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# 1. The API requires it and attaches the applicable techniques to the item payload.
api_path = os.path.join(ROOT, "src", "Mcp", "api.lua")
with io.open(api_path, encoding="utf-8") as handle:
    api = handle.read()

require_anchor = 'local Claims = require("Craft.Claims")'
if "Craft.Techniques" not in api:
    if require_anchor not in api:
        raise SystemExit("claims require not found")
    api = api.replace(require_anchor, require_anchor + '\nlocal Techniques = require("Craft.Techniques")', 1)
    print("api: required Techniques")

removable_anchor = "\t\tremovable = removable,"
if "Techniques.forItem(item)" not in api:
    if removable_anchor not in api:
        raise SystemExit("removable anchor not found")
    api = api.replace(
        removable_anchor,
        removable_anchor
        + "\n\t\t-- Advanced methods that only apply to a specific item state (jewel suffix cap, tag hunt,"
        + "\n\t\t-- desecration wash). Each comes with its precondition already checked against this item."
        + "\n\t\ttechniques = Techniques.forItem(item),",
        1)
    print("api: attached techniques to the methods payload")

with io.open(api_path, "w", encoding="utf-8", newline="") as handle:
    handle.write(api)

# 2. Both syntax guards must know the file, or a mistake in it goes unseen.
ANCHOR = '"Craft/Claims.lua",'
for relative in ("src/Launch.lua", "src/Tests/runner.lua"):
    path = os.path.join(ROOT, relative)
    with io.open(path, encoding="utf-8") as handle:
        text = handle.read()
    if "Craft/Techniques.lua" in text:
        print(relative, "already lists it")
        continue
    if ANCHOR not in text:
        print(relative, "anchor missing")
        continue
    text = text.replace(ANCHOR, ANCHOR + ' "Craft/Techniques.lua",', 1)
    with io.open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print(relative, "listed Techniques")

print("done")
