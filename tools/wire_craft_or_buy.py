"""Wire the CraftOrBuy module into the craft_step payload.

The step card is where the decision belongs: it is shown before the player spends, and the block is cheap
because the advisor result the card already holds carries the priced methods.
"""

import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

api_path = os.path.join(ROOT, "src", "Mcp", "api.lua")
with io.open(api_path, encoding="utf-8") as handle:
    api = handle.read()

anchor = 'local Curriculum = require("Craft.Curriculum")'
if "Craft.CraftOrBuy" not in api:
    if anchor not in api:
        raise SystemExit("curriculum require not found")
    api = api.replace(anchor, anchor + '\nlocal CraftOrBuy = require("Craft.CraftOrBuy")', 1)
    print("api: required CraftOrBuy")

old = "\t\treturn Coach.report(parsed, advice, itemText), nil"
if "CraftOrBuy.forItem(parsed, advice)" not in api:
    if old not in api:
        raise SystemExit("craft_step return not found")
    new = (
        "\t\tlocal report = Coach.report(parsed, advice, itemText)\n"
        "\t\t-- \"Should I craft this at all?\" - the expected cost of the cheapest route plus exactly what to\n"
        "\t\t-- search in trade to compare. The finished-item price is NOT filled in: the price snapshot has\n"
        "\t\t-- never carried rare items, and inventing one would be the worst thing a mentor could do.\n"
        "\t\treport.craftOrBuy = CraftOrBuy.forItem(parsed, advice)\n"
        "\t\treturn report, nil"
    )
    api = api.replace(old, new, 1)
    print("api: attached the craft-or-buy block")

with io.open(api_path, "w", encoding="utf-8", newline="") as handle:
    handle.write(api)

print("done")
