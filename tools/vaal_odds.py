"""Vaal Orb: the odds are published, so state them instead of saying "it can brick".

poewiki (Vaal Orb, fetched 2026-10-20) is explicit for equipment: the orb applies ONE of four outcomes, each
with an equal chance. One of those four turns the item into a rare of the same base with six RANDOM affixes -
the craft is gone. That is 25%, one attempt in four, and a warning that only says "can brick" does not convey
it. The same page also settles the gem case: +1 level is 1/8 (12.5%), because 1/4 for the level effect times
1/2 for the sign.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEAGUE = os.path.join(ROOT, "src", "Data", "league_0_5_5.lua")
CLAIMS = os.path.join(ROOT, "src", "Craft", "Claims.lua")

with io.open(LEAGUE, encoding="utf-8") as handle:
    league = handle.read()

OLD_EN = (
    '\t\t\twarningEn = "One-way: the item becomes corrupted and cannot be crafted further. It can also lose "\n'
    '\t\t\t\t.. "modifiers or the whole craft, so use it only when you are ready to keep the result.",'
)
NEW_EN = (
    '\t\t\t-- Four outcomes, equal chance (poewiki, Vaal Orb): a corruption implicit that REPLACES the existing\n'
    '\t\t\t-- one, a socket going non-white, a reroll into a rare with six random affixes, or nothing. A\n'
    '\t\t\t-- warning that says "can brick" does not convey that one attempt in four destroys the craft.\n'
    '\t\t\twarningEn = "One-way. Equipment has FOUR equal outcomes, 25% each: a corruption implicit (it "\n'
    '\t\t\t\t.. "REPLACES the existing implicit), a socket turning non-white, the item becoming rare with SIX "\n'
    '\t\t\t\t.. "random affixes (the craft is gone), or no change. One attempt in four destroys the result.",'
)

OLD_RU = (
    '\t\t\twarning = "Необратимо: предмет станет осквернённым, и крафт на нём больше не применяется. Vaal может "\n'
    '\t\t\t\t.. "убрать моды или испортить предмет, поэтому применять только когда результат уже устраивает.",'
)
NEW_RU = (
    '\t\t\twarning = "Необратимо. У снаряжения ЧЕТЫРЕ равных исхода по 25 %: осквернённый имплисит (он "\n'
    '\t\t\t\t.. "ЗАМЕНИТ существующий), цвет сокета станет не белым, предмет станет редким с ШЕСТЬЮ "\n'
    '\t\t\t\t.. "случайными модами — крафт пропадает, — либо ничего не изменится. Одна попытка из четырёх "\n'
    '\t\t\t\t.. "уничтожает результат.",'
)

for old, new, label in ((OLD_EN, NEW_EN, "warningEn"), (OLD_RU, NEW_RU, "warning")):
    if old in league:
        league = league.replace(old, new, 1)
        print("replaced", label)
    else:
        print("MISS", label)

with io.open(LEAGUE, "w", encoding="utf-8", newline="") as handle:
    handle.write(league)

# The claim itself: replace the "rate not measured" wording with the published one.
with io.open(CLAIMS, encoding="utf-8") as handle:
    claims = handle.read()

start = claims.find('id = "vaal_all_skills_rate",')
if start == -1:
    print("claim MISS")
else:
    block_start = claims.rfind("\t{", 0, start)
    block_end = claims.find("\n\t},", start)
    if block_start == -1 or block_end == -1:
        print("claim bounds MISS")
    else:
        new_block = '''\t{
\t\tid = "vaal_all_skills_rate",
\t\tmatches = { "+1 all skills", "+1 ко всем умениям", "ваал +1", "осквернение +1", "vaal +1" },
\t\tverdict = "true",
\t\ttitle = "Vaal: четыре равных исхода, один из них уничтожает крафт",
\t\twhy = "У снаряжения осквернение даёт ОДИН из четырёх равных исходов, по 25 % каждый: осквернённый "
\t\t\t.. "имплисит (он заменяет существующий), цвет сокета станет не белым, предмет станет редким с "
\t\t\t.. "ШЕСТЬЮ случайными модами — весь крафт пропадает, — либо не изменится ничего. Именно поэтому "
\t\t\t.. "Vaal делают последним и только на предмете, который готовы потерять. Шанс получить нужный "
\t\t\t.. "имплисит — это 25 % МИНУС вероятность того, что выпадет не тот имплисит: набор имплиситов "
\t\t\t.. "зависит от базы, поэтому «+1 ко всем умениям» с конкретной базы нужно смотреть отдельно.",
\t\tsource = "poewiki Vaal_Orb, снято 2026-10-20: четыре исхода, равный шанс; для самоцветов +1 к уровню "
\t\t\t.. "= 1/8 (1/4 на эффект уровня × 1/2 на знак)",
\t},'''
        claims = claims[:block_start] + new_block + claims[block_end + len("\n\t},"):]
        print("claim rewritten")
        with io.open(CLAIMS, "w", encoding="utf-8", newline="") as handle:
            handle.write(claims)
print("written")
