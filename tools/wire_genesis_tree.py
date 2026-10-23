"""Wire the Genesis Tree advisor into the guide payload and the syntax guards."""

import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

api_path = os.path.join(ROOT, "src", "Mcp", "api.lua")
with io.open(api_path, encoding="utf-8") as handle:
    api = handle.read()

anchor = 'local CraftOrBuy = require("Craft.CraftOrBuy")'
if "Craft.GenesisTree" not in api:
    if anchor not in api:
        raise SystemExit("craftorbuy require not found")
    api = api.replace(anchor, anchor + '\nlocal GenesisTree = require("Craft.GenesisTree")', 1)
    print("api: required GenesisTree")

marker = "\t\t\tclaims = Claims.list(),"
if "GenesisTree.overview" not in api:
    if marker not in api:
        raise SystemExit("claims marker not found")
    api = api.replace(
        marker,
        marker
        + "\n\t\t\t-- The Genesis Tree as plans with expected births, so the reference can answer \"how do I"
        + "\n\t\t\t-- get the catalyst I need\" - the question 0.5.0's drop change made unavoidable."
        + "\n\t\t\tgenesisTree = {"
        + "\n\t\t\t\tlocation = (ruleset().genesisTree or {}).location,"
        + "\n\t\t\t\tnotes = (ruleset().genesisTree or {}).notes,"
        + "\n\t\t\t\tgoals = GenesisTree.overview(ruleset()),"
        + "\n\t\t\t},",
        1)
    print("api: attached the tree to the guide payload")

with io.open(api_path, "w", encoding="utf-8", newline="") as handle:
    handle.write(api)

ANCHOR = '"Craft/CraftOrBuy.lua",'
for relative in ("src/Launch.lua", "src/Tests/runner.lua"):
    path = os.path.join(ROOT, relative)
    with io.open(path, encoding="utf-8") as handle:
        text = handle.read()
    if "Craft/GenesisTree.lua" in text:
        print(relative, "already lists it")
        continue
    if ANCHOR not in text:
        print(relative, "anchor missing")
        continue
    text = text.replace(ANCHOR, ANCHOR + ' "Craft/GenesisTree.lua",', 1)
    with io.open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print(relative, "listed GenesisTree")

print("done")
