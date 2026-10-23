"""A full item needs "there is nothing left to add", not "no price is known"."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "src", "Craft", "CraftOrBuy.lua")

with io.open(PATH, encoding="utf-8") as handle:
    text = handle.read()

if "fullNote" in text:
    print("already present")
    raise SystemExit(0)

old = "\t\tpriceNote = "
new = (
    "\t\t-- A full item needs a different sentence: not \"we have no price\" but \"there is nothing left to\n"
    "\t\t-- add\". Reporting a cheap Exalted Orb on a 3/3 item reads as \"you can improve this cheaply\".\n"
    "\t\tfullNote = (not hasRoom) and (\"Свободных аффиксов нет: добавить мод некуда. Остаются качество, \"\n"
    "\t\t\t.. \"переброс чисел Divine и необратимый Vaal последним шагом.\") or nil,\n"
    "\t\tpriceNote = "
)

if old not in text:
    raise SystemExit("anchor not found")

text = text.replace(old, new, 1)
with io.open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)
print("fullNote added")
