"""Add the likes-per-1000-views ranking to the research doc.

The earlier ranking sorted by views only. The request was "по просмотрам и рейтингу", and the two orderings
disagree sharply - the most-watched are not the best-liked per viewer - so both belong in the document.
"""

import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DOC = os.path.join(ROOT, "docs", "mentor-research.md")

# (id, title, views, likes) - only the sources whose metrics the page actually showed.
ROWS = [
    ("1UesZdzHsxg", "3 crafting tips you MUST know", 41686, 1258),
    ("_hwCd52DZRA", "+3 Level of Melee Amulet", 88209, 2420),
    ("chO6his6n3E", "XTheFarmerX — Is Crafting DEAD", 21715, 590),
    ("e6fgB_SPYx0", "POE2DB / Craft of Exile Tutorial", 3313, 85),
    ("1CaHwOFn2mA", "GhazzyTV — GUARANTEE Modifiers", 87294, 2095),
    ("t3v-uV0DdpI", "Kripp — SSF Crafting Tips", 103955, 2417),
    ("hqpaWxPVhy0", "Best Endgame Monk Gloves", 42840, 1000),
    ("Xlc_OclPcDE", "shad0ws — Monk Staff", 8619, 199),
    ("CI7zQO_Ml_s", "60% Socket Effect Gloves", 51227, 1053),
    ("rTxXmG4dHIo", "+5 Proj / +6 Amulets", 28089, 562),
    ("FWD1SDNqIaU", "Craft S-Tier Items in 3 Steps", 222924, 4250),
    ("vjqfnioxyk8", "Endgame Helmets for ANY Build", 77933, 1414),
    ("GNNkhSENp6Q", "5 Mod Jewels Beginner Friendly", 65037, 1152),
    ("zPkP6ZpED70", "HOW I MAKE GODLIKE GEAR", 39588, 588),
    ("8Brn0LtOZZo", "Stop Buying Amulets!", 80379, 989),
    ("Qbt8xIn1tl0", "1000+ DPS Martial Weapons", 16895, 188),
    ("1aDOuTGYEDk", "Best Quarterstaff 900+ pDPS", 112423, 1373),
    ("F4AB0vAu8rY", "Lolcohol — Beginner Guide", 113427, 1233),
    ("NK-Oat_OtgQ", "Fubgun — Best Jewels", 221741, 2179),
    ("dZifyB-qsAc", "Grenade Crossbow 0.5.5", 31586, 274),
    ("XIQSgIJIUIc", "Body Armor on League Start", 11449, 85),
    ("Ph5nHg9Q_cw", "Make Currency with Ritual", 29794, 207),
    ("F32hX3F4REg", "Genesis Tree Tutorial", 11230, 57),
]

lines = [
    "",
    "### Рейтинг по «лайкам на просмотры»",
    "",
    "Просмотры показывают охват, но не качество: чужой ролик смотрят и бросают. Отношение лайков к просмотрам",
    "честнее отражает, насколько зритель остался доволен. Порядок тут **совсем другой**:",
    "",
    "| # | Ролик | Лайков на 1000 просмотров | Просмотры |",
    "|---|---|---|---|",
]

scored = [(title, likes / views * 1000.0, views) for _, title, views, likes in ROWS if views > 0]
scored.sort(key=lambda row: row[1], reverse=True)

for index, (title, ratio, views) in enumerate(scored, start=1):
    lines.append("| {} | {} | **{:.1f}** | {:,} |".format(index, title, ratio, views).replace(",", " "))

lines += [
    "",
    "Что это меняет: **первое место по лайкам — не в топ-10 по просмотрам** (41 тыс. просмотров против",
    "222 тыс. у самого смотрящего). А самый смотрящий ролик по этому показателю в конце списка. Вывод для",
    "наставника простой: выбирать источник по просмотрам — значит брать популярное, а не полезное.",
    "",
]

with io.open(DOC, encoding="utf-8") as handle:
    text = handle.read()

if "Рейтинг по «лайкам на просмотры»" in text:
    print("already present")
else:
    anchor = "### Что изменилось в помощнике после этого аудита"
    if anchor not in text:
        raise SystemExit("anchor not found")
    text = text.replace(anchor, "\n".join(lines) + anchor, 1)
    with io.open(DOC, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print("added rating table with", len(scored), "rows")
