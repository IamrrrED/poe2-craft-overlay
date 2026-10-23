#!/usr/bin/env python3
"""Build a display dictionary (English -> Russian) by inverting the parser's translation pairs.

The engine works in English on purpose: the game text is translated Russian -> English on the way
in (src/Item/Ru.lua), because the modifier data, the trade site and every calculation are English.
Show that text back to a Russian player unchanged and the panel turns into a mixture of languages.

So the display direction needs its own dictionary, and it does not have to be written by hand: the
pairs already exist, in the opposite direction, inside Ru.lua. Inverting them keeps both directions
in step - a word added for parsing shows up for display automatically, and the two can never drift.

Writes src/Data/display_ru.lua: English label -> Russian label.

Usage:
    python tools/build_display_ru.py
    python tools/build_display_ru.py --report
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from datetime import datetime


def lua_quote(value: str) -> str:
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


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="src/Item/Ru.lua")
    parser.add_argument("--out", default="src/Data/display_ru.lua")
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    source = root / args.source
    if not source.exists():
        print(f"нет файла пар: {source}")
        return 1

    text = source.read_text(encoding="utf-8")
    pairs = re.findall(r'\{\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\}', text)
    if not pairs:
        print("в источнике не найдено ни одной пары")
        return 1

    display: dict[str, str] = {}
    conflicts: list[str] = []
    for russian, english in pairs:
        # Several Russian words can map to one English label ("броня" and "брони"); for display the
        # first wins and the rest are reported, so the choice is visible rather than silent.
        if english in display and display[english] != russian:
            conflicts.append(f"{english}: {display[english]} / {russian}")
            continue
        display[english] = russian

    # Display forms the inversion cannot produce correctly. The parser's pairs carry the Russian
    # wording in the case the game text uses ("брони"), while a panel label needs the nominative
    # ("Броня"); and a few labels the parser recognises are not in the pairs at all ("Quality").
    # Kept here, next to the inversion, so the reason for each override is visible.
    display.update({
        "Quality": "Качество",
        "Armour": "Броня",
        "Evasion Rating": "Уклонение",
        "Energy Shield": "Энергетический щит",
        "Requirements": "Требуется",
        "Level": "Уровень",
        "Str": "Сила",
        "Dex": "Ловкость",
        "Int": "Интеллект",
        # Plan headings, as Advisor.lua words them. The Russian panel already used these two
        # phrases, so the wording matches what the overlay showed before.
        "MIN - lowest budget": "МИН — минимальный бюджет",
        "MAX - best result": "МАКС — максимальное качество",
    })

    share = len(display)
    print(f"  пар в источнике: {len(pairs)}")
    print(f"  уникальных английских подписей: {share}")
    print(f"  расхождений (несколько русских на одну английскую): {len(conflicts)}")
    if args.report:
        for key in ("Quality", "Armour", "Requirements", "Level", "Str", "Dex", "Int"):
            print(f"    {key:<14} -> {display.get(key, '(нет)')}")
        if conflicts:
            print("  примеры расхождений: " + "; ".join(conflicts[:4]))

    lines = [
        "-- PoE2 Craft Overlay : Data/display_ru.lua",
        "-- GENERATED FILE - do not edit by hand (tools/build_display_ru.py).",
        "--",
        "-- English label -> Russian label, for showing the panel to a Russian player. Built by",
        "-- inverting the parser's Russian -> English pairs, so the two directions stay in step.",
        "return {",
        "\tsource = 'Item/Ru.lua (inverted)',",
        f"\tgeneratedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        f"\tcount = {share},",
        "\tlabels = {",
    ]
    for english in sorted(display):
        lines.append(f"\t\t[{lua_quote(english)}] = {lua_quote(display[english])},")
    lines += ["\t},", "}", ""]

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"  записано: {out_path} ({out_path.stat().st_size / 1024:.0f} кБ)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
