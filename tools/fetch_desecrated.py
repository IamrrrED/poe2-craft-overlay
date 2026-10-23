#!/usr/bin/env python3
"""The official desecration modifier vocabulary, in both languages.

The Well of Souls offers modifiers that the game counts as desecrated. The trade site
publishes exactly that set - stat type `desecrated` - on its public data endpoint:

    https://www.pathofexile.com/api/trade2/data/stats   -> runes...  desecrated type
    https://ru.pathofexile.com/api/trade2/data/stats    -> the same ids, Russian text

Both hosts share the stat ids, so pairing them by id gives an official vocabulary without
guessing. This is the set our local Path of Building table lacked: it only carried 36
breach-themed mods, while the game's pool is seven hundred and fifty five entries wide.

The result is written as src/Data/desecrated.lua: id, English template and Russian template,
plus a lookup by template so an item copied in either language can be matched.

Usage:
    python tools/fetch_desecrated.py
    python tools/fetch_desecrated.py --list        # counts and a few samples
    python tools/fetch_desecrated.py --has "к максимуму здоровья"
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.request
from datetime import datetime

PATH = "/api/trade2/data/stats"
HOSTS = {"en": "www.pathofexile.com", "ru": "ru.pathofexile.com"}
USER_AGENT = "PoE2CraftOverlay/1.0 (local crafting helper)"
RANGE = re.compile(r"\(\s*[-+]?\d+(?:\.\d+)?\s*-\s*[-+]?\d+(?:\.\d+)?\s*\)")
NUMBER = re.compile(r"[-+]?\d+(?:\.\d+)?")


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


def template(text: str) -> str:
    """Numbers become '#', so any roll matches its template."""
    value = RANGE.sub("#", text)
    value = NUMBER.sub("#", value)
    value = value.replace("+", "")
    value = re.sub(r"#(\s*)#", "#", value)
    # Lower case: the overlay compares templates case-insensitively, and a capitalised key
    # here silently matched nothing (the desecration pool came back empty).
    return re.sub(r"\s+", " ", value).strip().lower()


def fetch(host: str) -> dict[str, dict]:
    request = urllib.request.Request(f"https://{host}{PATH}",
                                     headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = json.loads(response.read().decode("utf-8-sig"))
    out: dict[str, dict] = { }
    for group in data.get("result") or []:
        for entry in group.get("entries") or []:
            if isinstance(entry, dict) and entry.get("type") == STAT_TYPE and entry.get("id"):
                out[str(entry["id"])] = {"text": entry.get("text") or ""}
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="src/Data/desecrated.lua")
    parser.add_argument("--cache", default="tools/cache/desecrated.json")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--type", default="desecrated",
                        help="stat type: desecrated (Well of Souls) or augment (alloys)")
    parser.add_argument("--has", default=None, help="check whether a Russian phrase is covered")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    cache = root / args.cache
    cache.parent.mkdir(parents=True, exist_ok=True)
    # Which stat type this run collects: the Well of Souls (desecrated) or the alloys
    # (augment). The rest of the pipeline - pairing the two languages by id and writing the
    # Lua file - is identical, so one tool serves both.
    global STAT_TYPE
    STAT_TYPE = args.type

    if cache.exists():
        stored = json.loads(cache.read_text(encoding="utf-8-sig"))
        english, russian = stored["en"], stored["ru"]
        print(f"using cached data: {len(english)} english, {len(russian)} russian")
    else:
        english = fetch(HOSTS["en"])
        russian = fetch(HOSTS["ru"])
        cache.write_text(json.dumps({"en": english, "ru": russian}), encoding="utf-8")
        print(f"fetched: {len(english)} english, {len(russian)} russian desecrated stats")

    pairs = []
    by_template: dict[str, str] = { }
    by_template_en: dict[str, str] = { }
    for stat_id, entry in sorted(english.items()):
        other = russian.get(stat_id) or { }
        pairs.append((stat_id, entry["text"], other.get("text") or ""))
        if other.get("text"):
            by_template[template(other["text"])] = entry["text"]
        if entry["text"]:
            by_template_en[template(entry["text"])] = entry["text"]

    if args.list:
        print(f"  desecrated stats: {len(pairs)}, templates in Russian: {len(by_template)}")
        for stat_id, en, ru in pairs[:10]:
            print(f"    {stat_id:<32} {en[:40]:<42} {ru[:34]}")
        return 0

    if args.has:
        needle = template(args.has)
        found = by_template.get(needle)
        print(f"  '{args.has}' -> {found if found else 'NOT FOUND'}")
        near = [key for key in by_template if needle.split()[0] in key][:5] if not found else []
        for key in near:
            print(f"    похожее: {key!r} -> {by_template[key]!r}")
        return 0 if found else 2

    lines = [
        "-- PoE2 Craft Overlay : Data/desecrated.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_desecrated.py).",
        "--",
        "-- The official desecration vocabulary: every stat the trade site marks as",
        "-- type 'desecrated', in English and Russian, paired by the same stat id.",
        "return {",
        f"\tsource = 'pathofexile.com/api/trade2/data/stats (type={args.type}, en+ru)',",
        f"\tfetchedAt = {lua_quote(datetime.now().strftime('%Y-%m-%d %H:%M'))},",
        f"\tcount = {len(pairs)},",
        "\tstats = {",
    ]
    for stat_id, en, ru in pairs:
        lines.append(f"\t\t[{lua_quote(stat_id)}] = {{ en = {lua_quote(en)}, ru = {lua_quote(ru)} }},")
    lines.append("\t},")
    lines.append(f"\ttemplateCount = {len(by_template)},")
    lines.append(f"\ttemplateCountEn = {len(by_template_en)},")
    lines.append("\tbyTemplateEn = {")
    for key in sorted(by_template_en):
        lines.append(f"\t\t[{lua_quote(key)}] = {lua_quote(by_template_en[key])},")
    lines.append("\t},")
    lines.append("\tbyTemplate = {")
    for key in sorted(by_template):
        lines.append(f"\t\t[{lua_quote(key)}] = {lua_quote(by_template[key])},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"written: {out_path} ({out_path.stat().st_size / 1024:.0f} kB), "
          f"{len(pairs)} stats, {len(by_template)} russian templates")
    for probe in ("к максимуму здоровья", "к максимуму маны", "повышение редкости найденных предметов"):
        found = by_template.get(template(probe))
        print(f"    {probe!r} -> {found!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
