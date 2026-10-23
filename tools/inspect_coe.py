#!/usr/bin/env python3
"""Summarise Craft of Exile's public data files.

The site has no REST API with keys: it publishes its datasets as static JSON under
https://www.craftofexile.com/json/data/... and the page loads them directly. This tool
prints what is inside them (structure and sizes) without dumping the whole payload, so
the data can be judged before it is used.

Usage:
    python tools/inspect_coe.py [--dir tools/cache/coe]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys


def describe(value, depth: int = 0, max_items: int = 3) -> str:
    if isinstance(value, dict):
        keys = list(value.keys())
        preview = ", ".join(keys[:8])
        return f"dict({len(keys)}): {preview}{' ...' if len(keys) > 8 else ''}"
    if isinstance(value, list):
        head = value[:max_items]
        shown = ", ".join(describe(item, depth + 1) for item in head)
        return f"list({len(value)}): [{shown}{' ...' if len(value) > max_items else ''}]"
    text = repr(value)
    return text if len(text) <= 60 else text[:57] + "..."


def load_jsonp(path: pathlib.Path):
    """Load a Craft of Exile data file.

    The files are JSONP: they start with a variable assignment (`poecd={...}`,
    `poecl={...}`) because the site loads them as scripts, not through fetch. Stripping
    that prefix yields plain JSON.
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise ValueError("no JSON object found")
    prefix = text[:start].strip()
    data = json.loads(text[start:])
    return data, prefix


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", default="tools/cache/coe")
    args = parser.parse_args(argv)

    root = pathlib.Path(args.dir)
    files = sorted(root.glob("*.json"))
    if not files:
        print(f"no JSON in {root}")
        return 1

    for path in files:
        size_kb = path.stat().st_size / 1024
        try:
            data, prefix = load_jsonp(path)
        except (ValueError, json.JSONDecodeError) as error:
            print(f"--- {path.name} ({size_kb:.0f} kB): NOT PARSEABLE: {error}")
            continue
        print(f"--- {path.name} ({size_kb:.0f} kB) prefix={prefix!r}")
        if isinstance(data, dict):
            for key, value in list(data.items())[:14]:
                print(f"    {key:<28} {describe(value)}")
            if len(data) > 14:
                print(f"    ... {len(data) - 14} more keys")
        else:
            print(f"    {describe(data)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
