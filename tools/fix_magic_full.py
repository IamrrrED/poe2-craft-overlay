"""Fix magic_full: a full Magic item is exactly where a Regal Orb is the right move.

The rule claimed "Regal finds no room" and "Regal would change nothing", and built its plans with NO steps.
Both statements are false and contradict our own currency table, where regal has adds = 1: a Regal Orb lifts
the item to Rare AND adds a third modifier, keeping the two already on it. The rarity cap rises with the
rarity, so there is always room - that is the whole point of Regal.

The consequence was visible on the customer's wand: two excellent modifiers on a Magic base, and the panel
answered "nothing can be added, raise the quality" - hiding the single most standard step in the game.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Data", "league_0_5_5.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

start_marker = '\t\t\t-- A Magic item holds one prefix and one suffix, so with both taken no rarity upgrade can add'
end_marker = '\t\t\tid = "magic_two_mods",'

start = text.find(start_marker)
if start == -1:
    raise SystemExit("start marker not found")
end = text.find(end_marker, start)
if end == -1:
    raise SystemExit("end marker not found")

replacement = '''\t\t\t-- A Magic item holds one prefix and one suffix. With both taken it is still NOT finished: a Regal
\t\t\t-- Orb lifts the item to Rare and adds a third modifier while keeping the two that are there, because
\t\t\t-- the cap rises with the rarity. The rule used to say the opposite - "Regal finds no room", "Regal
\t\t\t-- would change nothing" - and planned no steps at all, so every full Magic item was told it was
\t\t\t-- finished and offered quality instead. That is one of the most common states in the game: any
\t\t\t-- two-mod base worth keeping.
\t\t\tid = "magic_full",
\t\t\twhen = { rarity = "MAGIC", maxAffixes = 2, minAffixes = 2 },
\t\t\tmin = { "regal" },
\t\t\tmax = { "regal", "greater_exalted", "greater_exalted", "vaal" },
\t\t\tblocker = "Оба аффикса Magic заняты, но предмет не закончен: Regal поднимет его до Rare и добавит "
\t\t\t\t.. "третий мод, сохранив оба имеющихся.",
\t\t\tblockerEn = "Both affixes of a Magic item are taken, but the item is not finished: a Regal Orb "
\t\t\t\t.. "lifts it to Rare and adds a third modifier, keeping both that are already there.",
\t\t\twhy = {
\t\t\t\tmin = "У Magic заняты префикс и суффикс — добавить в них нечего. Regal поднимает редкость до Rare "
\t\t\t\t\t.. "и добавляет третий мод, НЕ снимая первые два: это единственный шаг, который здесь строго "
\t\t\t\t\t.. "улучшает предмет. Качество при этом не теряется и его можно добрать позже.",
\t\t\t\tmax = "Regal, затем добить открытые слоты Exalted и закрыть качеством; Vaal — последним и только "
\t\t\t\t\t.. "если готовы потерять предмет.",
\t\t\t},
\t\t\twhyEn = {
\t\t\t\tmin = "Both a prefix and a suffix are taken, so nothing can be added to them. A Regal Orb raises "
\t\t\t\t\t.. "the rarity to Rare and adds a third modifier WITHOUT removing the first two: it is the one "
\t\t\t\t\t.. "move here that strictly improves the item. Quality is not lost and can be added later.",
\t\t\t\tmax = "Regal, then fill the open slots with Exalted, and close with quality; Vaal last, and only "
\t\t\t\t\t.. "if you are willing to lose the item.",
\t\t\t},
\t\t},
\t\t{
'''

text = text[:start] + replacement + text[end:]

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("magic_full fixed")
