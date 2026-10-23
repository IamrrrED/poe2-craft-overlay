#!/usr/bin/env python3
"""Read a stash tab from a screenshot: find the slots and name what is inside them.

Slots are not found by a grid, and that was the mistake for a long time. Specialised tabs -
currency, essences, catalysts, splinters - have their own layouts, with slots of different sizes
and different gaps, so any single lattice describes some tabs and misses others.

What every slot has in common is its appearance: a dark navy interior, while the tab background is
reddish stone. So the slots are found as connected regions of that navy mask. Size and spacing
stop mattering, because nothing is assumed about them.

The magenta marker, when present, only reports the measured slot size as a sanity check - the
recognition itself no longer depends on it.

Usage:
    python tools/read_stash_tab.py --image shot.png
    python tools/read_stash_tab.py --image shot.png --annotate docs/tab_read.png
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import numpy
from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import icon_match  # pyright: ignore  # sibling script, resolved from this directory at runtime

NAVY_BLUE_MARGIN = 15
NAVY_MIN_BLUE = 40
MIN_SLOT_PIXELS = 220      # меньше этого — шум, а не слот
MIN_SLOT_SIDE = 20


def navy_mask(image: numpy.ndarray) -> numpy.ndarray:
    """Слоты тайника: синий канал заметно выше красного, и сам синий не тёмный."""
    red = image[:, :, 0].astype(numpy.int16)
    blue = image[:, :, 2].astype(numpy.int16)
    return (blue > red + NAVY_BLUE_MARGIN) & (blue > NAVY_MIN_BLUE)


def find_slots(mask: numpy.ndarray) -> list[tuple[int, int, int, int, int]]:
    """Связные области синей внутренности: каждая и есть слот. Размер и промежутки не важны."""
    height, width = mask.shape
    # Предмет перекрывает подложку слота, поэтому синее остаётся обрывками. Закрытие
    # (расширение с последующим сужением) склеивает обрывки одной ячейки, не затрагивая
    # соседние: между ячейками промежуток заметно больше радиуса склейки.
    grown = mask.copy()
    for _ in range(6):
        grown = (grown | numpy.roll(grown, 1, 0) | numpy.roll(grown, -1, 0)
                 | numpy.roll(grown, 1, 1) | numpy.roll(grown, -1, 1))
    shrunk = grown.copy()
    for _ in range(6):
        shrunk = (shrunk & numpy.roll(shrunk, 1, 0) & numpy.roll(shrunk, -1, 0)
                  & numpy.roll(shrunk, 1, 1) & numpy.roll(shrunk, -1, 1))
    mask = shrunk
    seen = numpy.zeros((height, width), dtype=bool)
    boxes: list[tuple[int, int, int, int, int]] = []
    ys, xs = numpy.where(mask)
    for start_y, start_x in zip(ys.tolist(), xs.tolist()):
        if seen[start_y, start_x]:
            continue
        stack = [(start_y, start_x)]
        seen[start_y, start_x] = True
        min_x = max_x = start_x
        min_y = max_y = start_y
        size = 0
        while stack:
            current_y, current_x = stack.pop()
            size += 1
            if current_x < min_x:
                min_x = current_x
            elif current_x > max_x:
                max_x = current_x
            if current_y < min_y:
                min_y = current_y
            elif current_y > max_y:
                max_y = current_y
            for next_y, next_x in ((current_y - 1, current_x), (current_y + 1, current_x),
                                   (current_y, current_x - 1), (current_y, current_x + 1)):
                if 0 <= next_y < height and 0 <= next_x < width:
                    if mask[next_y, next_x] and not seen[next_y, next_x]:
                        seen[next_y, next_x] = True
                        stack.append((next_y, next_x))
        if size >= MIN_SLOT_PIXELS and (max_x - min_x) >= MIN_SLOT_SIDE and (max_y - min_y) >= MIN_SLOT_SIDE:
            boxes.append((min_x, min_y, max_x + 1, max_y + 1, size))
    boxes.sort(key=lambda box: (box[1] // 40, box[0]))
    return boxes


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True)
    parser.add_argument("--icons", default="tools/cache/icons")
    parser.add_argument("--cells", default="tools/cache/cells")
    parser.add_argument("--annotate", default="")
    parser.add_argument("--limit", type=int, default=30)
    args = parser.parse_args(argv)

    root = pathlib.Path(__file__).resolve().parent.parent
    shot_path = pathlib.Path(args.image)
    if not shot_path.is_absolute():
        shot_path = root / shot_path
    if not shot_path.exists():
        print(f"нет файла {shot_path}")
        return 1

    cells_dir = root / args.cells
    cells_dir.mkdir(parents=True, exist_ok=True)
    with Image.open(shot_path) as raw:
        shot = raw.convert("RGB")
    image = numpy.asarray(shot)
    mask = navy_mask(image)
    slots = find_slots(mask)
    sizes = [max(box[2] - box[0], box[3] - box[1]) for box in slots]
    if not sizes:
        print(f"  снимок {image.shape[1]}x{image.shape[0]}: слотов не найдено")
        return 1
    print(f"  снимок {image.shape[1]}x{image.shape[0]}: слотов {len(slots)}, "
          f"размеры от {min(sizes)} до {max(sizes)} px (медиана {int(numpy.median(sizes))})")

    index = icon_match.Index(root / args.icons)
    results = []
    for number, (left, top, right, bottom, _) in enumerate(slots):
        crop = shot.crop((left, top, right, bottom))
        cell_path = cells_dir / f"slot_{number:03d}.png"
        crop.save(cell_path)
        score, name, margin, _ = index.match(icon_match.prepare(cell_path))
        if name:
            results.append(((left + right) // 2, (top + bottom) // 2, score, margin, name,
                            (right - left, bottom - top)))

    print(f"  опознано предметов: {len(results)} из {len(slots)}")
    for cx, cy, score, margin, name, box in sorted(results, key=lambda r: -r[2])[:args.limit]:
        print(f"    {score:0.3f} (запас {margin:+0.3f}) {name:<34} x={cx:<5} y={cy:<5} {box[0]}x{box[1]}")

    summary: dict[str, int] = {}
    for _, _, _, _, name, _ in results:
        summary[name] = summary.get(name, 0) + 1
    print("  по названиям:")
    for name, count in sorted(summary.items(), key=lambda kv: -kv[1]):
        print(f"    {count:>3} × {name}")

    if args.annotate:
        canvas = shot.copy()
        draw = ImageDraw.Draw(canvas)
        for left, top, right, bottom, _ in slots:
            draw.rectangle((left, top, right, bottom), outline=(70, 90, 130), width=1)
        for cx, cy, score, margin, name, _ in results:
            draw.rectangle((cx - 20, cy - 20, cx + 20, cy + 20), outline=(255, 210, 90), width=2)
            draw.text((cx - 18, cy - 18), name.replace("omen-of-", "")[:14], fill=(255, 235, 160))
        out = root / args.annotate
        out.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(out)
        print(f"  размечено: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
