"""Record that craft-vs-buy is no longer blocked: the player supplies the market price."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "docs", "mentor-research.md")

with io.open(DOC, encoding="utf-8") as handle:
    text = handle.read()

old = (
    "| **«Крафт vs купить»** | ⚠️ **частично**: стоимость крафта считается точно, цена готового предмета — "
    "**нет в данных** |"
)
new = (
    "| **«Крафт vs купить»** | ✅ **работает**: стоимость крафта считает движок, цену готового предмета "
    "вводит игрок — сравнение настоящее |"
)

if old in text:
    text = text.replace(old, new, 1)
    print("table row updated")
elif "цену готового предмета вводит игрок" in text:
    print("already updated")
else:
    print("table anchor MISS")

anchor = "### Почему «крафт vs купить» только частично"
replacement = (
    "### «Крафт vs купить»: как обошлись без цен на готовые предметы\n"
    "\n"
    "Снимок цен содержит только валюты, руны, эссенции, ритуал, брешь, веризий и души. Публичного источника\n"
    "цен на «редкий предмет с вот этими модами» не существует — редкие продаются поштучно, и никакой API их не\n"
    "отдаёт. Раньше это считалось блокером.\n"
    "\n"
    "Решение: **цену вводит сам игрок**. Он смотрит трейд, вводит число в хаосе — и дальше сравнение\n"
    "арифметическое на двух известных величинах:\n"
    "\n"
    "* стоимость крафта движок считает точно (веса модов × попытки × цены валют);\n"
    "* цену рынка вводит человек, и панель прямо пишет, что **её не проверяет**;\n"
    "* вердикт выносится только когда разница **больше 20 %** — потому что стоимость крафта это **среднее**,\n"
    "  и разница в 5 % неотличима от разброса.\n"
    "\n"
    "Так задача решена без выдуманных чисел: обе стороны сравнения имеют названный источник.\n"
)

if anchor in text:
    text = text.replace(anchor, replacement, 1)
    print("explanation section replaced")
elif "«Крафт vs купить»: как обошлись без цен" in text:
    print("explanation already replaced")
else:
    print("explanation anchor MISS")

with io.open(DOC, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("written")
