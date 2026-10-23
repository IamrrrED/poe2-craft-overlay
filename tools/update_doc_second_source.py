"""Record that the two single-source numbers are now confirmed, and the two false statements fixed."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "docs", "mentor-research.md")

with io.open(DOC, encoding="utf-8") as handle:
    text = handle.read()

old = (
    "Единственное, что осталось **непроверенным**: точные шансы Genesis Tree взяты из одного источника\n"
    "(basicknowledge.xyz, цитирующего заметки 0.5.0), а не сверены со вторым."
)
new = (
    "**Проверено вторым и третьим источником** (после первого прохода):\n"
    "\n"
    "- **Шанс катализатора в Genesis Tree — 15 %** подтверждён независимо: poe2wiki («Catalyst Chance | 15 %»),\n"
    "  fextralife и basicknowledge. Одного источника больше нет.\n"
    "- **Очернение в 0.5.x работает** — это подтверждено: кости, Колодец Душ в Акте 2, три омена на личей.\n"
    "  Раньше это было единственное место, где наши данные шли впереди внешних подтверждений.\n"
    "\n"
    "### Что пришлось исправить после второй проверки\n"
    "\n"
    "| Наше утверждение | Как на самом деле |\n"
    "|---|---|\n"
    "| `Omen of Putrefaction` «противоречит лимиту одного очернённого мода и не подтверждён» | Это **не противоречие, а исключение**: он заменяет все моды, оставляет до шести нераскрытых и **оскверняет** предмет. Подтверждён |\n"
    "| «Ноды Genesis Tree необратимы в рамках настройки» | **Неверно**: пассивные ноды снимаются и ставятся заново **бесплатно**. Совет пугал новичка зря |\n"
    "\n"
    "Заодно добавлено то, чего не было: вторая нода `Additional Duplicate Catalyst Chance` (**30 %** на\n"
    "дополнительный катализатор того же типа), порог `ilvl 65`, с которого среди трёх вариантов появляется мод,\n"
    "который обычно не роллится, лимит «один очернённый мод» и то, что Abyss-омены с 0.5.0 не падают ниже 65-го\n"
    "уровня."
)

if old in text:
    text = text.replace(old, new, 1)
    with io.open(DOC, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print("summary updated")
elif "Проверено вторым и третьим источником" in text:
    print("already updated")
else:
    print("ANCHOR MISS")
