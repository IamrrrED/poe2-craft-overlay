#!/usr/bin/env python3
"""Full icon index: every PoE2 category poe.ninja prices, plus unique items.

The first index covered seven exchange categories (401 icons). Two labelled samples - the
Simulacrum Splinter and the Cradle of the Origin - were not in it at all, so the matcher could
only return nonsense for them. This version walks every category poe.ninja exposes, tries both
the exchange and the item overviews, downloads the game's own artwork and rewrites
src/Data/icon_index.lua.

Categories that the API does not know simply return nothing useful and are skipped, so the
candidate list can be generous without breaking anything.

Writes:
  src/Data/icon_index.lua        hash -> { name, category, file }
  tools/cache/icons/*.png        the artwork itself
  tools/cache/ninja_full/*.json  raw answers, so a rerun needs no network

Usage:
    python tools/fetch_all_icons.py
    python tools/fetch_all_icons.py --check
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime

from PIL import Image
import numpy

EXCHANGE = "https://poe.ninja/poe2/api/economy/exchange/current/overview"
ITEM = "https://poe.ninja/poe2/api/economy/item/current/overview"
USER_AGENT = "PoE2CraftOverlay/1.0 (local crafting helper)"

EXCHANGE_TYPES = [
    "Currency", "Fragments", "Runes", "Essences", "Ritual", "Breach", "Verisium",
    "SoulCores", "Delirium", "Abyss", "Expedition", "Legion", "Blight", "Ultimatum",
    "Sanctum", "Incursion", "Betrayal", "Heist", "Kalandra", "Crucible", "Sentinel",
    "Affliction", "Necropolis", "Settlers", "Ancestor", "ToTA", "Halls", "Vaults",
]
ITEM_TYPES = [
    "UniqueWeapon", "UniqueArmour", "UniqueAccessory", "UniqueJewel", "UniqueFlask",
    "UniqueRelic", "UniqueTincture", "UniqueIdol", "UniqueGolden", "UniqueMap",
    "ForbiddenJewel", "Beast", "DivinationCard", "SkillGem", "ImbuedGem",
]


def lua_quote(value: str) -> str:
    out = ['"']
    for char in str(value):
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char == "\r":
            out.append("\\r")
        elif char == "\n":
            out.append("\\n")
        elif char == "\t":
            out.append("\\t")
        else:
            out.append(char)
    out.append('"')
    return "".join(out)


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "icon"


def dhash(path: pathlib.Path) -> str:
    with Image.open(path) as image:
        small = image.convert("L").resize((9, 8), Image.Resampling.LANCZOS)
        grid = numpy.asarray(small, dtype=numpy.int16)
    bits = 0
    for row in range(8):
        for column in range(8):
            bits = (bits << 1) | (1 if grid[row, column] > grid[row, column + 1] else 0)
    return f"{bits:016x}"


def fetch(url: str, cache: pathlib.Path) -> dict | None:
    if cache.exists():
        try:
            return json.loads(cache.read_text(encoding="utf-8-sig"))
        except Exception:
            return None
    try:
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                                       "Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=45) as response:
            data = json.loads(response.read().decode("utf-8-sig"))
    except Exception:
        return None
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(data), encoding="utf-8")
    return data


def collect(data: object) -> list[dict]:
    """Entries live either under items or under core.items depending on the endpoint.

    The parameter is typed as object on purpose: the answer comes straight off the network, so
    the check below is real and the annotation must not promise more than the caller guarantees.
    """
    if not isinstance(data, dict):
        return []
    result = [e for e in (data.get("items") or []) if isinstance(e, dict)]
    result += [e for e in ((data.get("core") or {}).get("items") or []) if isinstance(e, dict)]
    lines = data.get("lines") or []
    for line in lines if isinstance(lines, list) else []:
        if isinstance(line, dict) and line.get("name"):
            result.append({"name": line.get("name"), "image": line.get("icon") or line.get("image")})
    return result


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", default="Forbidden Rites")
    parser.add_argument("--out", default="src/Data/icon_index.lua")
    parser.add_argument("--icons", default="tools/cache/icons")
    parser.add_argument("--cache-dir", default="tools/cache/ninja_full")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    icons_dir = root / args.icons
    cache_dir = root / args.cache_dir
    icons_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)

    entries: dict[str, dict] = {}
    downloaded = 0
    plan = ([("exchange", t) for t in EXCHANGE_TYPES] + [("item", t) for t in ITEM_TYPES])
    for kind, name in plan:
        base = EXCHANGE if kind == "exchange" else ITEM
        url = f"{base}?league={urllib.parse.quote(args.league)}&type={urllib.parse.quote(name)}"
        data = fetch(url, cache_dir / f"{kind}_{name}.json")
        items = collect(data) if data else []
        got = 0
        for entry in items:
            item_name = entry.get("name")
            image = entry.get("image") or entry.get("icon")
            if not item_name or not image:
                continue
            if isinstance(image, str) and image.startswith("http"):
                image_url = image
            else:
                image_url = "https://web.poecdn.com" + str(image)
            target = icons_dir / f"{slug(item_name)}.png"
            if not target.exists():
                try:
                    request = urllib.request.Request(image_url, headers={"User-Agent": USER_AGENT})
                    with urllib.request.urlopen(request, timeout=40) as response:
                        target.write_bytes(response.read())
                    downloaded += 1
                except Exception:
                    continue
            label = name if kind == "exchange" else f"Unique/{name}"
            entries[item_name] = {"category": label, "file": target.name, "hash": dhash(target)}
            got += 1
        if got:
            print(f"  {kind:<9} {name:<18} {got:>4} предметов")

    by_hash: dict[str, dict] = {}
    collisions = 0
    for item_name, entry in sorted(entries.items()):
        if entry["hash"] in by_hash:
            collisions += 1
            continue
        by_hash[entry["hash"]] = {"name": item_name, **entry}

    print(f"  всего: {len(entries)} предметов, уникальных хешей: {len(by_hash)}, "
          f"скачано заново: {downloaded}, совпавших хешей: {collisions}")

    lines = [
        "-- PoE2 Craft Overlay : Data/icon_index.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_all_icons.py).",
        "--",
        "-- Artwork of every item poe.ninja prices for the league, so a screenshot can be read",
        "-- without hovering anything. Artwork is the game's own, served from web.poecdn.com.",
        "return {",
        "\tsource = 'poe.ninja poe2 economy (exchange + item overviews)',",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        "\tleague = " + lua_quote(args.league) + ",",
        f"\tcount = {len(by_hash)},",
        "\ticons = {",
    ]
    for key in sorted(by_hash):
        entry = by_hash[key]
        lines.append(f"\t\t[{lua_quote(key)}] = {{ name = {lua_quote(entry['name'])}, "
                     f"category = {lua_quote(entry['category'])}, file = {lua_quote(entry['file'])} }},")
    lines.append("\t},")
    lines.append("\tbyName = {")
    for item_name in sorted(entries):
        entry = entries[item_name]
        lines.append(f"\t\t[{lua_quote(item_name)}] = {{ hash = {lua_quote(entry['hash'])}, "
                     f"category = {lua_quote(entry['category'])}, file = {lua_quote(entry['file'])} }},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"  записано: {out_path} ({out_path.stat().st_size / 1024:.0f} кБ)")

    if args.check:
        hits = sum(1 for item_name, entry in entries.items()
                   if (by_hash.get(entry["hash"]) or {}).get("name") == item_name)
        print(f"  проверка: {hits} из {len(entries)} иконок узнаются как сами себя")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
