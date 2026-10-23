#!/usr/bin/env python3
"""Build the reverse dictionary: English names and modifier texts -> Russian, for the panel.

The engine works in English on purpose (the Russian client's text is translated on the way in), so
showing it back to a Russian player needs the opposite direction. That direction is not written by
hand: the official pairs already exist in the other direction, in three files the parser itself uses:

    src/Item/Ru.lua              the fixed vocabulary (rarity words, item classes, labels)
    src/Data/ru_bases.lua        3128 base and currency names, from the localised trade site
    src/Data/ru_stats_*.lua      3084 modifier texts, from the localised trade site

Inverting them keeps both directions in step: a word added for parsing appears for display
automatically, and the two cannot drift apart. A collision (two Russian names for one English name,
which happens where the game prints an older spelling) keeps the first and is reported.

Writes src/Data/display_names_ru.lua.

Usage:
    python tools/build_display_names.py
    python tools/build_display_names.py --report
"""

from __future__ import annotations

import argparse
import glob
import io
import os
import re
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "src", "Data", "display_names_ru.lua")

# ["русский"] = "English",  - the shape of every pair in all three sources.
PAIR = re.compile(r'\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"')


def read(path: str) -> str:
    with io.open(path, encoding="utf-8") as handle:
        return handle.read()


def pairs_in(path: str) -> list[tuple[str, str]]:
    """(russian, english) pairs of one source file."""
    return PAIR.findall(read(path))


def lua_string(text: str) -> str:
    # Newlines are real in these data files: the trade site's stat text carries line breaks inside one
    # entry, and a raw one inside a quoted Lua literal is a syntax error - the whole part then fails to
    # load and every name in it silently disappears (which is exactly what happened once).
    return (
        '"'
        + text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
        + '"'
    )


def invert(pairs: list[tuple[str, str]], lower_english: bool = False) -> tuple[dict[str, str], int]:
    """english -> russian; the first russian spelling of a name wins, duplicates are counted."""
    out: dict[str, str] = {}
    clashes = 0
    for russian, english in pairs:
        key = english.lower() if lower_english else english
        if key in out:
            if out[key] != russian:
                clashes += 1
            continue
        out[key] = russian
    return out, clashes


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", action="store_true", help="print what would be written and stop")
    args = parser.parse_args()

    vocabulary = pairs_in(os.path.join(ROOT, "src", "Item", "Ru.lua"))
    bases = pairs_in(os.path.join(ROOT, "src", "Data", "ru_bases.lua"))
    stats: list[tuple[str, str]] = []
    stat_files = sorted(glob.glob(os.path.join(ROOT, "src", "Data", "ru_stats_*.lua")))
    for path in stat_files:
        stats.extend(pairs_in(path))

    names, name_clashes = invert(vocabulary + bases)
    # The only hand-written entries in the output: the overlay's OWN labels for price-snapshot lines.
    # They are not game object names, so no official pair exists for them (they are our invented rows
    # "Essence", "Perfect Essence", "Desecration Bone"), and a Russian panel should still not print them
    # in English. Everything else in this file is inverted data.
    #
    # The three units are the same idea: the engine composes a price sentence as "0.0318 chaos per
    # attempt", and the word after the number is a unit, not a name. The trade site names the currency
    # "Chaos Orb", so the lower-case unit has no official pair of its own - Russian players say "хаоса",
    # and the panel was printing "0.0318 chaos за попытку".
    ours = {
        "Essence": "Эссенция",
        "Perfect Essence": "Совершенная эссенция",
        "Desecration Bone": "Кость очернения",
        "Desecration": "Очернение",
        "Greater Essence": "Большая эссенция",
        "chaos": "хаоса",
        "exalted": "возвышения",
        "divine": "божественных",
    }
    for english, russian in ours.items():
        names.setdefault(english, russian)
    stat_map, stat_clashes = invert(stats, lower_english=True)

    print("vocabulary pairs:", len(vocabulary))
    print("base/currency pairs:", len(bases))
    print(f"modifier pairs: {len(stats)} from {len(stat_files)} files")
    print("names written:", len(names), "clashes:", name_clashes)
    print("modifier templates written:", len(stat_map), "clashes:", stat_clashes)
    if args.report:
        for english in ("Pariah Mask", "Helmets", "Magic", "Exalted Orb", "Orb of Augmentation"):
            print(f"  {english!r} -> {names.get(english)!r}")
        print("  '#% to Cold Resistance' ->", repr(stat_map.get("#% to cold resistance")))
        return 0

    lines = [
        "-- PoE2 Craft Overlay : Data/display_names_ru.lua",
        "-- GENERATED FILE - do not edit by hand (tools/build_display_names.py).",
        "--",
        "-- English name -> Russian name, and English modifier template -> Russian modifier template.",
        "-- Built by inverting the pairs the parser already uses (Item/Ru.lua, Data/ru_bases.lua,",
        "-- Data/ru_stats_*.lua), so the parsing direction and the display direction cannot drift apart.",
        "--",
        "-- The pairs live in parts (display_names_ru_1.lua ...) for the same measured reason the modifier",
        "-- dictionary does: the host reads a small data file reliably and a large one not at all.",
        "-- Modifier keys are lower-cased templates with the numbers blanked to '#', exactly the form",
        "-- Item/Ru.lua compares against; the numbers are put back by Ru.toRussian.",
        "return {",
        "\tsource = 'Item/Ru.lua + Data/ru_bases.lua + Data/ru_stats_*.lua (inverted)',",
        f'\tgeneratedAt = {lua_string(datetime.now().strftime("%Y-%m-%d %H:%M"))},',
        f"\tnameCount = {len(names)},",
        f"\tstatCount = {len(stat_map)},",
        "\tparts = {",
    ]

    # One part holds both sections, at most PART_SIZE pairs each: 400 pairs is about 90 kB, which is the
    # size the parser's own dictionaries were split to after the host failed on the combined file.
    PART_SIZE = 300
    names_sorted = sorted(names)
    stats_sorted = sorted(stat_map)
    part_count = max(
        (len(names_sorted) + PART_SIZE - 1) // PART_SIZE,
        (len(stats_sorted) + PART_SIZE - 1) // PART_SIZE,
        1,
    )
    stale = glob.glob(os.path.join(ROOT, "src", "Data", "display_names_ru_*.lua"))
    for path in stale:
        os.remove(path)
    for index in range(part_count):
        name_slice = names_sorted[index * PART_SIZE:(index + 1) * PART_SIZE]
        stat_slice = stats_sorted[index * PART_SIZE:(index + 1) * PART_SIZE]
        part = [
            "-- PoE2 Craft Overlay : Data/display_names_ru_%d.lua" % (index + 1),
            "-- GENERATED FILE - do not edit by hand (tools/build_display_names.py).",
            "-- Part %d of %d: English -> Russian names and modifier templates." % (index + 1, part_count),
            "return {",
            f"\tnames = {len(name_slice)},",
            "\tmap = {",
        ]
        for english in name_slice:
            part.append(f"\t\t[{lua_string(english)}] = {lua_string(names[english])},")
        part.append("\t},")
        part.append(f"\tstatCount = {len(stat_slice)},")
        part.append("\tstats = {")
        for english in stat_slice:
            part.append(f"\t\t[{lua_string(english)}] = {lua_string(stat_map[english])},")
        part.append("\t},")
        part.append("}")
        part.append("")
        part_path = os.path.join(ROOT, "src", "Data", f"display_names_ru_{index + 1}.lua")
        with io.open(part_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write("\n".join(part))
        lines.append(f'\t\t"display_names_ru_{index + 1}",')
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    with io.open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    print("written:", os.path.relpath(OUT, ROOT), "and", part_count, "parts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
