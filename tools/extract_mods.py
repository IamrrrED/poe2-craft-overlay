#!/usr/bin/env python3
"""Extract Path of Exile 2 item modifier data from the Path of Building checkout.

The overlay needs three things the clipboard text does not carry: whether a modifier
is a prefix or a suffix, which tier it is, and the item level it starts appearing at.
PoB's generated data files have exactly that, so this build-time tool converts them
into one compact Lua table that the overlay loads at startup.

Usage (from the poe2craft directory):
    python tools/extract_mods.py
    python tools/extract_mods.py --source ../vendor/PathOfBuilding-PoE2/src/Data \
                                --out src/Data/mods.lua

Output schema (src/Data/mods.lua):
    groups["<group>|<type>"] = { type = "Prefix", tiers = { {lvl, tier, affix, text}, ... } }
    index["<normalized text>"] = { "<group>|<type>", ... }

Tier convention: within a group, the tier with the highest level requirement is T1
(Path of Exile numbering: T1 is the best roll). Tiers are sorted by level ascending.

The text normalization implemented here MUST stay in sync with Mods.normalize() in
src/Item/Mods.lua - the two are cross-checked by a test.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path

# Data files that describe modifiers which can appear on items.
# Deliberately excluded: ModItemExclusive.lua and the unique/exclusive tables - those
# entries carry no `type` field and an empty `affix`, i.e. they are not prefix/suffix
# modifiers and can never be rolled onto a rare by crafting currency.
DEFAULT_FILES = [
    "ModItem.lua",
    "ModItemExclusive.lua",
    "ModJewel.lua",
    "ModFlask.lua",
    "ModCharm.lua",
    "ModRunes.lua",
    "ModVeil.lua",
    "ModCorrupted.lua",
    # Desecration (Abyss / Genesis Tree) pools live in the veiled table: their spawn
    # weights use the "breach_desecration" tag, which is what makes desecration odds
    # computable from the same weight data as everything else.
    "ModVeiled.lua",
]

ENTRY_RE = re.compile(
    r'^\s*\["(?P<key>[^"]+)"\]\s*=\s*\{\s*'
    r'type\s*=\s*"(?P<type>Prefix|Suffix)"\s*,\s*'
    r'affix\s*=\s*"(?P<affix>(?:[^"\\]|\\.)*)"\s*,\s*'
    r'(?P<text>"(?:[^"\\]|\\.)*")'
    r'(?P<rest>.*)$'
)

# ModItemExclusive.lua holds the implicit modifiers, and they are written WITHOUT a `type` field:
#   ["AmuletImplicitPrefixSuffixAllowed1"] = { affix = "", "+1 Prefix Modifier allowed",
#   "-1 Suffix Modifier allowed", statOrder = { 18, 19 }, level = 1, group = "PrefixSuffixAllowed", ... }
# The parser above only accepted lines carrying `type = "Prefix"|"Suffix"`, so every implicit modifier in
# that file was dropped - and dropped silently, because the per-line skip counter only counted lines that
# had both `type` and `affix`. Amulet and ring implicits are exactly what changes how many prefix and
# suffix slots an item has ("+1 Prefix Modifier allowed", "-2 Suffix Modifiers allowed"), so the overlay
# was reporting the wrong number of free slots for those items. They are read here as type "Implicit".
IMPLICIT_ENTRY_RE = re.compile(
    r'^\s*\["(?P<key>[^"]+)"\]\s*=\s*\{\s*'
    r'affix\s*=\s*"(?P<affix>(?:[^"\\]|\\.)*)"\s*,\s*'
    r'(?P<texts>(?:"(?:[^"\\]|\\.)*"\s*,\s*)+)'
    r'(?P<rest>.*)$'
)

LEVEL_RE = re.compile(r"\blevel\s*=\s*(\d+)")
GROUP_RE = re.compile(r'\bgroup\s*=\s*"([^"]+)"')

# Base tables: itemBases["Name"] = { type = ..., tags = { armour = true, ... } }
TAGS_RE = re.compile(r"tags\s*=\s*\{([^}]*)\}")
QUOTED_TAGS_RE = re.compile(r"([A-Za-z0-9_]+)\s*=\s*true")

# Essence table: each essence guarantees one specific modifier per item class.
ESSENCE_RE = re.compile(
    r'\["(?P<path>[^"]+)"\]\s*=\s*\{\s*'
    r'name\s*=\s*"(?P<name>(?:[^"\\]|\\.)*)"\s*,\s*'
    r'type\s*=\s*"(?P<type>(?:[^"\\]|\\.)*)"\s*,\s*'
    r'tierLevel\s*=\s*(?P<level>\d+)\s*,\s*'
    r'mods\s*=\s*\{(?P<mods>[^}]*)\}'
)
MOD_PAIR_RE = re.compile(r'\["([^"]+)"\]\s*=\s*"([^"]+)"')

# Rune / soul-core table: per rune, per item slot, one guaranteed modifier.
#
# The name and slot keys sit at fixed depths, but the block bodies do not: a slot body contains nested
# tables (`bonded = { ... }`, `tradeHashes = { ... }`), and PoB's own emitter has produced different
# indentation over time. A single regex anchored on `\n\t\t\},` therefore matched only 166 of the
# source's 305 runes - every Ancient Rune, every Warding Rune and all 13 missing Soul Cores were
# silently dropped. The table is read by brace depth instead, which does not care about indentation.
RUNE_ENTRY_RE = re.compile(r'\n\t\["(?P<name>(?:[^"\\]|\\.)*)"\] = \{\n(?P<body>.*?)\n\t\},', re.S)
RUNE_SLOT_KEY_RE = re.compile(r'\["(?P<slot>(?:[^"\\]|\\.)*)"\]\s*=\s*\{')
RUNE_FIELD_RE = re.compile(r'^\s*(?P<key>%s)\s*=\s*(?P<value>.+?),?\s*$' % "|".join(
    ("type", "limit", "localMod", "canSocketInUniqueItems", "levelReq")), re.M)
RUNE_TEXT_RE = re.compile(r'^(?P<indent>\t*)"((?:[^"\\]|\\.)*)"', re.M)

# Runeforging: which base types a craft transforms into which (VerisiumCrafts.lua).
VERISIUM_ENTRY_RE = re.compile(r'\n\t\["(?P<base>(?:[^"\\]|\\.)*)"\] = \{\n(?P<body>.*?)\n\t\},', re.S)
VERISIUM_NAME_RE = re.compile(r'\["name"\] = "((?:[^"\\]|\\.)*)"')

# Spawn eligibility: weightKey lists the base tags a modifier can roll on, weightVal
# holds the matching weights (0 means "cannot roll here"). Without this the overlay
# would count jewel/flask modifiers when advising about a pair of gloves.
WEIGHT_KEYS_RE = re.compile(r"weightKey\s*=\s*\{([^}]*)\}")
WEIGHT_VALS_RE = re.compile(r"weightVal\s*=\s*\{([^}]*)\}")
QUOTED_RE = re.compile(r'"([^"]*)"')
INT_RE = re.compile(r"-?\d+")

# Normalization: parenthesised ranges collapse to a single "#", then any remaining
# number does too. Kept deliberately small so the Lua side can mirror it exactly.
RANGE_RE = re.compile(r"\(\s*-?\d+(?:\.\d+)?\s*-\s*-?\d+(?:\.\d+)?\s*\)")
NUMBER_RE = re.compile(r"-?\d+(?:\.\d+)?")
SPACE_RE = re.compile(r"\s+")


def lua_unescape(value: str) -> str:
    """Undo the escapes PoB uses inside generated Lua string literals."""
    return value.replace('\\"', '"').replace("\\\\", "\\")


def normalize(text: str) -> str:
    """Normalize modifier text so clipboard values match data templates."""
    text = text.strip().lower()
    text = RANGE_RE.sub("#", text)
    text = NUMBER_RE.sub("#", text)
    text = text.replace("+", "+")
    return SPACE_RE.sub(" ", text).strip()


def lua_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def parse_file(path: Path) -> tuple[list[dict], int]:
    entries: list[dict] = []
    skipped = 0
    if not path.exists():
        return entries, skipped

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        implicit = False
        if '"Prefix"' not in line and '"Suffix"' not in line:
            # A line with no type field is still a modifier when it is written in the implicit layout.
            match = IMPLICIT_ENTRY_RE.match(line)
            if not match:
                continue
            implicit = True
        else:
            match = ENTRY_RE.match(line)
            if not match:
                # Multi-stat or otherwise unusual entry: reported, never guessed at.
                if "type = " in line and "affix = " in line:
                    skipped += 1
                continue

        rest = match.group("rest")
        level_match = LEVEL_RE.search(rest)
        group_match = GROUP_RE.search(rest)
        if not level_match or not group_match:
            skipped += 1
            continue

        keys_match = WEIGHT_KEYS_RE.search(rest)
        vals_match = WEIGHT_VALS_RE.search(rest)
        keys = QUOTED_RE.findall(keys_match.group(1)) if keys_match else []
        vals = [int(v) for v in INT_RE.findall(vals_match.group(1))] if vals_match else []
        # Spawn weights are per base tag; keeping them lets the overlay compute the
        # probability of a specific modifier for a specific base and item level.
        weights = {
            key: value for key, value in zip(keys, vals) if value > 0
        }
        bases = sorted(weights)

        if implicit:
            # An implicit entry can carry several stat lines ("+1 Prefix Modifier allowed" AND
            # "-1 Suffix Modifier allowed"). Each is kept as its own tier of the group so the Lua side
            # can read how many prefix/suffix slots the item really has.
            texts = QUOTED_RE.findall(match.group("texts"))
            if not texts:
                skipped += 1
                continue
            for position, raw in enumerate(texts):
                entries.append(
                    {
                        "key": match.group("key") + ("#%d" % position if position else ""),
                        "type": "Implicit",
                        "affix": lua_unescape(match.group("affix")),
                        "text": lua_unescape(raw),
                        "level": int(level_match.group(1)),
                        "group": group_match.group(1),
                        "file": path.name,
                        "bases": bases,
                        "weights": ",".join("%s=%d" % (key, weights[key]) for key in bases),
                    }
                )
            continue

        entries.append(
            {
                "key": match.group("key"),
                "type": match.group("type"),
                "affix": lua_unescape(match.group("affix")),
                "text": lua_unescape(match.group("text")[1:-1]),
                "level": int(level_match.group(1)),
                "group": group_match.group(1),
                "file": path.name,
                "bases": bases,
                "weights": ",".join("%s=%d" % (key, weights[key]) for key in bases),
            }
        )
    return entries, skipped


def build_groups(entries: list[dict]) -> dict[str, dict]:
    groups: dict[str, dict] = {}
    for entry in entries:
        key = f"{entry['group']}|{entry['type']}"
        group = groups.setdefault(key, {"type": entry["type"], "tiers": [], "src": entry["file"]})
        group["tiers"].append(entry)

    for key, group in groups.items():
        # Highest level requirement first: tier 1 is the best roll.
        group["tiers"].sort(key=lambda item: (item["level"], item["key"]))
        total = len(group["tiers"])
        for position, tier in enumerate(group["tiers"]):
            tier["tier"] = total - position
    return groups


def build_index(groups: dict[str, dict]) -> dict[str, list[str]]:
    index: dict[str, list[str]] = {}
    for key, group in groups.items():
        for tier in group["tiers"]:
            normalized = normalize(tier["text"])
            bucket = index.setdefault(normalized, [])
            if key not in bucket:
                bucket.append(key)
    return index


def build_key_index(groups: dict[str, dict]) -> dict[str, str]:
    """Modifier entry key -> "group|tier".

    Essences (and other guaranteed crafts) reference modifiers by their data key,
    e.g. "IncreasedLife7", so the runtime needs a way back to the tier.
    """
    index: dict[str, str] = {}
    for group_key, group in groups.items():
        for tier in group["tiers"]:
            index[tier["key"]] = f"{group_key}|{tier['tier']}"
    return index


def parse_essences(source: Path) -> list[dict]:
    """Read PoB's essence table: which modifier each essence guarantees, per class."""
    path = source / "Essence.lua"
    essences: list[dict] = []
    if not path.exists():
        return essences

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = ESSENCE_RE.search(line)
        if not match:
            continue
        mods = {
            klass: mod_key
            for klass, mod_key in MOD_PAIR_RE.findall(match.group("mods"))
        }
        if not mods:
            continue
        name = lua_unescape(match.group("name"))
        tier = ""
        for prefix in ("Lesser ", "Greater ", "Perfect "):
            if name.startswith(prefix):
                tier = prefix.strip()
                break
        essences.append(
            {
                "name": name,
                "type": lua_unescape(match.group("type")),
                "tier": tier,
                "level": int(match.group("level")),
                "mods": mods,
            }
        )
    return essences


def lua_block(text: str, open_index: int) -> tuple[str, int]:
    """Return the body of the Lua table whose "{" is at open_index, and the index just past its "}".

    String literals are skipped so a brace inside a modifier text cannot upset the count. This is what
    replaces the depth-anchored regexes: PoB's emitter changes indentation between releases, so matching
    on "\\n\\t\\t\\}," quietly loses every entry written at another depth.
    """
    depth = 0
    index = open_index
    length = len(text)
    while index < length:
        char = text[index]
        if char == '"':
            index += 1
            while index < length and text[index] != '"':
                index += 2 if text[index] == "\\" else 1
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[open_index + 1:index], index + 1
        index += 1
    return text[open_index + 1:], length


def split_lua_lines(body: str) -> list[tuple[str, int]]:
    """Split a table body into (line, brace depth at the start of that line) pairs."""
    lines: list[tuple[str, int]] = []
    depth = 0
    for line in body.split("\n"):
        lines.append((line, depth))
        depth += line.count("{") - line.count("}")
    return lines


def parse_runes(source: Path) -> dict[str, list[dict]]:
    """Read PoB's rune / soul-core table, grouped by the item slot it fits."""
    path = source / "ModRunes.lua"
    if not path.exists():
        return { }

    text = path.read_text(encoding="utf-8", errors="replace")
    by_slot: dict[str, list[dict]] = { }
    for entry in RUNE_ENTRY_RE.finditer(text):
        name = lua_unescape(entry.group("name"))
        # The entry body starts with "{" at the first slot key; walk it by depth instead of by regex.
        body = entry.group("body")
        for slot_match in RUNE_SLOT_KEY_RE.finditer(body):
            slot = lua_unescape(slot_match.group("slot"))
            # The key pattern stops at the "{" that opens the slot table.
            open_index = body.index("{", slot_match.start())
            slot_body, _ = lua_block(body, open_index)
            # Only the slot's own fields count: nested tables (bonded modifiers, trade hashes) hold
            # text that is not the guaranteed modifier and must not be read as one.
            texts: list[str] = []
            fields: dict[str, str] = { }
            for line, depth in split_lua_lines(slot_body):
                if depth != 0:
                    continue
                stripped = line.strip()
                text_match = re.match(r'^"((?:[^"\\]|\\.)*)"', stripped)
                if text_match:
                    texts.append(lua_unescape(text_match.group(1)))
                    continue
                field_match = re.match(r'^(\w+)\s*=\s*(.+?),?$', stripped)
                if field_match:
                    fields[field_match.group(1)] = field_match.group(2).strip()
            if not texts:
                continue
            limit = re.match(r"(\d+)", fields.get("limit", ""))
            unique_ok = fields.get("canSocketInUniqueItems", "").strip() == "true"
            level_req = re.match(r"(\d+)", fields.get("levelReq", ""))
            by_slot.setdefault(slot, []).append(
                {
                    "name": name,
                    "type": lua_unescape(fields["type"].strip('"')) if "type" in fields else "Rune",
                    "limit": int(limit.group(1)) if limit else 1,
                    "local": fields.get("localMod", "").strip() == "true",
                    "unique": unique_ok,
                    "levelReq": int(level_req.group(1)) if level_req else 0,
                    "texts": texts,
                }
            )
    for slot in by_slot:
        by_slot[slot].sort(key=lambda item: (item["type"], item["name"]))
    return by_slot


def render_runes_lua(by_slot: dict[str, list[dict]], generated: str) -> str:
    total = sum(len(items) for items in by_slot.values())
    lines: list[str] = []
    lines.append("-- PoE2 Craft Overlay : Data/runes.lua")
    lines.append("-- GENERATED FILE - do not edit by hand (tools/extract_mods.py).")
    lines.append("--")
    lines.append("-- Runes, soul cores, idols and abyssal eyes. Each entry is a GUARANTEED")
    lines.append("-- modifier for a specific item slot, so its chance is 100% by definition;")
    lines.append("-- `limit` is how many of that rune the item accepts.")
    lines.append("return {")
    lines.append(f"\tgenerated = {lua_quote(generated)},")
    lines.append(f"\tstats = {{ runes = {len({item['name'] for items in by_slot.values() for item in items})}, slots = {len(by_slot)}, entries = {total} }},")
    lines.append("\tbySlot = {")
    for slot in sorted(by_slot):
        lines.append(f"\t\t[{lua_quote(slot)}] = {{")
        for item in by_slot[slot]:
            texts = ", ".join(lua_quote(value) for value in item["texts"])
            lines.append(
                "\t\t\t{ name = %s, type = %s, limit = %d, isLocal = %s, unique = %s, levelReq = %d, texts = { %s } },"
                % (
                    lua_quote(item["name"]),
                    lua_quote(item["type"]),
                    item["limit"],
                    "true" if item["local"] else "false",
                    "true" if item["unique"] else "false",
                    item["levelReq"],
                    texts,
                )
            )
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def parse_runeforging(source: Path) -> dict[str, list[str]]:
    """Base type -> transformed base names (runeforging / runemastering)."""
    path = source / "VerisiumCrafts.lua"
    if not path.exists():
        return { }
    text = path.read_text(encoding="utf-8", errors="replace")
    table: dict[str, list[str]] = { }
    for entry in VERISIUM_ENTRY_RE.finditer(text):
        base = lua_unescape(entry.group("base"))
        names: list[str] = []
        for raw in VERISIUM_NAME_RE.findall(entry.group("body")):
            name = lua_unescape(raw)
            if name not in names:
                names.append(name)
        if names:
            table[base] = names
    return table


def render_runeforging_lua(table: dict[str, list[str]], generated: str) -> str:
    lines: list[str] = []
    lines.append("-- PoE2 Craft Overlay : Data/runeforging.lua")
    lines.append("-- GENERATED FILE - do not edit by hand (tools/extract_mods.py).")
    lines.append("--")
    lines.append("-- Runeforging / runemastering: base types that a craft turns into an")
    lines.append("-- upgraded base ('Runeforged ...', 'Runemastered ...'). Source: PoB")
    lines.append("-- VerisiumCrafts.lua.")
    lines.append("return {")
    lines.append(f"\tgenerated = {lua_quote(generated)},")
    lines.append(f"\tstats = {{ bases = {len(table)} }},")
    lines.append("\tbyBase = {")
    for base in sorted(table):
        names = ", ".join(lua_quote(name) for name in table[base])
        lines.append(f"\t\t[{lua_quote(base)}] = {{ {names} }},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render_essences_lua(essences: list[dict], generated: str) -> str:
    lines: list[str] = []
    lines.append("-- PoE2 Craft Overlay : Data/essences.lua")
    lines.append("-- GENERATED FILE - do not edit by hand (tools/extract_mods.py).")
    lines.append("--")
    lines.append("-- Each essence guarantees ONE modifier, and which modifier depends on the")
    lines.append("-- item class. Values are PoB modifier keys, resolved through Data/mods.lua.")
    lines.append("return {")
    lines.append(f"\tgenerated = {lua_quote(generated)},")
    lines.append(f"\tstats = {{ essences = {len(essences)} }},")
    lines.append("\tlist = {")
    for essence in sorted(essences, key=lambda item: (item["type"], item["level"], item["name"])):
        lines.append("\t\t{")
        lines.append(f'\t\t\tname = {lua_quote(essence["name"])},')
        lines.append(f'\t\t\ttype = {lua_quote(essence["type"])},')
        lines.append(f'\t\t\ttier = {lua_quote(essence["tier"])},')
        lines.append(f'\t\t\tlevel = {essence["level"]},')
        lines.append("\t\t\tmods = {")
        for klass in sorted(essence["mods"]):
            lines.append(f'\t\t\t\t[{lua_quote(klass)}] = {lua_quote(essence["mods"][klass])},')
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render_lua(groups: dict[str, dict], index: dict[str, list[str]],
               key_index: dict[str, str], stats: dict) -> str:
    lines: list[str] = []
    lines.append("-- PoE2 Craft Overlay : Data/mods.lua")
    lines.append("-- GENERATED FILE - do not edit by hand.")
    lines.append("-- Regenerate with: python tools/extract_mods.py")
    lines.append("--")
    lines.append("-- Source: Path of Building community data (item modifier tables).")
    lines.append("-- tiers per group are ordered by level ascending, tier 1 = best roll.")
    lines.append("return {")
    lines.append(f'\tgenerated = {lua_quote(stats["generated"])},')
    lines.append(f'\tsourceFiles = {{ {", ".join(lua_quote(f) for f in stats["files"])} }},')
    lines.append("\tstats = {")
    for field in ("entries", "groups", "indexKeys", "skipped"):
        lines.append(f"\t\t{field} = {stats[field]},")
    lines.append("\t},")
    lines.append("\tgroups = {")
    for key in sorted(groups):
        group = groups[key]
        lines.append(f"\t\t[{lua_quote(key)}] = {{")
        lines.append(f'\t\t\ttype = {lua_quote(group["type"])},')
        # Source table: in PoB data a "default" spawn tag means "any base within this
        # table", not "any item in the game", so the table is part of eligibility.
        lines.append(f'\t\t\tsrc = {lua_quote(group["src"].replace(".lua", ""))},')
        lines.append("\t\t\ttiers = {")
        for tier in group["tiers"]:
            lines.append(
                "\t\t\t\t{ lvl = %d, tier = %d, affix = %s, text = %s, bases = %s, w = %s },"
                % (
                    tier["level"],
                    tier["tier"],
                    lua_quote(tier["affix"]),
                    lua_quote(tier["text"]),
                    lua_quote(",".join(tier["bases"])),
                    lua_quote(tier["weights"]),
                )
            )
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("\tindex = {")
    for key in sorted(index):
        buckets = ", ".join(lua_quote(bucket) for bucket in index[key])
        lines.append(f"\t\t[{lua_quote(key)}] = {{ {buckets} }},")
    lines.append("\t},")
    # Modifier entry key -> "group|tier", used by guaranteed crafts (essences).
    lines.append("\tbyKey = {")
    for key in sorted(key_index):
        lines.append(f"\t\t[{lua_quote(key)}] = {lua_quote(key_index[key])},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def parse_bases(source: Path) -> dict[str, str]:
    """Map base-type name -> spawn tags from PoB's per-class base tables.

    The tags decide whether a modifier can appear on a given base at all, e.g.
    {"armour", "default", "gloves", "str_armour"} for "Stocky Mitts".
    """
    tags_by_base: dict[str, str] = {}
    bases_dir = source / "Bases"
    if not bases_dir.is_dir():
        return tags_by_base

    for path in sorted(bases_dir.glob("*.lua")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for chunk in text.split('itemBases["')[1:]:
            name_end = chunk.find('"]')
            if name_end < 0:
                continue
            name = lua_unescape(chunk[:name_end])
            tags_match = TAGS_RE.search(chunk)
            if not tags_match:
                continue
            tags = QUOTED_TAGS_RE.findall(tags_match.group(1))
            if tags:
                tags_by_base[name] = ",".join(sorted(tags))
    return tags_by_base


def render_bases_lua(tags_by_base: dict[str, str], generated: str) -> str:
    lines: list[str] = []
    lines.append("-- PoE2 Craft Overlay : Data/bases.lua")
    lines.append("-- GENERATED FILE - do not edit by hand.")
    lines.append("-- Regenerate with: python tools/extract_mods.py")
    lines.append("--")
    lines.append("-- Base type name -> spawn tags used by the modifier tables, so the overlay")
    lines.append("-- can tell which modifiers may appear on the hovered item.")
    lines.append("return {")
    lines.append(f"\tgenerated = {lua_quote(generated)},")
    lines.append(f"\tstats = {{ bases = {len(tags_by_base)} }},")
    lines.append("\ttags = {")
    for name in sorted(tags_by_base):
        lines.append(f"\t\t[{lua_quote(name)}] = {lua_quote(tags_by_base[name])},")
    lines.append("\t},")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def stats_of(path: Path) -> dict[str, int]:
    """Read the `stats = { ... }` numbers out of an already generated Lua table."""
    if not path.exists():
        return { }
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"stats = \{(.*?)\n\t\},", text, re.S) or re.search(r"stats = \{([^}]*)\}", text)
    if not match:
        return { }
    return {name: int(value) for name, value in re.findall(r"(\w+) = (\d+)", match.group(1))}


def check_no_regression(path: Path, new_stats: dict[str, int], labels: dict[str, str]) -> int:
    """Fail when a regeneration would carry LESS data than the table it replaces.

    Two real bugs in this project were an extractor that silently dropped whole families - 139 of 305
    runes, and every implicit modifier - while still printing "skipped: 0". Comparing the new numbers
    with the ones already on disk turns that silent loss into a failure, whichever counter it hides in.
    """
    old_stats = stats_of(path)
    if not old_stats:
        return 0
    problems = [ ]
    for key, new_value in new_stats.items():
        old_value = old_stats.get(key)
        if old_value is not None and new_value < old_value:
            problems.append(f"{labels.get(key, key)}: {old_value} -> {new_value}")
    if problems:
        print(f"refusing to write {path}: it would lose data against the current table", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Extract PoE2 item modifier data from PoB into Lua.")
    parser.add_argument(
        "--source",
        default="../vendor/PathOfBuilding-PoE2/src/Data",
        help="directory holding PoB's Mod*.lua data files",
    )
    parser.add_argument("--out", default="src/Data/mods.lua", help="output Lua file")
    parser.add_argument(
        "--bases-out",
        default="src/Data/bases.lua",
        help="output Lua file for base-type spawn tags",
    )
    parser.add_argument(
        "--essences-out",
        default="src/Data/essences.lua",
        help="output Lua file for the essence table",
    )
    parser.add_argument(
        "--runes-out",
        default="src/Data/runes.lua",
        help="output Lua file for the rune / soul-core table",
    )
    parser.add_argument(
        "--runeforging-out",
        default="src/Data/runeforging.lua",
        help="output Lua file for runeforging base transformations",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="refuse to write a table that would lose data against the one already on disk",
    )
    args = parser.parse_args(argv)

    source = Path(args.source)
    if not source.is_dir():
        print(f"error: source directory not found: {source}", file=sys.stderr)
        return 2

    entries: list[dict] = []
    skipped = 0
    used_files: list[str] = []
    for name in DEFAULT_FILES:
        path = source / name
        if not path.exists():
            continue
        file_entries, file_skipped = parse_file(path)
        if file_entries:
            used_files.append(name)
        entries.extend(file_entries)
        skipped += file_skipped

    if not entries:
        print(f"error: no modifiers parsed from {source}", file=sys.stderr)
        return 3

    groups = build_groups(entries)
    index = build_index(groups)
    key_index = build_key_index(groups)

    stats = {
        "generated": dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "files": used_files,
        "entries": len(entries),
        "groups": len(groups),
        "indexKeys": len(index),
        "keys": len(key_index),
        "skipped": skipped,
    }

    out_path = Path(args.out)
    if args.verify:
        problem = check_no_regression(
            out_path,
            {"entries": stats["entries"], "groups": stats["groups"]},
            {"entries": "modifier entries", "groups": "modifier groups"},
        )
        if problem:
            return problem
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render_lua(groups, index, key_index, stats), encoding="utf-8")

    print(f"parsed {stats['entries']} modifiers from {len(used_files)} files")
    print(f"groups: {stats['groups']}, unique normalized texts: {stats['indexKeys']}, "
          f"keyed modifiers: {stats['keys']}")
    print(f"skipped (unparsed layouts, reported not guessed): {stats['skipped']}")
    print(f"wrote {out_path} ({out_path.stat().st_size / 1024:.0f} kB)")

    essences = parse_essences(source)
    essences_path = Path(args.essences_out)
    if essences:
        if args.verify and check_no_regression(essences_path, {"essences": len(essences)},
                                               {"essences": "essences"}):
            return 1
        essences_path.parent.mkdir(parents=True, exist_ok=True)
        essences_path.write_text(render_essences_lua(essences, stats["generated"]), encoding="utf-8")
        print(f"essences: {len(essences)} -> {essences_path} "
              f"({essences_path.stat().st_size / 1024:.0f} kB)")
    else:
        essence_file = source / "Essence.lua"
        if not essence_file.exists():
            print(f"warning: essence table not found at {essence_file}", file=sys.stderr)
        else:
            print(f"warning: essence table found but no entries matched ({essence_file})",
                  file=sys.stderr)

    runes_by_slot = parse_runes(source)
    runes_path = Path(args.runes_out)
    if runes_by_slot:
        rune_count = len({item["name"] for items in runes_by_slot.values() for item in items})
        rune_entries = sum(len(items) for items in runes_by_slot.values())
        if args.verify and check_no_regression(
                runes_path,
                {"runes": rune_count, "slots": len(runes_by_slot), "entries": rune_entries},
                {"runes": "distinct runes", "slots": "slots", "entries": "rune entries"}):
            return 1
        runes_path.parent.mkdir(parents=True, exist_ok=True)
        runes_path.write_text(render_runes_lua(runes_by_slot, stats["generated"]), encoding="utf-8")
        print(f"runes: {rune_count} distinct across {len(runes_by_slot)} slots -> {runes_path} "
              f"({runes_path.stat().st_size / 1024:.0f} kB)")

    runeforging = parse_runeforging(source)
    runeforging_path = Path(args.runeforging_out)
    if runeforging:
        runeforging_path.parent.mkdir(parents=True, exist_ok=True)
        runeforging_path.write_text(render_runeforging_lua(runeforging, stats["generated"]),
                                    encoding="utf-8")
        print(f"runeforging: {len(runeforging)} base types -> {runeforging_path} "
              f"({runeforging_path.stat().st_size / 1024:.0f} kB)")

    tags_by_base = parse_bases(source)
    bases_path = Path(args.bases_out)
    if tags_by_base:
        bases_path.parent.mkdir(parents=True, exist_ok=True)
        bases_path.write_text(render_bases_lua(tags_by_base, stats["generated"]), encoding="utf-8")
        print(f"base types: {len(tags_by_base)} -> {bases_path} "
              f"({bases_path.stat().st_size / 1024:.0f} kB)")
    else:
        print(f"warning: no base tables found under {source / 'Bases'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
