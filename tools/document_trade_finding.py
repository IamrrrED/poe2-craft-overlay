"""Record that the trade API CAN price a rare by its modifiers - the opposite of what the doc claimed."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "docs", "mentor-research.md")

with io.open(DOC, encoding="utf-8") as handle:
    text = handle.read()

anchor = "Снимок цен содержит только валюты, руны, эссенции, ритуал, брешь, веризий и души."
addition = (
    "**Поправка от 19.10: утверждение ниже о том, что цену редкого получить негде, — неверно.** Проверено\n"
    "живым запросом, см. раздел «Цена редкого по модам: проверено запросом» ниже. Абзац сохранён как есть,\n"
    "чтобы было видно, что именно было неправильно.\n"
    "\n"
)

if "Цена редкого по модам: проверено запросом" in text:
    print("already documented")
else:
    if anchor not in text:
        raise SystemExit("anchor not found")
    text = text.replace(anchor, addition + anchor, 1)

    # Append the verification section before the quality section.
    marker = "## Качество выше +20 %: все пути"
    section = (
        "## Цена редкого по модам: проверено запросом\n"
        "\n"
        "Ранее я утверждал, что цену готового редкого предмета взять негде: «редкие продаются поштучно, API их\n"
        "не отдаёт». **Это неверно.** Торговый API умеет искать по модам, и цена получается.\n"
        "\n"
        "Проверено скриптом `tools/probe_trade_rare.js` на существующей библиотеке `mcp-market/lib/trade.js`:\n"
        "\n"
        "| Шаг | Результат |\n"
        "|---|---|\n"
        "| Список лиг | `Forbidden Rites \\| HC Forbidden Rites \\| Runes of Aldur \\| …` |\n"
        "| Разбор модов в stat-id | `# to maximum Life` → `explicit.stat_3299347043`, `#% to Chaos Resistance` → `explicit.stat_2923486259` |\n"
        "| Поиск + чтение лотов | **10 000 совпадений**, 5 лотов с ценами |\n"
        "| С фильтром базы (`Ceremonial Robe`) | **546 совпадений**, все одной базы, цены `1 transmute` и `1 exalted` |\n"
        "\n"
        "**Что уже есть в проекте** (я этого не использовал): `mcp-market` — сервер `poe2-market-mcp` с 24\n"
        "инструментами (`price_check`, `bulk_exchange`, `quota_status`, `resolve_stat`, …), кэшем в\n"
        "`mcp-market/.cache` и учётом лимитов. Источники: **pathofexile.com/api/trade2** (живой поиск и лоты),\n"
        "**poe2scout** (цены уникалов и тренды), **poe.ninja** (exchange и распределение классов).\n"
        "\n"
        "Курс валют проверен отдельно: `poe.ninja/poe2/api/economy/exchange/current/overview?league=Forbidden%20Rites&type=Currency`\n"
        "отдаёт 200, 51 строку, `chaos = 10.09` при `primary = divine`.\n"
        "\n"
        "### Что мешает сделать это «просто» и требует решения\n"
        "\n"
        "1. **Имя базы должно быть тем, что знает трейд.** `Charming Tiara` дал `400 Unknown item base type`,\n"
        "   а `Ceremonial Robe` — работает. Нужно либо брать имя из данных трейда, либо фильтровать по классу.\n"
        "2. **Без фильтра базы — мусор.** 10 000 совпадений, самые дешёвые по 1 трансмуту: это не цена\n"
        "   сопоставимого предмета. Нужна база и, вероятно, ilvl.\n"
        "3. **Цены приходят в разных валютах** (`transmute`, `exalted`, `regal`) — их надо приводить к хаосу\n"
        "   через курс poe.ninja.\n"
        "4. **Брать медиану, а не минимум.** Самые дешёвые лоты — обычно хлам.\n"
        "5. **Лимиты.** Торговый API строгий; у `mcp-market` уже есть бюджет и кулдауны в `.cache` — надо\n"
        "   переиспользовать их, а не ходить напрямую.\n"
        "\n"
        "### Как это должно быть встроено\n"
        "\n"
        "Lua-движок сеть не трогает. Правильный путь: C#-хост вызывает Node-скрипт на `mcp-market/lib`, получает\n"
        "цену, и передаёт её в уже существующий `craft_or_buy` вместе со стоимостью крафта. Тогда поле ввода\n"
        "цены остаётся как ручной режим и запасной вариант, а автоцена — как обычный.\n"
        "\n"
    )
    if marker not in text:
        raise SystemExit("quality section marker not found")
    text = text.replace(marker, section + marker, 1)

    with io.open(DOC, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print("documented")
