#!/usr/bin/env python3
"""Icon index: recognise what is in a stash tab from a screenshot, without hovering anything.

Why this exists
---------------
The mods of a rare item can only be read from its tooltip, one item at a time. Everything else -
currency, runes, essences, breach and ritual items, soul cores - is identified by its artwork,
and those are the things a beginner's wealth is actually made of. The game uses the same images
the trade site publishes, so a screenshot cell can be matched against a local icon index.

How the matching works
----------------------
poe.ninja's overview carries the game's own icon path for every item it prices, on the CDN. Each
icon is downloaded once, reduced to a 64-bit difference hash, and stored in a Lua table keyed by
that hash. A cell cropped from a screenshot gets the same treatment and the nearest hash wins.
Equal images hash equally, so this is exact for the common case and cheap enough to run on every
tab.

Writes:
  src/Data/icon_index.lua           hash -> { name, category, image }
  tools/cache/icons/<slug>.png      the icons themselves, for inspection

Usage:
    python tools/fetch_icon_index.py
    python tools/fetch_icon_index.py --check      # verify the index against its own icons
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

BASE = "https://poe.ninja/poe2/api/economy/exchange/current/overview"
CDN = "https://web.poecdn.com"
USER_AGENT = "PoE2CraftOverlay/1.0 (local crafting helper)"
CATEGORIES = ["Currency", "Runes", "Essences", "Ritual", "Breach", "Verisium", "SoulCores"]


def lua_quote(value: str) -> str:
    text = str(value)
    out = ['"']
    for char in text:
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char in "\r\n\t":
            out.append({"\\": "\\\\", "\r": "\\r", "\n": "\\n", "\t": "\\t"}[char])
        else:
            out.append(char)
    out.append('"')
    return "".join(out)


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "icon"


def dhash(path: pathlib.Path) -> str:
    """64-bit difference hash of an image, as hex. Equal artwork gives equal hashes."""
    with Image.open(path) as image:
        small = image.convert("L").resize((9, 8), Image.Resampling.LANCZOS)
        grid = numpy.asarray(small, dtype=numpy.int16)
    bits = 0
    for row in range(8):
        for column in range(8):
            bits = (bits << 1) | (1 if grid[row, column] > grid[row, column + 1] else 0)
    return f"{bits:016x}"


def fetch_category(league: str, category: str, cache: pathlib.Path) -> dict:
    if cache.exists():
        return json.loads(cache.read_text(encoding="utf-8-sig"))
    url = f"{BASE}?league={urllib.parse.quote(league)}&type={urllib.parse.quote(category)}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = json.loads(response.read().decode("utf-8-sig"))
    cache.write_text(json.dumps(data), encoding="utf-8")
    return data


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", default="Forbidden Rites")
    parser.add_argument("--out", default="src/Data/icon_index.lua")
    parser.add_argument("--icons", default="tools/cache/icons")
    parser.add_argument("--cache-dir", default="tools/cache/ninja")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    icons_dir = root / args.icons
    cache_dir = root / args.cache_dir
    icons_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)

    entries: dict[str, dict] = {}
    downloaded = 0
    for category in CATEGORIES:
        try:
            data = fetch_category(args.league, category, cache_dir / f"{category}.json")
        except Exception as error:
            print(f"  {category}: не получено ({str(error)[:60]})")
            continue
        items = (data.get("items") or []) + ((data.get("core") or {}).get("items") or [])
        for entry in items:
            if not isinstance(entry, dict):
                continue
            name = entry.get("name")
            image = entry.get("image")
            if not name or not image:
                continue
            target = icons_dir / f"{slug(name)}.png"
            if not target.exists():
                try:
                    request = urllib.request.Request(CDN + image, headers={"User-Agent": USER_AGENT})
                    with urllib.request.urlopen(request, timeout=45) as response:
                        target.write_bytes(response.read())
                    downloaded += 1
                except Exception:
                    continue
            entries[name] = {"category": category, "image": image, "file": target.name, "hash": dhash(target)}
        print(f"  {category}: {len([e for e in entries.values() if e['category'] == category])} предметов")

    by_hash: dict[str, dict] = {}
    collisions = 0
    for name, entry in sorted(entries.items()):
        if entry["hash"] in by_hash:
            collisions += 1
            continue
        by_hash[entry["hash"]] = {"name": name, **entry}

    print(f"  всего иконок: {len(entries)}, уникальных хешей: {len(by_hash)}, скачано новых: {downloaded}")
    if collisions:
        print(f"  одинаковых хешей (разные предметы с похожей иконкой): {collisions}")

    lines = [
        "-- PoE2 Craft Overlay : Data/icon_index.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_icon_index.py).",
        "--",
        "-- Icon hashes of the items a stash tab is made of, so a screenshot can be read without",
        "-- hovering anything. The artwork is the game's own, taken from poe.ninja's overview.",
        "return {",
        "\tsource = 'poe.ninja poe2 economy overview (icons on web.poecdn.com)',",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        "\tleague = " + lua_quote(args.league) + ",",
        f"\tcount = {len(by_hash)},",
        "\ticons = {",
    ]
    for key in sorted(by_hash):
        entry = by_hash[key]
        lines.append(
            f"\t\t[{lua_quote(key)}] = {{ name = {lua_quote(entry['name'])}, "
            f"category = {lua_quote(entry['category'])}, file = {lua_quote(entry['file'])} }},")
    lines.append("\t},")
    lines.append("\tbyName = {")
    for name in sorted(entries):
        entry = entries[name]
        lines.append(f"\t\t[{lua_quote(name)}] = {{ hash = {lua_quote(entry['hash'])}, "
                     f"category = {lua_quote(entry['category'])}, file = {lua_quote(entry['file'])} }},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"  записано: {out_path} ({out_path.stat().st_size / 1024:.0f} кБ)")

    if args.check:
        hits = 0
        for name, entry in sorted(entries.items()):
            found = by_hash.get(entry["hash"])
            if found and found["name"] == name:
                hits += 1
        print(f"  проверка индекса: {hits} из {len(entries)} иконок узнаются как сами себя")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
