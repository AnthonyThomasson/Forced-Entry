#!/usr/bin/env python3
"""Contact sheets of the look gate's shots (tests/general/render_3d_look_gate_windowed_test.gd).

usage: tools/look_gate_sheets.py SHOT_DIR [OUT_DIR]

Reads `<scene>_<3d|2d>_z<zoom>_yaw<yaw>.png` from SHOT_DIR and writes, per scene (into OUT_DIR, default
SHOT_DIR/sheets): `<scene>_3d.png`, a grid of the 3D shots (a row per zoom, a column per turn), and
`<scene>_2d_vs_3d.png`, rows of the 2D picture on the left and the 3D picture at the same zoom
(north up) on the right. A scene that moves (firefight, grenade) is one picture per (zoom, yaw)
moment, so it sheets as the list of its moments.
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw

NAME = re.compile(r"^(?P<scene>.+)_(?P<mode>3d|2d)_z(?P<zoom>[0-9p]+)_yaw(?P<yaw>\d+)\.png$")
TILE = (576, 324)
MOVING = ("firefight", "grenade")


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
    found: dict = defaultdict(lambda: defaultdict(list))
    for path in sorted(shots.glob("*.png")):
        m = NAME.match(path.name)
        if m:
            found[m["scene"]][m["mode"]].append((zoom_of(m["zoom"]), int(m["yaw"]), path))
    for scene, modes in found.items():
        three = sorted(modes.get("3d", []))
        two = sorted(modes.get("2d", []))
        if three:
            tiles = [(f"{scene} 3D zoom {z:g} yaw {y}", p) for z, y, p in three]
            grid(tiles, 4).save(out / f"{scene}_3d.png")
        pairs = []
        for z, y, p3 in three:
            if y != 0 and scene not in MOVING:
                continue
            twod = [p for zz, yy, p in two if zz == z and (yy == y or yy == 0)]
            if twod:
                pairs.append((f"{scene} 2D zoom {z:g}", twod[0]))
                pairs.append((f"{scene} 3D zoom {z:g} yaw {y}", p3))
        if pairs:
            grid(pairs, 2).save(out / f"{scene}_2d_vs_3d.png")
    print("sheets in", out)


if __name__ == "__main__":
    main()
