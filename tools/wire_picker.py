"""Wire the chosen picker into the panel: data in, scroll handler, tab repaint.

Small, targeted edits on panel.html so each change is reviewable: the tab repaint loses its stale
argument, showCoach hands the picker the payload that already arrives with the analysis, and the panel
body gets the scroll listener that loads the rest of a long modifier list.
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PANEL = os.path.join(ROOT, "overlay", "Ui", "panel.html")

with io.open(PANEL, encoding="utf-8") as handle:
    text = handle.read()

edits = []


def replace(old, new, label):
    global text
    if old not in text:
        sys.exit("marker missing: " + label)
    if text.count(old) != 1:
        sys.exit("marker appears %d times: %s" % (text.count(old), label))
    text = text.replace(old, new, 1)
    edits.append(label)


replace(
    "if(which==='methods'){paintMethods(false);}",
    "if(which==='methods'){paintMethods();}",
    "tab repaint argument",
)

SHOW_COACH_OLD = "window.showCoach=function(report, analysis, client, guide){"
SHOW_COACH_NEW = (
    "window.showCoach=function(report, analysis, client, guide){\n"
    "  // The methods payload arrives with the analysis, so the picker costs no extra engine call. The\n"
    "  // previous choice is kept when the item is still the same, because a capture right after a step\n"
    "  // should show that same method's updated numbers rather than jump back to the first one.\n"
    "  methodsData=(analysis&&analysis.methods)||null;\n"
    "  var previous=methodsSel?methodsSel.id:null;\n"
    "  methodsSel=null;\n"
    "  if(previous&&methodsData){selectMethod(previous);}\n"
    "  if(!methodsSel&&methodsData&&(methodsData.groups||[]).length){\n"
    "    var firstGroup=methodsData.groups[0];\n"
    "    var firstMethod=(firstGroup.methods||[])[0];\n"
    "    if(firstMethod){selectMethod(firstMethod.id);}\n"
    "  }\n"
)
replace(SHOW_COACH_OLD, SHOW_COACH_NEW, "showCoach payload")

SCROLL_OLD = "  document.addEventListener('mouseup', function () { last = null; });"
SCROLL_NEW = (
    "  document.addEventListener('mouseup', function () { last = null; });\n"
    "  // The picker draws twenty modifiers and loads the rest when the panel is scrolled to the end.\n"
    "  window.addEventListener('scroll', methodsOnScroll, true);"
)
replace(SCROLL_OLD, SCROLL_NEW, "scroll listener")

with io.open(PANEL, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)

print("edits applied:", ", ".join(edits))
for needle in ("methodsData=(analysis&&analysis.methods)", "methodsOnScroll, true",
               "if(which==='methods'){paintMethods();}"):
    print("present:", needle, "->", needle in text)
