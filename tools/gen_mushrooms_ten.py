"""Ten more mushrooms, drawn as recognisable species and animated in one GIF.

Each species keeps the features a mushroom picker actually uses to tell it apart, and gets a movement of its
own: the boletus trudges, the fly agaric hops, the chanterelle patters, the morel rocks sideways, the puffball
bounces like a ball, the oyster leans like a fan. Drawing is procedural (Pillow), so every frame is exact and
the whole thing stays editable - there is no model in this loop.

    <bundled python> tools/gen_mushrooms_ten.py
"""

import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "docs", "mushrooms-ten.gif")

SS = 3
CELL_W, CELL_H = 300, 112
COLS, ROWS = 2, 5
FRAMES = 24
DURATION = 50

BG = (18, 18, 18)
CARD = (26, 25, 24)
EDGE = (46, 44, 42)
GROUND = (62, 60, 56)
SHADOW = (12, 11, 10)
EYE = (26, 24, 22)
PALE = (232, 226, 210)
BROWN = (126, 86, 52)
BROWN_D = (86, 56, 32)
RED = (176, 46, 38)
RED_D = (128, 30, 26)
GOLD = (216, 154, 46)
GOLD_D = (162, 108, 28)
GREEN = (108, 138, 84)
GREEN_D = (72, 98, 56)
HONEY = (176, 132, 74)
HONEY_D = (126, 88, 46)
GREY = (150, 146, 138)
GREY_D = (108, 104, 96)
PORE = (214, 202, 176)
GILL = (206, 190, 164)
WART = (245, 240, 228)
DUST = (70, 66, 60)


def dome(d, cx, cy, w, h, dark, light, rings=6):
    """A lit dome: nested ellipses from the dark rim up to a light crown."""
    for index in range(rings):
        t = index / (rings - 1)
        colour = tuple(int(dark[i] + (light[i] - dark[i]) * t) for i in range(3))
        cw = int(w * (1 - 0.42 * t))
        ch = int(h * (1 - 0.30 * t))
        offset = int(h * 0.16 * t)
        d.ellipse([cx - cw // 2, cy - ch // 2 - offset, cx + cw // 2, cy + ch // 2 - offset], fill=colour)
    return int(w * 0.5)


def stem(d, cx, top_y, base_y, width, colour, highlight, ring=False, speckles=False, bulb=False):
    half = width // 2
    if bulb:
        d.ellipse([cx - int(half * 1.5), base_y - int(width * 0.7), cx + int(half * 1.5), base_y + int(width * 0.2)],
                  fill=colour)
    d.rounded_rectangle([cx - half, top_y, cx + half, base_y], radius=int(width * 0.35), fill=colour)
    d.rounded_rectangle([cx - half + int(2 * SS), top_y, cx - half + int(5 * SS), base_y],
                        radius=int(2 * SS), fill=highlight)
    if ring:
        d.rounded_rectangle([cx - int(half * 1.35), top_y + int(width * 0.5), cx + int(half * 1.35),
                             top_y + int(width * 0.5) + int(3 * SS)], radius=int(2 * SS), fill=highlight)
    if speckles:
        for index in range(5):
            yy = top_y + int((base_y - top_y) * (0.2 + 0.16 * index))
            d.ellipse([cx - half + int(3 * SS), yy, cx - half + int(6 * SS), yy + int(3 * SS)], fill=highlight)


def legs(d, cx, base_y, phase, stride=1.0, colour=PALE):
    """Hip - knee - foot, out of phase: the feet land past the stem so the step reads."""
    for side, offset in ((-1, 0.0), (1, math.pi)):
        swing = math.sin(phase * 2 * math.pi + offset) * stride
        hip_x, hip_y = cx + side * int(4 * SS), base_y - int(17 * SS)
        knee_x, knee_y = hip_x + side * int((5 + 5 * swing) * SS), base_y - int(9 * SS)
        foot_x = cx + side * int((11 + 7 * swing) * SS)
        foot_y = base_y - int(SS) - int(5 * SS * max(0.0, swing))
        d.line([(hip_x, hip_y), (knee_x, knee_y)], fill=colour, width=int(7 * SS))
        d.line([(knee_x, knee_y), (foot_x, foot_y)], fill=colour, width=int(6 * SS))
        d.ellipse([foot_x - int(4 * SS), foot_y - int(4 * SS), foot_x + int(4 * SS), foot_y + int(4 * SS)],
                  fill=colour)


def eyes(d, cx, y, scale=1.0, wide=False):
    eye_w, eye_h = int(4 * SS * scale), int(5 * SS * scale)
    if wide:
        eye_w, eye_h = int(6 * SS * scale), int(7 * SS * scale)
    for dx in (-int(7 * SS), int(2 * SS)):
        d.ellipse([cx + dx, y, cx + dx + eye_w, y + eye_h], fill=EYE)


def shadow(d, cx, base_y, width):
    d.ellipse([cx - width, base_y - int(3 * SS), cx + width, base_y + int(3 * SS)], fill=SHADOW)


def dust(d, cx, base_y, phase, reach=20, count=3):
    for index in range(count):
        t = (phase + index / count) % 1.0
        radius = (3 + 5 * t) * SS
        x = cx - (10 + reach * t) * SS
        y = base_y - (1 + 4 * t) * SS
        d.ellipse([x - radius, y - radius, x + radius, y + radius], fill=DUST + (int(120 * (1 - t)),))


def boletus(d, cx, base_y, phase):
    """Белый гриб: толстая бочка-ножка, коричневая шляпка, трубчатый слой."""
    bob = int(2 * SS * math.sin(phase * 2 * math.pi))
    stem(d, cx, base_y - int(46 * SS) + bob, base_y - int(2 * SS), int(20 * SS), PALE, (246, 240, 226), bulb=True)
    d.rounded_rectangle([cx - int(15 * SS), base_y - int(30 * SS), cx + int(15 * SS), base_y - int(24 * SS)],
                        radius=int(4 * SS), fill=PORE)
    for index in range(7):
        d.ellipse([cx - int(13 * SS) + index * int(4 * SS), base_y - int(29 * SS),
                   cx - int(11 * SS) + index * int(4 * SS), base_y - int(26 * SS)], fill=(196, 182, 152))
    dome(d, cx, base_y - int(54 * SS) + bob, int(58 * SS), int(36 * SS), BROWN_D, (168, 122, 78))
    eyes(d, cx, base_y - int(40 * SS) + bob)
    return bob


def fly_agaric(d, cx, base_y, phase):
    """Мухомор: красная шляпка в белых бородавках, юбочка, вольва; скачет."""
    lift = int(9 * SS * max(0.0, math.sin(phase * 2 * math.pi)))
    stem(d, cx, base_y - int(48 * SS), base_y - int(2 * SS) - lift, int(13 * SS), (240, 236, 224), (252, 250, 244),
         ring=True)
    d.ellipse([cx - int(14 * SS), base_y - int(6 * SS) - lift, cx + int(14 * SS), base_y - lift], fill=(236, 232, 220))
    dome(d, cx, base_y - int(56 * SS) - lift, int(54 * SS), int(32 * SS), RED_D, (222, 92, 74))
    for dx, dy, radius in ((-16, -8, 4), (-4, -12, 3), (10, -9, 4), (18, -3, 3), (-10, -2, 3), (2, -4, 4)):
        d.ellipse([cx + int((dx - radius) * SS), base_y - int(56 * SS) - lift + int((dy - radius) * SS),
                   cx + int((dx + radius) * SS), base_y - int(56 * SS) - lift + int((dy + radius) * SS)], fill=WART)
    eyes(d, cx, base_y - int(43 * SS) - lift, wide=lift > 0)
    return lift


def chanterelle(d, cx, base_y, phase):
    """Лисичка: воронка с волнистым краем и рёбрами вместо пластинок."""
    bob = int(2 * SS * math.sin(phase * 4 * math.pi))
    d.rounded_rectangle([cx - int(8 * SS), base_y - int(38 * SS) + bob, cx + int(8 * SS), base_y - int(2 * SS)],
                        radius=int(7 * SS), fill=(214, 150, 44))
    dome(d, cx, base_y - int(46 * SS) + bob, int(40 * SS), int(26 * SS), GOLD_D, (238, 182, 74))
    d.ellipse([cx - int(13 * SS), base_y - int(50 * SS) + bob, cx + int(13 * SS), base_y - int(40 * SS) + bob],
              fill=(196, 132, 36))
    for index in range(5):
        dx = int((-14 + index * 7) * SS)
        d.line([(cx + dx, base_y - int(42 * SS) + bob), (cx + int(dx * 0.6), base_y - int(30 * SS) + bob)],
               fill=(232, 172, 66), width=int(2 * SS))
    eyes(d, cx, base_y - int(34 * SS) + bob)
    return bob


def russula(d, cx, base_y, phase):
    """Сыроежка: плоская шляпка с ямкой, хрупкая белая ножка; семенит."""
    wobble = int(3 * SS * math.sin(phase * 2 * math.pi))
    stem(d, cx, base_y - int(38 * SS), base_y - int(2 * SS), int(14 * SS), (238, 234, 220), (250, 248, 240))
    dome(d, cx, base_y - int(44 * SS), int(50 * SS), int(22 * SS), (108, 60, 66), (186, 124, 126))
    d.ellipse([cx - int(11 * SS), base_y - int(46 * SS), cx + int(11 * SS), base_y - int(40 * SS)],
              fill=(128, 74, 78))
    for index in range(6):
        d.line([(cx - int(14 * SS) + index * int(6 * SS), base_y - int(36 * SS)),
                (cx - int(14 * SS) + index * int(6 * SS), base_y - int(32 * SS))], fill=GILL, width=int(2 * SS))
    eyes(d, cx, base_y - int(30 * SS) + wobble // 2)
    return wobble


def honey_fungus(d, cx, base_y, phase):
    """Опёнок: тонкая ножка с кольцом, медовые шляпки; второй отстаёт."""
    bob = int(2 * SS * math.sin(phase * 2 * math.pi))
    for offset, scale in ((-int(16 * SS), 0.82), (int(14 * SS), 0.7)):
        lift = int(4 * SS * max(0.0, math.sin(phase * 2 * math.pi + offset)))
        stem(d, cx + offset, base_y - int(40 * SS * scale) - lift, base_y - int(2 * SS),
             int(9 * SS * scale), (228, 214, 190), (242, 232, 212), ring=True)
        dome(d, cx + offset, base_y - int((48 + 2) * SS * scale) - lift, int(34 * SS * scale),
             int(20 * SS * scale), HONEY_D, (206, 164, 100), rings=5)
    eyes(d, cx - int(16 * SS), base_y - int(36 * SS) + bob)
    return bob


def morel(d, cx, base_y, phase):
    """Сморчок: коническая ячеистая шляпка; раскачивается вбок."""
    rock = int(5 * SS * math.sin(phase * 2 * math.pi))
    stem(d, cx, base_y - int(34 * SS), base_y - int(2 * SS), int(13 * SS), (236, 226, 206), (248, 242, 226))
    cx_shift = cx + rock
    # honeycomb: an oval base plus a cone, then pits only where the cone is wide enough
    top_y = base_y - int(62 * SS)
    bottom_y = base_y - int(34 * SS)
    d.polygon([(cx_shift - int(13 * SS), bottom_y), (cx_shift - int(5 * SS), top_y + int(4 * SS)),
               (cx_shift, top_y), (cx_shift + int(5 * SS), top_y + int(4 * SS)),
               (cx_shift + int(13 * SS), bottom_y)], fill=(116, 92, 60))
    d.ellipse([cx_shift - int(13 * SS), bottom_y - int(3 * SS), cx_shift + int(13 * SS), bottom_y + int(4 * SS)],
              fill=(116, 92, 60))
    rows = 6
    for row in range(rows):
        t_row = row / (rows - 1)
        half = int((13 - 9 * t_row) * SS)
        y = top_y + int((bottom_y - top_y) * t_row) + int(3 * SS)
        cells = max(2, int(half / (4 * SS)))
        for column in range(cells):
            x = cx_shift - half + int((column + 0.5) * (2 * half / cells))
            d.ellipse([x - int(2 * SS), y - int(1.5 * SS), x + int(2 * SS), y + int(1.5 * SS)],
                      fill=(88, 68, 42))
    eyes(d, cx, base_y - int(28 * SS))
    return rock


def oyster(d, cx, base_y, phase):
    """Вешенка: веер на боковой ножке; наклоняется как веер."""
    lean = int(6 * SS * math.sin(phase * 2 * math.pi))
    d.rounded_rectangle([cx - int(4 * SS), base_y - int(30 * SS), cx + int(6 * SS), base_y - int(2 * SS)],
                        radius=int(4 * SS), fill=(206, 200, 188))
    d.ellipse([cx - int(26 * SS) + lean // 2, base_y - int(52 * SS), cx + int(18 * SS) + lean // 2,
               base_y - int(26 * SS)], fill=(158, 152, 142))
    d.ellipse([cx - int(22 * SS) + lean // 2, base_y - int(50 * SS), cx + int(12 * SS) + lean // 2,
               base_y - int(30 * SS)], fill=(182, 176, 164))
    for index in range(6):
        d.line([(cx - int(16 * SS) + index * int(5 * SS), base_y - int(32 * SS)),
                (cx - int(16 * SS) + index * int(5 * SS) + lean // 3, base_y - int(26 * SS))],
               fill=(140, 134, 124), width=int(2 * SS))
    eyes(d, cx - int(4 * SS), base_y - int(44 * SS) + lean // 3)
    return lean


def leccinum(d, cx, base_y, phase):
    """Подберёзовик: коричневая шляпка и ножка в тёмных чешуйках; пружинит на пятках."""
    bounce = int(3 * SS * abs(math.sin(phase * 4 * math.pi)))
    stem(d, cx, base_y - int(48 * SS) - bounce, base_y - int(2 * SS), int(15 * SS), (222, 214, 196),
         (186, 176, 156), speckles=True)
    dome(d, cx, base_y - int(58 * SS) - bounce, int(48 * SS), int(26 * SS), (88, 58, 34), (162, 116, 76))
    eyes(d, cx, base_y - int(42 * SS) - bounce)
    return bounce


def puffball(d, cx, base_y, phase):
    """Дождевик: шар с дырочкой сверху; катится-подпрыгивает, оставляя споры."""
    lift = int(10 * SS * abs(math.sin(phase * 2 * math.pi)))
    radius = int(17 * SS)
    cy = base_y - radius - lift
    for index in range(5, 0, -1):
        t = index / 5.0
        colour = tuple(int(c * (0.72 + 0.28 * (1 - t))) for c in GREY)
        r = int(radius * t)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tuple(min(255, int(v * 1.08)) for v in colour))
    d.ellipse([cx - int(3 * SS), cy - radius + int(2 * SS), cx + int(3 * SS), cy - radius + int(7 * SS)],
              fill=(96, 92, 84))
    eyes(d, cx, cy - int(2 * SS))
    for index in range(3):
        t = (phase + index / 3) % 1.0
        x = cx - int((6 + 16 * t) * SS)
        y = cy - int((4 + 6 * t) * SS)
        r = (2 + 3 * t) * SS
        d.ellipse([x - r, y - r, x + r, y + r], fill=(168, 162, 150) + (int(110 * (1 - t)),))
    return lift


def agaricus(d, cx, base_y, phase):
    """Шампиньон: белая шляпка, розовеющие пластинки, кольцо на ножке; шагает с достоинством."""
    bob = int(2 * SS * math.sin(phase * 2 * math.pi))
    stem(d, cx, base_y - int(42 * SS), base_y - int(2 * SS), int(15 * SS), (240, 236, 226), (252, 250, 244),
         ring=True)
    dome(d, cx, base_y - int(50 * SS) + bob, int(48 * SS), int(24 * SS), (206, 198, 182),
         (252, 250, 242))
    for index in range(7):
        d.line([(cx - int(14 * SS) + index * int(4 * SS), base_y - int(40 * SS) + bob),
                (cx - int(14 * SS) + index * int(4 * SS), base_y - int(36 * SS))], fill=(196, 150, 140),
               width=int(2 * SS))
    eyes(d, cx, base_y - int(32 * SS) + bob)
    return bob


SPECIES = [
    ("boletus", boletus, 1.0),
    ("fly_agaric", fly_agaric, 0.9),
    ("chanterelle", chanterelle, 1.15),
    ("russula", russula, 1.25),
    ("honey_fungus", honey_fungus, 1.1),
    ("morel", morel, 0.85),
    ("oyster", oyster, 0.95),
    ("leccinum", leccinum, 1.2),
    ("puffball", puffball, 1.3),
    ("agaricus", agaricus, 0.8),
]


def cell(species_index, phase, width, height):
    name, draw_species, stride = SPECIES[species_index]
    frame = Image.new("RGBA", (width, height), CARD)
    d = ImageDraw.Draw(frame)
    base_y = int(height - 22 * SS)
    d.line([(int(8 * SS), base_y), (width - int(8 * SS), base_y)], fill=GROUND, width=SS)
    cx = int(width * 0.55)
    shadow(d, cx, base_y, int(18 * SS))
    legs(d, cx, base_y, phase, stride)
    if name == "honey_fungus":
        draw_species(d, cx, base_y, phase)
    else:
        draw_species(d, cx, base_y, phase)
    if name in ("boletus", "puffball", "leccinum", "morel"):
        dust(d, cx - int(16 * SS), base_y, phase)
    try:
        font = ImageFont.load_default(size=int(13 * SS))
        d.text((int(8 * SS), int(6 * SS)), str(species_index + 1), fill=(150, 148, 142), font=font)
    except Exception:
        pass
    d.rectangle([0, 0, width - 1, height - 1], outline=EDGE, width=SS)
    return frame


def main():
    cell_w, cell_h = CELL_W * SS, CELL_H * SS
    sheet_w, sheet_h = cell_w * COLS, cell_h * ROWS
    frames = []
    for index in range(FRAMES):
        phase = index / FRAMES
        sheet = Image.new("RGBA", (sheet_w, sheet_h), BG)
        for species_index in range(len(SPECIES)):
            column = species_index % COLS
            row = species_index // COLS
            sheet.alpha_composite(cell(species_index, phase, cell_w, cell_h),
                                  (column * cell_w + int(2 * SS), row * cell_h + int(2 * SS)))
        frames.append(sheet.convert("RGB").resize((sheet_w // SS, sheet_h // SS), Image.Resampling.LANCZOS))
    palette = [frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=128) for frame in frames]
    palette[0].save(OUT, save_all=True, append_images=palette[1:], duration=DURATION, loop=0,
                    optimize=True, disposal=2)
    print("frames:", len(frames), "size:", frames[0].size, "bytes:", os.path.getsize(OUT))


if __name__ == "__main__":
    main()
