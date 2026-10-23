#!/usr/bin/env python3
"""Currency prices straight from the game, through the official trade API.

The trade site powers the in-game currency exchange, and its endpoint is public:

    POST https://www.pathofexile.com/api/trade2/exchange/{league}
    {"query": {"status": {"option": "online"}, "have": ["chaos"], "want": ["divine"]},
     "sort": {"have": "asc"}, "engine": "new"}

One request asks for several currencies at once (which matters: the API is rate limited),
and the best offer per currency gives its price in chaos. The result is written in the same
format as the other price tool, so the overlay does not care where the numbers came from -
but the file says so, together with the league and the time.

Usage:
    python tools/fetch_prices_official.py --league "Forbidden Rites"
    python tools/fetch_prices_official.py --league "Forbidden Rites" --list
    python tools/fetch_prices_official.py --league Standard --max-age 3600
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime

BASE = "https://www.pathofexile.com/api/trade2/exchange/"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120 Safari/537.36"
)

# The currencies the overlay actually recommends, plus the unit everything is quoted in.
WANTED = [
    ("divine", "Divine Orb"),
    ("exalted", "Exalted Orb"),
    ("greater-exalted-orb", "Greater Exalted Orb"),
    ("perfect-exalted-orb", "Perfect Exalted Orb"),
    ("chaos", "Chaos Orb"),
    ("orb-of-annulment", "Orb of Annulment"),
    ("regal-orb", "Regal Orb"),
    ("orb-of-transmutation", "Orb of Transmutation"),
    ("orb-of-augmentation", "Orb of Augmentation"),
    ("orb-of-alchemy", "Orb of Alchemy"),
    ("vaal-orb", "Vaal Orb"),
    ("fracturing-orb", "Fracturing Orb"),
]


def lua_quote(value: str) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def post_exchange(league: str, want: list[str]) -> dict:
    body = json.dumps({
        "query": {"status": {"option": "online"}, "have": ["chaos"], "want": want},
        "sort": {"have": "asc"},
        "engine": "new",
    }).encode("utf-8")
    request = urllib.request.Request(
        BASE + urllib.parse.quote(league),
        data=body,
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8-sig"))


def rate_from_offer(offer: dict, unit_id: str) -> float | None:
    """Price of one wanted item in the unit (chaos), from a single offer."""
    item = offer.get("item") or { }
    pay = offer.get("pay") or { }
    # "item" is what the seller gives, "pay" what they want for it.
    got = float(item.get("amount") or 0)
    paid = float(pay.get("amount") or 0)
    if got <= 0 or paid <= 0:
        return None
    if str(pay.get("currency", "")).lower() != unit_id:
        return None
    return paid / got


def collect(league: str) -> dict[str, float]:
    """Ask for one currency at a time: the endpoint rejects a long `want` list.

    Each answer is a separate request, so the caller caches the result and this function
    stops quietly when the API starts rate limiting instead of hammering it.
    """
    prices: dict[str, float] = { }
    for index, (currency_id, label) in enumerate(WANTED):
        if index > 0:
            time.sleep(1.2)  # stay well inside the endpoint's rate limit
        try:
            data = post_exchange(league, [currency_id])
        except urllib.error.HTTPError as error:
            print(f"  {label}: the API refused ({error.code}), stopping here", file=sys.stderr)
            break
        except Exception as error:  # noqa: BLE001
            print(f"  {label}: {error}", file=sys.stderr)
            continue
        best = None
        for entries in (data.get("result") or { }).values():
            for offer in entries if isinstance(entries, list) else [ ]:
                rate = rate_from_offer(offer, "chaos")
                if rate is not None and (best is None or rate < best):
                    best = rate
        if best is None:
            print(f"  {label}: no offer found", file=sys.stderr)
            continue
        prices[label] = best
        print(f"  {label}: {best:.4f} chaos")
    return prices


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--league", default="Standard",
                        help="league name as the official API reports it (tools/fetch_leagues.py --list)")
    parser.add_argument("--out", default="src/Data/prices.lua")
    parser.add_argument("--cache", default="tools/cache/official_exchange")
    parser.add_argument("--max-age", type=int, default=3600,
                        help="reuse a cached answer younger than this many seconds (default 3600)")
    parser.add_argument("--refresh", action="store_true", help="ignore the cache")
    parser.add_argument("--list", action="store_true", help="print the prices and exit")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    cache_dir = root / args.cache
    cache_dir.mkdir(parents=True, exist_ok=True)
    safe = "".join(char if char.isalnum() else "_" for char in args.league)
    cache_file = cache_dir / f"{safe}.json"

    named: dict[str, float] = { }
    if cache_file.exists() and not args.refresh:
        age = time.time() - cache_file.stat().st_mtime
        if age < args.max_age:
            named = json.loads(cache_file.read_text(encoding="utf-8-sig"))
            print(f"cached answer, {age / 60:.0f} min old")
    if not named:
        named = collect(args.league)
        if named:
            cache_file.write_text(json.dumps(named), encoding="utf-8")
    # Chaos is the unit, so it is worth exactly one.
    named.setdefault("Chaos Orb", 1.0)
    if not named:
        print("no prices could be read", file=sys.stderr)
        return 1

    if args.list:
        for label, value in sorted(named.items(), key=lambda pair: pair[1]):
            print(f"  {label}: {value:.4f} chaos")
        return 0

    lines = [
        "-- PoE2 Craft Overlay : Data/prices.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_prices_official.py).",
        "--",
        "-- Prices from the game's own currency exchange through the official trade API.",
        "-- Everything is quoted in Chaos Orbs, the league is recorded with the numbers, and",
        "-- the answer is cached because that endpoint is rate limited.",
        "return {",
        f"\tsource = 'official trade2 exchange (pathofexile.com)',",
        f"\turl = {lua_quote(BASE + args.league)},",
        f"\tleague = {lua_quote(args.league)},",
        "\tchosen = true,",
        f"\trequestedLeague = {lua_quote(args.league)},",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        "\tunit = 'chaos',",
        f"\tcurrencyCount = {len(named)},",
        "\tcurrency = {",
    ]
    for label in sorted(named):
        lines.append(f"\t\t[{lua_quote(label)}] = {named[label]:.6f},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"league: {args.league!r}, currencies: {len(named)} -> {out_path}")
    for label, value in sorted(named.items(), key=lambda pair: pair[1]):
        print(f"    {label}: {value:.4f} chaos")
    return 0


if __name__ == "__main__":
    import urllib.parse  # used by post_exchange

    sys.exit(main(sys.argv[1:]))
