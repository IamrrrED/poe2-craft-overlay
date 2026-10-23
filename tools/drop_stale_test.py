"""Drop the stale test_zz_stage entry from the runner.

The probe file is gone but its registration stayed, and the runner reports a missing module for it. Kept as a
file because the inline PowerShell/Python quoting mangled the read back slash-escaped quotes.
"""

import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RUNNER = os.path.join(ROOT, "src", "Tests", "runner.lua")

with io.open(RUNNER, encoding="utf-8") as handle:
    text = handle.read()

before = text.count('"Tests.test_zz_stage"')
text = text.replace('\t"Tests.test_zz_stage",\n', "")
with io.open(RUNNER, "w", encoding="utf-8", newline="") as handle:
    handle.write(text)

print("removed entries:", before)
print("test_stage present:", '"Tests.test_stage"' in text)
print("stale entries left:", text.count("test_zz_"))
