#!/usr/bin/env python3
"""The desecration pool: official stat vocabulary joined with datamined mod data.

Two sources, both public and both checkable:

  1. the official trade API's `desecrated` stats (tools/fetch_desecrated.py) - the vocabulary
     the game itself uses for the Well of Souls, with English and Russian text;
  2. the RePoE-fork Path of Exile 2 export (`mods.min.json`) - the datamined mod table the
     community project poe2-better-trade-filter is built on, which carries, per mod, its
     stats, its required level and its spawn weights per item tag.

A mod belongs to the desecration pool when one of its stats has a `desecrated.` id. Its
eligibility for an item then comes from the spawn weights, exactly as for ordinary crafting:
a weight above zero on a tag the item has means the mod can be offered.

Writes src/Data/desecration_pool.lua and reports how many mods a helmet gets, which is the
acceptance check for the real item: the three modifiers the Well of Souls offered it must be
in that set.

Usage:
    python tools/fetch_desecration_pool.py
    python tools/fetch_desecration_pool.py --item-tags armour,helmet,default --ilvl 79
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.request
from datetime import datetime

MODS_URL = "https://repoe-fork.github.io/poe2/mods.min.json"
USER_AGENT = "PoE2CraftOverlay/1.0 (local crafting helper)"

# The modifiers the Well of Souls actually offered the test helmet, by official stat id.
ACCEPTANCE = {
    "desecrated.stat_3299347043": "# to maximum Life",
    "desecrated.stat_1050105434": "# to maximum Mana",
    "desecrated.stat_3917489142": "#% increased Rarity of Items found",
}


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


def fetch_mods(cache: pathlib.Path) -> dict:
    if cache.exists():
        print(f"using cached mods: {cache.stat().st_size / 1024 / 1024:.1f} MB")
        return json.loads(cache.read_text(encoding="utf-8-sig"))
    request = urllib.request.Request(MODS_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=300) as response:
        payload = response.read()
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_bytes(payload)
    print(f"downloaded mods: {len(payload) / 1024 / 1024:.1f} MB")
    return json.loads(payload.decode("utf-8-sig"))


def stat_id_of(entry: dict) -> str:
    """RePoE writes a stat as {"id": "..."} or, in some versions, as a plain string."""
    if isinstance(entry, dict):
        return str(entry.get("id") or "")
    return str(entry or "")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="src/Data/desecration_pool.lua")
    parser.add_argument("--mods-cache", default="tools/cache/repoe_mods.json")
    parser.add_argument("--stats-cache", default="tools/cache/desecrated.json")
    parser.add_argument("--item-tags", default="armour,helmet,default")
    parser.add_argument("--ilvl", type=int, default=79)
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    mods = fetch_mods(root / args.mods_cache)

    stats_cache = root / args.stats_cache
    vocabulary = { }
    if stats_cache.exists():
        stored = json.loads(stats_cache.read_text(encoding="utf-8-sig"))
        for stat_id, entry in stored.get("en", {}).items():
            russian = stored.get("ru", {}).get(stat_id, { })
            vocabulary[stat_id] = {"en": entry.get("text") or "", "ru": russian.get("text") or ""}
    print(f"official desecrated vocabulary: {len(vocabulary)} stats")

    tags = [tag.strip() for tag in args.item_tags.split(",") if tag.strip()]

    # The datamine lists a stat under its explicit id, while the official API marks which of
    # those stat ids the game treats as desecrated. The numeric part of the id is the join key:
    # "explicit.stat_3299347043" and "desecrated.stat_3299347043" are the same stat.
    desecrated_suffixes = { }
    for stat_id in vocabulary:
        if "_" in stat_id:
            desecrated_suffixes[stat_id.split("_")[-1]] = stat_id

    pool = []
    for mod in mods.values() if isinstance(mods, dict) else mods:
        if not isinstance(mod, dict):
            continue
        stat_ids = [stat_id_of(s) for s in (mod.get("stats") or [])]
        desecrated = []
        for sid in stat_ids:
            suffix = sid.split("_")[-1] if "_" in sid else sid
            if suffix in desecrated_suffixes:
                desecrated.append(desecrated_suffixes[suffix])
        desecrated = sorted(set(desecrated))
        if not desecrated:
            continue
        weights = mod.get("spawn_weights") or []
        positive = { }
        for weight in weights:
            if isinstance(weight, dict) and float(weight.get("weight") or 0) > 0:
                positive[str(weight.get("tag") or "")] = float(weight.get("weight"))
        eligible = [tag for tag in tags if tag in positive]
        pool.append({
            "mod": str(mod.get("id") or mod.get("name") or "?"),
            "name": str(mod.get("name") or ""),
            "generation": str(mod.get("generation_type") or ""),
            "level": int(mod.get("required_level") or 0),
            "stats": desecrated,
            "tags": sorted(positive.keys()),
            "eligible": eligible,
        })

    usable = [entry for entry in pool if entry["eligible"] and entry["level"] <= args.ilvl]
    print(f"desecration mods in the datamine: {len(pool)}")
    print(f"eligible for tags {tags} at item level {args.ilvl}: {len(usable)}")

    print("acceptance check (the modifiers the Well of Souls offered):")
    ok = True
    for stat_id, label in ACCEPTANCE.items():
        hits = [entry for entry in pool if stat_id in entry["stats"]]
        if not hits:
            print(f"  MISSING from the pool: {stat_id} ({label})")
            ok = False
            continue
        entry = hits[0]
        fits = bool(entry["eligible"]) and entry["level"] <= args.ilvl
        print(f"  {'ok ' if fits else 'no '} {label:<34} level>={entry['level']:<3} tags={entry['tags'][:6]}")
        if not fits:
            ok = False
    print(f"acceptance: {'PASSED' if ok else 'NOT PASSED'}")

    lines = [
        "-- PoE2 Craft Overlay : Data/desecration_pool.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_desecration_pool.py).",
        "--",
        "-- The mods the Well of Souls can offer, from two public sources: the official trade",
        "-- API marks which stats are desecrated, and the RePoE-fork datamine says which mod",
        "-- carries them, at what level and with which spawn weights per item tag.",
        "return {",
        "\tstatsSource = 'pathofexile.com/api/trade2/data/stats (type=desecrated)',",
        "\tmodsSource = 'repoe-fork.github.io/poe2/mods.min.json',",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        f"\tcount = {len(pool)},",
        "\tvocabulary = {",
    ]
    for stat_id in sorted(vocabulary):
        entry = vocabulary[stat_id]
        lines.append(f"\t\t[{lua_quote(stat_id)}] = {{ en = {lua_quote(entry['en'])}, ru = {lua_quote(entry['ru'])} }},")
    lines.append("\t},")
    lines.append(f"\tmodCount = {len(pool)},")
    lines.append("\tmods = {")
    for entry in sorted(pool, key=lambda item: item["mod"]):
        stats = ", ".join(lua_quote(sid) for sid in entry["stats"])
        tags_list = ", ".join(lua_quote(tag) for tag in entry["tags"])
        lines.append(
            f"\t\t{{ id = {lua_quote(entry['mod'])}, name = {lua_quote(entry['name'])}, "
            f"generation = {lua_quote(entry['generation'])}, level = {entry['level']}, "
            f"stats = {{ {stats} }}, tags = {{ {tags_list} }} }},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"written: {out_path} ({out_path.stat().st_size / 1024:.0f} kB)")
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
