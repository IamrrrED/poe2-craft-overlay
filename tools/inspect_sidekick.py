#!/usr/bin/env python3
"""Look up how the Sidekick app styles its overlay panel.

Sidekick stores its settings in a SQLite database and ships its UI as web assets, so the
panel colours can be read from those files instead of guessed. Used while matching the
overlay's background to Sidekick's; kept because it documents where the values came from.

Usage: python tools/inspect_sidekick.py
"""

from __future__ import annotations

import json
import pathlib
import re
import sqlite3
import sys

APPDATA = pathlib.Path.home() / "AppData" / "Roaming" / "sidekick"
LOCALAPPDATA = pathlib.Path.home() / "AppData" / "Local" / "Sidekick" / "current"
INTERESTING = re.compile(r"(overlay|colou?r|opacity|theme|background|transparen|alpha|font)", re.I)


def dump_database() -> None:
    db_path = APPDATA / "sidekick.db"
    if not db_path.exists():
        print(f"no database: {db_path}")
        return
    print(f"database: {db_path} ({db_path.stat().st_size / 1024:.0f} kB)")
    connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    cursor = connection.cursor()
    tables = [row[0] for row in cursor.execute("select name from sqlite_master where type='table'")]
    print("tables:", ", ".join(tables))
    for table in tables:
        try:
            columns = [row[1] for row in cursor.execute(f"PRAGMA table_info({table})")]
            rows = cursor.execute(f"select * from {table} limit 500").fetchall()
        except sqlite3.Error:
            continue
        for row in rows:
            blob = " | ".join(str(value) for value in row if value is not None)
            if INTERESTING.search(blob):
                print(f"  [{table}] {blob[:500]}")
    connection.close()


def scan_assets() -> None:
    """Report colour literals and overlay CSS rules from the web assets."""
    roots = [LOCALAPPDATA / "wwwroot"]
    counters: dict[str, int] = { }
    overlay_rules: list[str] = []
    for root in roots:
        if not root.exists():
            print(f"missing directory: {root}")
            continue
        for path in list(root.rglob("*.css")) + list(root.rglob("*.razor.css")):
            text = path.read_text(encoding="utf-8", errors="replace")
            for match in re.finditer(r"#([0-9a-fA-F]{6})\b", text):
                key = "#" + match.group(1).lower()
                counters[key] = counters.get(key, 0) + 1
            for match in re.finditer(r"rgba?\([^)]{5,40}\)", text):
                value = match.group(0).replace(" ", "")
                counters[value] = counters.get(value, 0) + 1
            for line in text.splitlines():
                if "overlay" in line.lower() and ("background" in line.lower() or "color" in line.lower()):
                    overlay_rules.append(f"[{path.name}] {line.strip()[:160]}")

    print("--- most frequent colours in the CSS ---")
    for value, count in sorted(counters.items(), key=lambda item: -item[1])[:18]:
        print(f"  {value:<28} {count}")
    print("--- rules mentioning 'overlay' with a colour ---")
    for rule in overlay_rules[:12]:
        print("  " + rule)


def scan_backgrounds() -> None:
    """Hunt for the overlay panel's own background declaration.

    Sidekick's UI is compiled Avalonia XAML that uses Tailwind-style utility classes, so
    the panel background appears as something like `bg-[#101010]` or a `Background="#..."`.
    """
    for path in sorted(LOCALAPPDATA.glob("Sidekick*.dll")):
        utf16 = path.read_bytes().decode("utf-16-le", errors="ignore")
        hits: list[str] = []
        for pattern in (r"bg-\[#[0-9A-Fa-f]{3,8}\]", r"Background=\"#[0-9A-Fa-f]{6,8}\"",
                        r"#[0-9A-Fa-f]{8}\b", r"opacity-\[?[0-9.]+\]?"):
            for match in re.finditer(pattern, utf16):
                start = max(0, match.start() - 70)
                context = re.sub(r"\s+", " ", utf16[start:match.end() + 30].replace("\x00", " "))
                hits.append(f"   {match.group(0):<22} {context.strip()[-120:]}")
        if hits:
            print(f"--- {path.name} ---")
            for line in hits[:14]:
                print(line)


def scan_assemblies() -> None:
    """Find colour literals in Sidekick's assemblies and print their context.

    The overlay UI is an Avalonia app, so its colours live inside the compiled
    assemblies rather than in a stylesheet. Strings there are UTF-16, which is also how
    the resource/style names next to a colour can be read out.
    """
    if not LOCALAPPDATA.exists():
        print(f"missing directory: {LOCALAPPDATA}")
        return
    for path in sorted(LOCALAPPDATA.glob("Sidekick*.dll")):
        raw = path.read_bytes()
        utf16 = raw.decode("utf-16-le", errors="ignore")
        ascii_view = raw.decode("latin-1", errors="ignore")
        hexes: dict[str, int] = { }
        for match in re.finditer(r"#[0-9A-Fa-f]{6}\b", utf16 + ascii_view):
            value = match.group(0).lower()
            hexes[value] = hexes.get(value, 0) + 1
        if not hexes:
            continue
        print(f"--- {path.name} ---")
        for value, count in sorted(hexes.items(), key=lambda item: -item[1])[:10]:
            context = ""
            position = utf16.find(value)
            if position > 0:
                context = utf16[max(0, position - 90):position + 40].replace("\x00", " ")
                context = re.sub(r"\s+", " ", context).strip()
            print(f"   {value} x{count}   {context[-110:]}")


def scan_settings_files() -> None:
    for path in list(APPDATA.rglob("*.json"))[:40]:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if not INTERESTING.search(text[:4000]):
            continue
        print(f"--- {path.name} ---")
        for line in text.splitlines():
            if INTERESTING.search(line):
                print("  " + line.strip()[:160])


def main() -> int:
    dump_database()
    scan_settings_files()
    scan_assemblies()
    scan_assets()
    return 0


if __name__ == "__main__":
    sys.exit(main())
