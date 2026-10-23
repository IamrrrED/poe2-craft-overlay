"""Send the trade site the league name it knows: without our version prefix."""

import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = os.path.join(ROOT, "src", "Mcp", "api.lua")

with io.open(API, encoding="utf-8") as handle:
    text = handle.read()

old = "\t\t\tleague = (ruleset() or { }).league,"
new = (
    "\t\t\t-- The trade site knows this league as \"Forbidden Rites\", without the version prefix our\n"
    "\t\t\t-- ruleset carries. Sending \"0.5.5 Forbidden Rites\" relied on the caller falling back to a\n"
    "\t\t\t-- substring match, which is a guess where an exact name is available.\n"
    "\t\t\tleague = (tostring((ruleset() or { }).league or \"\"):gsub(\"^%d+%.%d+%.?%d*%s*\", \"\")),"
)

if old in text:
    text = text.replace(old, new, 1)
    with io.open(API, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print("league normalised")
elif "without the version prefix" in text:
    print("already normalised")
else:
    print("ANCHOR MISS")
