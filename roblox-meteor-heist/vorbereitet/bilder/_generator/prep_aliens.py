#!/usr/bin/env python3
"""Bereitet gerenderte Alien-/Ei-Freisteller für release.js vor.

Aufruf:  python3 prep_aliens.py <quellordner> <zielordner> [maxHoehe]
- schneidet jeden PNG-Freisteller auf seinen sichtbaren Inhalt zu (+ kleiner Rand),
- verkleinert auf höchstens maxHoehe Pixel Höhe (Standard 640),
- speichert optimiert als PNG unter demselben Namen.
Die Freisteller kommen aus dem Alien-Renderer (echte Spielmodelle aus AlienFactory, three.js).
"""
import os
import sys

from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
max_h = int(sys.argv[3]) if len(sys.argv) > 3 else 640
os.makedirs(dst, exist_ok=True)
for name in sorted(os.listdir(src)):
    if not name.lower().endswith(".png"):
        continue
    im = Image.open(os.path.join(src, name)).convert("RGBA")
    # nur deutlich sichtbare Pixel zählen (weiche Leucht-Ränder nicht abschneiden: Rand 3 %)
    alpha = im.getchannel("A").point(lambda a: 255 if a > 8 else 0)
    box = alpha.getbbox()
    if not box:
        continue
    pad = int(max(box[2] - box[0], box[3] - box[1]) * 0.03) + 4
    box = (max(0, box[0] - pad), max(0, box[1] - pad), min(im.width, box[2] + pad), min(im.height, box[3] + pad))
    im = im.crop(box)
    if im.height > max_h:
        k = max_h / im.height
        im = im.resize((max(1, round(im.width * k)), max_h), Image.LANCZOS)
    im.save(os.path.join(dst, name), optimize=True)
    print(f"{name}: {im.width}x{im.height}")
