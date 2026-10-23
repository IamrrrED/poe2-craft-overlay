"""Check the C# host's own strings: the messages, the tray labels and their call sites.

Why this exists: the Lua side is covered by the test suite, but the host builds text too - the tray menu, the
"buffer is empty" notice, the market reasons - and that text never goes through the engine's language gate.
A missing key prints the key itself, a missing Russian row silently shows English, and a `{0}` in one language
but not the other throws at runtime instead of showing a message. None of it is visible in a screenshot until
it happens to the player.

Checks:
  * the Ru and En message tables have the same keys;
  * the English values hold no Cyrillic, and the Russian values do (a Russian row that is identical to the
    English one means the translation was skipped - unless it is punctuation or a bare placeholder);
  * the `{0}`, `{1}` placeholders match between the two languages, because string.Format fails otherwise;
  * every Messages.Get(lang, "key") call in the code names a key that exists;
  * the tray labels are translated too, and none of them is English in the Russian set.
"""

from __future__ import annotations

import io
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OVERLAY = os.path.join(ROOT, "overlay")
LANGUAGE = os.path.join(OVERLAY, "PanelLanguage.cs")

CYRILLIC = re.compile(r"[\u0400-\u04FF]")
PLACEHOLDER = re.compile(r"\{\d+\}")

ROW = re.compile(r'\["([A-Za-z0-9_]+)"\]\s*=\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*)+),', re.S)
QUOTED = re.compile(r'"((?:[^"\\]|\\.)*)"')


def unquote(raw: str) -> str:
    parts = QUOTED.findall(raw)
    return "".join(parts)


def table_block(text: str, start_marker: str) -> str:
    start = text.index(start_marker)
    depth = 0
    index = text.index("{", start)
    begin = index
    while index < len(text):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[begin:index + 1]
        index += 1
    raise SystemExit("unbalanced braces after " + start_marker)


def rows(block: str) -> dict[str, str]:
    return {key: unquote(value) for key, value in ROW.findall(block)}


def main() -> int:
    with io.open(LANGUAGE, encoding="utf-8") as handle:
        text = handle.read()

    ru = rows(table_block(text, "private static readonly Dictionary<string, string> Ru = new()"))
    en = rows(table_block(text, "private static readonly Dictionary<string, string> En = new()"))

    problems: list[str] = []
    checks: dict[str, bool] = {}

    checks["the message tables have keys"] = bool(ru) and bool(en)
    only_ru = sorted(set(ru) - set(en))
    only_en = sorted(set(en) - set(ru))
    checks["both languages have the same message keys"] = not only_ru and not only_en
    if only_ru:
        problems.append("only in Ru: " + ", ".join(only_ru))
    if only_en:
        problems.append("only in En: " + ", ".join(only_en))

    # A key listed twice in one table means the first row is dead code.
    duplicates = []
    for name, block in (("Ru", table_block(text, "Dictionary<string, string> Ru = new()")),
                        ("En", table_block(text, "Dictionary<string, string> En = new()"))):
        keys = re.findall(r'\["([A-Za-z0-9_]+)"\]', block)
        duplicates += ["%s:%s" % (name, key) for key in keys if keys.count(key) > 1 and keys.index(key) == keys.index(key)]
    duplicates = sorted(set(duplicates))
    checks["no message key is defined twice"] = not duplicates
    if duplicates:
        problems.append("duplicate keys: " + ", ".join(duplicates))

    cyrillic_in_english = [key for key, value in en.items() if CYRILLIC.search(value)]
    checks["no Russian in the English messages"] = not cyrillic_in_english
    if cyrillic_in_english:
        problems.append("Russian in En: " + ", ".join(cyrillic_in_english))

    # A language is written in its own language in the tray menu ("English" stays "English"), so these
    # rows are allowed to match.
    ALLOWED_SAME = {"trayLanguageEn", "trayLanguageRu"}

    same_in_both = []
    for key, value in ru.items():
        english = en.get(key)
        if english is None or value != english:
            continue
        # Punctuation and bare placeholders are legitimately identical.
        if not re.search(r"[A-Za-z]", value):
            continue
        if key not in ALLOWED_SAME:
            same_in_both.append(key)
    checks["no message reads the same in both languages"] = not same_in_both
    if same_in_both:
        problems.append("identical in both: " + ", ".join(same_in_both))

    placeholder_mismatch = []
    for key, value in ru.items():
        english = en.get(key, "")
        if sorted(PLACEHOLDER.findall(value)) != sorted(PLACEHOLDER.findall(english)):
            placeholder_mismatch.append("%s: ru=%s en=%s" % (
                key, PLACEHOLDER.findall(value) or "none", PLACEHOLDER.findall(english) or "none"))
    checks["the placeholders match between the languages"] = not placeholder_mismatch
    problems.extend(placeholder_mismatch)

    # Every call site must name a real key: otherwise the panel prints "trayQuti" to the player.
    used = set()
    for name in sorted(os.listdir(OVERLAY)):
        if not name.endswith(".cs"):
            continue
        with io.open(os.path.join(OVERLAY, name), encoding="utf-8") as handle:
            body = handle.read()
            # Two ways to reach a message: directly, and through the error-script helper that the page
            # calls back into. Both name the key as a literal, so both are greppable.
            for match in re.finditer(r'(?:Messages\.Get\([^,]+|EngineErrorScript)\s*,\s*"([A-Za-z0-9_]+)"|EngineErrorScript\("([A-Za-z0-9_]+)"\)', body):
                used.add(match.group(1) or match.group(2))
    unknown = sorted(used - set(ru))
    unused = sorted(set(ru) - used)
    checks["every message call names an existing key"] = not unknown
    if unknown:
        problems.append("unknown message keys: " + ", ".join(unknown))
    checks["no message key is left unused"] = not unused
    if unused:
        problems.append("unused message keys: " + ", ".join(unused))

    print("message keys:", len(ru), "| call sites:", len(used))
    for line in problems:
        print("FINDING", line)
    for label, ok in checks.items():
        print(("PASS " if ok else "FAIL ") + label)

    if not all(checks.values()):
        raise SystemExit(1)
    print("host message checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
