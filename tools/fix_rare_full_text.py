"""Say out loud what a Chaos Orb does to a full rare: it removes a RANDOM modifier.

The plan keeps Chaos as the cheapest step - about one chaos against ten for a Divine - but the explanation
presented it as "swapping a modifier", which reads as if you choose which one. You do not. On a six-mod rare
that means the roll can take the best affix, which is the most expensive mistake the advisor could let a player
make quietly. Targeted replacement needs the Omen of Whittling, and that is now stated in both languages.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Data", "league_0_5_5.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

OLD_RU = """\t\t\twhy = {
\t\t\t\tmin = "Все шесть модов заняты: добавить некуда. Остаётся сменить мод, перебросить числа, поднять качество — или Vaal последним и необратимо.",
\t\t\t\tmax = "Хаос меняет один мод, Divine подстраивает числа, качество добавляется в конце; Vaal — последним.",
\t\t\t},"""

NEW_RU = """\t\t\twhy = {
\t\t\t\tmin = "Все шесть модов заняты: добавить некуда. Chaos — самый дешёвый шаг, но он снимает "
\t\t\t\t\t.. "СЛУЧАЙНЫЙ мод: может уйти лучший. Чтобы заменить именно слабый, нужен Omen of Whittling — "
\t\t\t\t\t.. "с ним снимается мод худшего тира. Если моды устраивают, ничего не трогайте и поднимите "
\t\t\t\t\t.. "качество — это дешевле.",
\t\t\t\tmax = "Omen of Whittling отбирает худший мод, Chaos заменяет его, Divine подстраивает числа, "
\t\t\t\t\t.. "качество добавляется в конце; Vaal — последним и необратимо.",
\t\t\t},"""

OLD_EN = """\t\t\twhyEn = {
\t\t\t\tmin = "No free slots: a Chaos Orb swaps a random modifier for a new one.",
\t\t\t\tmax = "An Omen restricts which modifier is removed, then Chaos - this targets the junk affix.",
\t\t\t},"""

NEW_EN = """\t\t\twhyEn = {
\t\t\t\tmin = "No free slots. Chaos is the cheap move, but it removes a RANDOM modifier - it can take "
\t\t\t\t\t.. "your best one. To replace a specific weak affix you need the Omen of Whittling. If the "
\t\t\t\t\t.. "modifiers are fine, leaving them alone and raising quality is cheaper.",
\t\t\t\tmax = "The Omen of Whittling picks the worst-tier modifier, Chaos replaces it, Divine tunes the "
\t\t\t\t\t.. "values, quality closes; Vaal last and irreversible.",
\t\t\t},"""

for old, new, label in ((OLD_RU, NEW_RU, "ru"), (OLD_EN, NEW_EN, "en")):
    if old in text:
        text = text.replace(old, new, 1)
        print("replaced", label)
    else:
        print("MISS", label)

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("written")
