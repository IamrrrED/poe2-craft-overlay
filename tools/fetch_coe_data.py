#!/usr/bin/env python3
"""Turn Craft of Exile's published weighting data into tables our engine can read.

`coe2.json` is a JavaScript assignment (`poecd={...}`) rather than plain JSON, so the six-byte
prefix is stripped before parsing.

How the data is actually laid out - this took a while to get right, and it matters:

* `modifiers` lists the mods: affix kind, mod group, tags (mod type ids), hybrid flag.
* Weights are **not** on the mod. They live in `tiers`, keyed first by mod-type id and then by
  base-item id, as a list of `{ilvl, weighting, ...}` rows. One mod type therefore carries several
  rows per base: those are the tiers, and a mod's weight depends on the item level.
* `modbases` (type -> bases) and `basemods` (base -> types) say which bases a type applies to.

Because the weight tables are large, they go into their own file and are keyed as they are in the
source: mod type, then base.

Writes:
  src/Data/coe_bases.lua     base items with the numeric ids the Craft of Exile format expects
  src/Data/coe_mods.lua      mods: affix, group, type names, bases
  src/Data/coe_weights.lua   tiers and weights: type -> base -> [{ilvl, weight}, ...]

Usage:
    python tools/fetch_coe_data.py
    python tools/fetch_coe_data.py --report
"""

from __future__ import annotations

import argparse
import json
import pathlib
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


def lua_list(values: list) -> str:
    return "{ " + ", ".join(lua_quote(item) for item in values) + " }"


def as_dict(value: object) -> dict:
    """Sections arrive from untyped JSON, so narrow them explicitly before use."""
    return value if isinstance(value, dict) else {}


def load(path: pathlib.Path) -> dict:
    raw = path.read_bytes()
    start = raw.find(b"{")
    if start < 0:
        raise SystemExit(f"в файле {path} не найден JSON")
    return json.loads(raw[start:].decode("utf-8", "replace"))


def rows(section: object) -> list[dict]:
    if isinstance(section, dict):
        seq = section.get("seq")
        if isinstance(seq, list):
            return [row for row in seq if isinstance(row, dict)]
        return [row for row in section.values() if isinstance(row, dict)]
    if isinstance(section, list):
        return [row for row in section if isinstance(row, dict)]
    return []


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="tools/cache/coe2.json")
    parser.add_argument("--data-dir", default="src/Data")
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    source = pathlib.Path(args.source)
    if not source.is_absolute():
        source = root / source
    if not source.exists():
        print(f"нет данных Craft of Exile: {source}")
        return 1
    data_dir = root / args.data_dir

    data = load(source)
    modifiers = rows(data.get("modifiers"))
    bitems = rows(data.get("bitems"))
    bases = rows(data.get("bases"))
    bgroups = rows(data.get("bgroups"))
    mtypes = rows(data.get("mtypes"))
    tiers = as_dict(data.get("tiers"))
    modbases = as_dict(data.get("modbases"))

    type_name = {str(row.get("id_mtype")): row.get("name_mtype") for row in mtypes}
    base_by_id = {str(row.get("id_base")): row for row in bases if row.get("id_base") is not None}
    group_by_id = {str(row.get("id_bgroup")): row for row in bgroups if row.get("id_bgroup") is not None}
    item_name = {str(row.get("id_bitem")): row.get("name_bitem") for row in bitems}

    if args.report:
        print("  === структура весов ===")
        sample_type = next(iter(tiers), None)
        if sample_type:
            per_base = tiers[sample_type]
            sample_base = next(iter(per_base), None)
            print(f"    тип {sample_type} ({type_name.get(str(sample_type), '?')}), база {sample_base}"
                  f" ({item_name.get(str(sample_base), '?')}): {per_base[sample_base]}")

    # --- базы предметов ---
    base_lines = []
    for item in bitems:
        name = item.get("name_bitem")
        if not name:
            continue
        base_row = base_by_id.get(str(item.get("id_base"))) or {}
        group_row = group_by_id.get(str(base_row.get("id_bgroup"))) or {}
        base_lines.append(
            f"\t\t[{lua_quote(name)}] = {{ id_bitem = {lua_quote(item.get('id_bitem'))}, "
            f"id_base = {lua_quote(item.get('id_base'))}, base = {lua_quote(base_row.get('name_base') or '')}, "
            f"class = {lua_quote(group_row.get('name_bgroup') or '')}, "
            f"dropLevel = {item.get('drop_level') if item.get('drop_level') is not None else 'nil'} }},")

    # --- моды: вид аффикса, группа, типы, базы ---
    mod_lines = []
    for row in modifiers:
        name = row.get("name_modifier")
        if not name:
            continue
        type_ids = [str(value) for value in (row.get("mtypes") or [])]
        bases_for_mod: list[str] = []
        for type_id in type_ids:
            for base_id in (modbases.get(type_id) or []):
                if base_id not in bases_for_mod:
                    bases_for_mod.append(str(base_id))
        mod_lines.append(
            f"\t\t[{lua_quote(name)}] = {{ id = {lua_quote(row.get('id_modifier'))}, "
            f"affix = {lua_quote(row.get('affix') or '')}, "
            f"group = {lua_quote(row.get('modgroup') or '')}, "
            f"types = {lua_list(type_ids)}, typeNames = "
            f"{lua_list([type_name.get(t, t) for t in type_ids])}, "
            f"hybrid = {'true' if row.get('hybrid') else 'false'}, "
            f"bases = {lua_list(bases_for_mod)} }},")

    # --- веса: тип -> база -> тиры ---
    weight_lines = []
    tier_count = 0
    for type_id, per_base in sorted(tiers.items()):
        if not isinstance(per_base, dict):
            continue
        weight_lines.append(f"\t\t[{lua_quote(type_id)}] = {{ -- {type_name.get(type_id, '?')}")
        for base_id, entries in sorted(per_base.items()):
            if not isinstance(entries, list):
                continue
            tiers_text = []
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                level = entry.get("ilvl")
                weight = entry.get("weighting")
                if weight is None:
                    continue
                tier_count += 1
                tiers_text.append(
                    "{ ilvl = " + str(level if level is not None else 0)
                    + ", weight = " + str(weight) + " }")
            if tiers_text:
                weight_lines.append(
                    f"\t\t\t[{lua_quote(base_id)}] = {{ {', '.join(tiers_text)} }}, "
                    f"-- {item_name.get(base_id, '?')}")
        weight_lines.append("\t\t},")

    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    header = [
        "-- PoE2 Craft Overlay",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_coe_data.py).",
    ]

    bases_path = data_dir / "coe_bases.lua"
    bases_path.write_text("\n".join(header + [
        "--",
        "-- Base items with the numeric ids Craft of Exile's item format expects.",
        "return {",
        "\tsource = 'craftofexile.com published weighting data (coe2.json)',",
        f"\tfetchedAt = {lua_quote(stamp)},",
        f"\tcount = {len(base_lines)},",
        "\tbases = {",
    ] + base_lines + ["\t},", "}", ""]), encoding="utf-8")

    mods_path = data_dir / "coe_mods.lua"
    mods_path.write_text("\n".join(header + [
        "--",
        "-- The mod pool: affix kind, group, and the mod types and bases it belongs to.",
        "-- Weights live in coe_weights.lua, keyed by mod type and base.",
        "return {",
        "\tsource = 'craftofexile.com published weighting data (coe2.json)',",
        f"\tfetchedAt = {lua_quote(stamp)},",
        f"\tcount = {len(mod_lines)},",
        "\tmods = {",
    ] + mod_lines + ["\t},", "}", ""]), encoding="utf-8")

    weights_path = data_dir / "coe_weights.lua"
    weights_path.write_text("\n".join(header + [
        "--",
        "-- Tier weights exactly as the source states them: mod type -> base item -> tiers.",
        "-- Each row is { ilvl, weight }, so a mod's weight depends on the item level.",
        "return {",
        "\tsource = 'craftofexile.com published weighting data (coe2.json)',",
        f"\tfetchedAt = {lua_quote(stamp)},",
        f"\ttypes = {len([line for line in weight_lines if line.startswith(chr(9) + chr(9)) and line.endswith(',')])},",
        f"\ttiers = {tier_count},",
        "\tweights = {",
    ] + weight_lines + ["\t},", "}", ""]), encoding="utf-8")

    print(f"  баз: {len(base_lines)}  -> {bases_path.name} ({bases_path.stat().st_size/1024:.0f} кБ)")
    print(f"  модов: {len(mod_lines)} -> {mods_path.name} ({mods_path.stat().st_size/1024:.0f} кБ)")
    print(f"  тиров с весом: {tier_count} -> {weights_path.name} "
          f"({weights_path.stat().st_size/1024/1024:.1f} МБ)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
