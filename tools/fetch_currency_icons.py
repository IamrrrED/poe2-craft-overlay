#!/usr/bin/env python3
"""Local icons for the currencies the page shows rates for.

poe.ninja's exchange answer carries the game's own icon for every currency it lists, on the
CDN. Downloading three small PNGs once means the page shows real currency icons without
reaching the network on every refresh, and it keeps working offline.

Writes src/Data/currency_icons.lua (name -> local path) and web/public/icons/*.png.

Usage:
    python tools/fetch_currency_icons.py
    python tools/fetch_currency_icons.py --list
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import urllib.parse
import urllib.request
from datetime import datetime

BASE = "https://poe.ninja/poe2/api/economy/exchange/current/overview"
CDN = "https://web.poecdn.com"
USER_AGENT = "PoE2CraftOverlay/1.0 (local crafting helper)"
NEEDED = ["Divine Orb", "Exalted Orb", "Chaos Orb"]


def lua_quote(value: str) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", default="Forbidden Rites")
    parser.add_argument("--out", default="src/Data/currency_icons.lua")
    parser.add_argument("--cache", default="tools/cache/currency_icons.json")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    cache = root / args.cache
    cache.parent.mkdir(parents=True, exist_ok=True)

    if cache.exists():
        meta = json.loads(cache.read_text(encoding="utf-8-sig"))["meta"]
        print(f"using cached metadata: {len(meta)} currencies")
    else:
        url = (f"{BASE}?league={urllib.parse.quote(args.league)}&type=Currency")
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                                       "Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = json.loads(response.read().decode("utf-8-sig"))
        meta = { }
        for entry in (data.get("items") or []) + ((data.get("core") or {}).get("items") or []):
            if isinstance(entry, dict) and entry.get("name") and entry.get("image"):
                meta[entry["name"]] = {"id": entry.get("id"), "image": entry["image"]}
        cache.write_text(json.dumps({"meta": meta}), encoding="utf-8")
        print(f"fetched metadata: {len(meta)} currencies")

    if args.list:
        for name in sorted(meta):
            print(f"  {name:<28} {meta[name].get('id')}")
        return 0

    icons_dir = root / "web/public/icons"
    icons_dir.mkdir(parents=True, exist_ok=True)

    written: dict[str, str] = { }
    for name in NEEDED:
        entry = meta.get(name)
        if not entry:
            print(f"  {name}: not in the exchange answer", file=sys.stderr)
            continue
        image = entry["image"]
        url = image if image.startswith("http") else CDN + image
        slug = entry.get("id") or name.lower().replace(" ", "-")
        target = icons_dir / f"{slug}.png"
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                target.write_bytes(response.read())
        except Exception as error:  # noqa: BLE001
            print(f"  {name}: {error}", file=sys.stderr)
            continue
        written[name] = f"icons/{slug}.png"
        print(f"  {name} -> {written[name]} ({target.stat().st_size / 1024:.1f} kB)")

    if not written:
        print("no icons could be written", file=sys.stderr)
        return 1

    lines = [
        "-- PoE2 Craft Overlay : Data/currency_icons.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_currency_icons.py).",
        "--",
        "-- Local copies of the game's currency icons, taken from the same answer the prices",
        "-- come from. Kept on disk so the page shows them instantly and offline.",
        "return {",
        "\tsource = 'poe.ninja PoE2 exchange (web.poecdn.com icons)',",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        "\ticons = {",
    ]
    for name in sorted(written):
        lines.append(f"\t\t[{lua_quote(name)}] = {lua_quote(written[name])},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"written: {out_path} ({out_path.stat().st_size / 1024:.1f} kB)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
