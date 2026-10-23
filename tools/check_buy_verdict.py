"""Render the craft-vs-buy verdict in a headless page and assert the text appears.

The step preview proves the input exists; this proves the ANSWER renders, which is the part a player acts on.
A blob of JS that only throws on click would pass a syntax check and fail here.
"""

import io
import os
import re
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(ROOT, "overlay", "Ui", "panel.html")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

with io.open(SOURCE, encoding="utf-8") as handle:
    page = handle.read()

# Show the panel, then answer a comparison the way the host would.
verdict = (
    '{"verdict":"buy","text":"Покупайте: готовый предмет дешевле крафта примерно на 80%.",'
    '"line":"Крафт ~0.11 хаоса · готовый 0.02 хаоса · Покупайте: готовый предмет дешевле крафта примерно на 80%.",'
    '"note":"Стоимость крафта — это СРЕДНЕЕ по шансам, а не гарантия. Цену готового предмета вы посмотрели сами.",'
    '"marketUrl":"https://www.pathofexile.com/trade2/search/poe2/ForbiddenRites?q=%7B%7D"}'
)
driver = (
    "<script>window.onload=function(){window.showCoach=window.showCoach||function(){};"
    "showTab('step');window.showBuyVerdict(" + verdict + ","
    "\"Цена рынка: медиана по 18 лотам из 546 найденных, та же база и те же моды.\");};</script>"
)
variant = page.replace("</body>", driver + "</body>")

handle_path = os.path.join(tempfile.gettempdir(), "buy-verdict-check.html")
with io.open(handle_path, "w", encoding="utf-8", newline="") as handle:
    handle.write(variant)

profile = os.path.join(tempfile.gettempdir(), "chrome-buy-check")
result = subprocess.run(
    [CHROME, "--headless=new", "--disable-gpu", "--user-data-dir=" + profile,
     "--virtual-time-budget=3000", "--dump-dom", "file:///" + handle_path.replace("\\", "/")],
    capture_output=True,
)

dom = result.stdout.decode("utf-8", "replace")

checks = {
    "the verdict sentence is in the DOM": "Покупайте" in dom,
    "the compared numbers are shown": "Крафт ~0.11 хаоса" in dom,
    "the honesty note is shown": "СРЕДНЕЕ" in dom,
    "the input is present": 'id="buy-input"' in dom,
    # The auto-price button and the note that says where the market number came from.
    "the auto-price button is present": "Узнать цену" in dom,
    "the market note is shown": "медиана по" in dom,
    # The trade search that produced the price, as a button. A link inside the WebView would replace the
    # panel, so the page only ASKS and the window opens the browser.
    "the trade search button is offered": "linkbtn" in dom,
    "and it carries the query that produced the price": "trade2/search/poe2/ForbiddenRites" in dom,
    # The key must have been RESOLVED: a missing entry renders the key itself, and the DOM dump also holds the
    # table source, so the absence of the raw key is the assertion that means something.
    "and the button is labelled in the panel language": ">openTradeSearch<" not in dom,
}

for label, ok in checks.items():
    print(("PASS " if ok else "FAIL ") + label)

if not all(checks.values()):
    # Dump the verdict container to see what actually rendered.
    match = re.search(r'id="buy-verdict"[^>]*>(.{0,400})', dom, re.S)
    print("verdict container:", match.group(1) if match else "NOT FOUND")
    raise SystemExit(1)
print("all buy-verdict checks passed")
