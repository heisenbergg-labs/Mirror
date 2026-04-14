#!/usr/bin/env python3
import pathlib
import struct
import sys


ENTRIES = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_64x64.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_1024x1024.png"),
]


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: make_icns.py ICONSET_DIR OUTPUT.icns", file=sys.stderr)
        return 2

    iconset_dir = pathlib.Path(sys.argv[1])
    output = pathlib.Path(sys.argv[2])
    chunks = []

    for icon_type, filename in ENTRIES:
        data = (iconset_dir / filename).read_bytes()
        chunks.append(icon_type.encode("ascii") + struct.pack(">I", len(data) + 8) + data)

    payload = b"".join(chunks)
    output.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
