# Ассеты и их лицензии / Assets and their licences

Код проекта — MIT. Ассеты имеют собственные лицензии, и здесь указано, кто что разрешает.

| Файл | Что это | Лицензия |
|---|---|---|
| `overlay/Ui/fonts/Alegreya-Variable.ttf` | засечный шрифт заголовков (кириллица и латиница, 67/67 глифов проверено `tools/check_font_coverage.py`) | **SIL Open Font License 1.1**, текст в `overlay/Ui/fonts/OFL.txt` |
| `overlay/Ui/mushroom.png`, `mushroom.ico`, `mushroom-source.png` | индикатор-гриб (рисунок заказчика проекта) | **MIT**, как и код: © IamrrrED, разрешено использование с сохранением уведомления |
| системные шрифты (`Segoe UI`, `Georgia`) | тело текста и запасные варианты | не поставляются, берутся из ОС |

## Почему так

Раньше в панели лежал шрифт **Fontin** — тот, что использует игра. Он принадлежит Grinding Gear Games, и держать
его в репозитории под MIT нельзя: это распространение чужого шрифта. Alegreya решает задачу честно: засечный
рисунок, близкий по духу, полная кириллица, свободная лицензия, и файл лицензии лежит рядом.

## Если меняете шрифт

1. Возьмите файл с лицензией, разрешающей распространение (OFL, Apache-2.0, CC0).
2. Положите в `overlay/Ui/fonts/` вместе с текстом лицензии.
3. Проверьте кириллицу: `python tools/check_font_coverage.py overlay/Ui/fonts/ВашШрифт.ttf` — должно быть
   `67/67`, иначе в русском интерфейсе появятся квадраты.
4. Укажите шрифт в `@font-face` и в переменной `--display` в `overlay/Ui/panel.html`.

---

# English

The project's code is MIT. The assets have their own licences, listed here.

| File | What it is | Licence |
|---|---|---|
| `overlay/Ui/fonts/Alegreya-Variable.ttf` | the serif used for headings (Latin and Cyrillic, 67/67 glyphs verified by `tools/check_font_coverage.py`) | **SIL Open Font License 1.1**, see `overlay/Ui/fonts/OFL.txt` |
| `overlay/Ui/mushroom.png`, `mushroom.ico`, `mushroom-source.png` | the mushroom indicator (the project owner's artwork) | **MIT**, like the code: © IamrrrED, reuse permitted with the notice kept |
| system fonts (`Segoe UI`, `Georgia`) | body text and fallbacks | not shipped, provided by the OS |

## Why

The panel used to carry **Fontin**, the game's own font. It belongs to Grinding Gear Games and cannot sit in an MIT
repository: that would be redistributing someone else's font. Alegreya solves it honestly — a serif with a similar
character, full Cyrillic, a free licence, and the licence file right next to it.

## If you change the font

1. Pick a file whose licence allows redistribution (OFL, Apache-2.0, CC0).
2. Put it in `overlay/Ui/fonts/` together with the licence text.
3. Verify Cyrillic: `python tools/check_font_coverage.py overlay/Ui/fonts/YourFont.ttf` must print `67/67`, otherwise
   the Russian interface will show boxes.
4. Point `@font-face` and the `--display` variable in `overlay/Ui/panel.html` at it.
