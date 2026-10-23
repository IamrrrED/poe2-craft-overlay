#!/usr/bin/env python3
"""End-to-end check of the capture pipeline: picture -> text -> crafting options.

This is the path the Ctrl+Q hotkey takes, minus the game: a tooltip image is drawn, the
same OCR script the overlay calls reads it, the recognised text is published exactly as
the overlay publishes a capture, and the local site is asked what to craft.

A failure here means the feature is broken even though every unit test passes, so it is
worth running before claiming the hotkey works.

Usage:
    python tools/pipeline_e2e.py
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

SAMPLE = "tools/cache/ocr_sample.png"
OCR_TEXT = "tools/cache/ocr_sample.txt"


def run(command: list[str], cwd: pathlib.Path) -> int:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    for line in (result.stdout or "").splitlines():
        print(f"    {line}")
    if result.returncode != 0:
        for line in (result.stderr or "").splitlines()[-4:]:
            print(f"    [stderr] {line}")
    return result.returncode


def http(url: str, timeout: float = 30.0):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.status, response.read()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=17498)
    parser.add_argument("--node", default="node")
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    failures: list[str] = []

    print("1. drawing a test tooltip in the game's own style")
    if run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", "tools\\test_ocr.ps1", "-Style", "game"], root) != 0:
        failures.append("the OCR test script failed (see output above)")

    text_path = root / OCR_TEXT
    if not text_path.exists():
        print("RESULT: no OCR text produced - stopping")
        return 1
    recognised = text_path.read_text(encoding="utf-8")
    print(f"2. OCR read {len(recognised.splitlines())} lines")

    # Publish exactly like the overlay does on Ctrl+Q.
    (root / "src" / "last_item.txt").write_text(recognised, encoding="utf-8")
    (root / "src" / "captured_at.txt").write_text(time.strftime("%Y-%m-%d %H:%M:%S"), encoding="utf-8")
    (root / "src" / "capture_source.txt").write_text("image", encoding="utf-8")
    capture = root / "src" / "capture.png"
    if (root / SAMPLE).exists():
        capture.write_bytes((root / SAMPLE).read_bytes())

    print("3. asking the local site what to craft")
    server = subprocess.Popen(
        [args.node, str(root / "web" / "server.js"), "--port", str(args.port), "--no-open"],
        cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )
    base = f"http://127.0.0.1:{args.port}"
    try:
        deadline = time.time() + 20
        while time.time() < deadline:
            try:
                if http(base + "/api/health", timeout=3)[0] == 200:
                    break
            except (urllib.error.URLError, OSError):
                time.sleep(0.3)
        else:
            failures.append("the site did not start")
            raise SystemExit(1)

        payload = json.loads(http(base + "/api/item")[1])
        item = (payload.get("analysis") or {}).get("item") or {}
        plans = (payload.get("analysis") or {}).get("plans") or []
        options = (payload.get("leagueMethods") or {}).get("options") or []

        print(f"   source={payload.get('source')} image={bool((payload.get('capture') or {}).get('image'))}")
        print(f"   item: {item.get('name')} / {item.get('baseType')} ilvl {item.get('itemLevel')}")
        print(f"   plans={len(plans)} league_options={len(options)}")

        if payload.get("source") != "image":
            failures.append("the site did not record the image source")
        if not (payload.get("capture") or {}).get("image"):
            failures.append("the captured picture is not published")
        if item.get("baseType") != "Blacksteel Gauntlets":
            failures.append(f"base type read as {item.get('baseType')!r}, expected Blacksteel Gauntlets")
        if not plans:
            failures.append("no crafting plans were produced from the OCR text")
        if not options:
            failures.append("no league crafting methods were produced from the OCR text")

        status, image = http(base + "/capture.png")
        print(f"   /capture.png: {status}, {len(image)} bytes")
        if status != 200 or len(image) < 1000:
            failures.append("the capture image endpoint returned nothing useful")
    finally:
        server.terminate()
        try:
            server.wait(timeout=10)
        except subprocess.TimeoutExpired:
            server.kill()

    print(f"RESULT: {'ok' if not failures else str(len(failures)) + ' failure(s)'}")
    for failure in failures:
        print(f"  FAIL {failure}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
