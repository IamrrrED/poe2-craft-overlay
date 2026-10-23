#!/usr/bin/env python3
"""Minimal MCP client: spawn a stdio server, handshake, list tools, optionally call one.

Used to verify MCP servers locally without a full client like Claude Desktop - both
third-party ones (is it installed and does it answer?) and our own overlay wrapper.

The Model Context Protocol over stdio is JSON-RPC 2.0 with one JSON object per line, so
a handshake is: initialize -> notifications/initialized -> tools/list -> tools/call.

Usage:
    python tools/mcp_probe.py -- poe2-mcp
    python tools/mcp_probe.py -- node mcp/server.js
    python tools/mcp_probe.py --call analyze_item '{"item_text": "..."}' -- node mcp/server.js
"""

from __future__ import annotations

import argparse
import json
import queue
import subprocess
import sys
import threading


class StdioClient:
    """Line-oriented JSON-RPC client with a real timeout.

    Reading stdout in a background thread is what makes a timeout possible: a server that
    starts but never answers (or answers only after minutes) must not hang the check.
    """

    def __init__(self, command: list[str], timeout: float = 60.0):
        self.timeout = timeout
        self.process = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", bufsize=1,
        )
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        assert self.process.stderr is not None
        self.stdin = self.process.stdin
        self.stdout = self.process.stdout
        self.stderr = self.process.stderr
        self.lines: queue.Queue = queue.Queue()
        self.logs: list[str] = []
        self.next_id = 1
        self.reader = threading.Thread(target=self._pump, daemon=True)
        self.reader.start()

    def _pump(self) -> None:
        try:
            for line in self.stdout:
                self.lines.put(line)
        except (ValueError, OSError):
            pass
        finally:
            self.lines.put(None)

    def send(self, method: str, params: dict | None = None, notify: bool = False) -> dict | None:
        message: dict = {"jsonrpc": "2.0", "method": method}
        if not notify:
            message["id"] = self.next_id
            self.next_id += 1
        if params is not None:
            message["params"] = params
        self.stdin.write(json.dumps(message) + "\n")
        self.stdin.flush()
        if notify:
            return None

        while True:
            line = self._next_line()
            if line is None:
                raise TimeoutError("server closed the connection or timed out")
            line = line.strip()
            if not line:
                continue
            if not line.startswith("{"):
                self.logs.append(line)
                print(f"    [server output] {line[:160]}", file=sys.stderr)
                continue
            try:
                reply = json.loads(line)
            except json.JSONDecodeError:
                print(f"    [unparsable] {line[:160]}", file=sys.stderr)
                continue
            if reply.get("id") == message["id"]:
                return reply

    def _next_line(self) -> str | None:
        try:
            return self.lines.get(timeout=self.timeout)
        except queue.Empty:
            return None

    def close(self) -> str:
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
        try:
            return self.stderr.read()
        except (ValueError, OSError):
            return ""


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--call", nargs=2, metavar=("TOOL", "JSON"), help="call a tool after listing")
    parser.add_argument("--timeout", type=float, default=25.0,
                        help="seconds to wait for each reply (default 60)")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="server command after --")
    args = parser.parse_args(argv)

    command = args.command
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        parser.error("no server command given (use: -- <command> [args...])")

    print(f"starting: {' '.join(command)} (timeout {args.timeout:.0f}s)")
    client = StdioClient(command, timeout=args.timeout)
    try:
        reply = client.send("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "dsh-mcp-probe", "version": "1.0"},
        })
        if not reply:
            print("no reply to initialize", file=sys.stderr)
            return 2
        info = (reply.get("result") or {}).get("serverInfo") or {}
        print(f"initialize -> {json.dumps(info, ensure_ascii=False)} "
              f"protocol={(reply.get('result') or {}).get('protocolVersion')}")

        client.send("notifications/initialized", notify=True)

        reply = client.send("tools/list") or {}
        tools = ((reply.get("result") or {}).get("tools")) or []
        print(f"tools/list -> {len(tools)} tool(s)")
        for tool in tools:
            description = (tool.get("description") or "").replace("\n", " ")
            if len(description) > 88:
                description = description[:85] + "..."
            print(f"    {tool.get('name'):<34} {description}")

        if args.call:
            name, raw = args.call
            print(f"tools/call {name}")
            reply = client.send("tools/call", {"name": name, "arguments": json.loads(raw)}) or {}
            text = json.dumps(reply, ensure_ascii=False)
            print("call -> " + (text[:1500] + "..." if len(text) > 1500 else text))
        return 0
    except TimeoutError as error:
        print(f"TIMEOUT: {error}", file=sys.stderr)
        return 3
    finally:
        errors = client.close()
        if errors:
            tail = errors.strip().splitlines()[-8:]
            print("--- server stderr (tail) ---", file=sys.stderr)
            for line in tail:
                print(f"    {line[:170]}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
