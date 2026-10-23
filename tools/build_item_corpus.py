#!/usr/bin/env python3
"""Collect every item fixture the tests already use into one corpus file.

The language parity test used two hand-written items. Two items are enough to prove the mechanism works,
but not to prove the panel speaks one language on every CLASS of item: waystones, tablets, relics, jewels,
flasks, uniques and weapons each go through their own branches, and a branch nobody exercised is exactly
where a Russian-only string survives.

So the corpus is not written by hand: this tool pulls every `[[ ... ]]` block that looks like a copied item
out of src/Tests/*.lua - fixtures that real behaviour is already tested against - deduplicates them and
writes src/Tests/item_corpus.lua. Regenerate it after adding fixtures:

    python tools/build_item_corpus.py

Usage:
    python tools/build_item_corpus.py --list      # what would be collected, without writing
"""

from __future__ import annotations

import argparse
import glob
import io
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "src", "Tests", "item_corpus.lua")

BLOCK = re.compile(r"\[\[(.*?)\]\]", re.S)
# The same fixtures also appear as table.concat({ "...", "..." }, "\n"): one quoted line per row. Both
# shapes are collected, because the waystone, tablet and relic fixtures are written that way.
CONCAT = re.compile(r"table\.concat\(\s*\{(.*?)\}\s*,\s*[\"']\\n[\"']\s*\)", re.S)
QUOTED_LINE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$')
LOOKS_LIKE_ITEM = ("Item Class:", "Класс предмета:")


def unescape(line: str) -> str:
    return line.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def concat_items(text: str) -> list[str]:
    """Item texts written as table.concat({...}, "\\n")."""
    out: list[str] = []
    for match in CONCAT.finditer(text):
        lines: list[str] = []
        usable = True
        for row in match.group(1).splitlines():
            if not row.strip():
                continue
            quoted = QUOTED_LINE.match(row)
            if not quoted:
                # A row built from a variable or a loop: this block is not a plain fixture.
                usable = False
                break
            lines.append(unescape(quoted.group(1)))
        if usable and any(marker in line for line in lines for marker in LOOKS_LIKE_ITEM):
            out.append("\n".join(lines))
    return out


def collect() -> list[tuple[str, str]]:
    """(source file, item text) for every fixture that looks like a copied item."""
    seen: set[str] = set()
    out: list[tuple[str, str]] = []
    for path in sorted(glob.glob(os.path.join(ROOT, "src", "Tests", "*.lua"))):
        if os.path.basename(path) == "item_corpus.lua":
            continue
        with io.open(path, encoding="utf-8") as handle:
            text = handle.read()
        found = [match.group(1) for match in BLOCK.finditer(text)]
        found.extend(concat_items(text))
        for body in found:
            if not any(marker in body for marker in LOOKS_LIKE_ITEM):
                continue
            item = body.strip("\n")
            if item in seen:
                continue
            seen.add(item)
            out.append((os.path.basename(path), item))
    return out


def lua_long_string(text: str) -> str:
    """A long bracket that the text itself cannot close."""
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    fence = "[" + "=" * level + "["
    close = "]" + "=" * level + "]"
    return fence + "\n" + text + "\n" + close


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true", help="print what would be collected")
    parser.add_argument("--check", action="store_true",
                        help="exit non-zero when the generated corpus is out of date")
    args = parser.parse_args()

    items = collect()
    if args.list:
        for source, item in items:
            kind = next((line for line in item.splitlines() if line.startswith(("Item Class:", "Класс предмета:"))), "?")
            rarity = next((line for line in item.splitlines() if line.startswith(("Rarity:", "Редкость:"))), "?")
            print(f"{source:28s} {kind:28s} {rarity}")
        print("total:", len(items))
        return 0

    lines = [
        "-- PoE2 Craft Overlay : Tests/item_corpus.lua",
        "-- GENERATED FILE - do not edit by hand (tools/build_item_corpus.py).",
        "--",
        "-- Every item fixture the tests already use, deduplicated: the language parity test runs ALL of them",
        "-- through the engine in both languages, because each item class takes its own branch and a branch",
        "-- nobody exercises is where a Russian-only string survives.",
        "return {",
    ]
    for source, item in items:
        lines.append(f"\t-- from {source}")
        lines.append(f"\t{lua_long_string(item)},")
    lines.append("}")
    lines.append("")
    body = "\n".join(lines)
    if args.check:
        existing = ""
        if os.path.exists(OUT):
            with io.open(OUT, encoding="utf-8") as handle:
                existing = handle.read()
        if existing != body:
            print("OUT OF DATE:", os.path.relpath(OUT, ROOT), "- run tools/build_item_corpus.py")
            return 1
        print("up to date:", os.path.relpath(OUT, ROOT), len(items), "items")
        return 0
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    print("written:", os.path.relpath(OUT, ROOT), len(items), "items")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
