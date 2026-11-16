#!/usr/bin/env python3
"""Contact sheets of the look gate's shots (tests/general/render_3d_look_gate_windowed_test.gd).

usage: python3 -I tools/look_gate_sheets.py SHOT_DIR [OUT_DIR]   (needs Pillow: `pip install pillow`)

Reads `<scene>_z<zoom>_yaw<yaw>.png` from SHOT_DIR and writes, per scene (into OUT_DIR, default
SHOT_DIR/sheets): `<scene>.png`, a grid of the shots (a row per zoom, a column per turn). A scene that
moves (firefight, grenade) is one picture per (zoom, yaw) moment, so it sheets as the list of its
moments.
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:  # the sheets are a dev aid; say what is missing instead of a traceback
    sys.exit("look_gate_sheets.py needs Pillow: pip install pillow")

NAME = re.compile(r"^(?P<scene>.+)_z(?P<zoom>[0-9p]+)_yaw(?P<yaw>\d+)\.png$")
TILE = (576, 324)


def zoom_of(text: str) -> float:
    return float(text.replace("p", "."))


def label(img: Image.Image, text: str) -> Image.Image:
    out = img.copy()
    draw = ImageDraw.Draw(out)
    draw.rectangle((0, 0, 7 * len(text) + 8, 14), fill=(0, 0, 0))
    draw.text((4, 1), text, fill=(255, 255, 0))
    return out


def grid(tiles: list[tuple[str, Path]], cols: int, size=TILE) -> Image.Image:
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * size[0], rows * size[1]), (24, 24, 24))
    for i, (text, path) in enumerate(tiles):
        img = Image.open(path).convert("RGB").resize(size, Image.NEAREST)
        sheet.paste(label(img, text), ((i % cols) * size[0], (i // cols) * size[1]))
    return sheet


def main() -> None:
    shots = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else shots / "sheets"
    out.mkdir(parents=True, exist_ok=True)
    found: dict = defaultdict(list)
    for path in sorted(shots.glob("*.png")):
        m = NAME.match(path.name)
        if m:
            found[m["scene"]].append((zoom_of(m["zoom"]), int(m["yaw"]), path))
    for scene, shots_of in found.items():
        tiles = [(f"{scene} zoom {z:g} yaw {y}", p) for z, y, p in sorted(shots_of)]
        grid(tiles, 4).save(out / f"{scene}.png")
    print("sheets in", out)


if __name__ == "__main__":
    main()
