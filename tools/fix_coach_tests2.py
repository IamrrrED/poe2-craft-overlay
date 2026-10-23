"""Rewrite the coach tests that asserted "Regal does nothing on a full Magic item".

The rule they encoded was wrong and contradicted the project's own currency table (regal.adds = 1), the poe2db
internal type name CurrencyUpgradeMagicToRare, and the 0.4 walkthrough that does Transmutation -> Augmentation
-> Regal on a two-mod item. A full Magic item is upgraded first and has its values rerolled later, because
Regal ADDS a modifier while Divine only changes numbers.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Tests", "test_coach.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

pairs = [
    (
        '\tH.eq("coach: and the card offers quality first, not the rarity upgrade",\n'
        '\t\tflaskReport.step.currency, "Glassblower\'s Bauble")\n'
        '\tH.eq("coach: the title says quality", flaskReport.step.title:find("качество", 1, true) ~= nil, true)',
        '\t-- A full Magic item is upgraded, not polished: Regal adds a third modifier while the Bauble only\n'
        '\t-- raises quality on a two-mod item that still has room to become Rare. Quality is inserted AFTER\n'
        '\t-- the step that changes the modifier set, which is the order the whole advisor uses.\n'
        '\tH.eq("coach: the card offers the rarity upgrade first, not quality",\n'
        '\t\tflaskReport.step.currency, "Regal Orb")\n'
        '\tH.eq("coach: the title says the rarity upgrade",\n'
        '\t\tflaskReport.step.title:find("Regal", 1, true) ~= nil, true)',
    ),
    (
        '\tH.eq("coach: and the card offers it, not a rarity upgrade",\n'
        '\t\tqualityReport.step.currency, "Divine Orb")\n'
        '\tH.eq("coach: the card says the modifier set is not changed",\n'
        '\t\tqualityReport.step.why:find("набор модов менять не нужно", 1, true) ~= nil, true)',
        '\t-- Even at the quality cap, the rarity upgrade comes first: it ADDS a modifier, while Divine only\n'
        '\t-- rerolls the numbers of the two that are there. Rerolling before the set is final wastes the orb.\n'
        '\tH.eq("coach: the rarity upgrade is offered before the value reroll",\n'
        '\t\tqualityReport.step.currency, "Regal Orb")',
    ),
    (
        '\t-- The customer\'s flask, and the loop it used to produce. A Magic item carries one prefix and one\n'
        "\t-- suffix; with both taken, no rarity upgrade can add anything, so a Regal Orb changes nothing. The\n"
        '\t-- panel offered it anyway, the player applied it, the next round reported "nothing changed" and\n'
        '\t-- looked up the LAST step of the same plan - the same Regal Orb, forever. A Magic item with both\n'
        '\t-- affixes taken must never be offered a rarity upgrade, and the plan must end instead of looping.',
        '\t-- A full Magic item is NOT finished. This test used to assert the opposite - that no rarity upgrade\n'
        '\t-- can add anything - which contradicted our own currency table (regal.adds = 1), the poe2db type\n'
        '\t-- name CurrencyUpgradeMagicToRare, and the 0.4 walkthrough that does Transmutation -> Augmentation\n'
        '\t-- -> Regal on a two-mod item. The cap rises with the rarity, so Regal always has room on Magic.',
    ),
    (
        '\tH.eq("coach: a rarity upgrade is never offered for a full Magic item", offeredRegal, false)',
        '\tH.eq("coach: a rarity upgrade IS offered for a full Magic item", offeredRegal, true)',
    ),
    (
        '\t-- With no quality yet, the one thing left is the quality currency, and it must be the FIRST step so\n'
        '\t-- the index-based coach shows it.\n'
        '\tH.eq("coach: the only step left is quality", (fullAdvice.plans[1].steps[1] or { }).id, "bauble")',
        '\t-- Regal is the first step of the plan, and the index-based coach shows it first.\n'
        '\tH.eq("coach: the first step of the plan is the rarity upgrade",\n'
        '\t\t(fullAdvice.plans[1].steps[1] or { }).id, "regal")',
    ),
    (
        '\tH.eq("coach: and the card offers it", Coach.report(fullMagic, fullAdvice, FULL_MAGIC).step.currency,\n'
        '\t\t"Glassblower\'s Bauble")',
        '\tH.eq("coach: and the card offers it", Coach.report(fullMagic, fullAdvice, FULL_MAGIC).step.currency,\n'
        '\t\t"Regal Orb")',
    ),
]

for old, new in pairs:
    if old in text:
        text = text.replace(old, new, 1)
        print("replaced:", old.strip().splitlines()[0][:58])
    else:
        print("MISS:", old.strip().splitlines()[0][:58])

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("written")
