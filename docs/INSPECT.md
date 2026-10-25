# Разведка владений: читать и оценивать, ничего не менять / Inventory sweep: read and judge, change nothing

Цель: **оценка** того, что у персонажа уже есть, без всякого влияния на его ценность. Никакого фарма, покупок,
крафта, перемещения и продажи предметов.

## Что делает

1. Находит окно игры и **читает зону из `Client.txt`** — файл лога игры, ничего больше.
2. Читает предметы: наводит курсор на слоты и нажимает **Ctrl+C** (копирование предмета — то же, что делает
   игрок, чтобы посмотреть текст).
3. Если ничего не прочиталось, **один раз** нажимает `I` (инвентарь) и повторяет проход. Ключ `I` —
   переключатель: если панель была открыта, он её закроет, поэтому нажимается только когда чтение не удалось.
4. В **убежище** (определяется по логу) может **кликнуть по вкладке тайника**, чтобы прочитать следующую
   страницу. Клик по вкладке не может переместить предмет — он только переключает страницу.
5. Каждый прочитанный предмет отправляет движку и пишет вердикт: есть ли маршрут крафта.
6. Возвращает курсор и буфер обмена на место.

## Жёсткие ограничения

| Ограничение | Значение |
|---|---|
| Запуск | только с `POE2CRAFT_INSPECT=1` |
| Чтений | не больше 40 |
| Кликов | не больше 8, **только по вкладкам** и только в убежище |
| Время | не больше 90 секунд |
| Прерывание | `Escape` или потеря фокуса игрой |
| Буфер и курсор | возвращаются всегда, даже при ошибке |

## Клики по сетке предметов — запрещены

25 октября 2026 клик по сетке взял предмет, а второй клик, который должен был положить его обратно, **чуть не
уронил его на землю**. Поэтому:

- в списке точек клика **нет ни одной сеточной**;
- в цикле кликов стоит явный отказ: точка, помеченная как слот, не нажимается никогда;
- `tools\check_click_safety.py` проверяет это по исходнику и падает, если сеточный клик вернётся.

Вкладка тайника — единственное, что можно нажать: она не берёт предмет в руки.

## Зона: почему из лога

В `Client.txt` есть строка вида

```
2026/10/25 14:14:45 ... [DEBUG Client 11676] Generating level 65 area "HideoutShoreline" with seed 1
```

Внутренний код зоны (`HideoutShoreline`) не зависит от языка клиента, и убежище — это любые зоны с `Hideout` в
коде. Локальное название (`[SCENE] Set Source [Убежище на берегу]`) используется как перекрёстная проверка и для
сообщения человеку. Лог читается с конца (последние 2 МБ), а не целиком: он уже 68 МБ.

## Запуск

```powershell
$env:POE2CRAFT_INSPECT = "1"
.\overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe --inspect --allow-clicks
Remove-Item Env:POE2CRAFT_INSPECT
```

Отчёт: `inspect-report.txt` рядом с exe. Проверить зону отдельно, не трогая игру:

```powershell
.\overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe --zone-check tests\fixtures\zone-hideout.txt
```

---

# English

Purpose: **judge** what the character already owns, without affecting its value. No farming, no purchases, no
crafting, no moving or selling items.

## What it does

1. Finds the game window and **reads the zone from `Client.txt`** — the game's own log, nothing else.
2. Reads items: moves the pointer over slots and sends **Ctrl+C** (copying an item's text, exactly what a player does
   to read it).
3. If nothing was read, presses `I` **once** (inventory) and repeats. `I` is a toggle, so it is only pressed when
   reading failed.
4. **Inside a hideout** (from the log) it may **click a stash tab** to read the next page. A tab click cannot move an
   item — it only changes which page is shown.
5. Sends every item it read to the engine and records the verdict: is there a crafting route.
6. Puts the cursor and the clipboard back.

## Hard limits

| Limit | Value |
|---|---|
| Start | only with `POE2CRAFT_INSPECT=1` |
| Reads | at most 40 |
| Clicks | at most 8, **tabs only**, hideout only |
| Time | at most 90 seconds |
| Abort | `Escape`, or the game losing focus |
| Clipboard and cursor | always restored, even on error |

## Grid clicks are forbidden

On 25 October 2026 a grid click picked an item up and the second click, meant to put it back, **nearly dropped it on
the ground**. Therefore:

- there is **no grid point** in the click list;
- the click loop refuses any point marked as a slot;
- `tools\check_click_safety.py` enforces this against the source and fails if a grid click returns.

A stash tab is the only thing that may be clicked: it cannot take an item into the cursor.

## Why the zone comes from the log

`Client.txt` carries `Generating level 65 area "HideoutShoreline" with seed 1`. The internal area code does not depend
on the client language, and a hideout is any area whose code contains `Hideout`. The localised `[SCENE] Set Source`
line is the cross-check and the human-readable half. The log is read from the end (last 2 MB), because it is already
68 MB.
