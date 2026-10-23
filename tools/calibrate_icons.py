#!/usr/bin/env python3
"""Calibration: find the known item icons inside a real stash screenshot.

The whole valuation idea rests on one question - can the icons we indexed be found in a
screenshot the game produced? This script answers it with numbers instead of hope: it slides
every indexed icon over the image at several scales and reports what it finds, where, and with
what score.

Usage:
    python tools/calibrate_icons.py --image "path/to/stash.png"
    python tools/calibrate_icons.py --image shot.png --threshold 0.62 --limit 25
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import numpy
from PIL import Image

DEFAULT_SCALES = [0.55, 0.65, 0.75, 0.85, 0.95, 1.05]


def grey(path: pathlib.Path, size: tuple[int, int] | None = None) -> numpy.ndarray:
    with Image.open(path) as image:
        if size is not None:
            image = image.resize(size, Image.Resampling.LANCZOS)
        return numpy.asarray(image.convert("L"), dtype=numpy.float32)


def normalised(image: numpy.ndarray) -> numpy.ndarray:
    centred = image - image.mean()
    deviation = centred.std()
    return centred / deviation if deviation > 1e-6 else centred


def correlate(image: numpy.ndarray, template: numpy.ndarray) -> numpy.ndarray:
    """Normalised cross-correlation of a template over an image, via FFT."""
    height, width = image.shape
    th, tw = template.shape
    if th >= height or tw >= width:
        return numpy.zeros((1, 1), dtype=numpy.float32)
    shape = (height, width)
    patch = numpy.zeros(shape, dtype=numpy.float32)
    patch[:th, :tw] = normalised(template)
    scores = numpy.fft.irfft2(
        numpy.fft.rfft2(normalised(image)) * numpy.conj(numpy.fft.rfft2(patch)), s=shape)
    # A rolling mean is what makes the score comparable across positions.
    window = numpy.ones((th, tw), dtype=numpy.float32)
    count = numpy.fft.irfft2(
        numpy.fft.rfft2(numpy.ones(shape, dtype=numpy.float32)) * numpy.conj(numpy.fft.rfft2(patch * 0 + window)),
        s=shape)[:height - th + 1, :width - tw + 1]
    valid = numpy.maximum(count, 1.0)
    result = scores[:height - th + 1, :width - tw + 1] / (valid * template.size)
    return result


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True)
    parser.add_argument("--icons", default="tools/cache/icons")
    parser.add_argument("--threshold", type=float, default=0.55)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--scales", default=",".join(str(s) for s in DEFAULT_SCALES))
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    shot_path = pathlib.Path(args.image)
    if not shot_path.is_absolute():
        shot_path = root / shot_path
    if not shot_path.exists():
        print(f"нет файла {shot_path}")
        return 1

    scale_list = [float(part) for part in args.scales.split(",") if part.strip()]
    icons_dir = root / args.icons
    image = normalised(grey(shot_path))
    print(f"  снимок: {shot_path.name}, {image.shape[1]}x{image.shape[0]} px")
    print(f"  иконок в справочнике: {len(list(icons_dir.glob('*.png')))}, масштабов: {len(scale_list)}")

    hits: list[tuple[float, str, int, int, float]] = []
    for icon_path in sorted(icons_dir.glob("*.png")):
        with Image.open(icon_path) as icon_image:
            base = icon_image.convert("L")
        for scale in scale_list:
            size = (max(8, int(base.width * scale)), max(8, int(base.height * scale)))
            template = numpy.asarray(base.resize(size, Image.Resampling.LANCZOS), dtype=numpy.float32)
            scores = correlate(image, template)
            if scores.size == 0:
                continue
            best = float(scores.max())
            if best >= args.threshold:
                y, x = numpy.unravel_index(int(scores.argmax()), scores.shape)
                hits.append((best, icon_path.stem, int(x), int(y), scale))

    hits.sort(reverse=True)
    print(f"  совпадений выше порога {args.threshold}: {len(hits)}")
    for score, name, x, y, scale in hits[:args.limit]:
        print(f"    {score:0.3f}  {name:<28} x={x:<5} y={y:<5} масштаб={scale}")
    if not hits:
        print("    ничего не найдено — нужен другой порог или другой масштаб")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
