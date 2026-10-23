#!/usr/bin/env python3
"""Find English words left inside our RUSSIAN prose, and sort them into "fix" and "keep".

The panel speaks two languages; this checks the Russian side. A Russian sentence may legitimately contain
a game object's name in Latin letters - the currency the player trades with is called Exalted Orb, and a
Russian player says it that way too - but it must not contain ordinary English words ("Magic", "Rare"),
because those have Russian words and reading them in the middle of a Russian sentence is what "the panel
is partly Russian" meant.

So the report is two lists:
  * FIX  - Latin words that are not game object names: rarity words, "quality", "ilvl", plain "chaos" as
           a unit. These are ours to reword.
  * KEEP - words that are part of a proper name (Exalted Orb, Omen of Whittling, Hinekora's Lock, ...):
           the Russian client and the trade site use these names, and the display dictionary translates
           them where they appear as values.

Usage:
    python tools/audit_russian_prose.py            # summary per file
    python tools/audit_russian_prose.py --list     # every finding, one per line
    python tools/audit_russian_prose.py --words    # the Latin words seen, by count
"""

from __future__ import annotations

import argparse
import io
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# The prose modules: everything a player reads on the card, the picker or the reference. Data files full
# of game names (ru_bases, ru_stats, display_names_ru) are deliberately not scanned - they are names.
FILES = [
    "src/Craft/Advisor.lua",
    "src/Craft/Coach.lua",
    "src/Craft/Lesson.lua",
    "src/Craft/Techniques.lua",
    "src/Craft/Curriculum.lua",
    "src/Craft/Claims.lua",
    "src/Craft/CraftOrBuy.lua",
    "src/Craft/GenesisTree.lua",
    "src/Craft/Stage.lua",
    "src/Data/crafting_guide.lua",
    "src/Data/league_0_5_5.lua",
    "src/Mcp/api.lua",
]

CYRILLIC = re.compile(r"[\u0400-\u04FF]")
# A Latin word with at least two letters; single letters (S in "S S", x in "x2") are notation, not words.
# A digit or an underscore glues a token together: "magic_two_mods" is a rule id, and the word inside it
# is not prose.
LATIN_WORD = re.compile(r"(?<![A-Za-z0-9_\-])[A-Za-z][A-Za-z'’\-]{1,}(?![A-Za-z0-9_\-])")
# Domains and file names are addresses, not words: "poe2craft.com" is not the word "craft".
DOTTED = re.compile(r"\S+\.[A-Za-z]+")
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
# A quotation: an external video title, a wiki sentence, a game property name. It is somebody else's
# text, quoted on purpose, and translating it would make the reference unfindable.
QUOTED = re.compile(r"«[^»]*»")

# Ordinary English words that have a Russian word and therefore must not stay in a Russian sentence.
# Everything else is either a proper name or a unit the trade site prints.
MUST_FIX_WORDS = {
    "magic", "rare", "normal", "unique", "quality", "ilvl", "item", "level", "tier", "chance",
    "better", "first", "second", "third", "slot", "slots", "mod", "mods", "prefix", "prefixes",
    "suffix", "suffixes", "affix", "affixes", "craft", "crafting", "itemlevel", "divinex",
}
# Words that are proper names or trade notation even on their own.
KEEP_ALWAYS = {
    "exalted", "chaos", "divine", "vaal", "regal", "alchemy", "annulment", "transmutation",
    "augmentation", "chance", "omen", "omens", "essence", "essences", "rune", "runes", "alloy",
    "alloys", "desecration", "sanctification", "waystone", "waystones", "catalyst", "catalysts",
    "tablet", "relic", "jewel", "breachstone", "verisium", "hinekora", "lock", "whittling", "light",
    "echoes", "necromancy", "exaltation", "homogenising", "sinistral", "dextral", "vitality",
    "infusion", "refined", "greater", "perfect", "lesser", "grand", "abyssal", "bone", "bones",
    "gnawed", "preserved", "ancient", "rib", "jawbone", "collarbone", "cranium", "vertebrae",
    "soul", "core", "cores", "idol", "mist", "liquid", "emotion", "emotions", "instil", "instilling",
    "runic", "ward", "runeforging", "verisium", "spirit", "womb", "wombgift", "genesis", "tree",
    "catalyst", "qualitybasecaps", "ilvl",
}


def russian_strings(path: str) -> list[tuple[int, str]]:
    """(line number, string literal) for every literal that contains Cyrillic."""
    with io.open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        text = handle.read()
    out = []
    for match in STRING.finditer(text):
        literal = match.group(1)
        if CYRILLIC.search(literal):
            line = text.count("\n", 0, match.start()) + 1
            out.append((line, literal))
    return out


def classify(word: str) -> str:
    lowered = word.lower().strip("'’-")
    if lowered in MUST_FIX_WORDS:
        return "FIX"
    if lowered in KEEP_ALWAYS:
        return "KEEP"
    # An unknown capitalised word is probably part of a name ("Orb of Whittling"); an unknown lower-case
    # word is reported as a question, not silently accepted.
    return "KEEP" if word[0].isupper() else "ASK"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true", help="print every finding")
    parser.add_argument("--words", action="store_true", help="print the Latin words seen, most common first")
    parser.add_argument("--out", help="write the report here as UTF-8 (a Windows console cannot print it)")
    args = parser.parse_args()

    per_file: Counter = Counter()
    words: Counter = Counter()
    findings: list[tuple[str, int, str, str, str]] = []
    for path in FILES:
        if not os.path.exists(os.path.join(ROOT, path)):
            print("missing file:", path, file=sys.stderr)
            continue
        for line, literal in russian_strings(path):
            # Quotations are somebody else's words (a video title, a wiki sentence, a property name), and
            # a domain or a file name is an address rather than a word.
            prose = DOTTED.sub(" ", QUOTED.sub(" ", literal))
            for match in LATIN_WORD.finditer(prose):
                word = match.group(0)
                verdict = classify(word)
                words[word] += 1
                if verdict in ("FIX", "ASK"):
                    per_file[path] += 1
                    findings.append((path, line, verdict, word, prose))

    if args.words:
        for word, count in words.most_common():
            print(f"{count:5d}  {word:24s} {classify(word)}")
        return 0

    if args.list or args.out:
        rows = [ ]
        for path, line, verdict, word, literal in findings:
            excerpt = literal.replace("\\n", " ")[:160]
            rows.append(f"{verdict:4s} {path}:{line}  [{word}]  {excerpt}")
        if args.out:
            target = os.path.join(ROOT, args.out)
            with io.open(target, "w", encoding="utf-8", newline="\n") as handle:
                handle.write("\n".join(rows) + "\n")
            print("written:", args.out, len(rows), "findings")
            return 0
        for row in rows:
            print(row)
        return 0

    print("findings per file (FIX = ordinary English word, ASK = unknown lower-case word):")
    for path, count in per_file.most_common():
        print(f"{count:5d}  {path}")
    print("total:", sum(per_file.values()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
