"""Build the stash map from the pages the overlay captured.

Input: `docs/stash-scan/tab-NN-<name>.png`, one per stash tab, captured by `--stash-walk` (the overlay clicks the tab
list rows that OCR reads, and records the panel difference for each page).

No guessing:
  * the tab names are the ones OCR read from the client's own list;
  * the tab types come from the wiki table in `docs/stash-tabs.md` / `Data/stash_tabs.lua`;
  * the occupancy comes from the pixels: a cell is "filled" when the patch inside it varies enough to be an icon
    rather than the flat dark of an empty slot.

    python tools/build_stash_map.py --frames docs/stash-scan --out docs/stash-map.png
"""
import argparse
import glob
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Panel geometry inside a 2560x1440 frame: the GRID BODY only. The full panel includes its ornate frame, and that frame
# is identical on every page - measuring it made all eleven tabs report the same number.
PANEL = (60, 270, 820, 970)

# Type per tab, from the wiki table. A tab missing here is reported as unknown rather than assumed to be a grid.
TYPES = {
    "RITUAL": ("Ритуал", "specialised", "ячейки под омены (до 5000)"),
    "soso": ("SOSO", "unknown", "нестандартное имя вкладки"),
    "MAPS": ("Карты", "specialised", "6 под-вкладок на тир, 96 Waystone"),
    "Сучности": ("Сучности", "specialised", "руны, soul cores, идолы"),
    "FRAGMENTS": ("Фрагменты", "specialised", "6 под-вкладок 8×12"),
    "RUNES": ("Руны", "specialised", "ячейки под руны"),
    "EXPEDITION": ("Экспедиция", "specialised", "руны/сплавы/флюсы, логбуки"),
    "RAZLOM": ("Разлом", "specialised", "катализаторы, осколки, 6×12"),
    "BEZDNA": ("Бездна", "specialised", "ячейки под предметы Бездны"),
    "DELIRIUM": ("Делириум", "specialised", "жидкие эмоции, осколки"),
    "GEMS": ("Камни", "specialised", "до 500 камней"),
}

GRID_COLS, GRID_ROWS = 12, 12


def occupied_cells(frame_path, cols=GRID_COLS, rows=GRID_ROWS, threshold=18.0):
    """Variance per cell: empty slots are flat, item icons are not."""
    image = Image.open(frame_path).convert("L")
    array = np.asarray(image)
    x0, y0, x1, y1 = PANEL
    pitch_x = (x1 - x0) / cols
    pitch_y = (y1 - y0) / rows
    values = []
    for row in range(rows):
        line = []
        for column in range(cols):
            left = int(x0 + column * pitch_x + pitch_x * 0.22)
            top = int(y0 + row * pitch_y + pitch_y * 0.22)
            right = int(x0 + column * pitch_x + pitch_x * 0.78)
            bottom = int(y0 + row * pitch_y + pitch_y * 0.78)
            patch = array[top:bottom, left:right]
            line.append(float(patch.std()) if patch.size else 0.0)
        values.append(line)
    filled = [[value > threshold for value in line] for line in values]
    return values, filled


def name_and_type(path):
    base = os.path.basename(path)
    parts = base.split("-", 2)
    raw = parts[2].replace(".png", "") if len(parts) > 2 else base
    for key, value in TYPES.items():
        if raw.lower().startswith(key.lower()) or key.lower() in raw.lower():
            return key, value
    return raw, (raw, "regular" if raw.isdigit() else "unknown", "формат неизвестен")


def draw(frames_dir, out_path):
    frames = sorted(glob.glob(os.path.join(frames_dir, "tab-*.png")))
    if not frames:
        raise SystemExit("no captured pages in " + frames_dir)

    entries = []
    for path in frames:
        key, (human, kind, note) = name_and_type(path)
        if key.isdigit() or key in ("Сун", "в"):
            continue
        values, filled = occupied_cells(path)
        count = sum(1 for line in filled for cell in line if cell)
        entries.append({
            "key": key,
            "name": human,
            "kind": kind,
            "note": note,
            "frame": os.path.basename(path),
            "filled": count,
            "of": GRID_COLS * GRID_ROWS,
            "values": values,
            "filled_map": filled,
        })

    width, height = 1500, 170 + 118 * len(entries)
    image = Image.new("RGB", (width, height), (20, 18, 15))
    ctx = ImageDraw.Draw(image)
    try:
        title = ImageFont.truetype("arial.ttf", 28)
        font = ImageFont.truetype("arial.ttf", 17)
        small = ImageFont.truetype("arial.ttf", 13)
    except Exception:
        title = font = small = ImageFont.load_default()

    ctx.text((24, 18), "Stash map / Карта тайника", fill=(220, 185, 106), font=title)
    ctx.text((24, 56), "Вкладки найдены и сняты оверлеем; имена прочитаны OCR; занятость — по пикселям кадров.",
             fill=(160, 152, 138), font=small)
    ctx.text((24, 74), f"Страниц снято: {len(entries)}", fill=(160, 152, 138), font=small)

    top = 110
    cell = 9
    for index, entry in enumerate(entries):
        y = top + index * 118
        colour = (220, 185, 106) if entry["kind"] == "regular" else (150, 190, 220)
        ctx.rectangle([24, y, 30, y + 56], fill=colour)
        ctx.text((40, y), entry["name"], fill=(232, 226, 212), font=font)
        ctx.text((40, y + 21), f"{entry['kind']}: {entry['note']}", fill=(150, 143, 130), font=small)
        share = entry["filled"] / entry["of"]
        ctx.text((40, y + 39), f"заполнено ≈ {share:.0%} по пикселям ({entry['filled']} из {entry['of']} ячеек)",
                 fill=(160, 152, 138), font=small)

        grid_left = 700
        for row in range(GRID_ROWS):
            for column in range(GRID_COLS):
                x = grid_left + column * cell
                gy = y + row * cell
                if entry["filled_map"][row][column]:
                    strength = min(1.0, entry["values"][row][column] / 60.0)
                    fill = (int(90 + 130 * strength), int(80 + 110 * strength), int(50 + 40 * strength))
                else:
                    fill = (32, 30, 26)
                ctx.rectangle([x, gy, x + cell - 1, gy + cell - 1], fill=fill, outline=(52, 48, 42))

    ctx.text((700, height - 30), "светлая ячейка — занята (яркость = измеренная дисперсия); тёмная — пусто",
             fill=(150, 143, 130), font=small)
    image.save(out_path)

    summary = {
        "pages": [{k: v for k, v in entry.items() if k not in ("values", "filled_map")} for entry in entries],
        "total_pages": len(entries),
        "grid": {"cols": GRID_COLS, "rows": GRID_ROWS},
    }
    with open(out_path.replace(".png", ".json"), "w", encoding="utf-8") as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=1)
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    summary = draw(args.frames, args.out)
    print(json.dumps({"out": args.out, "pages": summary["total_pages"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
