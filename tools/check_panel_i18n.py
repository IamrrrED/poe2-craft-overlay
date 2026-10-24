"""Check the panel's language plumbing at the source level, without a browser.

Three things have to hold and none of them is visible in a screenshot: the RU and EN columns of the chrome
table must have the SAME key set, every t('...') call must name a key that exists (a typo would silently
print the key into the panel), and no Russian literal may live outside that table - the engine's own text
arrives already localised and must not be duplicated here.
"""

import io
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PANEL = os.path.join(ROOT, "overlay", "Ui", "panel.html")

CYRILLIC = re.compile(r"[\u0400-\u04FF]")

with io.open(PANEL, encoding="utf-8") as handle:
    page = handle.read()

start = page.index("var T={")
end = page.index("\n};\nfunction t(key){", start)
table = page[start:end]

split = table.index("\n  en:{")
ru_block = table[:split]
en_block = table[split:]

keys = re.compile(r"^    ([A-Za-z0-9_]+):", re.M)
ru_keys = keys.findall(ru_block)
en_keys = keys.findall(en_block)

checks = {
    "the RU column has keys": len(ru_keys) > 0,
    # Sorted: the ORDER of rows in the table is cosmetic, the SET is the contract.
    "the EN column has the same keys": sorted(ru_keys) == sorted(en_keys),
    "no key is defined twice": len(ru_keys) == len(set(ru_keys)),
}

# Every English value must be free of Cyrillic: a leftover in the EN column is the exact bug this whole
# table exists to prevent, and it is invisible in an English screenshot because the card looks uniform.
def values_of(block):
    """{key: text} of one column, quoted value only."""
    found = {}
    for match in re.finditer(r"^    ([A-Za-z0-9_]+):\s*'((?:[^'\\]|\\.)*)'", block, re.M):
        found[match.group(1)] = match.group(2)
    return found


ru_values = values_of(ru_block)
en_values = values_of(en_block)
english_with_cyrillic = [key for key, text in en_values.items() if CYRILLIC.search(text)]
checks["no Russian in the English column"] = not english_with_cyrillic

# Matching values in both columns are only allowed for pure Latin names (the RU/EN switch itself) - a row
# that reads the same in both languages usually means the translation was never done.
both_same = []
for key, text in ru_values.items():
    english = en_values.get(key)
    if english is None or text != english:
        continue
    if CYRILLIC.search(text) or not re.search(r"[A-Za-z]", text):
        # punctuation-only rows ("—", "·") are fine, and a Cyrillic row can only be identical if the
        # English one is wrong (caught above).
        continue
    both_same.append((key, text))
# "SSF" is the game's own abbreviation and is written the same in both languages on purpose.
allowed_same = {"switchRu", "switchEn", "brandName", "ctxModeSsf"}
both_same = [(key, text) for key, text in both_same if key not in allowed_same]
checks["no row reads the same in both languages"] = not both_same

# The glossary: one Russian word per concept, because a player who reads "модификатор" in one place and
# "мод" in another has to guess whether they are the same thing.
GLOSSARY = {
    "модификатор": "мод",
    "модификаторов": "модов",
    "приставк": "префикс",
    "базовый тип": "база",
}
GLOSSARY_FILES = [
    PANEL,
    os.path.join(ROOT, "src", "Core", "i18n.lua"),
    os.path.join(ROOT, "src", "Data", "rules_ru.lua"),
]
glossary_hits = []
for path in GLOSSARY_FILES:
    with io.open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if stripped.startswith("--") or stripped.startswith("#"):
                continue
            for banned, preferred in GLOSSARY.items():
                if banned in line.lower():
                    glossary_hits.append(
                        "%s:%d uses %r, the panel says %r" % (os.path.basename(path), number, banned, preferred))
checks["one Russian word per concept"] = not glossary_hits

# Everything the render code asks for must exist, otherwise t() would print the key itself.
# `t('key')` is the translation call, but the pattern must not fire inside another word: `format('truetype')`
# in a @font-face rule ends with `t('truetype')` and used to be reported as a missing key. The lookbehind
# requires the call to start at a word boundary.
used = set(re.findall(r"(?<![\w.$])t\('([A-Za-z0-9_]+)'\)", page))
missing = sorted(used - set(ru_keys))
checks["every t() call names a key of the table"] = not missing

# The table is the only place allowed to hold Russian. The one exception is the error detector in
# showEngineError: it matches the ENGINE's Russian message ("ошиб"), which is data, not chrome.
outside = page[:start] + page[end:]
outside = outside.replace("/error|ошиб|bad argument/i", "")
checks["no Russian outside the table"] = not CYRILLIC.search(outside)

print("keys in the RU column:", len(ru_keys))
print("keys in the EN column:", len(en_keys))
print("keys used by t():", len(used))
print("missing keys:", missing or "none")
if ru_keys != en_keys:
    print("only in RU:", sorted(set(ru_keys) - set(en_keys)) or "none")
    print("only in EN:", sorted(set(en_keys) - set(ru_keys)) or "none")
for line in outside.splitlines():
    if CYRILLIC.search(line):
        # repr, not the text itself: a Russian console cannot print Russian and would turn a real finding
        # into a UnicodeEncodeError.
        print("Russian outside the table:", repr(line.strip())[:160])

if english_with_cyrillic:
    print("Russian in the English column:", english_with_cyrillic)
if both_same:
    print("rows reading the same in both languages:", both_same)
if glossary_hits:
    for hit in glossary_hits:
        print("glossary:", hit)

for label, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + label)

if not all(checks.values()):
    raise SystemExit(1)
print("panel i18n checks passed")
