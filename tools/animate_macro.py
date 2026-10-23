"""Bring a still macro photograph to life: breathing frame, drifting spores, pulsing light, floating dust.

This is a cinemagraph, not a video model: the photograph itself is kept and moved. Four layers are animated
on top of each other -
  * the frame breathes: a slow zoom plus a sub-pixel rise, so the image never sits perfectly still;
  * the light pulses: a soft radial mask is multiplied in and out, which reads as sun through moving leaves;
  * the spore cloud drifts: particles start inside the burst under the cap, rise with a little turbulence and
    fade, additive so they glow;
  * dust motes cross the whole frame at their own speeds.

    <bundled python> tools/animate_macro.py <source.png>
"""

import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

WIDTH = 600
FRAMES = 48
DELAY = 50          # ms per frame -> about 2.4 s loop
SPORES = 34
MOTES = 26
GIF_WIDTH = 440


def load(source):
    image = Image.open(source).convert("RGB")
    height = int(image.height * WIDTH / image.width)
    return image.resize((WIDTH, height), Image.Resampling.LANCZOS)


def glow_particles(size, particles, brightness=1.0):
    """One additive layer of soft dots: draw small discs, blur them, scale."""
    layer = Image.new("L", size, 0)
    draw = ImageDraw.Draw(layer)
    for x, y, radius, alpha in particles:
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=int(255 * alpha * brightness))
    return layer.filter(ImageFilter.GaussianBlur(2.2))


def frame_at(base, index, height, width):
    phase = index / FRAMES
    angle = 2 * np.pi * phase

    # 1. breathing frame: gentle zoom + rise
    zoom = 1.0 + 0.018 * np.sin(angle)
    rise = 3.5 * np.sin(angle + 0.6)
    padded = base.resize((int(width * zoom), int(height * zoom)), Image.Resampling.BICUBIC)
    left = (padded.width - width) // 2
    top = (padded.height - height) // 2 + int(rise)
    frame = padded.crop((left, top, left + width, top + height))

    # 2. light pulse: multiply a soft centre-weighted mask
    mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(mask)
    pulse = 0.5 + 0.5 * np.sin(angle - 0.4)
    radius = int(max(width, height) * (0.62 + 0.05 * pulse))
    mask_draw.ellipse([width // 2 - radius, height // 2 - radius, width // 2 + radius, height // 2 + radius],
                      fill=int(200 + 55 * pulse))
    mask = mask.filter(ImageFilter.GaussianBlur(width * 0.12))
    frame = Image.composite(frame, Image.eval(frame, lambda v: int(v * 0.82)), mask)

    # 3. the spore burst under the cap, rising and fading
    spores = []
    for order in range(SPORES):
        seed = (order * 37) % 100 / 100.0
        life = (phase + seed) % 1.0
        spread = (seed - 0.5)
        x = width * (0.5 + 0.17 * spread) + 26 * spread * life + 5 * np.sin(angle * 2 + order)
        y = height * 0.80 - life * height * 0.42
        radius = 1.2 + 2.6 * (1 - life)
        alpha = 0.85 * (1 - life) ** 1.4
        spores.append((x, y, radius, alpha))
    # 4. dust motes crossing the frame
    for order in range(MOTES):
        seed = (order * 53) % 100 / 100.0
        life = (phase * 0.6 + seed) % 1.0
        x = width * (1.05 - 1.1 * life)
        y = height * (0.12 + 0.75 * ((seed * 7) % 1.0)) + 8 * np.sin(angle + order)
        radius = 1.0 + 1.8 * (1 - life)
        spores.append((x, y, radius, 0.35 * (1 - life)))

    light = glow_particles((width, height), spores, brightness=1.0)
    light = light.filter(ImageFilter.GaussianBlur(1.2))
    glow = Image.merge("RGB", (light, Image.eval(light, lambda v: int(v * 0.92)),
                               Image.eval(light, lambda v: int(v * 0.72))))
    frame = ImageChops.add(frame, glow, scale=1.0, offset=0)
    return frame


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "macro-source.png")
    base = load(source)
    width, height = base.size
    frames = [frame_at(base, index, height, width) for index in range(FRAMES)]

    webp = os.path.join(ROOT, "docs", "macro-alive.webp")
    gif = os.path.join(ROOT, "docs", "macro-alive.gif")
    frames[0].save(webp, save_all=True, append_images=frames[1:], duration=DELAY, loop=0, quality=82,
                   method=4)
    small = [frame.resize((GIF_WIDTH, int(frame.height * GIF_WIDTH / frame.width)), Image.Resampling.LANCZOS) for frame in frames[::2]]
    palette = [frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=160) for frame in small]
    palette[0].save(gif, save_all=True, append_images=palette[1:], duration=DELAY * 2, loop=0, optimize=True,
                    disposal=2)
    print("size:", (width, height), "| webp bytes:", os.path.getsize(webp), "| gif bytes:", os.path.getsize(gif))


if __name__ == "__main__":
    main()
