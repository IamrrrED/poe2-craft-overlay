"""The last two assertions that still expect quality instead of the rarity upgrade on a full Magic item."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

COACH = os.path.join(ROOT, "src", "Tests", "test_coach.lua")
ORDER = os.path.join(ROOT, "src", "Tests", "test_order.lua")

with io.open(COACH, encoding="utf-8") as handle:
    coach = handle.read()

old = (
    '\tH.eq("coach: at the cap the step is the value reroll",\n'
    '\t\tcappedStep and cappedStep.currency, "Divine Orb")'
)
new = (
    '\t-- The rarity upgrade still comes first at the quality cap: it ADDS a modifier, while the value reroll\n'
    '\t-- only changes the numbers of the two the flask already carries.\n'
    '\tH.eq("coach: at the cap the step is still the rarity upgrade",\n'
    '\t\tcappedStep and cappedStep.currency, "Regal Orb")'
)
if old in coach:
    coach = coach.replace(old, new, 1)
    print("coach: replaced")
else:
    print("coach: MISS")

# The comment above the step loop refers to the Bauble; make it match what the loop now does.
coach = coach.replace(
    "\t-- The step loop: the Bauble worked (quality went up), so the next look moves on to the value reroll\n"
    "\t-- rather than offering the Bauble again.",
    "\t-- The step loop: once the rarity upgrade is applied the item is Rare, so the next look moves on\n"
    "\t-- instead of offering the same orb again.",
    1,
)

with io.open(COACH, "w", encoding="utf-8", newline="") as handle:
    handle.write(coach)

with io.open(ORDER, encoding="utf-8") as handle:
    order = handle.read()

old_order = (
    '\tH.eq("order: the Magic flask with no quality still gets the Bauble",\n'
    '\t\tCoach.step(flask, flaskAdvice, Coach.state(flask, FLASK), nil).currency, "Glassblower\'s Bauble")'
)
new_order = (
    '\tH.eq("order: a full Magic flask upgrades to Rare before anything else",\n'
    '\t\tCoach.step(flask, flaskAdvice, Coach.state(flask, FLASK), nil).currency, "Regal Orb")'
)
if old_order in order:
    order = order.replace(old_order, new_order, 1)
    print("order: replaced")
else:
    print("order: MISS")

with io.open(ORDER, "w", encoding="utf-8", newline="") as handle:
    handle.write(order)
print("written")
