#!/usr/bin/env python3
"""Fetch the Path of Exile 2 league list from the official trade API.

The official API needs no key for this: https://www.pathofexile.com/api/trade2/data/leagues
returns every realm's leagues (id, realm, text), including the current challenge league.

The list is written to src/Data/leagues.lua so the overlay and the agent can show the
leagues the game itself knows about, instead of guessing or asking a third-party site.

Usage:
    python tools/fetch_leagues.py                 # write src/Data/leagues.lua
    python tools/fetch_leagues.py --list          # print the poe2 league names
    python tools/fetch_leagues.py --list --all    # include other realms (xbox, sony)
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import urllib.request

URL = "https://www.pathofexile.com/api/trade2/data/leagues"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120 Safari/537.36"
)


def fetch(cache: pathlib.Path, refresh: bool) -> dict:
    cache.parent.mkdir(parents=True, exist_ok=True)
    if cache.exists() and not refresh:
        return json.loads(cache.read_text(encoding="utf-8-sig"))
    request = urllib.request.Request(URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = response.read()
    cache.write_bytes(payload)
    return json.loads(payload.decode("utf-8-sig"))


def lua_quote(value: str) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", default="tools/cache/official_leagues.json")
    parser.add_argument("--out", default="src/Data/leagues.lua")
    parser.add_argument("--realm", default="poe2", help="realm to keep (default poe2)")
    parser.add_argument("--all", action="store_true", help="keep every realm")
    parser.add_argument("--list", action="store_true", help="print names and exit")
    parser.add_argument("--refresh", action="store_true", help="ignore the cache")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    data = fetch(root / args.cache, args.refresh)
    leagues = data.get("result") or []

    kept = [entry for entry in leagues
            if args.all or str(entry.get("realm", "")).lower() == args.realm.lower()]
    if not kept:
        print("no leagues returned - the endpoint changed?", file=sys.stderr)
        return 1

    if args.list:
        for entry in kept:
            print(entry.get("text") or entry.get("id"))
        return 0

    lines = [
        "-- PoE2 Craft Overlay : Data/leagues.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_leagues.py).",
        "--",
        "-- The official Path of Exile 2 league list: the trade API publishes it without a",
        "-- key, so the overlay can offer the leagues the game itself knows about.",
        "return {",
        f"\tsource = 'api/trade2/data/leagues (official)',",
        f"\trealm = {lua_quote(args.realm if not args.all else 'all')},",
        "\tleagues = {",
    ]
    for entry in kept:
        lines.append("\t\t{ id = %s, text = %s, realm = %s }," % (
            lua_quote(entry.get("id", "")),
            lua_quote(entry.get("text", entry.get("id", ""))),
            lua_quote(entry.get("realm", "")),
        ))
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"leagues: {len(kept)} (realm {args.realm if not args.all else 'all'}) -> {out_path}")
    for entry in kept:
        print("   ", entry.get("text"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
