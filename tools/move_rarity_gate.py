"""Move RARITY_GATE and rarityGate above toolCraftSummary.

Lua locals only see definitions that appear EARLIER in the same file. toolCraftSummary moved up so
toolMethods can reach it, and it calls rarityGate - which stayed behind and became a nil global at call
time, the exact failure the file's own comments warn about. The gate and its table move up together.
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


table_start = find_line(r"^local RARITY_GATE")
gate_start = find_line(r"^local function rarityGate")
summary_start = find_line(r"^local function toolCraftSummary")

if min(table_start, gate_start, summary_start) < 0:
    sys.exit(f"markers not found: table={table_start} gate={gate_start} summary={summary_start}")
if not (summary_start < table_start < gate_start):
    sys.exit(f"unexpected order: summary={summary_start} table={table_start} gate={gate_start}")

# The gate ends at its own top-level "end".
gate_end = -1
for index in range(gate_start + 1, len(lines)):
    if re.match(r"^end\s*$", lines[index]):
        gate_end = index + 1
        break
if gate_end < 0:
    sys.exit("could not find the end of rarityGate")

block = lines[table_start:gate_end]
rest = lines[:table_start] + lines[gate_end:]
new_lines = rest[:summary_start] + block + rest[summary_start:]

with open(PATH, "w", encoding="utf-8", newline="") as handle:
    handle.writelines(new_lines)

print(f"moved lines {table_start + 1}-{gate_end} to before toolCraftSummary")
for pattern in (r"^local RARITY_GATE", r"^local function rarityGate", r"^local function toolCraftSummary",
                r"^local function toolModChances", r"^local function toolMethods"):
    print(pattern, "->", find_line(pattern) + 1)
