#!/usr/bin/env python3
"""Build the Russian -> English modifier map from the official trade site.

The trick is that the trade site has localised hosts, and the data endpoints behind them
share their ids:

    https://www.pathofexile.com/api/trade2/data/stats   -> "#% to Fire Resistance"
    https://ru.pathofexile.com/api/trade2/data/stats    -> "+#% к сопротивлению огню"

Both list 8221 stats with identical ids, so pairing them by id gives an official Russian
vocabulary - no guessing, no third-party translation. The parameter `?language=ru` on the
main host is ignored (checked), which is why the localised host is used instead.

Only `explicit` and `implicit` stats are kept: the `pseudo` group describes trade filters
("total to Cold Resistance") and never appears in an item tooltip.

Everything is stored with numbers replaced by `#`, so a line copied from the game matches
its template regardless of the rolls.

Usage:
    python tools/fetch_ru_map.py
    python tools/fetch_ru_map.py --check
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import urllib.request

STATS_PATH = "/api/trade2/data/stats"
USER_AGENT = "PoE2CraftOverlay/1.0 (local crafting helper)"

# Groups that can appear in a copied item.
KEPT_TYPES = {"explicit", "implicit", "crafted", "fractured", "enchant", "scourge",
              "cruel", "veiled", "desecrated", "rune"}

NUMBER = re.compile(r"[-+]?\d+(?:\.\d+)?")
RANGE = re.compile(r"\(\s*[-+]?\d+(?:\.\d+)?\s*-\s*[-+]?\d+(?:\.\d+)?\s*\)")


def normalise(text: str) -> str:
    """Reduce a modifier line to a comparable template: numbers become '#'."""
    value = RANGE.sub("#", text)          # "(2-4)" first, it contains digits too
    value = NUMBER.sub("#", value)
    value = value.replace("+", "").replace("%#", "%#")
    value = re.sub(r"#(\s*)#", "#", value)  # "# #" -> "#"
    value = re.sub(r"\s+", " ", value).strip().lower()
    return value


def fetch(host: str) -> dict[str, dict]:
    url = f"https://{host}{STATS_PATH}"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                                   "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = json.loads(response.read().decode("utf-8-sig"))
    out: dict[str, dict] = { }
    for group in data.get("result") or []:
        for entry in group.get("entries") or []:
            if not isinstance(entry, dict) or not entry.get("id"):
                continue
            out[str(entry["id"])] = {
                "text": entry.get("text") or "",
                "type": entry.get("type") or "",
            }
    return out


def lua_quote(value: str) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def fetch_items(host: str) -> list[dict]:
    """Item entries, group by group: they carry only a base-type name, no id."""
    url = f"https://{host}/api/trade2/data/items"
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                                   "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = json.loads(response.read().decode("utf-8-sig"))
    groups = []
    for group in data.get("result") or []:
        entries = [entry.get("type") or "" for entry in (group.get("entries") or [])
                   if isinstance(entry, dict)]
        groups.append({"id": group.get("id") or "", "entries": entries})
    return groups


def score_offset(english: list[str], russian: list[str], offset: int) -> float:
    """How well does `english[i]` line up with `russian[i + offset]`?

    Base names are built from the same parts in both languages ("Рунномастерская тиара
    волшебника" / "Runemastered Magus Tiara"), so under the right offset the parts pair up
    consistently: "тиара" always with "Tiara", "волшебника" always with "Magus". A wrong
    offset pairs unrelated words, and no such consistency appears. Only pairs with the same
    number of words are judged, and the score is the share of pairs that agree with the
    majority mapping of every part.
    """
    maps: dict[str, dict[str, int]] = { }
    samples = []
    for index, english_name in enumerate(english):
        other = index + offset
        if other < 0 or other >= len(russian):
            continue
        left = english_name.lower().replace("-", " ").split()
        right = russian[other].lower().replace("-", " ").split()
        if len(left) != len(right) or not left:
            continue
        samples.append((left, right))
        for one, two in zip(left, right):
            maps.setdefault(two, { })[one] = maps.setdefault(two, { }).get(one, 0) + 1

    if not samples:
        return 0.0
    majority = { word: max(counts, key=counts.get) for word, counts in maps.items() }
    agreed = 0
    for left, right in samples:
        if all(majority.get(two) == one for one, two in zip(left, right)):
            agreed += 1
    return agreed / len(samples)


def align_group(english: list[str], russian: list[str]) -> list[str] | None:
    """Line a category up, allowing for the extra Russian entry the game repeats.

    Returns the Russian list re-indexed to match the English one, or None when no offset is
    convincing. The score has to be good in absolute terms and better than the alternatives,
    because a wrong base name is worse than an untranslated one.
    """
    if len(russian) == len(english):
        return russian
    best, best_score, runner_up = None, 0.0, 0.0
    for offset in range(-3, 4):
        score = score_offset(english, russian, offset)
        if score > best_score:
            best, best_score, runner_up = offset, score, best_score
        elif score > runner_up:
            runner_up = score
    if best is None or best_score < 0.6 or best_score - runner_up < 0.1:
        return None
    # Trim or pad so that english[i] matches russian[i] afterwards.
    if best >= 0:
        return russian[best:]
    return [None] * (-best) + russian


def pair_bases(root: pathlib.Path) -> dict[str, str]:
    """Pair base type names by position, but only inside a group and only when the group has
    the same number of entries in both languages - a mismatch means the lists cannot be
    trusted for that group, and a wrong base name is worse than an untranslated one."""
    cache = root / "tools/cache/ru_items.json"
    cache.parent.mkdir(parents=True, exist_ok=True)
    if cache.exists():
        stored = json.loads(cache.read_text(encoding="utf-8-sig"))
        english_groups, russian_groups = stored["en"], stored["ru"]
        print(f"using cached item data: {len(english_groups)} groups")
    else:
        english_groups = fetch_items("www.pathofexile.com")
        russian_groups = fetch_items("ru.pathofexile.com")
        cache.write_text(json.dumps({"en": english_groups, "ru": russian_groups}), encoding="utf-8")
        print(f"fetched items: {len(english_groups)} english groups, "
              f"{len(russian_groups)} russian groups")

    russian_by_id = { group["id"]: group for group in russian_groups }
    pairs: dict[str, str] = { }
    skipped = 0
    for group in english_groups:
        other = russian_by_id.get(group["id"])
        if not other:
            skipped += 1
            continue
        english = group["entries"]
        russian = other["entries"]

        if len(russian) != len(english):
            # One category (armour) has an extra Russian entry: the game repeats a base name
            # where English distinguishes the variants, which shifts everything after it.
            aligned = align_group(english, russian)
            if aligned is None:
                skipped += 1
                print(f"    {group['id']}: en={len(english)} ru={len(russian)} - no convincing alignment")
                continue
            print(f"    {group['id']}: en={len(english)} ru={len(russian)} - aligned")
            russian = aligned

        for english_name, russian_name in zip(english, russian):
            if not english_name or not russian_name or russian_name == english_name:
                continue
            # Note: a word-count check was tried here to catch a drifted pair, but common base
            # names differ in word count between the languages ("Тиара волшебника" / "Magus
            # Tiara" is two and two, yet many others are not), and it threw away a third of the
            # names. Only the alignment above decides whether a category can be trusted.
            pairs[russian_name] = english_name
    print(f"paired base types: {len(pairs)} (groups skipped: {skipped})")
    return pairs


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="src/Data/ru_stats.lua")
    parser.add_argument("--out-bases", default="src/Data/ru_bases.lua")
    parser.add_argument("--cache", default="tools/cache/ru_stats.json")
    parser.add_argument("--check", action="store_true", help="only report what would change")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    cache = root / args.cache
    cache.parent.mkdir(parents=True, exist_ok=True)

    if cache.exists():
        stored = json.loads(cache.read_text(encoding="utf-8-sig"))
        english, russian = stored["en"], stored["ru"]
        print(f"using cached data: {len(english)} english, {len(russian)} russian stats")
    else:
        english = fetch("www.pathofexile.com")
        russian = fetch("ru.pathofexile.com")
        cache.write_text(json.dumps({"en": english, "ru": russian}), encoding="utf-8")
        print(f"fetched: {len(english)} english, {len(russian)} russian stats")

    pairs: dict[str, str] = { }
    kinds: dict[str, dict[str, str]] = { }
    for stat_id, entry in english.items():
        if entry["type"] not in KEPT_TYPES:
            continue
        other = russian.get(stat_id)
        if not other or not other["text"]:
            continue
        template = normalise(other["text"])
        if not template or template in pairs:
            continue
        pairs[template] = entry["text"]
        kinds.setdefault(entry["type"], { })[template] = entry["text"]
    print(f"paired modifiers: {len(pairs)}")
    for kind in sorted(kinds):
        print(f"    {kind}: {len(kinds[kind])}")

    bases = pair_bases(root)

    # One file per chunk of entries. Splitting by stat group was not enough - the explicit
    # group alone is 436 kB - and the host reads a small data file reliably while a large one
    # comes back empty, so the dictionaries are cut into pieces of a few dozen kilobytes.
    CHUNK = 400
    part_names: list[str] = []
    for kind in sorted(kinds):
        entries = kinds[kind]
        ordered = sorted(entries)
        for start in range(0, len(ordered), CHUNK):
            piece = ordered[start:start + CHUNK]
            index = start // CHUNK + 1
            name = f"ru_stats_{kind}_{index}"
            part_names.append(name)
            part_lines = [
                f"-- PoE2 Craft Overlay : Data/{name}.lua",
                "-- GENERATED FILE - do not edit by hand (tools/fetch_ru_map.py).",
                f"-- Russian -> English {kind} modifiers, part {index} (official trade site data).",
                "return {",
                f"\tkind = {lua_quote(kind)},",
                f"\tcount = {len(piece)},",
                "\tstats = {",
            ]
            for template in piece:
                part_lines.append(f"\t\t[{lua_quote(template)}] = {lua_quote(entries[template])},")
            part_lines.append("\t},")
            part_lines.append("}")
            part_lines.append("")
            part_path = root / "src/Data" / f"{name}.lua"
            part_path.write_text("\n".join(part_lines), encoding="utf-8")
        print(f"  {kind}: {len(ordered)} entries in {(len(ordered) + CHUNK - 1) // CHUNK} file(s)")

    lines = [
        "-- PoE2 Craft Overlay : Data/ru_stats.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_ru_map.py).",
        "--",
        "-- Index of the Russian modifier dictionaries. Each group lives in its own file",
        "-- (ru_stats_<kind>.lua) because the host reads a small data file reliably and a large",
        "-- one not at all; the engine loads them on first use and merges them.",
        "return {",
        "\tsource = 'pathofexile.com/api/trade2/data/stats (en + ru, paired by id)',",
        f"\tcount = {len(pairs)},",
        "\tparts = {",
    ]
    for name in part_names:
        lines.append(f"\t\t{ lua_quote(name) },")
    lines.append("\t},")
    lines.append("\tcounts = {")
    for kind in sorted(kinds):
        lines.append(f"\t\t[{lua_quote(kind)}] = {len(kinds[kind])},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")

    out_path = root / args.out
    if args.check:
        print(f"would write {len(pairs)} entries to {out_path}")
        return 0
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"written: {out_path} ({out_path.stat().st_size / 1024:.0f} kB)")

    # Base type names go into their own file. A single 575 kB data file was not read reliably
    # by the overlay's host (the dictionary came back empty), and the two lookups are
    # independent anyway: modifiers by template, base types by name.
    base_lines = [
        "-- PoE2 Craft Overlay : Data/ru_bases.lua",
        "-- GENERATED FILE - do not edit by hand (tools/fetch_ru_map.py).",
        "--",
        "-- Russian base type names -> English, paired from the official localised trade site",
        "-- (ru.pathofexile.com and www.pathofexile.com list the same categories in the same",
        "-- order; a category whose counts differ is skipped rather than guessed).",
        "return {",
        "\tsource = 'pathofexile.com/api/trade2/data/items (en + ru)',",
        f"\tcount = {len(bases)},",
        "\tbases = {",
    ]
    for russian_name in sorted(bases):
        base_lines.append(f"\t\t[{lua_quote(russian_name)}] = {lua_quote(bases[russian_name])},")
    base_lines.append("\t},")
    base_lines.append("}")
    base_lines.append("")
    base_path = root / args.out_bases
    base_path.write_text("\n".join(base_lines), encoding="utf-8")
    print(f"written: {base_path} ({base_path.stat().st_size / 1024:.0f} kB)")

    for probe in ("к сопротивлению огню", "к максимальному здоровью", "к ловкости"):
        for template, target in pairs.items():
            if probe in template:
                print(f"    {template[:44]!r} -> {target[:44]!r}")
                break
    for probe in ("Алый амулет", "Кожаный нагрудник"):
        if probe in bases:
            print(f"    {probe!r} -> {bases[probe]!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
