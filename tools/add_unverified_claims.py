"""Record the three claims we cannot settle, so the panel answers "not measured" instead of staying silent.

A claim with no entry in VERIFIERS is automatically flagged as unverified, so these three are honest by
construction: the panel can say what is known, and say plainly what is not.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Craft", "Claims.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

if "vaal_all_skills_rate" in text:
    print("already present")
    raise SystemExit(0)

ANCHOR = '\t\tsource = "правило locked и предупреждение шага vaal",\n\t},'

BLOCK = '''\t\tsource = "правило locked и предупреждение шага vaal",
\t},
\t{
\t\tid = "vaal_all_skills_rate",
\t\tmatches = { "+1 all skills", "+1 ко всем умениям", "ваал +1", "осквернение +1", "vaal +1" },
\t\tverdict = "true",
\t\ttitle = "Vaal может дать +1 ко всем умениям — но ставка не измерена",
\t\twhy = "Осквернение действительно иногда добавляет +1 к уровню всех умений, и это одна из причин "
\t\t\t.. "делать Vaal последним. А вот КАК ЧАСТО — в наших данных не измерено: числа, которые ходят по "
\t\t\t.. "гайдам, это выборка одного автора, а не статистика. Планировать на этом нельзя, и панель не "
\t\t\t.. "называет шанс.",
\t\tsource = "механика подтверждена правилом vaal; частота — нет, источника с замерами нет",
\t},
\t{
\t\tid = "homogenising_both_sides",
\t\tmatches = { "homogenising", "гомогениз", "теги обеих сторон", "tags of both sides" },
\t\tverdict = "true",
\t\ttitle = "Homogenising Exaltation стягивает мод к тегам предмета",
\t\twhy = "Omen of Homogenising Exaltation заставляет следующий Exalted добавить мод из тегов, которые "
\t\t\t.. "уже есть на предмете, — это подтверждено разбором и правилом. Но формулировка «теги ОБЕИХ "
\t\t\t.. "сторон» (будто префикс и суффикс считаются вместе) в наших данных не подтверждена: точную "
\t\t\t.. "трактовку проверить нечем, поэтому на неё не опираемся. И помните: с 0.4.0 омен больше не "
\t\t\t.. "падает, работает только на уже существующих копиях.",
\t\tsource = "разбор GhazzyTV + правило омэна; трактовка «обеих сторон» не проверена",
\t},
\t{
\t\tid = "ilvl_mod_thresholds",
\t\tmatches = { "ilvl", "уровень предмета", "порог тира", "item level threshold", "итем левел" },
\t\tverdict = "true",
\t\ttitle = "Пороги уровня предмета задают тир — но точные числа не сверены",
\t\twhy = "Тир мода ограничен уровнем предмета, и это работает. Однако конкретные пороги, которые "
\t\t\t.. "называют в видео, мы не сверяли построчно с poe2db: часть чисел взята из разбора, а не из "
\t\t\t.. "таблиц. Поэтому панель показывает тир, который нашла в данных, и не обещает, что бо́льший "
\t\t\t.. "уровень предмета всегда даст следующий тир.",
\t\tsource = "механика из данных предмета; построчной сверки порогов с poe2db нет",
\t},'''

if ANCHOR not in text:
    raise SystemExit("anchor not found")

text = text.replace(ANCHOR, BLOCK, 1)

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("three claims added")
