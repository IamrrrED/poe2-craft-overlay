"""Build one template per stash tab from the pages already captured, and prove the templates are distinguishable.

What a template is here: the part of the page just under the tab strip (its own header, sub-tab row, first item
rows). That area carries the tab's identity - the Augments page has its category buttons, the Gems page its level
filters, the Fragments page its sub-tabs - while the text on it is not needed, so the template works in any language.

The script refuses to write a template for a page that duplicates another one: duplicates were the whole reason the
earlier "map" was invalid. It then cross-matches every template against every page and prints the separation
(own page vs the best other page), so a template that is not distinctive is visible as a number, not as a hope.

    python tools/build_tab_templates.py --frames <dir> [--frames <dir>] --out docs/tabs
"""
import argparse
import glob
import json
import os

import numpy as np
from PIL import Image

# The strip is at y 120..170; the identity area sits right under it.
SIGNATURE = (20, 190, 850, 420)
# Pages are compared on the whole panel body.
PANEL = (20, 190, 850, 1010)
DUPLICATE_THRESHOLD = 3.0


def load(path):
    return np.asarray(Image.open(path).convert("L"), dtype=np.float32)


def crop(array, box):
    x0, y0, x1, y1 = box
    return array[y0:y1, x0:x1]


def ncc(a, b):
    """Normalised cross-correlation of two same-shaped patches."""
    a = a - a.mean()
    b = b - b.mean()
    denominator = float(np.sqrt((a * a).sum()) * np.sqrt((b * b).sum()))
    return float((a * b).sum() / denominator) if denominator else 0.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", action="append", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    paths = []
    for directory in args.frames:
        paths.extend(sorted(glob.glob(os.path.join(directory, "tab-*.png"))))
    if not paths:
        raise SystemExit("no captured pages found")

    pages = []
    for path in paths:
        array = load(path)
        panel = crop(array, PANEL)
        duplicate = False
        for entry in pages:
            if panel.shape == entry["panel"].shape and np.abs(panel - entry["panel"]).mean() < DUPLICATE_THRESHOLD:
                duplicate = True
                break
        if duplicate:
            continue
        pages.append({"source": path, "panel": panel, "signature": crop(array, SIGNATURE)})

    os.makedirs(args.out, exist_ok=True)
    for stale in glob.glob(os.path.join(args.out, "*.png")):
        os.remove(stale)

    wrote = []
    for index, entry in enumerate(pages, start=1):
        name = os.path.basename(entry["source"]).replace(".png", "")
        target = os.path.join(args.out, f"tab-{index:02d}.png")
        Image.fromarray(entry["signature"].astype(np.uint8)).save(target)
        wrote.append({"index": index, "template": os.path.basename(target), "source": name})

    # Separation: every template against every page. Own page must score highest by a clear margin.
    report = []
    worst = 1.0
    for entry in wrote:
        template = pages[entry["index"] - 1]["signature"]
        scores = [ncc(template, other["signature"]) for other in pages]
        own = scores[entry["index"] - 1]
        others = [score for position, score in enumerate(scores) if position != entry["index"] - 1]
        best_other = max(others) if others else 0.0
        margin = own - best_other
        worst = min(worst, margin)
        report.append({"template": entry["template"], "source": entry["source"], "own": round(own, 3),
                       "best_other": round(best_other, 3), "margin": round(margin, 3)})

    with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump({"templates": wrote, "separation": report, "worst_margin": round(worst, 3)},
                  handle, ensure_ascii=False, indent=1)

    print(json.dumps({"templates": len(wrote), "pages": len(pages), "worst_margin": round(worst, 3)},
                     ensure_ascii=False))
    for row in report:
        print(f"  {row['template']}  own {row['own']:+.3f}  best other {row['best_other']:+.3f}  "
              f"margin {row['margin']:+.3f}   ({row['source']})")


if __name__ == "__main__":
    main()
