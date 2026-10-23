#!/usr/bin/env python3
"""Base type -> official item category, from the game's own trade data.

The engine knows an item's class from Path of Building, which is a Path of Exile 1 heritage
and names some PoE2 things differently. The official trade API groups every base type into
the categories the game itself uses:

    accessory 153   armour 1552   currency 616   flask 48   gem 905
    jewel 24        map 63        weapon 521     sanctum 13  wombgift 5

So this map is a second opinion on the class: it is what the game's own trade site believes
a base type is, and it is used to correct and to enrich what the parser read.

Usage:
    python tools/fetch_categories.py
    python tools/fetch_categories.py --list
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import urllib.request
from datetime import datetime

URL = "https://www.pathofexile.com/api/trade2/data/items"
USER_AGENT = "PoE2CraftOverlay/1.0 (local crafting helper)"


def lua_quote(value: str) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="src/Data/categories.lua")
    parser.add_argument("--cache", default="tools/cache/items_categories.json")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    cache = root / args.cache
    cache.parent.mkdir(parents=True, exist_ok=True)

    if cache.exists():
        groups = json.loads(cache.read_text(encoding="utf-8-sig"))["groups"]
        print(f"using cached data: {len(groups)} groups")
    else:
        request = urllib.request.Request(URL, headers={"User-Agent": USER_AGENT,
                                                       "Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=120) as response:
            data = json.loads(response.read().decode("utf-8-sig"))
        groups = []
        for group in data.get("result") or []:
            groups.append({
                "id": group.get("id") or "",
                "entries": [entry.get("type") or "" for entry in (group.get("entries") or [])
                            if isinstance(entry, dict)],
            })
        cache.write_text(json.dumps({"groups": groups}), encoding="utf-8")
        print(f"fetched: {len(groups)} groups")

    by_base: dict[str, str] = { }
    for group in groups:
        for base in group["entries"]:
            if base:
                by_base.setdefault(base, group["id"])

    if args.list:
        for category in sorted(groups, key=lambda g: g["id"]):
            print(f"  {category['id']:<12} {len(category['entries']):>4}")
        print(f"  total base types: {len(by_base)}")
        return 0

    lines = [
        "-- PoE2 Craft Overlay : Data/categories.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_categories.py).",
        "--",
        "-- Base type -> the category the game's own trade data puts it in. Used as a second",
        "-- opinion on the item class the parser read from Path of Building data, which is a",
        "-- Path of Exile 1 heritage and names some PoE2 things differently.",
        "return {",
        "\tsource = 'pathofexile.com/api/trade2/data/items',",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        f"\tbaseCount = {len(by_base)},",
        "\tbyBase = {",
    ]
    for base in sorted(by_base):
        lines.append(f"\t\t[{lua_quote(base)}] = {lua_quote(by_base[base])},")
    lines.append("\t},")
    lines.append("\tgroupCount = {")
    for group in sorted(groups, key=lambda g: g["id"]):
        lines.append(f"\t\t[{lua_quote(group['id'])}] = {len(group['entries'])},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"written: {out_path} ({out_path.stat().st_size / 1024:.0f} kB), bases: {len(by_base)}")
    for probe in ("Crimson Amulet", "Leather Vest", "Glass Shank", "Emerald"):
        if probe in by_base:
            print(f"    {probe!r} -> {by_base[probe]!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
