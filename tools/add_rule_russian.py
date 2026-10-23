"""Give the remaining rules Russian explanations.

Only `whyEn` existed for most rules, so the Russian panel printed English advice. The advisor prefers
`rule.why` and falls back to `rule.whyEn`, so adding the Russian field is all that is needed.
"""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Data", "league_0_5_5.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

RUSSIAN = {
    "normal_base": (
        "Дешёвый вход: Magic с одним модом как заготовка, дальше качество и остальное.",
        "Полный путь: Трансмутация → Аугментация → Эссенция на ключевой мод → Регал → добивка "
        "Экзальтами, затем качество.",
    ),
    "magic_one_mod": (
        "Дёшево добить Magic до двух модов, затем поднять до Rare.",
        "Закрепить ключевой мод Эссенцией, пока предмет ещё Magic, затем добить Экзальтами.",
    ),
    "rare_prefixes_full": (
        "Все три префикса заняты: следующая валюта может добавить только суффикс, так что терять нечего.",
        "Заполнить суффиксы Greater/Perfect Exalted, затем подстроить числа Divine.",
    ),
    "rare_suffixes_full": (
        "Все суффиксы заняты: следующая валюта может добавить только префикс.",
        "Заполнить префиксы Greater/Perfect Exalted, затем подстроить числа Divine.",
    ),
    "rare_open_affix": (
        "Слот свободен — один Экзальт добавит мод, не рискуя уже имеющимися.",
        "Greater/Perfect Exalted поднимают минимальный уровень модов, затем Divine подстраивает числа.",
    ),
    "unique": (
        "Уникальные предметы нельзя крафтить модами: только качество и переброс чисел Divine.",
        "Качество + Divine на хорошие числа + руны в сокеты.",
    ),
    "magic_two_mods": (
        "Magic с двумя модами: Регал поднимет до Rare и добавит третий, сохранив оба.",
        "Эссенция на ключевой мод, затем Регал и добивка Экзальтами.",
    ),
    "rare_full": (
        "Все шесть модов заняты: добавить некуда. Остаётся сменить мод, перебросить числа, поднять "
        "качество — или Vaal последним и необратимо.",
        "Хаос меняет один мод, Divine подстраивает числа, качество добавляется в конце; Vaal — последним.",
    ),
}

added = 0
for rule_id, (why_min, why_max) in RUSSIAN.items():
    anchor = f'\t\t\tid = "{rule_id}",'
    start = text.find(anchor)
    if start == -1:
        print("MISS id:", rule_id)
        continue
    # The rule block ends at the next rule id or the closing of the rules table.
    next_id = text.find('\t\t\tid = "', start + len(anchor))
    block_end = next_id if next_id != -1 else len(text)
    block = text[start:block_end]

    if "why = {" in block:
        print("has RU already:", rule_id)
        continue

    insertion = (
        '\t\t\twhy = {\n'
        f'\t\t\t\tmin = "{why_min}",\n'
        f'\t\t\t\tmax = "{why_max}",\n'
        '\t\t\t},\n'
    )

    en_at = block.find("\t\t\twhyEn = {")
    if en_at == -1:
        # No English text either: add the Russian block at the end of the rule's own fields, before the
        # blank line that closes it.
        insert_at = start + len(block.rstrip().rstrip()) - 1
        text = text[:start + len(block)] + insertion + text[start + len(block):]
        added += 1
        continue

    absolute = start + en_at
    text = text[:absolute] + insertion + text[absolute:]
    added += 1
    print("added RU:", rule_id)

with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("added:", added)
