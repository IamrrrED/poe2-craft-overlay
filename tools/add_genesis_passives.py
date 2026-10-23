"""Genesis Tree: the passives that change what a womb produces, as data.

Source: poewiki.net/wiki/The_Genesis_Tree (fetched 2026-10-20). The tree has four wombs with dozens of
passives each; encoding all of them would be a dump nobody reads. These are the ones that change a CRAFTING
decision - tier rating, fractured chance, socket rolls, value rerolls, modifier biasing, extra items - and the
block says plainly that it is a subset.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Data", "league_0_5_5.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

if "wombPassives" in text:
    print("already present")
    raise SystemExit(0)

ANCHOR = "\t\trefinedBreachRingChance = 0.05,"

BLOCK = '''\t\trefinedBreachRingChance = 0.05,
\t\t-- Passives that change what a womb produces, and therefore change a crafting decision. A SUBSET on
\t\t-- purpose: the tree carries dozens per womb and a full dump would be unreadable. Source: poewiki
\t\t-- "The_Genesis_Tree", fetched 2026-10-20. Passives are freely refundable, so nothing here is a
\t\t-- one-way choice.
\t\twombPassives = {
\t\t\t{
\t\t\t\twomb = "equipment",
\t\t\t\tnodes = {
\t\t\t\t\t{ name = "Modifier Tier Rating", kind = "small", effectEn = "+20 to Modifier Tier Rating",
\t\t\t\t\t\teffectRu = "+20 к рейтингу тира модов" },
\t\t\t\t\t{ name = "Divine Rolls", kind = "small",
\t\t\t\t\t\teffectEn = "Values of random modifiers are rolled an additional time, keeping the best",
\t\t\t\t\t\teffectRu = "Числа случайных модов перебрасываются ещё раз, берётся лучшее" },
\t\t\t\t\t{ name = "Solid Cysts", kind = "notable",
\t\t\t\t\t\teffectEn = "33% chance to be Fractured",
\t\t\t\t\t\teffectRu = "33 % шанс, что предмет выйдет расколотым" },
\t\t\t\t\t{ name = "Severing", kind = "notable",
\t\t\t\t\t\teffectEn = "The lowest level Modifier is removed",
\t\t\t\t\t\teffectRu = "Снимается мод с наименьшим уровнем" },
\t\t\t\t\t{ name = "Arterial Mesh", kind = "notable",
\t\t\t\t\t\teffectEn = "Sockets and Links rolled +50 times, keeping the best",
\t\t\t\t\t\teffectRu = "Сокеты и связи перебрасываются +50 раз, берётся лучшее" },
\t\t\t\t\t{ name = "Forsaken Soul", kind = "notable",
\t\t\t\t\t\teffectEn = "Parent of the three 'reduced <type> modifier chance' passives",
\t\t\t\t\t\teffectRu = "Родитель трёх пассивок «меньше модов <типа>»" },
\t\t\t\t\t{ name = "Devoted Soul", kind = "notable",
\t\t\t\t\t\teffectEn = "Parent of the 'increased <type> modifier chance' passives",
\t\t\t\t\t\teffectRu = "Родитель пассивок «больше модов <типа>»" },
\t\t\t\t\t{ name = "Increased Resistance Modifier Chance", kind = "notable",
\t\t\t\t\t\teffectEn = "300% increased chance for Resistance Modifiers",
\t\t\t\t\t\teffectRu = "300 % к шансу модов сопротивлений" },
\t\t\t\t\t{ name = "Increased Life Modifier Chance", kind = "notable",
\t\t\t\t\t\teffectEn = "300% increased chance for Life Modifiers",
\t\t\t\t\t\teffectRu = "300 % к шансу модов здоровья" },
\t\t\t\t},
\t\t\t},
\t\t\t{
\t\t\t\twomb = "currency",
\t\t\t\tnodes = {
\t\t\t\t\t{ name = "Prodigal Offspring", kind = "notable",
\t\t\t\t\t\teffectEn = "25% chance to birth 3 extra currency, 3% for 10",
\t\t\t\t\t\teffectRu = "25 % шанс на 3 дополнительные валюты, 3 % — на 10" },
\t\t\t\t\t{ name = "Fertile Genesis", kind = "notable",
\t\t\t\t\t\teffectEn = "Currency is rolled an additional time, keeping the rarest outcome",
\t\t\t\t\t\teffectRu = "Валюта перебрасывается ещё раз, берётся самый редкий исход" },
\t\t\t\t\t{ name = "Wild Growth", kind = "notable",
\t\t\t\t\t\teffectEn = "2% chance for birthed currency to drop as a full stack",
\t\t\t\t\t\teffectRu = "2 % шанс, что валюта выйдет полным стеком" },
\t\t\t\t\t{ name = "Mutation Cultivation", kind = "notable",
\t\t\t\t\t\teffectEn = "25% extra currency; 100% increased chance for Graft Implants and Foulborn",
\t\t\t\t\t\teffectRu = "25 % к дополнительной валюте; вдвое выше шанс имплантов и Foulborn" },
\t\t\t\t},
\t\t\t},
\t\t\t{
\t\t\t\twomb = "unique",
\t\t\t\tnodes = {
\t\t\t\t\t{ name = "Recessive Genes", kind = "notable",
\t\t\t\t\t\teffectEn = "Uniques are rolled an additional time, keeping the rarest outcome - biases to T3/T4",
\t\t\t\t\t\teffectRu = "Уникалка перебрасывается ещё раз, берётся редчайший исход — уклон к T3/T4" },
\t\t\t\t\t{ name = "Cleansed of Impurity", kind = "notable",
\t\t\t\t\t\teffectEn = "Birthed uniques have 100% reduced chance to be Foulborn",
\t\t\t\t\t\teffectRu = "Осквернённая (Foulborn) версия не выпадет" },
\t\t\t\t\t{ name = "Foulborn Gluttony", kind = "notable",
\t\t\t\t\t\teffectEn = "30% chance for an extra item; +30% chance to be Foulborn",
\t\t\t\t\t\teffectRu = "30 % шанс на лишний предмет; +30 % к шансу Foulborn" },
\t\t\t\t},
\t\t\t},
\t\t},
\t\twombPassivesSource = "poewiki The_Genesis_Tree, снято 2026-10-20; это подмножество, а не весь список",'''

if ANCHOR not in text:
    raise SystemExit("anchor not found")

text = text.replace(ANCHOR, BLOCK, 1)

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("genesis passives added")
