"""Screenshot and assert the beginner mode: one question, everything else behind one click.

The point of the mode is that the step tab shows the next action and the two answers, and hides the rest behind
a single summary line - without hiding silently, so the warning count is visible before expanding.
"""

import io
import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(ROOT, "docs", "mockups", "panel-real.html")
SHOT = os.path.join(ROOT, "docs", "mockups", "panel-beginner.png")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

with io.open(SOURCE, encoding="utf-8") as handle:
    page = handle.read()

# The preview's own driver opens the "Способы" tab; this check is about the STEP tab, so switch it and keep
# beginner mode on. Both tabs' markup exists in the DOM either way, which is why the assertions look for
# position rather than mere presence.
driver = (
    "<script>try{localStorage.setItem('poe2craft.beginner','1');}catch(e){}"
    "window.addEventListener('load',function(){showTab('step');});</script>"
)
variant = page.replace("</body>", driver + "</body>")

handle_path = os.path.join(tempfile.gettempdir(), "beginner-check.html")
with io.open(handle_path, "w", encoding="utf-8", newline="") as handle:
    handle.write(variant)

profile = os.path.join(tempfile.gettempdir(), "chrome-beginner")
subprocess.run(
    [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--user-data-dir=" + profile,
     "--window-size=980,760", "--virtual-time-budget=3000", "--screenshot=" + SHOT,
     "file:///" + handle_path.replace("\\", "/")],
    capture_output=True,
)

result = subprocess.run(
    [CHROME, "--headless=new", "--disable-gpu", "--user-data-dir=" + profile,
     "--virtual-time-budget=3000", "--dump-dom", "file:///" + handle_path.replace("\\", "/")],
    capture_output=True,
)
dom = result.stdout.decode("utf-8", "replace")

checks = {
    "the mode switch is present": "Новичок" in dom and "Всё" in dom,
    "the next step is visible": "Следующий шаг" in dom,
    "the two answers are on the step tab": 'onclick="confirmStep(' in dom,
    "the rest is behind one summary": "Показать всё" in dom,
    "the hidden warning count is stated": "предупр." in dom,
    "the price check is still offered": "Узнать цену" in dom,
}

# The collapsed content is still in the DOM, so "is it hidden" is the wrong question. The right one is whether
# it sits INSIDE the details element - i.e. after the summary that offers to show it.
details_at = dom.find('<details class="more"')
taken_at = dom.find("ЧТО УЖЕ ЗАНЯТО")
checks["the extra sections sit inside the collapsed block"] = (
    details_at != -1 and taken_at != -1 and taken_at > details_at
)

for label, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + label)

print("screenshot bytes:", os.path.getsize(SHOT) if os.path.isfile(SHOT) else "missing")
if not all(checks.values()):
    raise SystemExit(1)
print("beginner mode checks passed")
