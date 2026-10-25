"""Draw the stash map: the tabs that were READ from the client, and the occupancy of the page that was CAPTURED.

No guessing anywhere in this file:
  * the tab names come from the OCR of the client's own tab list (`tools/ocr.ps1`), copied into TABS below;
  * the tab types and their layouts come from the wiki table in `docs/stash-tabs.md`;
  * the occupancy comes from the pixels of an actual screenshot: a cell is "occupied" when the patch inside it has
    enough variance to be an icon rather than the flat dark of an empty slot.

    python tools/draw_stash_map.py --frame docs/stash-map-frames/strip-MAPS.png --out docs/stash-map.png
"""
import argparse
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Names exactly as the OCR read them from the side list (y positions are in the same order).
TABS = [
    ("RITUAL", "Ритуал", "specialised", "ячейки под омены"),
    ("SOSO", "SOSO", "unknown", "нестандартное имя, содержимое снято кадром"),
    ("MAPS", "Карты", "specialised", "6 под-вкладок на тир, 96 Waystone"),
    ("Сучности", "Сучности", "specialised", "руны, soul cores, идолы"),
    ("FRAGMENTS", "Фрагменты", "specialised", "6 под-вкладок 8×12"),
    ("RUNES", "Руны", "specialised", "ячейки под руны"),
    ("EXPEDITION", "Экспедиция", "specialised", "руны/сплавы/флюсы, логбуки"),
    ("RAZLOM", "Разлом", "specialised", "катализаторы, осколки, 6×12"),
    ("BEZDNA", "Бездна", "specialised", "ячейки под предметы Бездны"),
    ("DELIRIUM", "Делириум", "specialised", "жидкие эмоции, осколки"),
    ("GEMS", "Камни", "specialised", "до 500 камней"),
    ("10", "10", "regular", "нумерованная вкладка 12×12"),
    ("12", "12", "regular", "нумерованная вкладка 12×12"),
    ("14", "14", "regular", "нумерованная вкладка 12×12"),
]

# The panel and its grid, in frame pixels, measured on the captured frame (2560x1440).
# Frame pixels, not preview pixels: the panel spans about x 20..850 and y 190..1010 in a 2560x1440 frame. The first
# version used preview-sized numbers and sampled only the left half of the page.
PANEL = (20, 190, 850, 1010)        # x0, y0, x1, y1 of the stash page area inside the frame
GRID = (45, 265, 840, 1000)         # the grid body inside that page


def occupancy(frame_path, grid, cols, rows, threshold=18.0):
    """Per-cell occupancy from pixel variance: an empty slot is flat, an item icon is not."""
    image = Image.open(frame_path).convert("L")
    array = np.asarray(image)
    x0, y0, x1, y1 = grid
    pitch_x = (x1 - x0) / cols
    pitch_y = (y1 - y0) / rows
    cells = []
    for row in range(rows):
        line = []
        for column in range(cols):
            left = int(x0 + column * pitch_x + pitch_x * 0.2)
            top = int(y0 + row * pitch_y + pitch_y * 0.2)
            right = int(x0 + column * pitch_x + pitch_x * 0.8)
            bottom = int(y0 + row * pitch_y + pitch_y * 0.8)
            patch = array[top:bottom, left:right]
            line.append(float(patch.std()) if patch.size else 0.0)
        cells.append(line)
    occupied = [[value > threshold for value in line] for line in cells]
    return cells, occupied


def draw(frame_path, out_path, cols=12, rows=12):
    values, occupied = occupancy(frame_path, GRID, cols, rows)
    filled = sum(1 for line in occupied for cell in line if cell)

    width, height = 1400, 900
    image = Image.new("RGB", (width, height), (20, 18, 15))
    draw_ctx = ImageDraw.Draw(image)
    try:
        title_font = ImageFont.truetype("arial.ttf", 26)
        font = ImageFont.truetype("arial.ttf", 16)
        small = ImageFont.truetype("arial.ttf", 13)
    except Exception:
        title_font = font = small = ImageFont.load_default()

    draw_ctx.text((24, 18), "Stash map / Карта тайника", fill=(220, 185, 106), font=title_font)
    draw_ctx.text((24, 52), "Вкладки прочитаны OCR-ом из клиента; занятость — из пикселей кадра.",
                  fill=(160, 152, 138), font=small)

    # Left column: the tab list.
    top = 90
    for index, (raw, human, kind, note) in enumerate(TABS):
        y = top + index * 52
        colour = (220, 185, 106) if kind == "regular" else (150, 190, 220)
        draw_ctx.rectangle([24, y, 30, y + 40], fill=colour)
        draw_ctx.text((40, y), f"{human}", fill=(230, 224, 210), font=font)
        draw_ctx.text((40, y + 20), f"{kind}: {note}", fill=(150, 143, 130), font=small)

    # Right side: the occupancy of the captured page.
    grid_left, grid_top = 620, 100
    cell = 34
    draw_ctx.text((grid_left, grid_top - 30),
                  f"Страница на кадре (руны): занято {filled} из {cols * rows} ячеек", fill=(220, 185, 106), font=font)
    for row in range(rows):
        for column in range(cols):
            x = grid_left + column * cell
            y = grid_top + row * cell
            value = values[row][column]
            if occupied[row][column]:
                # Brightness follows the measured variance, so a dense icon looks denser than a faint one.
                strength = min(1.0, value / 60.0)
                fill = (int(90 + 130 * strength), int(80 + 110 * strength), int(50 + 40 * strength))
            else:
                fill = (32, 30, 26)
            draw_ctx.rectangle([x, y, x + cell - 3, y + cell - 3], fill=fill,
                               outline=(60, 56, 48))
    draw_ctx.text((grid_left, grid_top + rows * cell + 12),
                  "пустая ячейка — тёмная; занятая — светлая (яркость = измеренная дисперсия)",
                  fill=(150, 143, 130), font=small)

    image.save(out_path)
    summary = {
        "frame": frame_path,
        "grid": {"cols": cols, "rows": rows, "occupied": filled},
        "tabs": [{"name": human, "kind": kind, "note": note} for _, human, kind, note in TABS],
        "occupancy": values,
    }
    with open(out_path.replace(".png", ".json"), "w", encoding="utf-8") as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=1)
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frame", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    summary = draw(args.frame, args.out)
    print(json.dumps({"out": args.out, "occupied": summary["grid"]["occupied"],
                      "tabs": len(summary["tabs"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
