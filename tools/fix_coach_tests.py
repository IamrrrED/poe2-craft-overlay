"""Correct the coach tests that encoded the belief "Regal cannot work on a full Magic item".

That belief is false and contradicts the project's own currency table (regal.adds = 1) and every guide in
docs/mentor-research.md - the 0.4 walkthrough does Transmutation -> Augmentation -> Regal on a two-mod weapon
precisely because Regal lifts the rarity and adds a third modifier. The tests below were written to match a
wrong rule, so they must be rewritten rather than the rule preserved.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Tests", "test_coach.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

replacements = [
    # The rule's premise, in the comment and in the assertion.
    (
        "\t-- The customer's flask, and the loop it used to produce. A Magic item carries one prefix and one\n"
        "\t-- suffix; with both taken, no rarity upgrade can add anything, so a Regal Orb changes nothing. The\n"
        "\t-- panel offered it anyway, the player applied it, the next round reported \"nothing changed\" and\n"
        "\t-- looked up the LAST step of the same plan - the same Regal Orb, forever. A Magic item with both\n"
        "\t-- affixes taken must never be offered a rarity upgrade, and the plan must end instead of looping.",
        "\t-- A full Magic item is NOT finished: a Regal Orb lifts it to Rare and adds a third modifier while\n"
        "\t-- keeping both already on it, because the cap rises with the rarity. This test used to assert the\n"
        "\t-- opposite - that Regal changes nothing - which contradicted our own currency table (regal.adds =\n"
        "\t-- 1) and the 0.4 walkthrough that does Transmutation -> Augmentation -> Regal on a two-mod item.",
    ),
    (
        '\tH.eq("coach: a rarity upgrade is never offered for a full Magic item", offeredRegal, false)',
        '\tH.eq("coach: a full Magic item IS offered a rarity upgrade", offeredRegal, true)',
    ),
    (
        "\t-- With no quality yet, the one thing left is the quality currency, and it must be the FIRST step so\n"
        "\t-- the index-based coach shows it.",
        "\t-- Regal comes first because it is the move that changes the item; quality is inserted AFTER the step\n"
        "\t-- that changes the modifier set, which is the order the whole advisor uses (mods -> quality -> Vaal).",
    ),
]

for old, new in replacements:
    if old in text:
        text = text.replace(old, new, 1)
        print("replaced:", old.strip().splitlines()[0][:60])
    else:
        print("MISS:", old.strip().splitlines()[0][:60])

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("written")
