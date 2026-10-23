#!/usr/bin/env python3
"""Generate a reference table for the desecration reveal model.

`Item/Mods.revealChance` is a port of the community model used by poe2-crafting-mcp
(`poe2_crafting_mcp/crafting/desecration.py`). To keep the port honest, this tool runs
*their* function over a grid of pool sizes and target counts and writes the results to
`src/Tests/reveal_reference.lua`; the Lua test suite then asserts that our implementation
reproduces every row.

Usage:
    python tools/gen_reveal_reference.py                 # uses vendor/poe2-crafting-mcp
    python tools/gen_reveal_reference.py --check         # verify the file is current
"""

from __future__ import annotations

import argparse
import ast
import pathlib
import sys

POOL_SIZES = [3, 4, 5, 6, 8, 12, 20, 50, 200, 8580]
TARGET_COUNTS = [1, 2, 3, 5]


def load_their_function(repo: pathlib.Path):
    """Extract `desecration_hit_probability` verbatim from their module.

    Importing the module itself is not possible: it does `from
    poe2_crafting_mcp.crafting.simulator import ...`, which drags in the whole
    application (and its dependency tree). Parsing the function out with `ast` and
    running it with just `math.comb` in scope keeps the reference *their* code - the
    body, docstring and edge cases are untouched - while staying dependency-free.
    """
    module_path = repo / "poe2_crafting_mcp" / "crafting" / "desecration.py"
    if not module_path.exists():
        raise SystemExit(
            f"{module_path} not found - clone the project first:\n"
            "  git clone --depth 1 https://github.com/MatthewWinnan/poe2-crafting-mcp.git "
            "vendor/poe2-crafting-mcp"
        )

    tree = ast.parse(module_path.read_text(encoding="utf-8"))
    target = next(
        (node for node in tree.body
         if isinstance(node, ast.FunctionDef) and node.name == "desecration_hit_probability"),
        None,
    )
    if target is None:
        raise SystemExit(f"desecration_hit_probability not found in {module_path}")

    isolated = ast.Module(
        body=[
            ast.ImportFrom(module="math", names=[ast.alias(name="comb")], level=0),
            target,
        ],
        type_ignores=[],
    )
    ast.fix_missing_locations(isolated)
    namespace: dict = { }
    exec(compile(isolated, str(module_path), "exec"), namespace)  # noqa: S102 - trusted local checkout
    return namespace["desecration_hit_probability"]


def render(rows: list[tuple[int, int, bool, float]]) -> str:
    lines = [
        "-- PoE2 Craft Overlay : Tests/reveal_reference.lua",
        "-- GENERATED FILE - do not edit by hand (tools/gen_reveal_reference.py).",
        "--",
        "-- Reference values for the desecration reveal model, produced by running the",
        "-- community implementation this port follows:",
        "--   poe2-crafting-mcp / poe2_crafting_mcp/crafting/desecration.py",
        "--     desecration_hit_probability(pool_size, target_count, draws=3, echoes)",
        "-- The Lua test suite asserts Item/Mods.revealChance reproduces every row, so a",
        "-- silent change in either implementation shows up as a test failure.",
        "return {",
        "\tgenerated = 'tools/gen_reveal_reference.py',",
        "\tsource = 'poe2-crafting-mcp (crafting/desecration.py, community model)',",
        "\trows = {",
    ]
    for pool, targets, echoes, expected in rows:
        lines.append(
            "\t\t{ poolSize = %d, targetCount = %d, draws = 3, echoes = %s, expected = %.12f },"
            % (pool, targets, "true" if echoes else "false", expected)
        )
    lines.append("\t},")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="../vendor/poe2-crafting-mcp")
    parser.add_argument("--out", default="src/Tests/reveal_reference.lua")
    parser.add_argument("--check", action="store_true", help="fail if the file would change")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    repo = (root / args.repo).resolve()
    hit_probability = load_their_function(repo)

    rows: list[tuple[int, int, bool, float]] = []
    for pool in POOL_SIZES:
        for targets in TARGET_COUNTS:
            if targets > pool:
                continue
            for echoes in (False, True):
                rows.append((pool, targets, echoes, hit_probability(pool, targets, 3, echoes)))

    text = render(rows)
    out_path = root / args.out
    current = out_path.read_text(encoding="utf-8") if out_path.exists() else ""
    if args.check:
        if current != text:
            print(f"{out_path} is out of date - run the tool without --check")
            return 1
        print(f"{out_path} is up to date ({len(rows)} rows)")
        return 0

    out_path.write_text(text, encoding="utf-8")
    print(f"{out_path}: {len(rows)} reference rows written from {repo.name}")
    for pool, targets, echoes, expected in rows[:4]:
        print(f"    pool={pool} targets={targets} echoes={echoes} -> {expected:.6f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
