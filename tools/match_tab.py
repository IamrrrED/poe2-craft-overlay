"""Which stash tab is on screen, and is it the expected one?

Matches the identity area of the live frame against every template in docs/tabs and reports the best one together
with the name recorded in docs/tabs/names.json. Templates, not labels: a tab can be renamed by its owner and the
game language can differ, but the page's pixels are the same.

    python tools/match_tab.py --frame docs/preflight.png --expect currency
    -> {"ok": true, "tab": "tab-10.png", "tab_name": "валюта (ваша вкладка)", "score": 1.0, "expect": "currency"}
"""
import argparse
import glob
import json
import os

import numpy as np
from PIL import Image

SIGNATURE = (20, 190, 850, 420)
# A template has to win by this much over the runner-up to be trusted.
MIN_SCORE = 0.85


def ncc(a, b):
    a = a - a.mean()
    b = b - b.mean()
    denominator = float(np.sqrt((a * a).sum()) * np.sqrt((b * b).sum()))
    return float((a * b).sum() / denominator) if denominator else 0.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frame", required=True)
    parser.add_argument("--expect", default="")
    parser.add_argument("--tabs", default="")
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    tabs_dir = args.tabs or os.path.join(root, "docs", "tabs")
    names_path = os.path.join(tabs_dir, "names.json")
    names = json.load(open(names_path, encoding="utf-8")) if os.path.exists(names_path) else {}

    frame = np.asarray(Image.open(args.frame).convert("L"), dtype=np.float32)
    live = frame[SIGNATURE[1]:SIGNATURE[3], SIGNATURE[0]:SIGNATURE[2]]

    scores = []
    for path in sorted(glob.glob(os.path.join(tabs_dir, "tab-*.png"))):
        template = np.asarray(Image.open(path).convert("L"), dtype=np.float32)
        if template.shape != live.shape:
            continue
        scores.append((ncc(live, template), os.path.basename(path)))
    if not scores:
        print(json.dumps({"ok": False, "reason": "no templates", "expect": args.expect}, ensure_ascii=False))
        return
    scores.sort(reverse=True)
    best_score, best_file = scores[0]
    entry = names.get(best_file, {})
    tab_name = entry.get("name", best_file)
    kind = entry.get("kind", "unknown")
    expect = args.expect.strip().lower()

    ok = best_score >= MIN_SCORE
    if expect and expect not in (kind.lower(), tab_name.lower()):
        ok = False

    print(json.dumps({
        "ok": ok,
        "tab": best_file,
        "tab_name": tab_name,
        "kind": kind,
        "score": round(best_score, 3),
        "runner_up": {"tab": scores[1][1], "score": round(scores[1][0], 3)} if len(scores) > 1 else None,
        "expect": args.expect,
        "min_score": MIN_SCORE,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
