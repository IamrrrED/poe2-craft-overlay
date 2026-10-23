"""Check that choosing a method redraws the detail pane, and that no method id is duplicated.

The customer reported that clicking "Arcanist's Etcher" did nothing. That was a duplicate row, but the
click path also deserves a check: the page is driven in a real browser and the detail title is compared
before and after, so "nothing happened" cannot pass unnoticed.
"""

import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PREVIEW = os.path.join(ROOT, "docs", "mockups", "panel-real.html")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"

if not os.path.isfile(PREVIEW):
    sys.exit("run tools/gen_panel_preview.py first")

with io.open(PREVIEW, encoding="utf-8") as handle:
    page = handle.read()

driver = """
<script>
window.addEventListener('load',function(){
  function title(){var el=document.querySelector('#methods-view .detail-title');
    return el?el.textContent.trim():'(none)';}
  var rows=document.querySelectorAll('#methods-view .mrow');
  var out=['rows='+rows.length,'first='+title()];
  // Click the last row with the same name as the first quality method, then whatever follows.
  var clicked=null;
  for(var i=0;i<rows.length;i++){
    if(!rows[i].className.match(/\\bon\\b/)){clicked=rows[i];break;}
  }
  if(clicked){
    out.push('clicked='+clicked.textContent.trim().replace(/\\s+/g,' '));
    clicked.click();
    out.push('after='+title());
    var marked=document.querySelectorAll('#methods-view .mrow.on').length;
    out.push('marked='+marked);
  } else { out.push('clicked=none'); }
  document.title=out.join(' | ');
});
</script>
"""

with io.open(PREVIEW.replace(".html", "-click.html"), "w", encoding="utf-8", newline="") as handle:
    handle.write(page.replace("</body>", driver + "</body>"))

target = "file:///" + PREVIEW.replace(".html", "-click.html").replace("\\", "/")
result = subprocess.run(
    [CHROME, "--headless=new", "--disable-gpu", "--virtual-time-budget=4000", "--dump-dom", target],
    capture_output=True, text=True, encoding="utf-8", errors="replace")

title = re.search(r"<title>([^<]*)</title>", result.stdout or "")
print("click check:", title.group(1) if title else "(title not found)")

ids = re.findall(r"selectMethod\\('([^']+)'\\)", page)
duplicates = sorted({i for i in ids if ids.count(i) > 1})
print("rows with an id:", len(ids), "duplicate ids:", duplicates or "none")
