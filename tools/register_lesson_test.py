"""Register test_lesson in the runner and drop any stale probe entries.

Kept as a file because inline shell quoting keeps mangling the tab-and-quote sequences Lua module lists need.
"""

import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RUNNER = os.path.join(ROOT, "src", "Tests", "runner.lua")

with io.open(RUNNER, encoding="utf-8") as handle:
    lines = handle.readlines()

kept = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith('"Tests.test_zz_'):
        print("dropped stale:", stripped)
        continue
    kept.append(line)

text = "".join(kept)
if '"Tests.test_lesson"' not in text:
    anchor = '\t"Tests.test_stage",\n'
    if anchor in text:
        text = text.replace(anchor, anchor + '\t"Tests.test_lesson",\n', 1)
        print("registered test_lesson")
    else:
        print("anchor for test_stage not found")

with io.open(RUNNER, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)

print("stale entries left:", text.count("test_zz_"))
print("test_lesson present:", '"Tests.test_lesson"' in text)
