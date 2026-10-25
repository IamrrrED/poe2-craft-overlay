"""The sweep must contain no mouse click at all.

On 2026-10-25 a grid click in the inventory picked an item up and the click meant to put it back nearly dropped it.
The customer's rule after that is absolute: no click in the inventory, no click in the stash, no click anywhere -
because only a click can change what the character owns. Reading is hovering plus Ctrl+C; the single key press it
allows is the inventory toggle, which cannot move an item.

This check reads the source and fails if a click comes back in any form.
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
inspect = (root / "overlay" / "Inspect.cs").read_text(encoding="utf-8")
failures = []

if "mouse_event" in inspect:
    failures.append("Inspect.cs declares mouse_event again")
if re.search(r"\bClickOnce\s*\(", inspect):
    failures.append("ClickOnce is called or defined")
if re.search(r"\bClickPoints\s*\(", inspect):
    failures.append("a click point list exists")
if "LeftDown" in inspect or "LeftUp" in inspect:
    failures.append("a mouse button constant is present")
if "clicks: none" not in inspect:
    failures.append("the action log does not state that the sweep clicks nothing")

# The probe (probe-capture) may still open the inventory and press Ctrl+C, but it must not click either.
probe = (root / "overlay" / "ProbeCapture.cs").read_text(encoding="utf-8")
if "mouse_event" in probe:
    failures.append("ProbeCapture.cs declares mouse_event")

if failures:
    print("FAIL click safety: " + "; ".join(failures))
    sys.exit(1)
print("PASS click safety: no mouse button anywhere in the sweep or the probe")