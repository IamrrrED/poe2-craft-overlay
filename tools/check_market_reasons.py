#!/usr/bin/env python3
"""Every refusal the market helper can produce must be translatable in the host.

The trade lookup is a Node script (tools/market_price.js); when it refuses, it says why in English
("base not found on the trade site"), and the panel shows that sentence inside its own message. A reason
the host does not know therefore appears in English in the middle of a Russian card - which is exactly
what the customer saw once ("Цену взять не удалось: base not found on the trade site").

This check keeps the two lists in step: it reads the reason literals out of the script and asserts each
one has an entry in the host's dictionary (overlay/PanelLanguage.cs, ReasonsRu). The catch-all path
(String(error)) is not a literal and cannot be checked - it is shown as it came, on purpose.

Usage:
    python tools/check_market_reasons.py
"""

from __future__ import annotations

import io
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT = os.path.join(ROOT, "tools", "market_price.js")
HOST = os.path.join(ROOT, "overlay", "PanelLanguage.cs")

# reason: 'text'  and  reason: "text"
REASON = re.compile(r"reason:\s*'([^']+)'")
# ["text"] = "перевод",  inside the host's dictionary
HOST_ENTRY = re.compile(r'\["([^"]+)"\]\s*=\s*"')


def main() -> int:
    with io.open(SCRIPT, encoding="utf-8") as handle:
        script = handle.read()
    with io.open(HOST, encoding="utf-8") as handle:
        host = handle.read()

    reasons = sorted(set(REASON.findall(script)))
    if not reasons:
        print("no reason literals found - did the script change shape?")
        return 1

    # Only the dictionary block matters, not the sentence tables above it.
    start = host.find("ReasonsRu")
    block = host[start:] if start >= 0 else ""
    known = set(HOST_ENTRY.findall(block))

    missing = [reason for reason in reasons if reason not in known]
    for reason in reasons:
        print(("PASS " if reason in known else "FAIL ") + "translatable: " + reason)
    print("reasons in the script:", len(reasons), "| translated:", len(reasons) - len(missing))
    if missing:
        print("missing from ReasonsRu:", ", ".join(missing))
        return 1
    print("market reason checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
