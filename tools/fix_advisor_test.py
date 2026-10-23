"""The description assertion must accept the Russian text, since that is what the panel now shows."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Tests", "test_advisor.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

old = 'H.contains("advisor: min plan has a description", open.plans[1].reason or "", "Exalted")'
new = (
    '-- The reason now reaches the panel in Russian: English used to win even when a Russian\n'
    '\t-- explanation existed, which is the leak this test used to encode.\n'
    '\tlocal openReason = open.plans[1].reason or ""\n'
    '\tH.check("advisor: min plan has a description",\n'
    '\t\topenReason:find("Экзальт", 1, true) ~= nil\n'
    '\t\t\tor openReason:find("Exalted", 1, true) ~= nil, openReason)'
)

if old in text:
    text = text.replace(old, new, 1)
    with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print("updated")
else:
    print("MISS")
