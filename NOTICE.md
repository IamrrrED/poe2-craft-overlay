# Сторонние данные и их условия / Third-party data and its terms

MIT (см. `LICENSE`) покрывает **код и документацию этого проекта**. Таблицы в `src/Data/` — нет: они собраны из
других источников, и у каждого свои условия. Этот файл фиксирует, что откуда взялось, чтобы не выдавать чужое
за своё и не обещать лишних прав.

## Что внутри и откуда

| Где | Что | Источник | Условия источника |
|---|---|---|---|
| `src/Data/mods.lua`, `bases.lua`, `coe_*` | моды, базы, веса, тиры | [Path of Building (Community)](https://github.com/PathOfBuildingCommunity/PathOfBuilding) | **GPL-3.0** |
| `src/Data/league_0_5_5.lua`, омены, эссенции | механики, тексты эффектов | официальные патчноуты, [poe2wiki](https://poe2wiki.net/), [poe2db](https://poe2db.tw/) | данные игры (GGG) + тексты вики |
| `src/Data/ru_bases.lua`, `ru_stats_*.lua`, `display_names_ru_*.lua` | официальные русские названия | торговый сайт `ru.pathofexile.com` | данные игры (GGG) |
| `src/Data/prices.lua` | снимок цен валют | [poe.ninja](https://poe.ninja/poe2/economy) | условия poe.ninja (не для перепубликации) |
| `docs/*.md` | цитаты из гайдов, видео, вики | соответствующие авторы | короткие цитаты с указанием источника |

## Что это значит на практике

1. **Код — MIT.** Берите, меняйте, распространяйте, коммерчески используйте — с сохранением уведомления.
2. **Данные — не MIT.** Они остаются под условиями источников. Если вы используете проект целиком, ограничения
   источников переходят и на вас.
3. **GPL-3.0 у Path of Building** — самый строгий пункт: если вы распространяете сборку, включающую
   PoB-производные таблицы, разумно распространять её под GPL-3.0 (или генерировать эти таблицы у
   пользователя скриптом, а не поставлять в репозитории).
4. **Имена и тексты — собственность Grinding Gear Games.** Инструмент использует их по прямому назначению
   (показать предмет, найти его на трейде), но это не даёт прав на переиздание данных игры.
5. **Цены poe.ninja** лучше получать в рантайме (проект так и делает: суточный кэш), а не поставлять снимком.

## Если нужен «чистый» репозиторий

Порядок действий, если захотите убрать любые сомнения:

1. Вынести `src/Data/` в отдельный репозиторий с лицензией **GPL-3.0** и указанием, что это производные данные.
2. Оставить в основном репозитории скрипты `tools/fetch_*.py`, которые собирают таблицы у пользователя.
3. Убрать `prices.lua` из репозитория: цена валют и так обновляется из poe.ninja при первом запросе.

Проект к этому готов: генераторы данных лежат в `tools/`, и ни один из них не требует закрытых ключей.

---

# English

MIT (see `LICENSE`) covers **this project's code and documentation**. The tables in `src/Data/` are not covered:
they were assembled from other sources, each with its own terms. This file records what came from where, so that
nothing is passed off as original and no rights are promised that cannot be granted.

## What is inside and where it came from

| Location | Content | Source | Source terms |
|---|---|---|---|
| `src/Data/mods.lua`, `bases.lua`, `coe_*` | modifiers, bases, weights, tiers | [Path of Building (Community)](https://github.com/PathOfBuildingCommunity/PathOfBuilding) | **GPL-3.0** |
| `src/Data/league_0_5_5.lua`, omens, essences | mechanics, effect texts | official patch notes, [poe2wiki](https://poe2wiki.net/), [poe2db](https://poe2db.tw/) | game data (GGG) + wiki text |
| `src/Data/ru_bases.lua`, `ru_stats_*.lua`, `display_names_ru_*.lua` | official Russian names | the trade site `ru.pathofexile.com` | game data (GGG) |
| `src/Data/prices.lua` | currency price snapshot | [poe.ninja](https://poe.ninja/poe2/economy) | poe.ninja terms (not for redistribution) |
| `docs/*.md` | quotations from guides, videos, wiki | their respective authors | short quotations with attribution |

## What that means in practice

1. **The code is MIT.** Use it, change it, redistribute it, use it commercially — keep the notice.
2. **The data is not MIT.** It stays under the sources' terms. If you use the project as a whole, those
   restrictions apply to you as well.
3. **Path of Building's GPL-3.0 is the strictest item**: if you distribute a build that includes PoB-derived
   tables, the reasonable choice is to distribute it under GPL-3.0 (or to generate those tables on the user's
   machine with a script instead of shipping them).
4. **Names and texts belong to Grinding Gear Games.** The tool uses them for their intended purpose (show an item,
   find it in trade), but that grants no right to republish the game's data.
5. **poe.ninja prices** are better fetched at runtime (the project does exactly that, with a daily cache) than
   shipped as a snapshot.

## If you want a "clean" repository

Steps to remove any doubt:

1. Move `src/Data/` into a separate repository under **GPL-3.0**, stating that it is derived data.
2. Keep only the `tools/fetch_*.py` scripts in the main repository, so tables are assembled by the user.
3. Drop `prices.lua` from the repository: currency prices are refreshed from poe.ninja on first request anyway.

The project is ready for this: the data generators live in `tools/` and none of them needs a private key.
