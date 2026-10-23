"""Render the step tab (with the craft-or-buy block) for a screenshot.

The picker preview is generated separately; this one switches the page to the step tab. Written as a file
because the shell keeps mangling the quotes in a one-liner.
"""

import io
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(ROOT, "docs", "mockups", "panel-real.html")
TARGET = os.path.join(ROOT, "docs", "mockups", "panel-step.html")
SHOT = os.path.join(ROOT, "docs", "mockups", "panel-step.png")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

with io.open(SOURCE, encoding="utf-8") as handle:
    page = handle.read()

variant = page.replace("showTab('methods')", "showTab('step')")
with io.open(TARGET, "w", encoding="utf-8", newline="") as handle:
    handle.write(variant)

uri = "file:///" + TARGET.replace("\\", "/")
profile = os.path.join(os.environ.get("TEMP", "."), "shotprofile-step")
subprocess.run([
    CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
    "--user-data-dir=" + profile, "--window-size=980,1100",
    "--virtual-time-budget=3000", "--screenshot=" + SHOT, uri,
], capture_output=True)

print("wrote", TARGET)
print("screenshot bytes:", os.path.getsize(SHOT) if os.path.isfile(SHOT) else "missing")
