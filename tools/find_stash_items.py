#!/usr/bin/env python3
"""Find the items on a stash screenshot and name them, without hovering anything.

How it works
------------
Every indexed item has its artwork from the game's own CDN. The screenshot is searched for that
artwork directly: for each icon the normalised cross-correlation over the whole image gives a
score for every position, and positions above a threshold are peaks, i.e. items. Nothing is
cropped by hand and no grid is guessed - the peaks are the grid.

The score is a correlation coefficient: 1.0 means the artwork is there, 0.0 means it is not.
That is what makes the answer checkable - a stack of four omens has to come back as exactly one
peak per cell, and the names have to match what the tooltip said.

Usage:
    python tools/find_stash_items.py --image shot.png --category Ritual
    python tools/find_stash_items.py --image shot.png --category Ritual --threshold 0.72
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import numpy
from PIL import Image

DEFAULT_SCALES = [1.00]


def load_rgb(path: pathlib.Path, size: tuple[int, int] | None = None) -> numpy.ndarray:
    with Image.open(path) as image:
        if size is not None:
            image = image.resize(size, Image.Resampling.LANCZOS)
        return numpy.asarray(image.convert("RGB"), dtype=numpy.float32)


def match_scores(image: numpy.ndarray, template: numpy.ndarray) -> numpy.ndarray:
    """Colour normalised cross-correlation of a template over an image, position by position.

    Colour matters: sibling items (Omen of Chaotic Monsters against Omen of Chaotic
    Effectiveness) share a shape and differ in hue, and brightness alone confused them.
    """
    height, width, _ = image.shape
    th, tw, _ = template.shape
    if th >= height or tw >= width:
        return numpy.zeros((1, 1), dtype=numpy.float32)

    centred = template - template.reshape(-1, 3).mean(axis=0)
    template_norm = float(numpy.sqrt((centred * centred).sum()))

    padded = numpy.zeros((height, width, 3), dtype=numpy.float32)
    padded[:th, :tw] = centred
    numerator = numpy.zeros((height - th + 1, width - tw + 1), dtype=numpy.float32)
    for channel in range(3):
        layer = numpy.fft.irfft2(
            numpy.fft.rfft2(image[:, :, channel]) * numpy.conj(numpy.fft.rfft2(padded[:, :, channel])),
            s=(height, width))
        numerator += layer[:height - th + 1, :width - tw + 1]

    def box_sum(values: numpy.ndarray) -> numpy.ndarray:
        cumulative = numpy.cumsum(numpy.cumsum(values, axis=0, dtype=numpy.float64), axis=1)
        cumulative = numpy.pad(cumulative, ((1, 0), (1, 0)))
        return (cumulative[th:, tw:] - cumulative[:-th, tw:]
                - cumulative[th:, :-tw] + cumulative[:-th, :-tw])

    count = float(th * tw)
    variance = numpy.zeros_like(numerator, dtype=numpy.float64)
    for channel in range(3):
        layer = image[:, :, channel]
        mean = box_sum(layer) / count
        variance += numpy.maximum(box_sum(layer * layer) / count - mean * mean, 0.0)
    # The denominator needs the L2 norm of the centred patch: the deviation times sqrt(pixels).
    denominator = numpy.sqrt(variance * count) * template_norm
    return numpy.where(denominator > 1e-6, numerator / denominator, 0.0).astype(numpy.float32)


def peaks(scores: numpy.ndarray, threshold: float, radius: int) -> list[tuple[float, int, int]]:
    """Local maxima above a threshold, thinned so one item yields one peak."""
    found: list[tuple[float, int, int]] = []
    work = scores.copy()
    while True:
        index = int(work.argmax())
        score = float(work.flat[index])
        if score < threshold:
            break
        y, x = numpy.unravel_index(index, work.shape)
        found.append((score, int(x), int(y)))
        y0, y1 = max(0, y - radius), min(work.shape[0], y + radius + 1)
        x0, x1 = max(0, x - radius), min(work.shape[1], x + radius + 1)
        work[y0:y1, x0:x1] = -1.0
    return found


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True)
    parser.add_argument("--icons", default="tools/cache/icons")
    parser.add_argument("--category", default="", help="ограничить поиск категорией (Ritual = омены)")
    parser.add_argument("--threshold", type=float, default=0.70)
    parser.add_argument("--limit", type=int, default=12)
    parser.add_argument("--scales", default=",".join(str(s) for s in DEFAULT_SCALES))
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    shot = pathlib.Path(args.image)
    if not shot.is_absolute():
        shot = root / shot
    if not shot.exists():
        print(f"нет файла {shot}")
        return 1

    index_path = root / "src" / "Data" / "icon_index.lua"
    categories: dict[str, str] = {}
    if index_path.exists():
        for line in index_path.read_text(encoding="utf-8").splitlines():
            if "category =" not in line or "name =" not in line:
                continue
            name = line.split('name = "')[1].split('"')[0]
            file_name = line.split('file = "')[1].split('"')[0].replace(".png", "") if 'file = "' in line else name
            category = line.split('category = "')[1].split('"')[0]
            categories[file_name] = category

    image = load_rgb(shot)
    scale_list = [float(p) for p in args.scales.split(",") if p.strip()]
    icons_dir = root / args.icons
    candidates = []
    for path in sorted(icons_dir.glob("*.png")):
        name = path.stem
        if args.category and categories.get(name) and categories[name] != args.category:
            continue
        candidates.append(path)
    print(f"  снимок: {shot.name} {image.shape[1]}x{image.shape[0]}, иконок к поиску: {len(candidates)}")

    results: list[tuple[float, str, int, int, float]] = []
    for path in candidates:
        with Image.open(path) as icon_image:
            base = icon_image.convert("RGB")
        for scale in scale_list:
            size = (max(10, int(base.width * scale)), max(10, int(base.height * scale)))
            template = numpy.asarray(base.resize(size, Image.Resampling.LANCZOS), dtype=numpy.float32)
            scores = match_scores(image, template)
            for score, x, y, in peaks(scores, args.threshold, max(12, size[0] // 3)):
                results.append((score, path.stem, x, y, scale))

    # One item per position: keep the best-scoring name for each spot on the screen.
    results.sort(reverse=True)
    chosen: list[tuple[float, str, int, int, float]] = []
    for score, name, x, y, scale in results:
        if any(abs(x - cx) < 24 and abs(y - cy) < 24 for _, _, cx, cy, _ in chosen):
            continue
        chosen.append((score, name, x, y, scale))

    print(f"  найдено позиций: {len(chosen)} (порог {args.threshold})")
    for score, name, x, y, scale in chosen[:args.limit]:
        print(f"    {score:0.3f}  {name:<32} x={x:<5} y={y:<5} масштаб={scale:0.2f}")
    summary: dict[str, int] = {}
    for _, name, _, _, _ in chosen:
        summary[name] = summary.get(name, 0) + 1
    print("  итог по названиям:")
    for name, count in sorted(summary.items(), key=lambda kv: -kv[1]):
        print(f"    {count:>3} × {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
