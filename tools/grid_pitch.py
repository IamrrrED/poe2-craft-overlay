"""Measure the item grid inside a panel: cell pitch and origin, from the screenshot itself.

Why: hard-coding cell coordinates ties the reader to one resolution and one UI scale. The grid is a regular lattice,
so its period can be measured: the edges between cells produce strong peaks in the row and column profiles, and the
distance between those peaks is the pitch. The panel is anchored by the title found in the same frame, so the only
fixed inputs are the panel's size relative to its title - not where any particular item sits.

    python tools/grid_pitch.py --frame tabs-tab3.png --title 370,104

Prints JSON: {"panel": [x0, y0, x1, y1], "pitch": [px, py], "origin": [ox, oy], "cells": [[x, y], ...]}
"""
import argparse
import json

import numpy as np
from PIL import Image


def edge_profile(region, axis):
    """Sum of absolute differences along one axis: peaks where cell borders are."""
    grey = region.astype(np.float64)
    diff = np.abs(np.diff(grey, axis=axis))
    return diff.sum(axis=1 if axis == 1 else 0)


def dominant_period(profile, minimum=20, maximum=140):
    """The lag with the strongest autocorrelation, i.e. the spacing of the repeating borders."""
    values = profile - profile.mean()
    if not np.any(values):
        return None
    correlation = np.correlate(values, values, mode="full")[len(values) - 1:]
    window = correlation[minimum:maximum]
    if window.size == 0:
        return None
    lag = int(np.argmax(window)) + minimum
    return lag if correlation[lag] > 0 else None


def measure(frame_path, panel, origin_hint):
    image = Image.open(frame_path).convert("L")
    full = np.asarray(image)
    x0, y0, x1, y1 = panel
    region = full[y0:y1, x0:x1]
    if region.size == 0:
        return None

    pitch_x = dominant_period(edge_profile(region, axis=1))
    pitch_y = dominant_period(edge_profile(region, axis=0))
    if pitch_x is None or pitch_y is None:
        return None

    # Cell centres: start half a pitch inside the grid area, then step by the pitch. The grid body begins a little
    # below the tab row, which is where the hint points.
    ox, oy = origin_hint
    cells = []
    columns = max(1, (x1 - ox) // pitch_x)
    rows = max(1, (y1 - oy) // pitch_y)
    for row in range(rows):
        for column in range(columns):
            cells.append([ox + column * pitch_x + pitch_x // 2, oy + row * pitch_y + pitch_y // 2])
    return {
        "panel": [x0, y0, x1, y1],
        "pitch": [pitch_x, pitch_y],
        "origin": [ox, oy],
        "grid": [columns, rows],
        "cells": cells,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frame", required=True)
    parser.add_argument("--title", required=True, help="x,y of the panel title, from find_label.py")
    parser.add_argument("--panel-width", type=int, default=720)
    parser.add_argument("--panel-height", type=int, default=640)
    parser.add_argument("--grid-top", type=int, default=95, help="distance from the panel top to the grid body")
    args = parser.parse_args()

    title_x, title_y = [int(part) for part in args.title.split(",")]
    # The title is centred over the panel; the panel hangs below it. These are relative to the title, so a different
    # resolution or UI scale moves both together.
    panel_left = max(0, title_x - args.panel_width // 2)
    panel_top = max(0, title_y - 40)
    panel = [panel_left, panel_top, panel_left + args.panel_width, panel_top + args.panel_height]
    origin = [panel_left + 24, panel_top + args.grid_top]

    result = measure(args.frame, panel, origin)
    if result is None:
        print(json.dumps({"ok": False, "reason": "no repeating grid found in the panel"}, ensure_ascii=False))
        return
    result["ok"] = True
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
