"""Find the game's interaction label (for example «Тайник») in a screenshot.

Why this exists: the stash cannot be opened by a fixed screen point. Measured twice on a live client, the label sat
at 638,423 in one frame and at about 190,408 in another - its position follows the camera and where the character
stands. So the point has to be FOUND in the current frame before anything is clicked.

How: normalised cross-correlation, computed with FFTs and local mean/variance from integral images, on a frame
downscaled by two. No OCR, no model, no new dependency: Pillow and numpy are enough, and the template is a crop of
the label itself.

    python tools/find_label.py --frame shot.png --template stash-label.png [--region 0.05,0.10,0.70,0.85]

Prints one JSON line: {"found": true, "x": 190, "y": 408, "score": 0.93, "size": [w, h]} in frame pixels, or
{"found": false, "score": ...}. Only the world area is searched by default, because a label is never in the HUD.
"""
import argparse
import json

import numpy as np
from PIL import Image


def sat(image):
    """Summed-area table with a one-pixel border: sum of image[:i, :j] sits at sat[i, j]."""
    height, width = image.shape
    table = np.zeros((height + 1, width + 1), dtype=np.float64)
    table[1:, 1:] = image.astype(np.float64).cumsum(axis=0).cumsum(axis=1)
    return table


def window_sums(table, th, tw):
    """Every th x tw window sum, read in four slices of the table."""
    height, width = table.shape[0] - 1, table.shape[1] - 1
    return (table[th:height + 1, tw:width + 1]
            - table[0:height - th + 1, tw:width + 1]
            - table[th:height + 1, 0:width - tw + 1]
            + table[0:height - th + 1, 0:width - tw + 1])


def match(frame, template):
    """Normalised cross-correlation of the template over the frame, via FFT."""
    fh, fw = frame.shape
    th, tw = template.shape
    if th >= fh or tw >= fw:
        return None

    f = frame.astype(np.float64)
    t = template.astype(np.float64)
    t_zero = t - t.mean()
    t_energy = float(np.sqrt((t_zero ** 2).sum()))
    if t_energy == 0:
        return None

    # C[y, x] = sum over the window of f[y+i, x+j] * t[i, j], which is F * conj(T) in the frequency domain.
    # The ZERO-MEAN template goes into the FFT: correlating with the raw template would carry the plate
    # brightness into the numerator and turn a correlation coefficient into a huge unrelated number.
    spectrum = np.fft.rfft2(f) * np.conj(np.fft.rfft2(t_zero, f.shape))
    correlation = np.fft.irfft2(spectrum, f.shape)[:fh - th + 1, :fw - tw + 1]

    count = th * tw
    mean = window_sums(sat(f), th, tw) / count
    square_mean = window_sums(sat(f * f), th, tw) / count
    variance = np.maximum(square_mean - mean * mean, 1e-9)
    # The denominator is the product of the two standard deviations SUM (not averaged): sqrt(sum of squares)
    # for the window and the template energy. An extra factor of the window size was in the first version and
    # pressed a perfect match down to 0.03.
    score = correlation / (np.sqrt(variance * count) * t_energy)
    return np.nan_to_num(score, nan=0.0, posinf=0.0, neginf=0.0)

def find(frame_path, template_path, region, downscale=2.0, min_score=0.55):
    frame_image = Image.open(frame_path).convert("L")
    template_image = Image.open(template_path).convert("L")
    full = np.asarray(frame_image)
    height, width = full.shape

    x0 = int(width * region[0])
    y0 = int(height * region[1])
    x1 = int(width * region[2])
    y1 = int(height * region[3])
    window = full[y0:y1, x0:x1]

    size = (max(1, int(window.shape[1] / downscale)), max(1, int(window.shape[0] / downscale)))
    small_frame = Image.fromarray(window).resize(size, Image.BILINEAR)
    small_template = template_image.resize(
        (max(1, int(template_image.width / downscale)), max(1, int(template_image.height / downscale))),
        Image.BILINEAR)

    score = match(np.asarray(small_frame), np.asarray(small_template))
    if score is None:
        return {"found": False, "score": 0.0, "reason": "template larger than the search region"}

    index = int(np.argmax(score))
    peak_y, peak_x = np.unravel_index(index, score.shape)
    best = float(score[peak_y, peak_x])

    # Back to frame pixels: the search region offset plus the peak, scaled up again.
    frame_x = x0 + int((peak_x + small_template.width / 2.0) * downscale)
    frame_y = y0 + int((peak_y + small_template.height / 2.0) * downscale)
    return {
        "found": best >= min_score,
        "x": frame_x,
        "y": frame_y,
        "score": round(best, 3),
        "size": [template_image.width, template_image.height],
        "region": [x0, y0, x1, y1],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frame", required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--region", default="0.05,0.10,0.70,0.85",
                        help="x0,y0,x1,y1 as fractions of the frame; the world area by default")
    parser.add_argument("--downscale", type=float, default=2.0)
    parser.add_argument("--min-score", type=float, default=0.55,
                        help="a title has to match much better than a label on a busy background")
    parser.add_argument("--save-crop", default=None)
    args = parser.parse_args()

    region = [float(part) for part in args.region.split(",")]
    result = find(args.frame, args.template, region, args.downscale, args.min_score)
    if result.get("found") and args.save_crop:
        half_w = result["size"][0] // 2
        half_h = result["size"][1] // 2
        image = Image.open(args.frame).convert("RGB")
        box = (result["x"] - half_w, result["y"] - half_h, result["x"] + half_w, result["y"] + half_h)
        image.crop(box).save(args.save_crop)
        result["crop"] = args.save_crop
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
