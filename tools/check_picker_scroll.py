"""Render the real panel, scroll it to the bottom, and report what the picker did.

The customer reported that scrolling did not load the rest of the modifier list. A screenshot of the top
of the page cannot show that, so this scrolls the real page in a real browser and prints how many
modifier rows existed before and after - the number that proves the fix.
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

# A driver appended to the preview: count rows, scroll the panel to the end, count again, and write the two
# numbers into the title so --dump-dom can report them.
driver = """
<script>
window.addEventListener('load',function(){
  function rows(){return document.querySelectorAll('#methods-view .modgrid').length;}
  function scroller(){
    var node=document.getElementById('methods-view');
    while(node&&node!==document.body){
      var s=window.getComputedStyle(node);
      if((s.overflowY==='auto'||s.overflowY==='scroll')&&node.scrollHeight>node.clientHeight+4){return node;}
      node=node.parentNode;
    }
    return document.scrollingElement;
  }
  var before=rows();
  for(var i=0;i<8;i++){
    var box=scroller();
    box.scrollTop=box.scrollHeight;
    window.dispatchEvent(new Event('scroll'));
  }
  document.title='BEFORE='+before+' AFTER='+rows();
});
</script>
"""

with io.open(PREVIEW.replace(".html", "-scroll.html"), "w", encoding="utf-8", newline="") as handle:
    handle.write(page.replace("</body>", driver + "</body>"))

target = "file:///" + PREVIEW.replace(".html", "-scroll.html").replace("\\", "/")
result = subprocess.run(
    [CHROME, "--headless=new", "--disable-gpu", "--virtual-time-budget=4000", "--dump-dom", target],
    capture_output=True, text=True, encoding="utf-8", errors="replace")

title = re.search(r"<title>([^<]*)</title>", result.stdout or "")
print("driver result:", title.group(1) if title else "(title not found)")
print("rows on the page now:", len(re.findall(r'class="modgrid"', result.stdout or "")))
