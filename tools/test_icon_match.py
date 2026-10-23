#!/usr/bin/env python3
"""Acceptance test for icon recognition, built from labelled cells of a real stash tab.

Every sample here is a crop of one cell from a live PoE2 session, labelled by the player from the
in-game tooltip. That makes it a test with a known right answer, which is the only reason the
matching pipeline could be tuned at all: each change is judged by whether the scorecard improves.

The samples also carry the cases that used to break the matcher - a cell whose stack count covers
part of the artwork, a featureless dark item that matches everything, a 2x2 item, and an empty
cell that must not match anything.

Usage:
    python tools/test_icon_match.py
    python tools/test_icon_match.py --verbose
"""

from __future__ import annotations

import argparse
import pathlib
import sys

# The matcher lives beside this script; make that explicit so both the interpreter and the type
# checker resolve it the same way.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import icon_match  # pyright: ignore  # sibling script, resolved from this directory at runtime

SAMPLES = [
    ("12_gambling.png", "omen-of-gambling", "стек 12: монеты в ветках"),
    ("13_bartering.png", "omen-of-bartering", "стек 13: золотой паук"),
    ("01_dextral_crystallisation.png", "omen-of-dextral-crystallisation", "стек 1: бледная кость"),
    ("04_orb_of_annulment.png", "orb-of-annulment", "стек 4: мраморная голова"),
    ("01_origin_cradle.png", "origin-cradle", "крупный предмет 2x2"),
    ("59_simulacrum_splinter.png", "simulacrum-splinter", "стек 59: осколок симулякра"),
    ("00_empty.png", None, "пустая ячейка — совпадений быть не должно"),
]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", default="tests/samples")
    parser.add_argument("--icons", default="tools/cache/icons")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    samples_dir = root / args.samples
    icons_dir = root / args.icons
    if not icons_dir.exists():
        print(f"нет справочника иконок: {icons_dir}")
        return 2

    index = icon_match.Index(icons_dir)
    print(f"  справочник: {len(index)} иконок, порог приёмки {icon_match.ACCEPT}, "
          f"порог пустоты по энергии {icon_match.ENERGY_FLOOR}")

    passed = 0
    failed: list[str] = []
    for file_name, expected, description in SAMPLES:
        path = samples_dir / file_name
        if not path.exists():
            print(f"  ? {description:<42} нет файла {file_name}")
            failed.append(description)
            continue
        cell = icon_match.prepare(path, from_screenshot=True)
        got_score, got_name, margin, note = index.match(cell)
        ok = got_name == expected
        passed += 1 if ok else 0
        mark = "✓" if ok else "✗"
        shown = got_name or note or "нет совпадения"
        print(f"  {mark} {description:<42} -> {shown:<40} "
              f"{got_score or 0.0:0.3f} (запас {margin:+0.3f})")
        if not ok:
            failed.append(f"{description}: ожидалось {expected}, получено {got_name}")
            if args.verbose:
                for score, name in index.score(cell)[:5]:
                    print(f"        {score:0.3f}  {name}")

    total = len(SAMPLES)
    print(f"  итог: {passed} из {total}")
    for line in failed:
        print(f"  не прошло: {line}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
