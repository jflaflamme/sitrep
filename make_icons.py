#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build SITREP's icon font (resources/fonts/icons.fnt + .png) from the Tabler Icons webfont.

    python3 make_icons.py path/to/tabler-icons.ttf path/to/tabler-icons.css

Tabler Icons (MIT, https://tabler.io/icons): download both files from
https://cdn.jsdelivr.net/npm/@tabler/icons-webfont/dist/. Each icon becomes a letter,
A..Z then a..z in ICONS order, so the face draws it with drawText in any colour.
Append to ICONS only: Fields.mc refers to icons by letter.
"""
import re
import sys
from PIL import Image, ImageDraw, ImageFont

SIZE = 24        # px, about the height of FONT_SMALL on the fenix 7X
ICONS = [        # letter: Tabler icon name
    "shoe", "route", "flame", "stairs", "run", "heart", "bolt", "mood-nervous",
    "mountain", "gauge", "temperature", "sunrise", "sunset", "battery-2", "sun",
    "message", "alarm", "cloud", "calendar", "battery-charging",
    "cloud-rain", "cloud-storm", "cloud-fog", "snowflake", "wind",
    "ufo", "alien", "skull", "ghost", "moon-stars", "rocket", "satellite",
]


def letter(index):
    """A..Z, then a..z: plain letters need no escaping in Monkey C strings."""
    return chr(ord("A") + index) if index < 26 else chr(ord("a") + index - 26)


def main(ttf, css_path):
    css = open(css_path, encoding="utf-8").read()
    codepoints = {m.group(1): int(m.group(2), 16) for m in
                  re.finditer(r'\.ti-([\w-]+):before\s*\{\s*content:\s*"\\([0-9a-f]+)"', css)}
    font = ImageFont.truetype(ttf, SIZE)
    cell = SIZE + 2
    atlas = Image.new("RGBA", (cell * len(ICONS), cell), (255, 255, 255, 0))
    draw = ImageDraw.Draw(atlas)
    lines = []
    for i, name in enumerate(ICONS):
        glyph = chr(codepoints[name])
        left, top, right, bottom = font.getbbox(glyph)
        w, h = right - left, bottom - top
        x = i * cell + (cell - w) // 2
        y = (cell - h) // 2
        draw.text((x - left, y - top), glyph, font=font, fill=(255, 255, 255, 255))
        lines.append(f"char id={ord(letter(i))} x={i * cell} y=0 width={cell} height={cell} "
                     f"xoffset=0 yoffset=0 xadvance={cell} page=0 chnl=15")
    atlas.save("resources/fonts/icons.png")
    with open("resources/fonts/icons.fnt", "w") as fh:
        fh.write(f'info face="tabler-icons" size={cell} bold=0 italic=0 charset="" unicode=1 '
                 f'stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=0,0\n')
        fh.write(f"common lineHeight={cell} base={cell} scaleW={atlas.width} scaleH={cell} pages=1 packed=0\n")
        fh.write('page id=0 file="icons.png"\n')
        fh.write(f"chars count={len(ICONS)}\n")
        fh.write("\n".join(lines) + "\n")
    for i, name in enumerate(ICONS):
        print(f"{letter(i)}  {name}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
