"""Wire the craft-vs-buy comparison into the API and the syntax guard."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

api_path = os.path.join(ROOT, "src", "Mcp", "api.lua")
with io.open(api_path, encoding="utf-8") as handle:
    api = handle.read()

marker = '\telseif name == "claims" then'
if 'name == "craft_or_buy"' not in api:
    if marker not in api:
        raise SystemExit("claims dispatch marker not found")
    block = (
        '\telseif name == "craft_or_buy" then\n'
        '\t\t-- "Is crafting this cheaper than buying it?" The player supplies the market price, because no\n'
        '\t\t-- feed prices individual rares; the engine supplies the craft cost it can compute exactly.\n'
        '\t\tlocal itemText = args and args.item_text\n'
        '\t\tif type(itemText) ~= "string" or itemText == "" then\n'
        '\t\t\treturn nil, "item_text is required"\n'
        '\t\tend\n'
        '\t\tlocal price = tonumber(args and (args.buy_price or args.price))\n'
        '\t\tif not price or price < 0 then\n'
        '\t\t\treturn nil, "buy_price is required and must be a number in chaos"\n'
        '\t\tend\n'
        '\t\tlocal parsed = parseItem(itemText)\n'
        '\t\tif not parsed then\n'
        '\t\t\treturn nil, "the item could not be parsed"\n'
        '\t\tend\n'
        '\t\tlocal advice = select(1, api.call("analyze_item", { item_text = itemText })) or { }\n'
        '\t\tlocal verdict = CraftOrBuy.verdictFor(price, advice)\n'
        '\t\tif not verdict then\n'
        '\t\t\treturn nil, "the craft cost is unknown for this item, so there is nothing to compare against"\n'
        '\t\tend\n'
        '\t\treturn verdict, nil\n'
    )
    api = api.replace(marker, block + marker, 1)
    print("api: added the craft_or_buy tool")

with io.open(api_path, "w", encoding="utf-8", newline="") as handle:
    handle.write(api)

print("done")
