"""Apply the second-source corrections to the league data.

Every change here came from a source that contradicts or confirms what we had:

1. Omen of Putrefaction was recorded as contradictory and unconfirmed. Two sources describe it as an explicit
   EXCEPTION to the one-desecrated-modifier rule, so both halves of our note were wrong.
2. The Genesis Tree has a second catalyst node - Additional Duplicate Catalyst Chance, 30% - which we did not
   have.
3. Desecration's own facts were only implied by the omen records: the bone tiers, the item level at which an
   off-pool option appears, and where the bones come from.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Data", "league_0_5_5.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

original = text

# 1. Putrefaction: confirmed, and an exception rather than a contradiction.
old_putrefaction = (
    '\t\tputrefaction = {\n'
    '\t\t\ten = "Omen of Putrefaction", effectEn = "Desecration replaces every modifier on the item, '
    'creating up to six unrevealed modifiers and corrupting it. The wording conflicts with the '
    'one-desecrated-modifier limit and has not been confirmed in game.",\n'
    '\t\t\tapplies = "bone", replacesAll = true, corrupts = true, cost = "unknown", status = "unverified",\n'
    '\t\t},'
)
new_putrefaction = (
    '\t\tputrefaction = {\n'
    '\t\t\ten = "Omen of Putrefaction",\n'
    '\t\t\t-- Confirmed by two sources, and it is an explicit EXCEPTION to the one-desecrated-modifier rule\n'
    '\t\t\t-- rather than a contradiction of it: it replaces every modifier, leaves up to six unrevealed ones\n'
    '\t\t\t-- and corrupts the item. Our note used to call it contradictory AND unconfirmed - wrong twice.\n'
    '\t\t\teffectEn = "The next desecration replaces every modifier on the item, creating up to six '
    'unrevealed modifiers and corrupting it. An explicit exception to the one-desecrated-modifier limit.",\n'
    '\t\t\tapplies = "bone", replacesAll = true, corrupts = true, cost = "veryhigh", status = "league",\n'
    '\t\t},'
)
if old_putrefaction in text:
    text = text.replace(old_putrefaction, new_putrefaction, 1)
    print("putrefaction: corrected")
elif "explicit EXCEPTION" in text:
    print("putrefaction: already corrected")
else:
    print("putrefaction: ANCHOR MISS")

# 2. A second catalyst node, and the desecration facts, added to the Genesis Tree block.
old_tree = "\t\tcatalystChance = 0.15,"
new_tree = (
    "\t\t-- Confirmed by three independent sources (poe2wiki, fextralife, basicknowledge).\n"
    "\t\tcatalystChance = 0.15,\n"
    "\t\t-- A second node: the chance to birth an EXTRA catalyst of the same type.\n"
    "\t\tduplicateCatalystChance = 0.30,"
)
if old_tree in text and "duplicateCatalystChance" not in text:
    text = text.replace(old_tree, new_tree, 1)
    print("genesis tree: duplicate catalyst chance added")
elif "duplicateCatalystChance" in text:
    print("genesis tree: already has the duplicate chance")
else:
    print("genesis tree: ANCHOR MISS")

# 3. Desecration facts. The omen records described what each omen does but nothing described the mechanic.
old_bones = "\tbones = {"
new_bones = (
    "\t-- Desecration itself: what the bone does, and the two thresholds that decide whether it is worth doing.\n"
    "\t-- Sources: basicknowledge.xyz/poe2/craft/abyss, poe2wiki. Applied with a bone on a rare; the result is\n"
    "\t-- unrevealed and chosen 1 of 3 at the Well of Souls in Act 2.\n"
    "\tdesecration = {\n"
    "\t\tappliedWith = \"preserved bone\",\n"
    "\t\trevealedAt = \"Колодец Душ (Well of Souls), хаб Акта 2\",\n"
    "\t\tchoices = 3,\n"
    "\t\t-- Above this item level at least one of the three options is a modifier that normally cannot roll.\n"
    "\t\toffPoolFromItemLevel = 65,\n"
    "\t\t-- 0.5.0: a desecrated modifier no longer counts as crafted, and the item holds one of them.\n"
    "\t\tmaxDesecrated = 1,\n"
    "\t\tdropsFrom = \"Abyssal Troves и Abyssal Depths\",\n"
    "\t\t-- Abyss omens stopped dropping in low areas in 0.5.0, which is why they are endgame-priced.\n"
    "\t\tomenDropLevel = 65,\n"
    "\t},"
    "\tbones = {"
)
if old_bones in text and "\tdesecration = {" not in text:
    text = text.replace(old_bones, new_bones, 1)
    print("desecration: facts added")
elif "\tdesecration = {" in text:
    print("desecration: already present")
else:
    print("desecration: ANCHOR MISS")

if text == original:
    print("NOTHING WRITTEN")
else:
    with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print("written")
