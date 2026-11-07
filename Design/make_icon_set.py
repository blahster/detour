#!/usr/bin/env python3
"""Regenerate the macOS app icon set from the master image.

Master: Design/AppIcon-1024.png, 1024x1024 with transparent corners. The rounded tile is 824x824,
centred, leaving a 100 px margin, which is the macOS icon grid.

Usage (needs Pillow):  python3 Design/make_icon_set.py
"""
import json
import pathlib

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
SET = HERE.parent / "Sources/Detour/Assets.xcassets/AppIcon.appiconset"
master = Image.open(HERE / "AppIcon-1024.png").convert("RGBA")
assert master.size == (1024, 1024), "master must be 1024x1024"

SET.mkdir(parents=True, exist_ok=True)
images = []
for pt in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f"icon_{pt}x{pt}" + ("@2x" if scale == 2 else "") + ".png"
        master.resize((pt * scale, pt * scale), Image.LANCZOS).save(SET / name)
        images.append({"idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}", "filename": name})

(SET / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))
print(f"Wrote {len(images)} icons to {SET}")
