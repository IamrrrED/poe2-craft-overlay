"""Move toolCraftSummary above toolModChances so toolMethods can call it.

Lua locals only see definitions that appear EARLIER in the file, and this file already documents one
silent nil-global bug from that rule. toolMethods needs toolCraftSummary for the per-method prices, so the
definition moves up instead of the price logic being duplicated.
"""

import re
import sys

PATH = "src/Mcp/api.lua"

with open(PATH, "r", encoding="utf-8") as handle:
    lines = handle.readlines()


def find_line(pattern, start=0):
    for index in range(start, len(lines)):
        if re.match(pattern, lines[index]):
            return index
    return -1


summary_start = find_line(r"^local function toolCraftSummary")
summary_end = find_line(r"^local function toolCraftCost")
target = find_line(r"^local function toolModChances")

if min(summary_start, summary_end, target) < 0:
    sys.exit(f"markers not found: summary={summary_start} end={summary_end} target={target}")

block = lines[summary_start:summary_end]
rest = lines[:summary_start] + lines[summary_end:]
new_lines = rest[:target] + block + rest[target:]

with open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.writelines(new_lines)

print(f"moved the block from lines {summary_start + 1}-{summary_end} to before line {target + 1}")
for pattern in (r"^local function toolCraftSummary", r"^local function toolModChances",
                r"^local function toolMethods"):
    print(pattern, "->", find_line(pattern) + 1)
