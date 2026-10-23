"""Turn the supplied mushroom picture into the overlay's launch indicator.

Run it after replacing overlay/Ui/mushroom-source.png:

    python tools/make_indicator.py

Why this is not a one line crop. The source file has no alpha channel: its 'transparent'
checkerboard is painted into the pixels as a strict 20 px grid, alternating 255 and 239, under a
gentle vignette - and the subject was composited onto it. So the transparency has to be recovered.

A brightness threshold cannot recover it. The mushroom's white spots, its gills and much of its stem
are exactly as bright as the bare background, so any threshold either keeps checkerboard or punches
holes in the subject (the spots fell out of the cap in an early attempt).

What works: the background is one connected region, so the mask is built by flooding inwards from the
border through pixels that could be background (bright and neutral) and calling everything the flood
cannot reach the subject. Enclosed bright areas - the spots - stay subject by construction.

The same rule then closes the gaps the outline leaves open. Between the two stems the backdrop shows
through, and a hole the flood cannot reach from the border is enclosed by the subject, so it is a gap
inside the silhouette rather than part of its outline: it is filled. Otherwise the indicator reads as
two mushrooms with white showing between their stems.

Pixels are then un-premultiplied, because the observed colour is the subject mixed with the
checkerboard behind it:  observed = alpha * subject + (1 - alpha) * backdrop.
"""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = Path(__file__).resolve().parent.parent / "overlay" / "Ui" / "mushroom-source.png"
DEST = Path(__file__).resolve().parent.parent / "overlay" / "Ui" / "mushroom.png"
# The same picture, with the gap between the stems filled in by hand in a loud colour. It is how the
# customer said which pixels are backdrop: the two stems of this illustration really do have a gap
# between them, and part of it is bright enough that the flood reads it as subject.
GAP_MARK = Path(__file__).resolve().parent.parent / "overlay" / "Ui" / "mushroom-gap-marked.png"
GAP_MARK_COLOUR = (237, 45, 255)     # ED2DFF

GRID = 20
LIGHT, DARK = 255.0, 239.0
TARGET_WIDTH = 160        # keep in step with ArtWidth/ArtHeight in overlay/SplashForm.cs
BACKGROUND_SAT = 7        # the backdrop is neutral
BACKGROUND_LUM = 228      # and bright; the stem sits lower than this, so the flood cannot leak into it


def largest_blob(mask):
    """Keep only the biggest connected group, so a stray mark elsewhere cannot punch a hole."""
    labels = np.zeros(mask.shape, dtype=np.int32)
    current = 0
    best_size, best_label = 0, 0
    height, width = mask.shape
    for start_y in range(height):
        for start_x in range(width):
            if not mask[start_y, start_x] or labels[start_y, start_x]:
                continue
            current += 1
            queue = deque([(start_y, start_x)])
            labels[start_y, start_x] = current
            size = 0
            while queue:
                y, x = queue.popleft()
                size += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = current
                        queue.append((ny, nx))
            if size > best_size:
                best_size, best_label = size, current
    return labels == best_label


def box_blur(field, radius):
    """A separable box mean, three passes: close enough to a Gaussian, and it takes float arrays."""
    result = field.astype(np.float32)
    height, width = result.shape
    for _ in range(3):
        padded = np.pad(result, ((radius, radius), (0, 0)), mode="edge")
        cumulative = np.vstack([np.zeros((1, width), np.float32), np.cumsum(padded, axis=0)])
        result = (cumulative[2 * radius + 1:] - cumulative[:-(2 * radius + 1)]) / (2 * radius + 1)
        padded = np.pad(result, ((0, 0), (radius, radius)), mode="edge")
        cumulative = np.hstack([np.zeros((height, 1), np.float32), np.cumsum(padded, axis=1)])
        result = (cumulative[:, 2 * radius + 1:] - cumulative[:, :-(2 * radius + 1)]) / (2 * radius + 1)
    return result


def main():
    img = Image.open(SRC).convert("RGB")
    rgb = np.asarray(img).astype(np.float32)
    height, width = rgb.shape[:2]
    print(f"source {width}x{height}")

    sat = rgb.max(axis=2) - rgb.min(axis=2)
    lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]

    # --- flood the background inwards from the border -------------------------------------------
    could_be_background = (sat <= BACKGROUND_SAT) & (lum >= BACKGROUND_LUM)
    reached = np.zeros((height, width), dtype=bool)
    queue = deque()
    for x in range(width):
        for y in (0, height - 1):
            if could_be_background[y, x] and not reached[y, x]:
                reached[y, x] = True
                queue.append((y, x))
    for y in range(height):
        for x in (0, width - 1):
            if could_be_background[y, x] and not reached[y, x]:
                reached[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < height and 0 <= nx < width and could_be_background[ny, nx] and not reached[ny, nx]:
                reached[ny, nx] = True
                queue.append((ny, nx))

    subject = ~reached
    print(f"subject {100 * subject.mean():.1f}% of the frame")

    # --- alpha -----------------------------------------------------------------------------------
    alpha = box_blur(subject.astype(np.float32), 1)
    alpha_img = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), mode="L")
    alpha_img = alpha_img.filter(ImageFilter.MedianFilter(size=3))
    alpha = np.asarray(alpha_img).astype(np.float32) / 255.0
    alpha[alpha < 0.35] = 0.0
    alpha[alpha > 0.92] = 1.0

    # --- reopen the gap between the stems ----------------------------------------------------------
    # The two stems have a real gap between them - the backdrop shows through and nothing should be
    # drawn there - but part of that gap is bright and neutral enough that the flood read it as
    # subject, so it came out opaque and pale. The area is taken from the mark the customer drew on
    # the source (GAP_MARK / GAP_MARK_COLOUR) instead of being guessed: the marked pixels become
    # transparent, widened slightly and feathered, so a rim of pale backdrop just outside the mark
    # cannot survive as an edge either.
    if GAP_MARK.exists():
        marked = np.asarray(Image.open(GAP_MARK).convert("RGB")).astype(int)
        red, green, blue = marked[..., 0], marked[..., 1], marked[..., 2]
        marked_pixels = ((np.abs(red - GAP_MARK_COLOUR[0]) < 45)
                         & (np.abs(green - GAP_MARK_COLOUR[1]) < 55)
                         & (np.abs(blue - GAP_MARK_COLOUR[2]) < 45))
        marked_pixels = largest_blob(marked_pixels)
        ys, xs = np.nonzero(marked_pixels)
        hole = Image.new("L", (width, height), 0)
        pen = ImageDraw.Draw(hole)
        for y, x in zip(ys.tolist(), xs.tolist()):
            pen.rectangle([x - 1.2, y - 1.2, x + 1.2, y + 1.2], fill=255)
        hole = hole.filter(ImageFilter.GaussianBlur(0.8))
        hole = hole.filter(ImageFilter.MaxFilter(3))
        hole = hole.filter(ImageFilter.GaussianBlur(0.7))
        hole_mask = np.asarray(hole).astype(np.float32) / 255.0
        print(f"gap reopened: {marked_pixels.sum()} marked pixels, "
              f"{int((hole_mask > 0.5).sum())} made transparent")
        alpha = alpha * (1.0 - hole_mask)
    else:
        print(f"gap mark not found at {GAP_MARK}; the gap between the stems stays as it is")

    # --- un-premultiply --------------------------------------------------------------------------
    square_level = np.where(
        ((np.arange(height)[:, None] // GRID + np.arange(width)[None, :] // GRID) % 2) == 1, LIGHT, DARK)
    safe = np.maximum(alpha, 1e-3)[..., None]
    recovered = (rgb - (1.0 - alpha[..., None]) * square_level[..., None]) / safe
    colours = np.clip(np.where((alpha < 0.7)[..., None], rgb, recovered), 0, 255)

    cut = Image.fromarray(np.dstack([colours, alpha * 255.0]).astype(np.uint8), mode="RGBA")
    ys, xs = np.nonzero(alpha > 0.35)
    cut = cut.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    print(f"trimmed to {cut.size}")

    final = cut.resize((TARGET_WIDTH, round(cut.height * TARGET_WIDTH / cut.width)),
                       Image.Resampling.LANCZOS)

    # --- make the edge binary ---------------------------------------------------------------------
    # The window is transparent by an exact colour key, so a semi-transparent pixel is not see
    # through: it is composited onto the key colour and drawn as an opaque dark pixel. Downscaling
    # leaves such pixels along the whole silhouette (about 9% of the picture), and together they read
    # as a frame drawn around the mushroom - the customer asked for it to go. With the alpha snapped
    # to nothing but 0 and 255 there is nothing left to blend, and the silhouette edge is as crisp as
    # the alpha channel allows.
    final_alpha = np.asarray(final)[..., 3]
    hard = np.where(final_alpha >= 128, 255, 0).astype(np.uint8)
    print(f"binary edge: {int(((final_alpha > 0) & (final_alpha < 255)).sum())} soft pixels removed")
    array = np.asarray(final).copy()
    array[..., 3] = hard
    final = Image.fromarray(array, mode="RGBA")

    final.save(DEST)
    print(f"indicator picture: {final.size} -> {DEST}")


if __name__ == "__main__":
    main()
