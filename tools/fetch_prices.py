#!/usr/bin/env python3
"""Fetch a currency price snapshot for the overlay.

Prices come from Craft of Exile's published data (the same JSONP files its own UI
loads): https://www.craftofexile.com/json/poe2/prices/poec_prices.json

Two things are recorded together with the numbers, because a price without them is
misleading: which league the snapshot belongs to and when it was fetched. The panel only
uses the snapshot when its league matches the league the overlay is configured for; the
MCP tools always report it with the label, so an AI client can see the context.

Usage:
    python tools/fetch_prices.py
    python tools/fetch_prices.py --cache tools/cache/coe
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import urllib.request
from datetime import datetime

URL = "https://www.craftofexile.com/json/poe2/prices/poec_prices.json"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120 Safari/537.36"
)


def download(cache: pathlib.Path) -> pathlib.Path:
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / "poec_prices.json"
    request = urllib.request.Request(URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=90) as response:
        target.write_bytes(response.read())
    print(f"downloaded {target.name}: {target.stat().st_size / 1024:.0f} kB")
    return target


def load_jsonp(path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise SystemExit(f"{path} has no JSON object")
    end = text.rfind("}")
    return json.loads(text[start:end + 1])


def lua_quote(value: str) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", default="tools/cache/coe")
    parser.add_argument("--out", default="src/Data/prices.lua")
    parser.add_argument("--refresh", action="store_true", help="re-download even if cached")
    parser.add_argument("--league", default=None,
                        help="league name to price (see --list); the choice is stored in the file")
    parser.add_argument("--list", action="store_true",
                        help="print the leagues the source offers and exit")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    cache = root / args.cache
    cached = cache / "poec_prices.json"
    path = download(cache) if args.refresh or not cached.exists() else cached
    data = load_jsonp(path)

    index = data.get("index") or [ ]
    leagues = data.get("data") or { }

    if args.list:
        for entry in index:
            name = entry.get("name") if isinstance(entry, dict) else None
            if name and name in leagues:
                print(name)
        return 0
    # The site lists a hardcore variant next to each league; the plain one is the base.
    # A league the user picked is used as given. The official league list
    # (tools/fetch_leagues.py) can name a league this price source does not have yet - the
    # source's own current league is used then, and both names are recorded so the page can
    # say exactly which snapshot it is showing.
    requested_league = args.league or ""
    league_name = args.league or None
    chosen = bool(args.league)
    if league_name and league_name not in leagues:
        league_name = None
    if not league_name:
        for entry in index:
            name = entry.get("name") if isinstance(entry, dict) else None
            if name and not str(name).startswith("HC ") and name in leagues:
                league_name = name
                break
    if not league_name and leagues:
        league_name = next(iter(leagues))

    snapshot = leagues.get(league_name, { }) if league_name else { }
    currency = snapshot.get("currency") or { }

    lines = [
        "-- PoE2 Craft Overlay : Data/prices.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_prices.py).",
        "--",
        "-- Currency prices from Craft of Exile's published data, expressed in Chaos Orbs",
        "-- (that is the unit the source uses). A price is only meaningful together with",
        "-- its league and fetch time, so both are stored and shown next to the numbers.",
        "return {",
        f"\tsource = {lua_quote('craftofexile.com (poec_prices.json)')},",
        f"\turl = {lua_quote(URL)},",
        f"\tleague = {lua_quote(league_name or '')},",
        f"\tchosen = {str(chosen).lower()},",
        f"\trequestedLeague = {lua_quote(requested_league)},",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        "\tunit = 'chaos',",
        f"\tcurrencyCount = {len(currency)},",
        "\tcurrency = {",
    ]
    for name in sorted(currency):
        value = currency[name]
        if isinstance(value, (int, float)):
            lines.append(f"\t\t[{lua_quote(name)}] = {value:.6f},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"league: {league_name!r}, currencies: {len(currency)}")
    for probe in ("Chaos Orb", "Divine Orb", "Exalted Orb"):
        if probe in currency:
            print(f"    {probe}: {currency[probe]:.4f} chaos")
    print(f"written: {out_path} ({out_path.stat().st_size / 1024:.0f} kB)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
