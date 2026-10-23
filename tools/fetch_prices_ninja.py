#!/usr/bin/env python3
"""Currency and material prices for Path of Exile 2 from poe.ninja.

Why an aggregator instead of the game's own trade endpoint: the official exchange API
rejects a list of currencies (HTTP 400), allows only a handful of calls before answering
429, and is per-IP. poe.ninja publishes the whole exchange of a category in one request and
its own data only refreshes about hourly, which is exactly what a desktop helper wants.

Endpoints (documented at https://poe.ninja/docs/api, no key needed):

    GET /poe2/api/economy/leagues
    GET /poe2/api/economy/exchange/current/overview?league={league}&type={type}

Their guidelines are followed here: a descriptive User-Agent, conditional requests with
ETag, a pause between categories, and a local cache - the API is a community resource and
polling it faster than its data changes is pointless.

The output keeps the format the overlay already reads (src/Data/prices.lua), so only the
source changes, not the rest of the program.

Usage:
    python tools/fetch_prices_ninja.py --league "Forbidden Rites"
    python tools/fetch_prices_ninja.py --league "Forbidden Rites" --types Currency,Runes
    python tools/fetch_prices_ninja.py --list
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

BASE = "https://poe.ninja/poe2/api/economy"
USER_AGENT = "PoE2CraftOverlay/1.0 (local crafting helper; contact: the overlay's own log)"

# The categories that back the crafting methods the overlay recommends.
DEFAULT_TYPES = ["Currency", "Runes", "Essences", "Ritual", "Breach", "Verisium", "SoulCores"]


def lua_quote(value: str) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def get_json(url: str, cache_file: pathlib.Path, max_age: int, refresh: bool) -> dict | None:
    """GET with ETag and age-based caching. Returns None when nothing changed."""
    etag_file = cache_file.with_suffix(".etag")
    if cache_file.exists() and not refresh:
        age = time.time() - cache_file.stat().st_mtime
        if age < max_age:
            return json.loads(cache_file.read_text(encoding="utf-8-sig"))

    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    if cache_file.exists() and etag_file.exists() and not refresh:
        headers["If-None-Match"] = etag_file.read_text(encoding="utf-8").strip()

    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = response.read()
            tag = response.headers.get("ETag")
    except urllib.error.HTTPError as error:
        if error.code == 304 and cache_file.exists():
            cache_file.touch()
            return json.loads(cache_file.read_text(encoding="utf-8-sig"))
        raise

    cache_file.parent.mkdir(parents=True, exist_ok=True)
    cache_file.write_bytes(payload)
    if tag:
        etag_file.write_text(tag, encoding="utf-8")
    return json.loads(payload.decode("utf-8-sig"))


def collect(league: str, types: list[str], cache_dir: pathlib.Path, max_age: int,
            refresh: bool) -> tuple[dict[str, float], dict[str, str]]:
    """Prices of every currency and material, converted to chaos."""
    prices: dict[str, float] = { }
    sources: dict[str, str] = { }

    for index, category in enumerate(types):
        if index > 0:
            time.sleep(1.5)  # be a good citizen between categories
        url = (f"{BASE}/exchange/current/overview?league={urllib.parse.quote(league)}"
               f"&type={urllib.parse.quote(category)}")
        cache_file = cache_dir / f"{league.replace(' ', '_')}_{category}.json"
        try:
            data = get_json(url, cache_file, max_age, refresh)
        except urllib.error.HTTPError as error:
            print(f"  {category}: HTTP {error.code}", file=sys.stderr)
            continue
        except Exception as error:  # noqa: BLE001
            print(f"  {category}: {error}", file=sys.stderr)
            continue
        if not data:
            continue

        core = data.get("core") or { }
        rates = core.get("rates") or { }
        # Every line is quoted in the primary reference currency (usually divine), so the
        # chaos rate of that currency converts them all at once.
        chaos_rate = float(rates.get("chaos") or 1.0)

        names: dict[str, str] = { }
        for entry in (data.get("items") or []) + (core.get("items") or []):
            if isinstance(entry, dict) and entry.get("id"):
                names[str(entry["id"])] = entry.get("name") or str(entry["id"])

        found = 0
        for line in data.get("lines") or []:
            item_id = str(line.get("id") or "")
            value = line.get("primaryValue")
            if not item_id or value is None:
                continue
            label = names.get(item_id, item_id)
            prices[label] = float(value) * chaos_rate
            sources[label] = category
            found += 1
        print(f"  {category}: {found} prices (chaos rate {chaos_rate:.3f})")

    return prices, sources


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", default="Forbidden Rites",
                        help="league id/name from /poe2/api/economy/leagues")
    parser.add_argument("--types", default=",".join(DEFAULT_TYPES),
                        help="comma-separated categories (default: the crafting ones)")
    parser.add_argument("--out", default="src/Data/prices.lua")
    parser.add_argument("--cache", default="tools/cache/ninja")
    parser.add_argument("--max-age", type=int, default=1800,
                        help="reuse a cached answer younger than this many seconds (default 1800)")
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--list", action="store_true", help="print the prices and exit")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    cache_dir = root / args.cache
    cache_dir.mkdir(parents=True, exist_ok=True)
    types = [part.strip() for part in args.types.split(",") if part.strip()]

    print(f"league {args.league!r}, categories: {', '.join(types)}")
    prices, sources = collect(args.league, types, cache_dir, args.max_age, args.refresh)
    if not prices:
        print("no prices could be read", file=sys.stderr)
        return 1
    prices.setdefault("Chaos Orb", 1.0)
    prices["Chaos Orb"] = 1.0

    if args.list:
        for label in sorted(prices, key=lambda name: prices[name]):
            print(f"  {label}: {prices[label]:.4f} chaos")
        return 0

    lines = [
        "-- PoE2 Craft Overlay : Data/prices.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_prices_ninja.py).",
        "--",
        "-- Prices from poe.ninja's PoE2 economy API: the whole exchange of a category comes",
        "-- in one request, which is what keeps a desktop helper away from trade-API limits.",
        "-- Everything is quoted in Chaos Orbs; the league and the fetch time travel with the",
        "-- numbers because a price without them means nothing.",
        "return {",
        f"\tsource = 'poe.ninja PoE2 economy API',",
        f"\turl = {lua_quote(BASE + '/exchange/current/overview')},",
        f"\tleague = {lua_quote(args.league)},",
        "\tchosen = true,",
        f"\trequestedLeague = {lua_quote(args.league)},",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        "\tunit = 'chaos',",
        f"\tcategories = {lua_quote(','.join(types))},",
        f"\tcurrencyCount = {len(prices)},",
        "\tcurrency = {",
    ]
    for label in sorted(prices):
        lines.append(f"\t\t[{lua_quote(label)}] = {prices[label]:.6f},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"prices: {len(prices)} entries -> {out_path}")
    highlights = ["Divine Orb", "Exalted Orb", "Chaos Orb", "Greater Exalted Orb",
                  "Orb of Annulment", "Regal Orb"]
    for label in highlights:
        if label in prices:
            print(f"    {label}: {prices[label]:.4f} chaos")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
