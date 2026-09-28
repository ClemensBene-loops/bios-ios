"""Prepare the BIOS brand assets from the "Seed" source artwork.

Source: docs/brand/bios-seed.png (square, cream lowercase "b" with a leaf-shaped
counter on dark forest green; made with an image tool, so the flat areas carry
slight noise). The earlier pulse-line icon generator lives in git history.

The script measures, per pixel, how much of the cream mark covers it (0..1,
from luminance), then recomposes that coverage with exactly two flat colors.
This removes the noise, keeps the anti-aliased edges and yields:

- BIOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
  1024x1024 RGB without alpha (App Store rejects alpha), flat green edge to
  edge, no rounded corners (iOS masks them).
- docs/icon-preview.png (same file, for the README).
- Shared/BrandAssets.xcassets/BIOSMark.imageset/BIOSMark@2x.png / @3x.png
  the cream "b" alone on transparency, cropped symmetrically around the icon
  center, for the start animation, the "Über" row and the Live Activity
  (Shared/ is compiled into the app and the widget extension).
- BIOS/Assets.xcassets/LaunchBackground.colorset: the icon green, used by
  UILaunchScreen and the splash so there is no flash.

    python tools/make_icon.py [source.png]

Requires Pillow and numpy.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "brand" / "bios-seed.png"
ASSETS = ROOT / "BIOS" / "Assets.xcassets"
OUT_ICON = ASSETS / "AppIcon.appiconset" / "AppIcon-1024.png"
OUT_PREVIEW = ROOT / "docs" / "icon-preview.png"
OUT_MARK = ROOT / "Shared" / "BrandAssets.xcassets" / "BIOSMark.imageset"
OUT_BG = ASSETS / "LaunchBackground.colorset"

ICON = 1024
GREEN = (0x13, 0x3D, 0x21)   # dominant background of the source
CREAM = (0xFD, 0xF9, 0xEF)   # dominant mark color of the source
# Luminance band mapped to coverage 0..1. Background noise sits around 45,
# the mark around 249, so everything outside the band snaps to a flat color.
LUM_LO, LUM_HI = 58.0, 238.0
# Mark crop relative to the canvas size (half width/height), symmetric around
# the center, so the mark keeps its place inside the icon square.
# Swift mirrors this in SplashView (BIOSMarkImage.canvasFraction).
MARK_HALF = (261 / 1254, 347 / 1254)
MARK_HEIGHTS = {"2x": 260, "3x": 390}   # 130 pt tall in the splash


def coverage(src: Image.Image) -> Image.Image:
    rgb = np.asarray(src.convert("RGB"), dtype=np.float32)
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    t = np.clip((lum - LUM_LO) / (LUM_HI - LUM_LO), 0.0, 1.0)
    return Image.fromarray(t.astype(np.float32), "F")


def compose(cov: Image.Image) -> Image.Image:
    t = np.asarray(cov, dtype=np.float32).clip(0, 1)[..., None]
    g = np.array(GREEN, dtype=np.float32)
    c = np.array(CREAM, dtype=np.float32)
    img = g * (1 - t) + c * t
    return Image.fromarray(np.rint(img).astype(np.uint8), "RGB")


def mark(cov: Image.Image, height: int) -> Image.Image:
    w, h = cov.size
    hx, hy = MARK_HALF[0] * w, MARK_HALF[1] * h
    box = (round(w / 2 - hx), round(h / 2 - hy), round(w / 2 + hx), round(h / 2 + hy))
    crop = cov.crop(box)
    width = round(height * crop.width / crop.height)
    a = np.asarray(crop.resize((width, height), Image.LANCZOS), dtype=np.float32)
    alpha = np.rint(a.clip(0, 1) * 255).astype(np.uint8)
    rgba = np.zeros((height, width, 4), dtype=np.uint8)
    rgba[..., :3] = CREAM
    rgba[..., 3] = alpha
    return Image.fromarray(rgba, "RGBA")


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    src = Image.open(sys.argv[1] if len(sys.argv) > 1 else SOURCE)
    assert src.width == src.height, "source must be square"
    cov = coverage(src)

    icon = compose(cov.resize((ICON, ICON), Image.LANCZOS))
    assert icon.mode == "RGB" and icon.size == (ICON, ICON)
    for p in (OUT_ICON, OUT_PREVIEW):
        p.parent.mkdir(parents=True, exist_ok=True)
        icon.save(p, "PNG", optimize=True)
        print(f"wrote {p}")

    OUT_MARK.mkdir(parents=True, exist_ok=True)
    images = []
    for scale in ("1x", "2x", "3x"):
        entry = {"idiom": "universal", "scale": scale}
        if scale in MARK_HEIGHTS:
            name = f"BIOSMark@{scale}.png"
            m = mark(cov, MARK_HEIGHTS[scale])
            m.save(OUT_MARK / name, "PNG", optimize=True)
            entry["filename"] = name
            print(f"wrote {OUT_MARK / name} {m.size}")
        images.append(entry)
    write_json(OUT_MARK / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})

    OUT_BG.mkdir(parents=True, exist_ok=True)
    r, g, b = GREEN
    write_json(OUT_BG / "Contents.json", {
        "colors": [{
            "color": {
                "color-space": "srgb",
                "components": {"alpha": "1.000", "red": f"0x{r:02X}", "green": f"0x{g:02X}", "blue": f"0x{b:02X}"},
            },
            "idiom": "universal",
        }],
        "info": {"author": "xcode", "version": 1},
    })
    print(f"wrote {OUT_BG / 'Contents.json'}")


if __name__ == "__main__":
    main()
