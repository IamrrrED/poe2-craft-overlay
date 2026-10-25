# Ограниченный зонд игры / Bounded game probe

Зонд нужен ровно для одного: **проверить, что предмет под настоящим курсором в игре доходит до карточки**. Всё
остальное в проекте либо подставляет текст предмета, либо ждёт, пока человек наведёт курсор и нажмёт Ctrl+Q.

## Что зонд делает — исчерпывающе

1. Находит окно игры по имени процесса (`Path of Exile 2`). Никакого чтения памяти, инъекций и хуков.
2. Двигает **курсор мыши** по 12 точкам: надетые предметы и сетка инвентаря справа, затем те же области слева (игрок может переставить панель).
3. Нажимает **Ctrl+C** — те же клавиши, что нажимает игрок.
4. Читает буфер обмена и проверяет, что там предмет.
5. Если ничего не нашлось — **один раз** нажимает `I` (инвентарь) и повторяет проход.
6. Отдаёт найденный текст **движку** и проверяет, что карточка собралась (engine: card built).
7. Возвращает **курсор и буфер обмена** туда, где они были.

## Чего зонд не делает — по конструкции, а не по обещанию

| Не делает | Почему это гарантировано |
|---|---|
| Кликов мышью | В коде нет ни одного вызова кнопок мыши — только `SetCursorPos` |
| Движения, атаки, умений | Разрешены ровно две клавиши: `I` и `Ctrl+C` |
| Повторов и циклов | Один запуск = один проход, не более 12 попыток и 25 секунд |
| Работы без разрешения | Отказывается стартовать без `POE2CRAFT_PROBE=1` |
| Работы рядом с панелью | Отказывается, если запущен второй экземпляр: два окна дерутся за фокус |
| Порта игры | Ничего не пишет в игру, не подменяет файлы, не читает память |

Это **зонд интерфейса**, как если бы человек один раз навёл курсор на предмет и нажал Ctrl+C. Игрового
преимущества он не даёт: предмет не подбирается, не переносится, не продаётся, ничего не кастуется.

## Как запускать

```powershell
$env:POE2CRAFT_PROBE = "1"                      # разрешение, только на эту консоль
.\overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe --probe-capture
Remove-Item Env:POE2CRAFT_PROBE                 # снять разрешение
```

Отчёт: `overlay\bin\<config>\net8.0-windows\probe-report.txt` (и те же строки в `overlay.log`).

```
game: window 0,0 2560x1440
candidates: 12 points inside the inventory panel
inventory: pressed I once to make sure the panel is open
item: found on attempt 1 at 1792,173 (1246 characters)
clipboard and cursor put back
RESULT: captured «Разрушительное проклятие» in 1 attempts, 585 ms
probe: 1 attempts, 585 ms, cap 12 attempts / 25 s
engine: card built for «Разрушительное проклятие» (40605 characters)
```

Геометрию точек можно проверить **без игры**:

```powershell
.\overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe --probe-candidates 1920 1080
```

Пишет `probe-candidates.txt` со списком точек; `tools\check_all.ps1` проверяет, что все они внутри левой трети
и вертикальной середины окна.

## Что зонд доказывает, а что нет

- **Доказывает:** захват работает на реальном предмете, под настоящим курсором, без участия человека; буфер и
  курсор возвращаются; карточка строится по этому предмету.
- **Не доказывает:** что наведение попадёт на предмет при любом разрешении и любом положении инвентаря — точки
  подобраны по долям окна. Если хит-тест не попал, отчёт скажет «no item under any of the N probed points», и
  это честный ответ, а не молчание.

---

# English

The probe exists for one thing: **prove that an item under the real cursor in the game reaches the card**. Every
other check in this project either fabricates the item text or waits for a human to hover an item and press Ctrl+Q.

## What it does, exhaustively

1. Finds the game window by process name (`Path of Exile 2`). No memory reading, no injection, no hooks.
2. Moves the **mouse pointer** over 8 points inside the inventory panel (left third of the screen, below the
   header).
3. Sends **Ctrl+C** — the same keys a player sends.
4. Reads the clipboard and checks that it holds an item.
5. If nothing was found, presses `I` **once** (inventory) and repeats the pass.
6. Puts the **cursor and the clipboard** back where they were.

## What it never does — by construction, not by promise

| Never | Why it is guaranteed |
|---|---|
| Mouse clicks | There is no mouse-button call in the code — only `SetCursorPos` |
| Movement, attacks, skills | Exactly two keys are allowed: `I` and `Ctrl+C` |
| Loops or retries | One invocation = one pass, at most 8 attempts and 20 seconds |
| Run unasked | Refuses to start without `POE2CRAFT_PROBE=1` |
| Run beside the panel | Refuses when a second instance is running: two windows fighting for focus |
| Touch the game files | Writes nothing into the game, replaces nothing, reads no memory |

It is a **UI probe**, the same as a human hovering an item once and pressing Ctrl+C. It confers no gameplay
advantage: nothing is picked up, moved, sold or cast.

## Running it

```powershell
$env:POE2CRAFT_PROBE = "1"
.\overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe --probe-capture
Remove-Item Env:POE2CRAFT_PROBE
```

Report: `overlay\bin\<config>\net8.0-windows\probe-report.txt` (and the same lines in `overlay.log`).

The hover geometry can be checked **without the game**:

```powershell
.\overlay\bin\Release\net8.0-windows\Poe2CraftOverlay.exe --probe-candidates 1920 1080
```

## What it proves and what it does not

- **Proves:** capture works on a real item under a real cursor without a human; the clipboard and the cursor come
  back; the card is built for that item.
- **Does not prove:** that the hover lands on an item at every resolution and inventory position — the points are
  fractions of the window. When the hit test misses, the report says "no item under any of the N probed points",
  which is an honest answer rather than silence.

## Что выяснилось на практике (и почему первые версии не работали)

1. **Процесс игры называется `PathOfExileSteam`**, а не «Path of Exile 2». Зонд искал по имени процесса и
   отвечал «окно не найдено», пока игра стояла на экране. Теперь он пользуется тем же поиском, что и хоткей:
   класс окна `POEWindowClass` или точный заголовок.
2. **Инвентарь справа, а не слева.** Первые точки были расставлены по гипотезе «панель в левой трети» и не
   попадали ни во что. Точки переставлены по скриншоту живого сеанса 2560×1440.
3. **`async void` в `Main` убивал прогон**: процесс завершался раньше, чем движок отвечал, и отчёт не
   записывался. Теперь вызов ожидается.
4. **Кириллица в JSON экранируется** (`\uXXXX`), поэтому «имя предмета не найдено в карточке» было ложной
   тревогой. Признак карточки теперь структурный: есть `routes` и объём ответа.

---

# English

## What the practice showed (and why the first versions failed)

1. **The game process is called `PathOfExileSteam`**, not "Path of Exile 2". The probe looked it up by process name
   and reported "window not found" while the game sat on screen. It now uses the same finder as the hotkey: window
   class `POEWindowClass` or the exact title.
2. **The inventory is on the right, not the left.** The first points were placed on the guess "panel in the left
   third" and hit nothing. They are now placed from a screenshot of a live 2560x1440 session.
3. **`async void` in `Main` killed the run**: the process exited before the engine answered, so no report was
   written. The call is awaited now.
4. **Cyrillic is escaped in JSON** (`\uXXXX`), so "the item name is not in the card" was a false alarm. The card is
   now judged structurally: it has `routes` and a plausible size.
