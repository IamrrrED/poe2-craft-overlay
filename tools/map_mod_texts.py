#!/usr/bin/env python3
"""Join our modifier texts to Craft of Exile's modifier ids.

The two sources describe the same modifiers but key them differently: we carry Path of Building
group names (`AbyssTargetMod|Prefix`) while Craft of Exile keys by its own modifier id and names a
mod by its display text. The shared thing is that text, once values are made comparable: we write
ranges as `(1-2)`, Craft of Exile writes `#`.

Doing the join here rather than in Lua has one purpose: the normalisation is written and tested
once, in the language where it was measured (65% of our texts match), instead of being duplicated
in Lua patterns and drifting apart.

Writes src/Data/coe_text_map.lua: our tier text -> { id = <modifier id>, coe = <their wording> }.

Usage:
    python tools/map_mod_texts.py
    python tools/map_mod_texts.py --report
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from datetime import datetime


def lua_quote(value: object) -> str:
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


def normalise(text: str) -> str:
    """Make the two wordings comparable: (1-2) and bare numbers both become #."""
    text = text.lower()
    text = re.sub(r"\([^)]*\)", "#", text)
    text = re.sub(r"\d+(?:\.\d+)?", "#", text)
    text = re.sub(r"[^a-z#\s]", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def load_coe(path: pathlib.Path) -> dict[str, int]:
    raw = path.read_bytes()
    data = json.loads(raw[raw.find(b"{"):].decode("utf-8", "replace"))
    result: dict[str, int] = {}
    for row in (data.get("modifiers") or {}).get("seq", []):
        if not isinstance(row, dict):
            continue
        text = row.get("name_modifier")
        modifier_id = row.get("id_modifier")
        if text and modifier_id is not None:
            result.setdefault(normalise(str(text)), int(modifier_id))
    return result


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--coe", default="tools/cache/coe2.json")
    parser.add_argument("--mods", default="src/Data/mods.lua")
    parser.add_argument("--out", default="src/Data/coe_text_map.lua")
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    coe_path = root / args.coe
    mods_path = root / args.mods
    if not coe_path.exists():
        print(f"нет данных Craft of Exile: {coe_path}")
        return 1
    if not mods_path.exists():
        print(f"нет наших данных модов: {mods_path}")
        return 1

    coe_by_text = load_coe(coe_path)
    lua_text = mods_path.read_text(encoding="utf-8")
    our_texts = sorted({text for text in re.findall(r'text\s*=\s*"([^"]{4,160})"', lua_text)})
    if not our_texts:
        print("в наших данных не найдено ни одного текста мода")
        return 1

    mapped: dict[str, int] = {}
    unmatched: list[str] = []
    for text in our_texts:
        key = normalise(text)
        modifier_id = coe_by_text.get(key)
        if modifier_id is None:
            unmatched.append(text)
        else:
            mapped[text] = modifier_id

    share = 100 * len(mapped) / len(our_texts)
    print(f"  наших текстов: {len(our_texts)}, текстов CoE: {len(coe_by_text)}")
    print(f"  сопоставлено: {len(mapped)} ({share:.0f}%), без пары: {len(unmatched)}")
    if args.report:
        print("  === примеры сопоставлений ===")
        for text in sorted(mapped)[:6]:
            print(f"    {text[:60]:<60} -> id {mapped[text]}")
        print("  === примеры без пары ===")
        for text in unmatched[:6]:
            print(f"    {text[:70]}")

    lines = [
        "-- PoE2 Craft Overlay : Data/coe_text_map.lua",
        "-- GENERATED FILE - do not edit by hand (tools/map_mod_texts.py).",
        "--",
        "-- Our modifier text -> Craft of Exile modifier id, joined by normalised wording",
        "-- (values written as # on both sides). Mods without an entry keep the tag-based weight.",
        "return {",
        "\tsource = 'craftofexile.com published weighting data (coe2.json)',",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        f"\tmatched = {len(mapped)},",
        f"\tunmatched = {len(unmatched)},",
        "\tmap = {",
    ]
    for text in sorted(mapped):
        lines.append(f"\t\t[{lua_quote(text)}] = {mapped[text]},")
    lines += ["\t},", "}", ""]

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"  записано: {out_path} ({out_path.stat().st_size / 1024:.0f} кБ)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
