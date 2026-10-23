"""Put the current state at the top of the handoff document.

The 261 lines below describe the base infrastructure (engine host, hotkeys, tray, capture) and are still
accurate. What they do not mention is the mentor work and the fixes that followed, which is what a new session
needs first.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "docs", "SESSION-HANDOFF.md")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

MARKER = "## АКТУАЛЬНО: наставник"

if MARKER in text:
    print("already present")
    raise SystemExit(0)

SECTION = """## АКТУАЛЬНО: наставник (обновлено 2026-10-20)

Разделы ниже описывают **инфраструктуру** (движок, хоткей, захват, трей) — они верны. Наставник и
последовавшие исправления описаны здесь.

**Тесты: 2047, все проходят.** `powershell -NoProfile -ExecutionPolicy Bypass -File .\\tests.ps1`.
Сборка: `dotnet build overlay\\Overlay.csproj -c Release`. Тесты гоняют файловый протокол движка напрямую,
поэтому работают без запущенной панели.

### Что умеет

| Область | Модуль |
|---|---|
| Способы крафта с шансами | `Craft/Advisor.lua`, правила в `Data/league_0_5_5.lua` |
| Пошаговый совет | `Craft/Coach.lua` (шаг, почему, что дальше, память) |
| Уроки «почему так» | `Craft/Lesson.lua` (24 урока) |
| Продвинутые техники | `Craft/Techniques.lua` (5, с предусловиями) |
| Курс наставника по предмету | `Craft/Curriculum.lua` (7 пунктов) |
| Проверка утверждений из гайдов | `Craft/Claims.lua` (верификаторы + честное «не проверено») |
| Крафт против покупки | `Craft/CraftOrBuy.lua` + живая цена рынка |
| Режим «Новичок» | `overlay/Ui/panel.html`, по умолчанию включён |

**Живая цена.** `tools/market_price.js` спрашивает трейд (та же база + те же моды, лестница допусков:
точное → −20 % → один префикс и один суффикс → без минимума) и переводит в хаос по курсу poe.ninja.
Бюджет и кулдауны берутся из `mcp-market/lib/http.js` и проверяются ДО запроса. Стоимость крафта —
среднее, поэтому вердикт выносится только при разнице больше 20 %.

### Исправлено в этой сессии (каждое подтверждено тестом)

1. **Имплисит считался «неопознанным модом»** → `affixSplitComplete=false` на любом предмете с
   имплиситом, и советник предлагал валюту на мод для полного предмета. Теперь блок имплисита
   распознаётся по аннотации и не считается аффиксом.
2. **`Coach.state` брал счётчики из `affixCount` и вычитал из жёсткой тройки** → у полного Magic
   показывал два свободных префикса. Теперь потолок берётся из `item.affixCaps`.
3. **`magic_full` утверждало, что «Regal не найдёт места»** → полный Magic объявлялся законченным.
   Regal поднимает редкость и **добавляет** третий мод; правило исправлено, 6 тестов переписаны.
4. **Английский текст в русской панели, три слоя**: `Advisor` (`reasonEn or reason`), `Coach`
   (вердикт памяти приклеивался к чужому шагу), `api.lua` (12 мест `titleEn or title`).
5. **`rare_full` называл Chaos «сменой мода»** — теперь сказано, что снимается СЛУЧАЙНЫЙ мод и что
   точечно снимает Omen of Whittling.
6. **Снимок цен был от 2026-10-06** — обновлён (409 позиций).

### Открытые вопросы

- **Имя базы для трейда.** `Charming Tiara` отвергается как `unknown item base type`, `Ceremonial Robe`
  принимается. Нужна сверка имени базы с данными трейда.
- **Nodы Genesis Tree** (`C8`) не вынесены в данные; в карточку шага (`C9`) сознательно не добавлены.
- **Живой WebView2 не проверялся** — только headless-отрисовка HTML и сборка C#.
- **`craft_memory.lua`** пишется при каждом `craft_step`, в том числе из тестов; после прогона тестов
  память содержит тестовый предмет. На совет это влияет только до первого нового захвата.

"""

first_newline = text.find("\n")
head = text[: first_newline + 1]
rest = text[first_newline + 1:]

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(head + "\n" + SECTION + rest)
print("handoff updated")
