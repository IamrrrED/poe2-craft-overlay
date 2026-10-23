"""Render the six running-mushroom indicators as ONE animated GIF, so the movement can be judged without a browser.

Pillow draws every frame: legs swing on a sine wave, the body leans and bobs, the cap lags a little, and each
variant adds its own joke (sweat, splash, tongue, breath puffs, stars, scarf). Drawn at 3x and downsampled, so
the edges are smooth; the palette is quantised to 128 colours, which is plenty for flat cartoon shapes and
keeps the file small.

    <bundled python> tools/gen_mushroom_gif.py
"""

import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "docs", "mushroom-runner-variants.gif")

SS = 3                       # supersampling factor
CELL_W, CELL_H = 300, 104    # one tile, final pixels
COLS, ROWS = 2, 3
FRAMES = 30                  # ~1.4 s at 40 ms
DURATION = 40

BG = (18, 18, 18)
CARD = (27, 27, 27)
EDGE = (44, 44, 44)
GROUND = (58, 58, 58)
CAP = (188, 56, 42)
CAP_DARK = (148, 40, 30)
SPOT = (245, 233, 208)
STEM = (238, 226, 200)
EYE = (28, 28, 24)
SHADOW = (12, 12, 12)
DUST = (62, 62, 62)
BLUE = (127, 209, 255)
PUDDLE = (37, 66, 92)
SPLASH = (77, 134, 179)
STAR = (242, 193, 78)
SCARF = (211, 84, 0)
TONGUE = (229, 115, 115)


def rot(px, py, degrees):
    angle = math.radians(degrees)
    cos, sin = math.cos(angle), math.sin(angle)
    return px * cos - py * sin, px * sin + py * cos


def body_image(scale=1.0, eye_scale=1.0):
    """The mushroom WITHOUT legs: cap, spots, stem and eyes, centred at the bottom of its own image."""
    width, height = int(56 * SS), int(64 * SS)
    layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx = width // 2
    # stem
    stem_w, stem_top, stem_bottom = int(18 * SS), int(26 * SS), int(44 * SS)
    draw.rounded_rectangle([cx - stem_w // 2, stem_top, cx + stem_w // 2, stem_bottom],
                           radius=int(7 * SS), fill=STEM)
    # cap: a wide ellipse with a slightly darker rim
    cap_w, cap_h = int(52 * SS * scale), int(30 * SS * scale)
    draw.ellipse([cx - cap_w // 2, int(6 * SS), cx + cap_w // 2, int(6 * SS) + cap_h], fill=CAP_DARK)
    draw.ellipse([cx - cap_w // 2 + int(2 * SS), int(4 * SS), cx + cap_w // 2 - int(2 * SS),
                  int(4 * SS) + cap_h], fill=CAP)
    # spots
    draw.ellipse([cx - int(14 * SS), int(11 * SS), cx - int(6 * SS), int(17 * SS)], fill=SPOT)
    draw.ellipse([cx + int(4 * SS), int(9 * SS), cx + int(11 * SS), int(15 * SS)], fill=SPOT)
    draw.ellipse([cx - int(2 * SS), int(18 * SS), cx + int(3 * SS), int(22 * SS)], fill=SPOT)
    # eyes
    eye_w, eye_h = int(4 * SS * eye_scale), int(5 * SS * eye_scale)
    for dx in (-int(6 * SS), int(3 * SS)):
        draw.ellipse([cx + dx, int(31 * SS), cx + dx + eye_w, int(31 * SS) + eye_h], fill=EYE)
    return layer


def draw_legs(draw, cx, base_y, phase, stride, colour=STEM):
    """Two legs swinging out of phase: hip -> knee -> foot, so the feet step OUTSIDE the stem silhouette.

    A straight leg from the hip stayed hidden behind the stem, which made the whole cycle read as a floating
    mushroom. The knee gives the swing a visible shape and the foot lands past the body.
    """
    for side, offset in ((-1, 0.0), (1, math.pi)):
        swing = math.sin(phase * 2 * math.pi + offset) * (stride / 30.0)
        hip_x, hip_y = cx + side * 4 * SS, base_y - int(18 * SS)
        knee_x, knee_y = hip_x + side * (5 + 5 * swing) * SS, base_y - int(9 * SS)
        foot_x = cx + side * (11 + 7 * swing) * SS
        foot_y = base_y - int(1 * SS) - int(5 * SS * max(0.0, swing))
        draw.line([(hip_x, hip_y), (knee_x, knee_y)], fill=colour, width=int(7 * SS))
        draw.line([(knee_x, knee_y), (foot_x, foot_y)], fill=colour, width=int(6 * SS))
        draw.ellipse([foot_x - 4 * SS, foot_y - 4 * SS, foot_x + 4 * SS, foot_y + 4 * SS], fill=colour)


def paste_body(frame, cx, base_y, lean, scale=1.0, eye_scale=1.0):
    layer = body_image(scale, eye_scale)
    layer = layer.rotate(-lean, resample=Image.Resampling.BICUBIC, center=(layer.width // 2, int(46 * SS)))
    frame.alpha_composite(layer, (int(cx - layer.width // 2), int(base_y - 44 * SS)))


def dust(draw, cx, base_y, phase, reach=26, count=3):
    for index in range(count):
        t = (phase + index / count) % 1.0
        radius = (3 + 5 * t) * SS
        alpha = int(150 * (1 - t))
        x = cx - (10 + reach * t) * SS
        y = base_y - (2 + 4 * t) * SS
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=DUST + (alpha,))


def cell_frame(variant, phase, width, height):
    frame = Image.new("RGBA", (width, height), CARD)
    draw = ImageDraw.Draw(frame)
    base_y = int(height - 26 * SS)
    draw.line([(int(10 * SS), base_y), (width - int(10 * SS), base_y)], fill=GROUND, width=SS)
    cx1, cx2 = int(width * 0.42), int(width * 0.68)

    if variant == 1:                       # sprint, sweat, dust
        lean = 14 + 3 * math.sin(phase * 2 * math.pi)
        draw_legs(draw, cx1, base_y, phase, 32)
        draw_legs(draw, cx2, base_y, (phase + 0.5) % 1.0, 32)
        dust(draw, cx1 - 18 * SS, base_y, phase)
        paste_body(frame, cx1, base_y, lean)
        paste_body(frame, cx2, base_y, lean + 2)
        drop_y = base_y - (40 + 10 * ((phase * 2) % 1.0)) * SS
        draw.ellipse([cx2 - 12 * SS, drop_y, cx2 - 8 * SS, drop_y + 6 * SS], fill=BLUE)
    elif variant == 2:                     # relay: one runs, the other jumps a puddle
        lift = int(16 * SS * max(0.0, math.sin(phase * 2 * math.pi)))
        draw_legs(draw, cx1, base_y, phase, 30)
        paste_body(frame, cx1, base_y, 12)
        draw.ellipse([cx2 - int(14 * SS), base_y - 4 * SS, cx2 + int(14 * SS), base_y + 3 * SS], fill=PUDDLE)
        draw_legs(draw, cx2, base_y - lift, (phase + 0.5) % 1.0, 22)
        paste_body(frame, cx2, base_y - lift, -10)
        ring = int((6 + 10 * ((phase * 2) % 1.0)) * SS)
        draw.ellipse([cx2 - ring, base_y - ring // 2, cx2 + ring, base_y + ring // 3], outline=SPLASH, width=SS)
    elif variant == 3:                     # panic: big eyes, tongue, speed lines
        for index in range(3):
            line_y = base_y - (34 + index * 8) * SS
            draw.line([(cx1 - (34 + 8 * index) * SS, line_y), (cx1 - (16 + 8 * index) * SS, line_y)],
                      fill=(90, 90, 90), width=SS)
        draw_legs(draw, cx1, base_y, phase, 38)
        draw_legs(draw, cx2, base_y, (phase + 0.5) % 1.0, 38)
        paste_body(frame, cx1, base_y, 8, eye_scale=1.7)
        paste_body(frame, cx2, base_y, 10, eye_scale=1.7)
        draw.ellipse([cx1 + 4 * SS, base_y - 27 * SS, cx1 + 10 * SS, base_y - 20 * SS], fill=TONGUE)
    elif variant == 4:                     # plodding, out of breath
        sway = 6 * math.sin(phase * 2 * math.pi)
        draw_legs(draw, cx1, base_y, phase, 20)
        draw_legs(draw, cx2, base_y, (phase + 0.5) % 1.0, 20)
        paste_body(frame, cx1, base_y, sway)
        paste_body(frame, cx2, base_y, -sway)
        for index in range(2):
            t = (phase + index * 0.5) % 1.0
            radius = (2 + 4 * t) * SS
            draw.ellipse([cx1 - (24 + 16 * t) * SS - radius, base_y - (34 + 6 * t) * SS - radius,
                          cx1 - (24 + 16 * t) * SS + radius, base_y - (34 + 6 * t) * SS + radius],
                         fill=DUST + (int(120 * (1 - t)),))
    elif variant == 5:                     # the partner trips over its own feet
        draw_legs(draw, cx1, base_y, phase, 30)
        paste_body(frame, cx1, base_y, 12)
        fall = max(0.0, math.sin(max(0.0, (phase - 0.35)) * 2 * math.pi))
        draw_legs(draw, cx2, base_y, (phase + 0.5) % 1.0, 18)
        paste_body(frame, cx2 + int(fall * 8 * SS), base_y - int(fall * 2 * SS), 10 + 42 * fall)
        if fall > 0.15:
            for index in range(3):
                angle = phase * 720 + index * 120
                x = cx2 + math.cos(math.radians(angle)) * 16 * SS
                y = base_y - (46 + math.sin(math.radians(angle)) * 6) * SS
                draw.ellipse([x - 2 * SS, y - 2 * SS, x + 2 * SS, y + 2 * SS], fill=STAR)
    elif variant == 6:                     # ninja run: arms back, scarf, dust cloud
        lean = 24 + 3 * math.sin(phase * 2 * math.pi)
        for cx, offset in ((cx1, 0.0), (cx2, 0.5)):
            draw_legs(draw, cx, base_y, (phase + offset) % 1.0, 42)
            paste_body(frame, cx, base_y, lean)
            for sx, sy in ((-1, 0), (-1, 1)):
                hip = (cx - 8 * SS, base_y - 30 * SS)
                elbow = (hip[0] - 12 * SS, hip[1] + (2 + 3 * sx) * SS - sy * 4 * SS)
                draw.line([hip, elbow], fill=STEM, width=int(5 * SS))
            scarf_x = cx - 14 * SS
            scarf_y = base_y - 34 * SS
            wiggle = int(4 * SS * math.sin(phase * 2 * math.pi + offset * 3))
            draw.line([(scarf_x, scarf_y), (scarf_x - 12 * SS, scarf_y + wiggle)], fill=SCARF, width=int(4 * SS))
        dust(draw, cx1 - 26 * SS, base_y, phase, reach=30, count=4)

    draw.rectangle([0, 0, width - 1, height - 1], outline=EDGE, width=SS)
    return frame


def main():
    cell_w, cell_h = CELL_W * SS, CELL_H * SS
    sheet_w, sheet_h = cell_w * COLS, cell_h * ROWS
    frames = []
    for index in range(FRAMES):
        phase = index / FRAMES
        sheet = Image.new("RGBA", (sheet_w, sheet_h), BG)
        for variant in range(1, 7):
            column = (variant - 1) % COLS
            row = (variant - 1) // COLS
            tile = cell_frame(variant, phase, cell_w, cell_h)
            sheet.alpha_composite(tile, (column * cell_w + int(2 * SS), row * cell_h + int(2 * SS)))
        frames.append(sheet.convert("RGB").resize((sheet_w // SS, sheet_h // SS), Image.Resampling.LANCZOS))

    palette_frames = [frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=96) for frame in frames]
    palette_frames[0].save(OUT, save_all=True, append_images=palette_frames[1:], duration=DURATION,
                           loop=0, optimize=True, disposal=2)
    print("frames:", len(frames), "size:", frames[0].size, "bytes:", os.path.getsize(OUT))


if __name__ == "__main__":
    main()
