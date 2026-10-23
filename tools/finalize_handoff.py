"""Bring the handoff up to the current state and add explicit resume instructions."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "docs", "SESSION-HANDOFF.md")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

text = text.replace("**Тесты: 2047, все проходят.**", "**Тесты: 2059, все проходят.**", 1)

NEW_FIXES = """7. **Снимок цен был от 2026-10-06** — обновлён с poe.ninja (409 позиций). Крупные процентные скачки
   проверил на предмет систематической ошибки: её нет, это неликвид с шумной ценой.
8. **Лоты трейда не конвертировались в хаос.** У poe.ninja в `core.rates` всего ДВА ключа (`exalted`,
   `chaos`), поэтому `transmute`/`regal`/`alch` падали с «none could be converted». Конвертация теперь
   берёт наш снимок (409 позиций), курс — запасной путь. База ещё и сверяется со списком трейда (3129
   баз) до запроса: выдуманная база получает «не найдена» + похожие варианты, а не голый 400.
9. **Genesis Tree: узлы внесены как данные** подмножеством, с источником (poewiki, 2026-10-20) и пометкой,
   что это не весь список. Пассивки свободно перераспределяются — это отдельное утверждение в тесте.
10. **Vaal: ставка опубликована.** poewiki даёт четыре РАВНЫХ исхода по 25 % для снаряжения, один из них —
    «стать редким с шестью случайными модами», то есть уничтожение крафта. Для самоцветов «+1 к уровню»
    = 1/8. Предупреждение шага теперь называет эти числа.

"""

marker = "### Открытые вопросы"
if marker not in text:
    raise SystemExit("open questions marker not found")

text = text.replace(marker, NEW_FIXES + marker, 1)

OLD_OPEN = """### Открытые вопросы

- **Имя базы для трейда.** `Charming Tiara` отвергается как `unknown item base type`, `Ceremonial Robe`
  принимается. Нужна сверка имени базы с данными трейда.
- **Nodы Genesis Tree** (`C8`) не вынесены в данные; в карточку шага (`C9`) сознательно не добавлены.
- **Живой WebView2 не проверялся** — только headless-отрисовка HTML и сборка C#.
- **`craft_memory.lua`** пишется при каждом `craft_step`, в том числе из тестов; после прогона тестов
  память содержит тестовый предмет. На совет это влияет только до первого нового захвата."""

NEW_OPEN = """### Открытые вопросы

- **Живой WebView2 не проверялся** — только headless-отрисовка HTML и сборка C#. Нужен один запуск панели
  и один захват: что реально произошло в живом окне, видно по `overlay/bin/Release/net8.0-windows/overlay.log`
  и `src/last_item.txt`.
- **`craft_memory.lua`** пишется при каждом `craft_step`, в том числе из тестов; после прогона тестов память
  содержит тестовый предмет. На совет влияет только до первого нового захвата, но лучше разделить рабочую
  и тестовую память.
- **Genesis Tree (`C9`)** — пассивки есть в данных, но в карточку шага сознательно не добавлены.

### Как продолжить в новой сессии

1. `powershell -NoProfile -ExecutionPolicy Bypass -File .\\tests.ps1` — должно быть **2059 passed, 0 failed**.
2. `dotnet build overlay\\Overlay.csproj -c Release` — должно быть `Ошибок: 0`. Пока панель запущена,
   сборка падает с MSB3021 — это не ошибка кода.
3. Прочитать `docs/mentor-research.md` — там разбор 32 видео по текущей лиге, аудит лиги и таблица
   пробелов по poe2db.
4. **Не выдумывать числа.** Если данных нет — искать в интернете (poewiki, poe2db, poe.ninja), а если
   источника нет, помечать «не проверено», а не «проверено». В этой сессии три таких утверждения были
   закрыты именно поиском, а два оказались ложными: «Regal не найдёт места» и «ставка Vaal не измерена».
5. **Проверять подозрения, а не верить им.** Крупные скачки цен выглядели как ошибка конвертации —
   проверка показала, что это неликвид. База `Charming Tiara` выглядела как баг парсера — это была
   выдуманная тестовая база.
"""

if OLD_OPEN in text:
    text = text.replace(OLD_OPEN, NEW_OPEN, 1)
    print("open questions replaced")
else:
    print("open questions MISS — appending instead")
    text = text.rstrip() + "\n\n" + NEW_OPEN

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("handoff updated")
