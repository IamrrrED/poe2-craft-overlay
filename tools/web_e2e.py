#!/usr/bin/env python3
"""End-to-end check of the local crafting site.

Starts web/server.js on a throwaway port with a sample capture, then verifies what a
browser would get: the page, its assets, the item payload the page renders, the on-demand
chance endpoint and the live-update stream. Stops the server again.

Usage:
    python tools/web_e2e.py
    python tools/web_e2e.py --port 17499 --item samples/rare_gloves.txt
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request


def http(url: str, timeout: float = 30.0) -> tuple[int, bytes]:
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.status, response.read()


def wait_for_server(port: int, deadline: float) -> bool:
    while time.time() < deadline:
        try:
            status, _ = http(f"http://127.0.0.1:{port}/api/health", timeout=3)
            if status == 200:
                return True
        except (urllib.error.URLError, OSError):
            time.sleep(0.3)
    return False


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=17499)
    parser.add_argument("--item", default="samples/rare_gloves.txt")
    parser.add_argument("--node", default="node")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    item_text = (root / args.item).read_text(encoding="utf-8")

    # Publish a capture exactly the way the overlay does, so the site has something to show.
    (root / "src" / "last_item.txt").write_text(item_text, encoding="utf-8")
    (root / "src" / "captured_at.txt").write_text(
        time.strftime("%Y-%m-%d %H:%M:%S"), encoding="utf-8")

    server = subprocess.Popen(
        [args.node, str(root / "web" / "server.js"), "--port", str(args.port), "--no-open"],
        cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )

    failures: list[str] = []
    base = f"http://127.0.0.1:{args.port}"
    try:
        if not wait_for_server(args.port, time.time() + 20):
            print("server did not come up", file=sys.stderr)
            return 2

        for path, min_size in (("/", 1000), ("/style.css", 1000), ("/app.js", 1000),
                               ("/fonts/fontin-regular-webfont.ttf", 10000)):
            try:
                status, body = http(base + path)
            except urllib.error.HTTPError as error:
                failures.append(f"{path}: HTTP {error.code}")
                continue
            state = "ok" if status == 200 and len(body) >= min_size else "BAD"
            if state == "BAD":
                failures.append(f"{path}: status {status}, {len(body)} bytes")
            print(f"  {path:<38} {state:<4} {len(body):>7} bytes")

        payload = json.loads(http(base + "/api/item")[1])
        print(f"  /api/item                              "
              f"engine_ok={payload.get('engine', {}).get('ok')} "
              f"has_item={payload.get('hasItem')}")
        if not payload.get("engine", {}).get("ok"):
            failures.append("engine did not answer /api/item")
        item = (payload.get("analysis") or {}).get("item") or {}
        if not item.get("baseType"):
            failures.append("no item in the payload")
        else:
            print(f"    item: {item.get('name')} / {item.get('baseType')} "
                  f"ilvl {item.get('itemLevel')} affixes {item.get('affixes')}")
        plans = (payload.get("analysis") or {}).get("plans") or []
        options = (payload.get("leagueMethods") or {}).get("options") or []
        methods = (payload.get("leagueMethods") or {}).get("methods") or []
        sources = (payload.get("sources") or {}).get("sources") or []
        print(f"    plans={len(plans)} league_options={len(options)} "
              f"methods={len(methods)} sources={len(sources)}")
        for label, value in (("plans", plans), ("league options", options),
                             ("methods", methods), ("sources", sources)):
            if not value:
                failures.append(f"{label} missing from /api/item")

        chances = json.loads(http(base + "/api/mod_chances?method=desecration")[1])
        result = chances.get("result") or {}
        reveal = result.get("reveal") or {}
        print(f"    mod_chances(desecration): pool={result.get('tierCount')} "
              f"reveal={reveal.get('perGroup')} echoes={reveal.get('withEchoes')}")
        if not result.get("groups"):
            failures.append("mod_chances returned no groups")

        # The live-update stream must open and send its retry hint immediately.
        with urllib.request.urlopen(base + "/events", timeout=20) as stream:
            first = stream.readline().decode("utf-8", "replace").strip()
            print(f"  /events                                {first!r}")
            if not first.startswith("retry:"):
                failures.append("event stream did not start as expected")
    finally:
        server.terminate()
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()
        errors = server.stderr.read()
        if errors:
            for line in errors.strip().splitlines()[-4:]:
                print(f"    [server] {line}")

    print(f"RESULT: {'ok' if not failures else str(len(failures)) + ' failure(s)'}")
    for failure in failures:
        print(f"  FAIL {failure}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
