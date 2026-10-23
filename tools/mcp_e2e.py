#!/usr/bin/env python3
"""End-to-end check of the overlay's MCP server.

Starts `mcp/server.js` as a real MCP client would, then calls every tool with the demo
item and prints a compact summary. Each tool call is one host run of the overlay engine,
so a slow machine shows up as a timeout rather than a wrong answer.

Usage:
    python tools/mcp_e2e.py                 # demo item from samples/
    python tools/mcp_e2e.py --item FILE     # any copied item text
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys

TOOL_CALLS = [
    ("sources", {}),
    ("analyze_item", {"item_text": "{ITEM}"}),
    ("mod_chances", {"item_text": "{ITEM}", "method": "exalted"}),
    ("mod_chances", {"item_text": "{ITEM}", "method": "desecration"}),
    ("league_methods", {"item_text": "{ITEM}"}),
    ("runeforging", {"base_type": "Blacksteel Gauntlets"}),
    ("prices", {}),
]


class Client:
    def __init__(self, command: list[str]):
        self.process = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", bufsize=1,
        )
        # Popen types its pipes as optional; the assertions keep the type checker (and a
        # future reader) honest about the fact that this client always uses all three.
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        assert self.process.stderr is not None
        self.stdin = self.process.stdin
        self.stdout = self.process.stdout
        self.stderr = self.process.stderr
        self.next_id = 1

    def send(self, method: str, params: dict | None = None) -> dict:
        message = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            message["params"] = params
        self.next_id += 1
        self.stdin.write(json.dumps(message) + "\n")
        self.stdin.flush()
        while True:
            line = self.stdout.readline()
            if not line:
                raise RuntimeError("server closed the connection")
            line = line.strip()
            if not line.startswith("{"):
                continue
            reply = json.loads(line)
            if reply.get("id") == message["id"]:
                return reply

    def notify(self, method: str) -> None:
        self.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method}) + "\n")
        self.stdin.flush()

    def close(self) -> None:
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
        errors = self.stderr.read()
        if errors:
            for line in errors.strip().splitlines()[-6:]:
                print(f"    [bridge] {line}")


def summarise(tool: str, result: dict) -> str:
    if tool == "sources":
        return f"{len(result.get('sources', []))} source(s), first: {result['sources'][0]['label']}"
    if tool == "analyze_item":
        item = result.get("item", {})
        plans = result.get("plans", [])
        steps = sum(len(plan.get("steps", [])) for plan in plans)
        return (f"{item.get('name')} / {item.get('baseType')} ilvl {item.get('itemLevel')} "
                f"-> plans {len(plans)} ({steps} steps), rule={result.get('ruleId')}, "
                f"notes={len(result.get('notes', []))}")
    if tool == "mod_chances":
        groups = result.get("groups", [])
        top = ", ".join(f"{g['chance']}% {g['text'][:34]}" for g in groups[:2])
        extra = ""
        if result.get("reveal"):
            reveal = result["reveal"]
            extra = (f" | reveal 3 of {reveal['poolSize']}: {reveal['perGroup'] * 100:.2f}% "
                     f"for the top group, {reveal['withEchoes'] * 100:.2f}% with echoes")
        return f"{result.get('name')}: pool {result.get('tierCount')} tiers | {top}{extra}"
    if tool == "prices":
        verdict = "applies" if result.get("appliesToConfiguredLeague") else "does not apply"
        divine = next((c for c in result.get("usedByMethods", []) if c["name"] == "Divine Orb"), None)
        sample = f", Divine Orb = {divine['chaos']:.2f} chaos" if divine else ""
        return (f"league '{result.get('league')}' fetched {result.get('fetchedAt')}: {verdict} "
                f"({result.get('appliesReason')}){sample}")
    if tool == "league_methods":
        kinds: dict[str, int] = {}
        for option in result.get("options", []):
            kinds[option["kind"]] = kinds.get(option["kind"], 0) + 1
        summary = ", ".join(f"{kind}={count}" for kind, count in sorted(kinds.items()))
        return (f"options {len(result.get('options', []))} ({summary}); "
                f"runeforging={result.get('runeforging')}")
    if tool == "runeforging":
        return f"{result.get('base_type')} -> {result.get('results')}"
    return json.dumps(result)[:120]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--item", default="samples/rare_gloves.txt")
    parser.add_argument("--node", default="node")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    item_text = (root / args.item).read_text(encoding="utf-8")
    client = Client([args.node, str(root / "mcp" / "server.js")])

    failures = 0
    try:
        reply = client.send("initialize", {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "mcp-e2e", "version": "1.0"},
        })
        info = (reply.get("result") or {}).get("serverInfo", {})
        print(f"initialize: {info.get('name')} {info.get('version')}")
        client.notify("notifications/initialized")

        reply = client.send("tools/list")
        tools = (reply.get("result") or {}).get("tools", [])
        print(f"tools/list: {len(tools)} -> {', '.join(t['name'] for t in tools)}")

        for tool, template in TOOL_CALLS:
            arguments = {key: (item_text if value == "{ITEM}" else value) for key, value in template.items()}
            reply = client.send("tools/call", {"name": tool, "arguments": arguments})
            result = reply.get("result") or {}
            if result.get("isError"):
                failures += 1
                text = (result.get("content") or [{}])[0].get("text", "")
                print(f"  {tool:<16} ERROR: {text[:120]}")
                continue
            payload = json.loads((result.get("content") or [{}])[0].get("text", "{}"))
            print(f"  {tool:<16} {summarise(tool, payload)}")

        reply = client.send("tools/call", {"name": "no_such_tool", "arguments": {}})
        result = reply.get("result") or {}
        handled = bool(result.get("isError"))
        print(f"  unknown tool     -> isError={handled} (expected True)")
        if not handled:
            failures += 1
    finally:
        client.close()

    print(f"RESULT: {'ok' if failures == 0 else str(failures) + ' failure(s)'}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
