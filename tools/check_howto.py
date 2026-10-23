"""Assert the "how to use" block actually renders when nothing has been captured yet.

The customer said he still does not understand how to use the assistant, which makes this the most important
text in the panel. Checking that it is in the rendered DOM - not only in the source - is the difference between
"we added instructions" and "the instructions are visible".
"""

import io
import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(ROOT, "docs", "mockups", "panel-real.html")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

with io.open(SOURCE, encoding="utf-8") as handle:
    page = handle.read()

# No capture: the panel shows its empty state, which is where the instructions belong.
driver = (
    "<script>window.onload=function(){window.showCoach=function(){};showTab('methods');};</script>"
)
variant = page.replace("</body>", driver + "</body>")

handle_path = os.path.join(tempfile.gettempdir(), "howto-check.html")
with io.open(handle_path, "w", encoding="utf-8", newline="") as handle:
    handle.write(variant)

profile = os.path.join(tempfile.gettempdir(), "chrome-howto-check")
result = subprocess.run(
    [CHROME, "--headless=new", "--disable-gpu", "--user-data-dir=" + profile,
     "--virtual-time-budget=3000", "--dump-dom", "file:///" + handle_path.replace("\\", "/")],
    capture_output=True,
)

dom = result.stdout.decode("utf-8", "replace")

checks = {
    "the panel is waiting for an item": "Панель ждёт предмет" in dom,
    "the Ctrl+Q hint is shown": "Ctrl+Q" in dom,
    "the how-to heading is shown": "Как пользоваться" in dom,
    "the step instruction is shown": "что сделать следующим" in dom,
    "the methods instruction is shown": "все доступные пути" in dom,
    "the reference instruction is shown": "известные ловушки" in dom,
    "the price button is explained": "Узнать цену" in dom,
}

for label, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + label)

if not all(checks.values()):
    raise SystemExit(1)
print("all how-to checks passed")
