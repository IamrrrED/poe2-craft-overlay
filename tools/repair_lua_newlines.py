#!/usr/bin/env python3
"""Escape raw newlines and tabs inside Lua string literals, in the generated data files.

Why this exists. The localised trade data puts a real line break inside some modifier texts, and the
extractor wrote those breaks straight into the Lua literal:

    ["#% chance to gain onslaught ... when you kill an
     enemy affected by abyssal wasting"] = "..."

Lua stops reading the literal at that newline: the whole file is a syntax error, `require` fails, and
because every reader uses pcall() the failure is silent - the modifier dictionary simply came up short
(3 of 10 parts loaded, 806 of 3084 entries) and every Russian item quietly fell back to "unrecognised".
A card full of half-translated modifiers was the visible end of it.

The repair walks each file character by character, tracking whether it is inside a quoted literal (with
backslash escapes) and turning a raw newline into \\n, a raw tab into \\t and dropping the \\r of CRLF.
Nothing else is touched, so the files stay generated data.

Usage:
    python tools/repair_lua_newlines.py --check        # only report what would change
    python tools/repair_lua_newlines.py                # repair every src/Data/*.lua
    python tools/repair_lua_newlines.py src/Data/mod.lua
"""

from __future__ import annotations

import argparse
import glob
import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def repair(text: str) -> tuple[str, int]:
    """Escaped text, and how many characters were escaped."""
    out: list[str] = []
    inside = False
    escaped = False
    fixed = 0
    index = 0
    length = len(text)
    while index < length:
        character = text[index]
        if not inside:
            # A comment is not Lua data: copy it verbatim to the end of its line, so a quote or a
            # newline inside a comment can neither flip the string state nor be "repaired".
            if character == "-" and text.startswith("--", index):
                end = text.find("\n", index)
                end = length if end < 0 else end
                out.append(text[index:end])
                index = end
                continue
            out.append(character)
            if character == '"':
                inside = True
            index += 1
            continue
        if escaped:
            # The backslash already started an escape sequence; keep it and the character after it.
            out.append(character)
            escaped = False
            index += 1
            continue
        if character == "\\":
            out.append(character)
            escaped = True
            index += 1
            continue
        if character == '"':
            out.append(character)
            inside = False
            index += 1
            continue
        if character == "\n":
            out.append("\\n")
            fixed += 1
            index += 1
            continue
        if character == "\r":
            # The \n that follows becomes the escape; the \r itself is dropped.
            index += 1
            continue
        if character == "\t":
            out.append("\\t")
            fixed += 1
            index += 1
            continue
        out.append(character)
        index += 1
    return "".join(out), fixed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="report without writing")
    parser.add_argument("files", nargs="*", help="files to repair (default: src/Data/*.lua)")
    args = parser.parse_args()

    files = args.files or sorted(glob.glob(os.path.join(ROOT, "src", "Data", "*.lua")))
    changed = 0
    for path in files:
        with io.open(path, encoding="utf-8", newline="") as handle:
            text = handle.read()
        repaired, fixed = repair(text)
        name = os.path.relpath(path, ROOT)
        if fixed == 0:
            print(f"clean   {name}")
            continue
        changed += 1
        print(f"repair  {name}: {fixed} characters escaped")
        if not args.check:
            with io.open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(repaired)
    print("files changed:", changed, "(dry run)" if args.check else "")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
