#!/usr/bin/env python3
"""Match an item icon from the game against the local icon index.

What made this work was comparing the right things.

1. Content against content. The game draws an item icon with padding inside its cell; the CDN
   publishes the same artwork cropped to the item. While the two were compared as they came, a
   correct icon sat at position 24 of 487; once both are cut to the item's own bounding box it
   comes first.
2. Shape and colour, not raw pixels. Pixel correlation alone let a featureless dark trinket beat
   the item actually on screen. A histogram of gradient directions over an 8x8 grid (shape and
   texture) combined with a coarse colour histogram separates them, and raises the score of a
   correct match from ~0.5 to ~0.7-0.9.
3. Emptiness by energy, not by score. A cosine comparison of normalised histograms is high even
   for empty cells, so "is there anything here" is decided by how much gradient energy the cell
   carries: an occupied cell measured 21-40, an empty one 8.6.

The stack count sits in the top-left corner. Masking a whole rectangle there erases part of the
item (the Omen of Gambling keeps its coins in that corner), so only the white digits and a thin
halo are removed - and only when the white area is small enough to be digits rather than artwork.

Public surface: load_index, Index, prepare, correlation, ACCEPT, ENERGY_FLOOR.
"""

from __future__ import annotations

import pathlib

import numpy
from PIL import Image

SIZE = 64
FRAME_TRIM = 0.11          # поля ячейки, которые срезаются у снимка игры
ACCEPT = 0.52              # ниже этого балла совпадением считать нельзя
ENERGY_FLOOR = 14.0        # ниже этой энергии градиентов ячейка считается пустой
W_PIXEL, W_SHAPE, W_COLOUR = 0.40, 0.40, 0.20


def content_box(image: Image.Image) -> tuple[int, int, int, int]:
    """Bounding box of the item itself: by alpha when the artwork has it, else by background."""
    if image.mode in ("RGBA", "LA"):
        alpha = numpy.asarray(image.convert("RGBA"))[:, :, 3]
        if alpha.max() > 0 and (alpha < 250).mean() < 0.98:
            ys, xs = numpy.where(alpha > 24)
            if len(xs):
                return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
    grey = numpy.asarray(image.convert("L"), dtype=numpy.float32)
    background = numpy.median(grey)
    ys, xs = numpy.where(numpy.abs(grey - background) > 22)
    if len(xs) < 30:
        return 0, 0, image.width, image.height
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def strip_count_badge(data: numpy.ndarray) -> numpy.ndarray:
    """Remove the white stack digits from the corner, keeping the item underneath."""
    height, width, _ = data.shape
    white_all = (data.min(axis=2) > 195) & ((data.max(axis=2) - data.min(axis=2)) < 40)
    # Spelled out: digits are a small white blob; a white item (the marble head of an Orb of
    # Annulment) covers much of the cell, and erasing it cost a correct match before this guard.
    if white_all.mean() > 0.18:
        return data
    qh, qw = max(8, int(height * 0.4)), max(8, int(width * 0.4))
    corner = data[:qh, :qw]
    white = (corner.min(axis=2) > 195) & ((corner.max(axis=2) - corner.min(axis=2)) < 40)
    if white.sum() < 8:
        return data
    grown = white.copy()
    for _ in range(2):
        grown = (grown | numpy.roll(grown, 1, 0) | numpy.roll(grown, -1, 0)
                 | numpy.roll(grown, 1, 1) | numpy.roll(grown, -1, 1))
    corner[grown] = data[qh:, qw:].reshape(-1, 3).mean(axis=0)
    return data


def prepare(path: pathlib.Path, from_screenshot: bool = False) -> numpy.ndarray:
    """Read an image and normalise it to a 64x64 block of the item alone."""
    with Image.open(path) as raw:
        image = raw.convert("RGB")
        box_source: object = raw
        if from_screenshot:
            dy, dx = int(image.height * FRAME_TRIM), int(image.width * FRAME_TRIM)
            image = image.crop((dx, dy, image.width - dx, image.height - dy))
            box_source = image
        x0, y0, x1, y1 = content_box(box_source)  # type: ignore[arg-type]
        if x1 - x0 < 8 or y1 - y0 < 8:
            x0, y0, x1, y1 = 0, 0, image.width, image.height
        cropped = image.crop((x0, y0, x1, y1)).resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        data = numpy.asarray(cropped, dtype=numpy.float32)
    return strip_count_badge(data)


def correlation(a: numpy.ndarray, b: numpy.ndarray) -> float:
    """Normalised cross-correlation of two blocks: 1.0 means identical, 0.0 means unrelated."""
    a = a - a.mean()
    b = b - b.mean()
    na, nb = float(numpy.sqrt((a * a).sum())), float(numpy.sqrt((b * b).sum()))
    if na < 1e-6 or nb < 1e-6:
        return 0.0
    return float((a * b).sum() / (na * nb))


def shape_features(data: numpy.ndarray) -> tuple[numpy.ndarray, float]:
    """Histogram of gradient directions over an 8x8 grid, plus the mean gradient energy."""
    grey = data.mean(axis=2)
    gx = numpy.zeros_like(grey)
    gy = numpy.zeros_like(grey)
    gx[:, 1:-1] = grey[:, 2:] - grey[:, :-2]
    gy[1:-1, :] = grey[2:, :] - grey[:-2, :]
    magnitude = numpy.hypot(gx, gy)
    # Directions are unsigned (an edge is an edge), so half a turn is mapped onto nine bins.
    bins = numpy.clip(((numpy.arctan2(gy, gx) % numpy.pi) / numpy.pi * 9).astype(int), 0, 8)
    parts = []
    for by in range(0, SIZE, 8):
        for bx in range(0, SIZE, 8):
            cell_magnitude = magnitude[by:by + 8, bx:bx + 8].ravel()
            cell_bins = bins[by:by + 8, bx:bx + 8].ravel()
            parts.append(numpy.bincount(cell_bins, weights=cell_magnitude, minlength=9)[:9])
    vector = numpy.concatenate(parts).astype(numpy.float32)
    return vector / (numpy.linalg.norm(vector) + 1e-6), float(magnitude.mean())


def colour_features(data: numpy.ndarray) -> numpy.ndarray:
    """Coarse colour histogram: eight levels per channel, normalised for cosine comparison."""
    levels = numpy.clip((data / 32).astype(int), 0, 7)
    index = levels[:, :, 0] * 64 + levels[:, :, 1] * 8 + levels[:, :, 2]
    histogram = numpy.bincount(index.ravel(), minlength=512).astype(numpy.float32)
    return histogram / (numpy.linalg.norm(histogram) + 1e-6)


class Index:
    """The icon index, prepared once and reused for every cell."""

    def __init__(self, icons_dir: pathlib.Path):
        self.pixels: dict[str, numpy.ndarray] = {}
        self.shapes: dict[str, numpy.ndarray] = {}
        self.colours: dict[str, numpy.ndarray] = {}
        for path in sorted(icons_dir.glob("*.png")):
            template = prepare(path)
            shape, _ = shape_features(template)
            self.pixels[path.stem] = template
            self.shapes[path.stem] = shape
            self.colours[path.stem] = colour_features(template)

    def __len__(self) -> int:
        return len(self.pixels)

    def score(self, cell: numpy.ndarray) -> list[tuple[float, str]]:
        """Every candidate with its combined score, best first."""
        shape, _ = shape_features(cell)
        colour = colour_features(cell)
        ranked = []
        for name, template in self.pixels.items():
            score = (W_PIXEL * correlation(cell, template)
                     + W_SHAPE * float(shape @ self.shapes[name])
                     + W_COLOUR * float(colour @ self.colours[name]))
            ranked.append((score, name))
        ranked.sort(reverse=True)
        return ranked

    def match(self, cell: numpy.ndarray) -> tuple[float | None, str | None, float, str]:
        """Best candidate, or a reason why the cell carries nothing to match.

        Returns (score, name, margin over the runner-up, note). A name of None means the cell is
        empty or no candidate reached the acceptance floor.
        """
        _, energy = shape_features(cell)
        ranked = self.score(cell)
        if not ranked:
            return None, None, 0.0, "справочник пуст"
        best = ranked[0]
        runner_up = ranked[1][0] if len(ranked) > 1 else 0.0
        margin = best[0] - runner_up
        if energy < ENERGY_FLOOR:
            return None, None, margin, f"пустая ячейка (энергия {energy:.1f})"
        if best[0] < ACCEPT:
            return None, None, margin, f"нет уверенного совпадения (лучший {best[0]:.3f})"
        return best[0], best[1], margin, ""
