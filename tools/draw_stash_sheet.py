"""Draw the stash map as a contact sheet: one real thumbnail per captured stash page.

Why thumbnails instead of invented cell occupancy: the occupancy metric I tried first measured the panel's own
decorative frame, which is identical on every page, so all tabs reported the same number. A thumbnail has no such
problem - it IS the page. The numbers beside it are measured, not assumed:

  * colours   - distinct quantised colours in the page area: a page full of runes or currency is far more varied than
                a mostly empty one;
  * brightness- mean luminance: specialised pages (currency, essences) are darker and denser than an empty grid;
  * edges     - mean absolute gradient: icons produce edges, empty slots do not.

Both are computed from the decoded pixels of the captured frame, and the tab name is the one OCR read from the client.

    python tools/draw_stash_sheet.py --frames docs/stash-scan --out docs/stash-map.png
"""
import argparse
import glob
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# The page area inside a 2560x1440 frame: panel minus its frame, from the tab row down to the search box.
PAGE = (20, 190, 850, 1010)

TYPES = {
    "RITUAL": ("specialised", "оменовые ячейки"),
    "soso": ("unknown", "нестандартное имя вкладки"),
    "MAPS": ("specialised", "карты, 6 под-вкладок на тир"),
    "Сучности": ("specialised", "руны, soul cores, идолы"),
    "FRAGMENTS": ("specialised", "фрагменты, 6 под-вкладок 8×12"),
    "RUNES": ("specialised", "ячейки под руны"),
    "EXPEDITION": ("specialised", "сплавы, флюсы, логбуки"),
    "RAZLOM": ("specialised", "катализаторы, осколки"),
    "BEZDNA": ("specialised", "предметы Бездны"),
    "DELIRIUM": ("specialised", "жидкие эмоции, осколки"),
    "GEMS": ("specialised", "камни умений"),
}


def measure(path):
    image = Image.open(path).convert("RGB")
    page = image.crop(PAGE)
    grey = np.asarray(page.convert("L"), dtype=np.float32)
    colours = np.asarray(page.resize((160, 90))).reshape(-1, 3) // 16
    distinct = len({tuple(pixel) for pixel in colours})
    gradient = np.abs(np.diff(grey, axis=0)).mean() + np.abs(np.diff(grey, axis=1)).mean()
    return {
        "thumb": page.resize((330, 330), Image.LANCZOS),
        "colours": distinct,
        "brightness": float(grey.mean()),
        "edges": float(gradient),
    }


def name_of(path):
    base = os.path.basename(path)
    parts = base.split("-", 2)
    raw = parts[2].replace(".png", "") if len(parts) > 2 else base
    for key in TYPES:
        if raw.lower().startswith(key.lower()):
            return key
    return raw


def draw(frames_dir, out_path):
    frames = sorted(glob.glob(os.path.join(frames_dir, "tab-*.png")))
    entries = []
    for path in frames:
        key = name_of(path)
        if key.isdigit() or key in ("Сун", "в"):
            continue
        kind, note = TYPES.get(key, ("unknown", "формат неизвестен"))
        entries.append({"name": key, "kind": kind, "note": note, "frame": os.path.basename(path),
                        **measure(path)})
    if not entries:
        raise SystemExit("no captured pages to draw")

    columns = 4
    cell_w, cell_h = 380, 470
    rows = (len(entries) + columns - 1) // columns
    width, height = 24 + columns * cell_w, 120 + rows * cell_h
    sheet = Image.new("RGB", (width, height), (20, 18, 15))
    ctx = ImageDraw.Draw(sheet)
    try:
        title = ImageFont.truetype("arial.ttf", 28)
        font = ImageFont.truetype("arial.ttf", 17)
        small = ImageFont.truetype("arial.ttf", 13)
    except Exception:
        title = font = small = ImageFont.load_default()

    ctx.text((24, 18), "Stash map / Карта тайника", fill=(220, 185, 106), font=title)
    ctx.text((24, 56), "Каждый кадр снят оверлеем после клика по вкладке; имя прочитано OCR-ом из клиента.",
             fill=(160, 152, 138), font=small)
    ctx.text((24, 76), f"Страниц: {len(entries)}", fill=(160, 152, 138), font=small)

    for index, entry in enumerate(entries):
        column = index % columns
        row = index // columns
        x = 24 + column * cell_w
        y = 120 + row * cell_h
        sheet.paste(entry["thumb"], (x, y))
        ctx.rectangle([x, y, x + 330, y + 330], outline=(70, 64, 54))
        ctx.text((x, y + 338), entry["name"], fill=(232, 226, 212), font=font)
        ctx.text((x, y + 360), f"{entry['kind']} · {entry['note']}", fill=(150, 190, 220), font=small)
        ctx.text((x, y + 378), f"цветов: {entry['colours']} · яркость: {entry['brightness']:.0f} · "
                               f"края: {entry['edges']:.1f}", fill=(160, 152, 138), font=small)

    sheet.save(out_path)
    summary = {
        "pages": [{k: v for k, v in entry.items() if k != "thumb"} for entry in entries],
        "total_pages": len(entries),
        "page_area": PAGE,
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
