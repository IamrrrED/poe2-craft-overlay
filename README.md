# PoE2 Craft Overlay

Помощник по крафту для **Path of Exile 2**: наводите предмет в игре, нажимаете **Ctrl+Q** — панель показывает
не «всю информацию о предмете», а **маршрут**: цель, три шага и точку остановки. Каждый шаг опирается на
правило, проверенное по независимым источникам, и это правило подписано прямо в карточке.

[English description below ↓](#english)

---

## Что это

Панель-оверлей (WinForms + WebView2) и движок на Lua, который разбирает текст предмета из буфера обмена,
считает шансы и цену и объясняет решение. Два языка интерфейса и движка: **русский и английский** —
переключаются на лету, включая прозу, названия предметов и валют.

**Главная идея:** новичку не нужен справочник. Ему нужен ответ «что нажать сейчас, сколько это стоит и когда
остановиться». Поэтому панель начинается с маршрута, а аналитика убрана за «Показать всё».

## Возможности

| Что | Детали |
|---|---|
| **Маршруты «цель → 3 шага → стоп»** | собираются только из правил, прошедших порог достоверности (см. ниже) |
| **Проверка слотов** | «дезекрация уже стоит → второй не будет» (C8), «эссенция заменит crafted-мод» (C1) |
| **Цена с трейда** | запрос уходит на хост **того же языка**, что и панель: русский предмет — на `ru.pathofexile.com`, английский — на `www.pathofexile.com` |
| **Стоп-правило** | считает бюджет попытки (`цена × попыток до 90 %`) и говорит, когда покупать выгоднее |
| **Контекст игрока** | лига или SSF, сколько валюты, предмет на продажу или носить — ответ меняется |
| **Наставник** | принцип шага (свёрнут), что изменилось с прошлого крафта, «что я могу знать, а что нет» |
| **Два языка целиком** | панель, движок, названия предметов и валют, отчёт о покрытии перевода |

## Достоверность советов

Правила не придуманы: они собраны из **22 расшифровок видео** и **10 письменных первоисточников** (патчноуты
0.5.0, вики оменов и дезекрации, poe2db, гайды) и принимаются только при **≥5 независимых подтверждениях и
нуле противоречий**. Что не прошло — в совет не попадает.

Отчёт с цитатами и счётом: [`docs/craft-consensus-0.5.md`](docs/craft-consensus-0.5.md).

Пример из практики: `Omen of Homogenising Exaltation` в лиге 0.5 недоступен — отключён от выпадения и на обмене
валют есть только в Standard. Поэтому способ **не предлагается вообще**, а не помечается «недоступно»: советник
не должен отправлять игрока за предметом, которого нет.

## Требования

- **Windows 10/11** x64
- **.NET 8 SDK** (сборка панели)
- **WebView2 Runtime** (обычно уже установлен)
- **Node.js 18+** — только для рыночного скрипта (`tools/market_price.js`)
- Собранный движок `headless/bin/Release/net8.0/PoE2 Craft Engine.exe` (Lua 5.1/LuaJIT)

## Сборка и запуск

```powershell
dotnet build overlay\Overlay.csproj -c Release
.\overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe
```

Панель появляется по **Ctrl+Q** при наведённом предмете. Язык — в шапке (RU/EN) или в меню трея.

## Проверки

Одна команда на всё:

```powershell
powershell -ExecutionPolicy Bypass -File tools\check_all.ps1
```

Внутри: набор движка (2208 проверок в Lua-хосте), таблицы панели, строки C#-хоста, причины отказа рынка,
актуальность сгенерированного корпуса предметов, скан данных на «сырые» переводы строк, сборка.

## Архитектура

```
src/                 движок: разбор предмета, правила, советник, рынок (Lua)
  Item/              парсер, перевод RU<->EN, модификаторы, линии
  Craft/             советник, тренер, маршруты, память крафта, рецепты
  Mcp/api.lua        единая точка вызова, языковой гейт
  Data/              правила лиги, базы, омены, цены, словари имён
overlay/             панель WinForms + WebView2 (PanelForm, Ui/panel.html)
mcp-market/lib       клиент трейда: поиск, статы, курсы, лимиты (Node.js)
tools/               рыночный скрипт, генераторы данных, проверки (Python/PowerShell)
docs/                отчёты, консенсус по правилам, скриншоты
```

## Источники данных и благодарности

- [Path of Building (Community)](https://github.com/PathOfBuildingCommunity/PathOfBuilding) — данные модов и баз
- [poe2db](https://poe2db.tw/) — датамайн предметов и модификаторов
- [Path of Exile 2 Wiki](https://poe2wiki.net/) — формулировки оменов и дезекрации
- [poe.ninja](https://poe.ninja/poe2/economy) — курсы валют (снимок на сутки)
- Официальный трейд — цены и лиги
- Авторы гайдов и видео — техники, которые затем проверялись по данным

## Ограничения, о которых честно

- Официальной таблицы **имён аффиксов** нет: в имени предмета переводится только база, слова аффикса остаются
  как в клиенте.
- Часть методов не оценена в цене (нет цен компонентов в снимке) — видно как «методов без цены: N».
- Цена готового предмета не выдумывается: панель даёт стоп-правило и ссылку на поиск.
- C7 (сочетание «великого» и «единого» возвышения) невозможно проверить в лиге, потому что второго омена там
  нет; правило остаётся открытым и в совет не входит.

## Лицензия

Код — **MIT** ([`LICENSE`](LICENSE)). Данные в `src/Data/` — **нет**: они собраны из Path of Building (GPL-3.0), poe2db, вики и трейда, у каждого источника свои условия. Полный разбор — [`NOTICE.md`](NOTICE.md).

## Правовая оговорка

Неофициальный фанатский проект. Не связан с Grinding Gear Games. Path of Exile 2 и его данные принадлежат GGG.
Используйте на свой риск: автоматизация действий в игре может нарушать правила игры.

---

<a id="english"></a>
# PoE2 Craft Overlay — English

A crafting assistant for **Path of Exile 2**: hover an item in game, press **Ctrl+Q**, and the panel shows not
"everything about the item" but a **route**: the goal, three steps, and the point where you stop. Every step
stands on a rule verified against independent sources, and the rule is labelled right on the card.

## What it is

An overlay panel (WinForms + WebView2) plus a Lua engine that reads the item text from the clipboard, works out
the odds and the cost, and explains the decision. Both the interface and the engine speak **Russian and
English**, switchable on the fly, including prose, item names and currency names.

**The idea:** a beginner does not need a reference book. They need an answer to "what do I click now, what does
it cost, and when do I stop". So the card opens with the route and keeps the analysis behind "Show everything".

## Features

| Feature | Detail |
|---|---|
| **Routes: goal → 3 steps → stop** | built only from rules that passed the evidence bar (see below) |
| **Slot checks** | "the desecration slot is taken, a second one will not happen" (C8), "an essence replaces the crafted modifier" (C1) |
| **Trade price** | the query goes to the host of the **same language** as the panel: a Russian item to `ru.pathofexile.com`, an English one to `www.pathofexile.com` |
| **Stop rule** | the cost of a proper attempt (`price × attempts for 90 %`) and the point at which buying wins |
| **Player context** | league or SSF, currency at hand, item for sale or to wear — the answer changes |
| **Mentor** | the principle behind a step (collapsed), what changed since the last craft, "what I can and cannot know" |
| **Full bilingual** | panel, engine, item and currency names, plus a coverage report |

## How the advice is validated

The rules are not invented: they were extracted from **22 video transcripts** and **10 primary written sources**
(official 0.5.0 patch notes, wiki pages for omens and desecration, poe2db, guides) and are accepted only with
**≥5 independent confirmations and zero contradictions**. Anything below that bar never reaches the advice.

Full report with quotes and counts: [`docs/craft-consensus-0.5.md`](docs/craft-consensus-0.5.md).

A real example: `Omen of Homogenising Exaltation` cannot be obtained in a 0.5 league — disabled from dropping and
restricted to Standard on the currency exchange. So the method is **not offered at all**, rather than marked
"unavailable": an adviser must not send a player after an item that does not exist.

## Requirements

- **Windows 10/11** x64
- **.NET 8 SDK** (panel build)
- **WebView2 Runtime** (usually already installed)
- **Node.js 18+** — for the market script only (`tools/market_price.js`)
- A built engine at `headless/bin/Release/net8.0/PoE2 Craft Engine.exe` (Lua 5.1/LuaJIT)

## Build and run

```powershell
dotnet build overlay\Overlay.csproj -c Release
.\overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe
```

The panel appears on **Ctrl+Q** with an item hovered. Language: the header switch (RU/EN) or the tray menu.

## Checks

One command for everything:

```powershell
powershell -ExecutionPolicy Bypass -File tools\check_all.ps1
```

It runs the engine suite (2208 checks inside the Lua host), the panel tables, the C# host strings, the market
refusal reasons, the freshness of the generated item corpus, a raw-newline scan over the data, and the build.

## Architecture

```
src/                 engine: item parsing, rules, adviser, market (Lua)
  Item/              parser, RU<->EN translation, modifiers, lines
  Craft/             adviser, coach, routes, craft memory, recipes
  Mcp/api.lua        single call entry point, language gate
  Data/              league rules, bases, omens, prices, name dictionaries
overlay/             WinForms + WebView2 panel (PanelForm, Ui/panel.html)
mcp-market/lib       trade client: search, stats, rates, quotas (Node.js)
tools/               market script, data generators, checks (Python/PowerShell)
docs/                reports, rule consensus, screenshots
```

## Data sources and credits

- [Path of Building (Community)](https://github.com/PathOfBuildingCommunity/PathOfBuilding) — modifier and base data
- [poe2db](https://poe2db.tw/) — datamined items and modifiers
- [Path of Exile 2 Wiki](https://poe2wiki.net/) — omen and desecration wording
- [poe.ninja](https://poe.ninja/poe2/economy) — currency rates (daily snapshot)
- The official trade site — prices and leagues
- The guide and video authors — the techniques, which were then checked against data

## Honest limitations

- There is no official table of **affix names**: inside an item name only the base is translated, the affix
  words stay as the client prints them.
- Some methods have no price (components missing from the snapshot) — shown as "methods without a price: N".
- The price of the finished item is never invented: the panel gives a stop rule and a search link instead.
- C7 (combining Greater and Homogenising Exaltation) cannot be tested in a league, because the second omen is
  not there; the rule stays open and is excluded from the advice.

## Licence

The code is **MIT** ([`LICENSE`](LICENSE)). The data in `src/Data/` is **not**: it was assembled from Path of Building (GPL-3.0), poe2db, the wiki and the trade site, each with its own terms. Full breakdown: [`NOTICE.md`](NOTICE.md).

## Legal

An unofficial fan project, not affiliated with Grinding Gear Games. Path of Exile 2 and its data belong to GGG.
Use at your own risk: automating in-game actions may violate the game's rules.
