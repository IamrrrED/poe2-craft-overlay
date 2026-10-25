"""Clicks in the sweep must never land on a grid slot.

On 2026-10-25 a grid click picked an item up and the click that was meant to put it back nearly dropped it on the
ground. The rule is now: the only click points are stash tabs, and the loop refuses any point marked as a grid slot.
This check reads the source and fails if a grid point comes back.
"""
import re
import sys
from pathlib import Path

source = (Path(__file__).resolve().parent.parent / "overlay" / "Inspect.cs").read_text(encoding="utf-8")
grid_points = re.findall(r"points\.Add\(\([^)]*?,\s*true\)\)", source)
failures = []
if grid_points:
    failures.append(f"{len(grid_points)} grid click point(s) in the list: {grid_points[:3]}")
if "grid clicks are forbidden" not in source:
    failures.append("the click loop does not refuse grid points")
if failures:
    print("FAIL click safety: " + "; ".join(failures))
    sys.exit(1)
print("PASS click safety: no grid click points, and the loop refuses one")