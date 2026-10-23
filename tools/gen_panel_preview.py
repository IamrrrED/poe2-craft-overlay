"""Render the REAL panel page with the REAL methods payload, for a screenshot.

The mockups showed layouts; this shows what the shipped panel actually draws, using its own CSS and its own
script with a payload captured from the engine. If this renders, the panel renders.
"""

import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PANEL = os.path.join(ROOT, "overlay", "Ui", "panel.html")
DATA = os.path.join(ROOT, "docs", "mockup-data.json")
OUT = os.path.join(ROOT, "docs", "mockups", "panel-real.html")

with io.open(PANEL, encoding="utf-8") as handle:
    page = handle.read()

if "</body>" not in page or "<script>" not in page:
    sys.exit("panel.html does not look like the panel page")
if "methodsData=(analysis&&analysis.methods)" not in page:
    sys.exit("the picker is not wired into panel.html yet")

# The payload is exactly what analyze_item returns for this item, minus the fields the picker ignores:
# the test that produced it called the engine, so the numbers are the engine's.
with io.open(DATA, encoding="utf-8") as handle:
    methods = json.load(handle)

# The test that produced the payload wrote the weight source as "src"; the panel expects the engine's own
# field name, so it is renamed here. Without this the preview rendered an empty source column and looked
# like a panel bug when it was a preview bug.
for group in methods.get("groups", []):
    for method in group.get("methods", []):
        for mod in method.get("mods", []):
            if "src" in mod:
                mod["weightSource"] = mod.pop("src")

analysis = {
    "item": {
        "name": methods["item"]["name"], "baseType": methods["item"]["base"],
        "name0": methods["item"]["base"], "itemClass": methods["item"]["class"],
        "rarity": methods["item"]["rarity"], "itemLevel": methods["item"]["ilvl"],
        "affixes": methods["item"]["affixes"],
    },
    "ruleId": methods["item"]["rule"],
    "craftSummary": {"entries": []},
    "methods": methods,
}
client = {
    "header": {"name": methods["item"]["name"], "base": methods["item"]["base"]},
    "properties": [{"label": "Дух", "value": "114"}],
    "mods": [{"text": m} for m in methods["item"].get("mods", [])],
    "flags": {},
}
report = {
    "step": {"title": "Следующий шаг: Exalted Orb", "currency": "Exalted Orb",
             "why": "Свободен суффикс — Exalted его займёт."},
    "state": {"splitKnown": True, "openPrefixes": methods["split"]["openPrefixes"],
              "openSuffixes": methods["split"]["openSuffixes"], "openSlots": 2,
              "craftedAnchorUsed": False, "desecratedAnchorUsed": False, "modifiable": True},
    "warnings": [],
    "review": None,
    # The "craft or buy" block, shaped exactly as Craft/CraftOrBuy.lua returns it.
    "craftOrBuy": {
        "hasCost": True,
        "cheapest": {"method": "Exalted Orb", "expectedAttempts": 7.1,
                     "expectedCost": {"chaos": 0.11, "exalted": 0.11, "divine": 0.01},
                     "costFor90": {"chaos": 0.24, "exalted": 0.24, "divine": 0.02}},
        "unpriced": [{"method": "Desecration", "missing": ["Preserved Rib"]}],
        "recipe": {"class": methods["item"].get("class", "Sceptres"),
                   "itemLevel": methods["item"].get("ilvl") or 80,
                   "rarity": methods["item"].get("rarity", "RARE"),
                   "stats": [{"text": entry["text"]}
                             for entry in (methods["item"].get("mods") or []) if entry.get("text")][:3]
                            or [{"text": "+3 to Level of all Minion Skills"},
                                {"text": "+45 to maximum Energy Shield"}]},
        "rule": "Правило простое: если готовый предмет в трейде дешевле ожидаемой стоимости крафта — "
                "покупайте. Крафт оправдан, когда нужных модов в продаже нет или они дороже.",
        "pricesAsOf": "2026-10-06 23:17",
        "priceNote": "Цены валют — снимок от 2026-10-06 23:17; на рынке они меняются. Стоимость готового "
                     "предмета панель не знает: цен на редкие предметы в снимке нет, поэтому её нужно "
                     "посмотреть в трейде.",
    },
}

# The reference tab needs the guide, and the claim checker needs the known traps. Both come from the same
# engine call the panel makes ("crafting_guide"), so the preview shows what the shipped panel shows.
guide = {
    "league": "0.5.5 Forbidden Rites",
    "mainRule": "Предмет собирается постепенно: Normal → Magic → Rare. Полного переролла нет.",
    "caps": [{"title": "Один created-мод", "text": "Эссенция, сплав или руна — только один такой мод."}],
    "orbs": [{"name": "Exalted Orb", "does": "добавляет один мод",
              "when": "сторона свободна", "risk": "мод случайный"}],
    "omens": {"entries": [{"name": "Omen of Whittling", "does": "Annulment снимает слабейший мод",
                           "why": "точечная правка"}]},
    "mistakes": [{"text": "Тратить Exalted на предмет, который заменят через два акта."}],
    "loop": ["Ctrl+Q — захват", "сделайте шаг", "Ctrl+Q снова"],
    # The Genesis Tree block, shaped as Craft/GenesisTree.lua returns it.
    "genesisTree": {
        "location": "Монастырь Хранителей, к югу от начала Атласа",
        "goals": [
            {"id": "catalyst_any", "title": "Любой катализатор", "wombgift": "Lavish Wombgift",
             "chance": 0.15, "expectedBirths": 6.67},
            {"id": "catalyst_refined", "title": "Refined-катализатор (ювелирка)",
             "wombgift": "Lavish Wombgift", "chance": 0.04, "expectedBirths": 25},
            {"id": "refined_breach_ring", "title": "Refined Breach Ring", "wombgift": "Signet Wombgift",
             "chance": 0.005, "expectedBirths": 200},
        ],
        "notes": ["С 0.5.0 катализаторы НЕ падают с монстров. Единственный источник — Genesis Tree."],
    },
    # The preview lists eight traps, so the summary has to describe those eight and not the full set.
    "claimsChecked": {"checked": 8, "failed": 0, "total": 8},
    "claims": [
        {"id": "scouring_orb", "verdict": "false", "title": "Орб Скуринга в PoE 2 не существует"},
        {"id": "regal_locks_prefix", "verdict": "false", "title": "Regal не «фиксирует префикс»"},
        {"id": "chaos_rerolls_all", "verdict": "false", "title": "Chaos в PoE 2 не перекатывает весь предмет"},
        {"id": "essence_twice", "verdict": "false", "title": "Один created-слот, а не два"},
        {"id": "vaal_reversible", "verdict": "false", "title": "Осквернение необратимо"},
        {"id": "quality_free_slot", "verdict": "false", "title": "Качество не занимает слот"},
        {"id": "divine_changes_mods", "verdict": "false", "title": "Divine меняет числа, а не набор модов"},
        {"id": "exalted_safe", "verdict": "true", "title": "Exalted не трогает существующие моды"},
    ],
}

# Drive the page exactly as the panel does: showCoach for the data, then the methods tab.
driver = (
    "<script>window.onload=function(){window.showCoach("
    + json.dumps(report, ensure_ascii=False) + ","
    + json.dumps(analysis, ensure_ascii=False) + ","
    + json.dumps(client, ensure_ascii=False) + ","
    + json.dumps(guide, ensure_ascii=False) + ");showTab('methods');};</script>"
)

with io.open(OUT, "w", encoding="utf-8", newline="") as handle:
    handle.write(page.replace("</body>", driver + "</body>"))
print("wrote", OUT)
print("groups in the payload:", len(methods["groups"]))
print("mods on the first method:", len(methods["groups"][0]["methods"][0]["mods"]))
