"""Check whether a TrueType font actually covers Cyrillic.

Written as a small standalone parser because fontTools is not installed in the bundled Python, and "the browser
renders Russian" proves nothing: the browser silently falls back to a system font when a glyph is missing.
"""
import struct
import sys


def read_tables(data):
    if len(data) < 12:
        return {}
    count = struct.unpack(">H", data[4:6])[0]
    tables = {}
    for index in range(count):
        offset = 12 + index * 16
        tag = data[offset:offset + 4].decode("latin-1")
        table_offset, length = struct.unpack(">II", data[offset + 8:offset + 16])
        tables[tag] = (table_offset, length)
    return tables


def cmap_codepoints(data, tables):
    if "cmap" not in tables:
        return set()
    base, _length = tables["cmap"]
    _version, num_tables = struct.unpack(">HH", data[base:base + 4])
    points = set()
    for index in range(num_tables):
        record = base + 4 + index * 8
        platform, _encoding, offset = struct.unpack(">HHI", data[record:record + 8])
        subtable = base + offset
        if subtable + 2 > len(data):
            continue
        fmt = struct.unpack(">H", data[subtable:subtable + 2])[0]
        if fmt == 4:
            seg_x2 = struct.unpack(">H", data[subtable + 6:subtable + 8])[0]
            segments = seg_x2 // 2
            ends = subtable + 14
            starts = ends + seg_x2 + 2
            deltas = starts + seg_x2
            ranges = deltas + seg_x2
            for segment in range(segments):
                end = struct.unpack(">H", data[ends + segment * 2:ends + segment * 2 + 2])[0]
                start = struct.unpack(">H", data[starts + segment * 2:starts + segment * 2 + 2])[0]
                delta = struct.unpack(">h", data[deltas + segment * 2:deltas + segment * 2 + 2])[0]
                range_offset = struct.unpack(">H", data[ranges + segment * 2:ranges + segment * 2 + 2])[0]
                for code in range(start, min(end, 0xFFFF) + 1):
                    if code == 0xFFFF:
                        continue
                    if range_offset == 0:
                        glyph = (code + delta) & 0xFFFF
                    else:
                        address = ranges + segment * 2 + range_offset + (code - start) * 2
                        if address + 2 > len(data):
                            continue
                        glyph = struct.unpack(">H", data[address:address + 2])[0]
                        if glyph:
                            glyph = (glyph + delta) & 0xFFFF
                    if glyph:
                        points.add(code)
        elif fmt == 12:
            groups = struct.unpack(">I", data[subtable + 12:subtable + 16])[0]
            for group in range(groups):
                start, end, _glyph = struct.unpack(
                    ">III", data[subtable + 16 + group * 12:subtable + 28 + group * 12])
                if end - start < 0x2000:
                    points.update(range(start, end + 1))
    return points


CYRILLIC = list(range(0x0410, 0x0450)) + [0x0401, 0x0451, 0x2116]  # А-я, Ё, ё, №

for path in sys.argv[1:]:
    with open(path, "rb") as handle:
        data = handle.read()
    points = cmap_codepoints(data, read_tables(data))
    covered = sum(1 for code in CYRILLIC if code in points)
    name = path.rsplit("\\", 1)[-1]
    print(f"{name:16} глифов: {len(points):5}  кириллица: {covered}/{len(CYRILLIC)}  "
          f"{'ПОЛНАЯ' if covered == len(CYRILLIC) else 'НЕПОЛНАЯ'}")
    missing = [chr(code) for code in CYRILLIC if code not in points][:12]
    if missing:
        print("   нет:", "".join(missing))
