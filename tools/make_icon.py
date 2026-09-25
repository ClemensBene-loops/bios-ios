"""Generate the BIOS app icon: a pulse line on a deep blue gradient.

Output: 1024x1024 RGB PNG without alpha (App Store rejects alpha in the
marketing icon). Rendered at 4x and downscaled with LANCZOS for clean
anti-aliasing.

    python tools/make_icon.py            # writes the asset + docs preview

Requires Pillow and numpy.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_ASSET = ROOT / "BIOS" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
OUT_PREVIEW = ROOT / "docs" / "icon-preview.png"

SIZE = 1024
SS = 4                      # supersampling factor
W = SIZE * SS

# Palette
BG_TOP = np.array([6, 18, 48], dtype=np.float32)       # deep navy
BG_BOTTOM = np.array([8, 58, 96], dtype=np.float32)    # deep ocean blue
BG_GLOW = np.array([22, 96, 150], dtype=np.float32)    # soft center light
TURQUOISE = np.array([64, 226, 214], dtype=np.float32)
WHITE = np.array([255, 255, 255], dtype=np.float32)

BASELINE = 588.0
STROKE = 26.0               # core line width in 1024 space


def background() -> np.ndarray:
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float32) / W
    # Diagonal linear gradient.
    t = np.clip(0.75 * yy + 0.25 * xx, 0, 1)[..., None]
    img = BG_TOP * (1 - t) + BG_BOTTOM * t
    # Soft radial light behind the spike.
    d = np.sqrt((xx - 0.52) ** 2 + ((yy - 0.50) * 1.15) ** 2)
    g = np.clip(1 - d / 0.62, 0, 1) ** 2.2
    img = img * (1 - 0.55 * g[..., None]) + BG_GLOW * (0.55 * g[..., None])
    # Gentle vignette toward the corners.
    v = np.clip((np.sqrt((xx - 0.5) ** 2 + (yy - 0.5) ** 2) - 0.45) / 0.35, 0, 1)
    img *= (1 - 0.35 * v ** 1.5)[..., None]
    return img


def fillet(pts: list[tuple[float, float]], radius: list[float]) -> list[tuple[float, float]]:
    """Round each interior corner with a quadratic Bezier of the given radius.

    Straight flanks stay perfectly straight, only the tips get softened, which
    reads crisper than global smoothing.
    """
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        (x0, y0), (x1, y1), (x2, y2) = pts[i - 1], pts[i], pts[i + 1]
        r = radius[i]
        la, lb = math.hypot(x1 - x0, y1 - y0), math.hypot(x2 - x1, y2 - y1)
        r = min(r, 0.45 * la, 0.45 * lb)
        a = (x1 + (x0 - x1) * r / la, y1 + (y0 - y1) * r / la)
        b = (x1 + (x2 - x1) * r / lb, y1 + (y2 - y1) * r / lb)
        out.append(a)
        for k in range(1, 24):
            t = k / 24
            out.append((
                (1 - t) ** 2 * a[0] + 2 * (1 - t) * t * x1 + t * t * b[0],
                (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * y1 + t * t * b[1],
            ))
        out.append(b)
    out.append(pts[-1])
    return out


def pulse_path() -> list[tuple[float, float]]:
    """The line in 1024 space: calm wave, one clean spike, calm wave."""
    pts: list[tuple[float, float]] = []
    # Left: slow glucose-like swell that settles on the baseline.
    for x in np.arange(-40, 400, 2.0):
        s = math.sin((x + 40) / 440 * math.pi * 1.5)
        damp = max(0.0, 1 - max(0.0, x - 250) / 150)
        pts.append((x, BASELINE - 20 * s * damp))
    # Spike: straight flanks, small rounded tips.
    spike = [
        (400, BASELINE),
        (446, BASELINE),
        (478, BASELINE + 34),   # small dip
        (528, BASELINE - 318),  # tall peak
        (584, BASELINE + 150),  # deep trough
        (618, BASELINE),
        (650, BASELINE),
    ]
    pts.extend(fillet(spike, [0, 18, 16, 20, 20, 16, 0])[1:])
    # Right: soft recovery bump, then flat to the edge.
    for x in np.arange(652, 1066, 2.0):
        bump = 44 * math.exp(-(((x - 740) / 44) ** 2))
        pts.append((x, BASELINE - bump))
    return pts


def densify(pts: list[tuple[float, float]], step: float) -> list[tuple[float, float]]:
    out = []
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(1, int(math.hypot(x1 - x0, y1 - y0) / step))
        for i in range(n):
            t = i / n
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    out.append(pts[-1])
    return out


def stroke_mask(pts: list[tuple[float, float]], width: float) -> Image.Image:
    """Stamp discs along the path: round joins and caps everywhere."""
    m = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(m)
    r = width * SS / 2
    for x, y in densify(pts, 0.6):
        cx, cy = x * SS, y * SS
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return m


def edge_fade() -> np.ndarray:
    """Line fades out toward the left and right icon edges."""
    x = np.arange(W, dtype=np.float32) / W
    f = np.clip(np.minimum((x - 0.04) / 0.22, (0.96 - x) / 0.22), 0, 1)
    f = f * f * (3 - 2 * f)  # smoothstep
    return np.broadcast_to(f[None, :], (W, W))


def main() -> None:
    img = background()
    path = pulse_path()
    fade = edge_fade()

    core = np.asarray(stroke_mask(path, STROKE), dtype=np.float32) / 255
    wide = stroke_mask(path, STROKE * 2.2)
    glow_far = np.asarray(wide.filter(ImageFilter.GaussianBlur(46 * SS)), dtype=np.float32) / 255
    glow_near = np.asarray(wide.filter(ImageFilter.GaussianBlur(14 * SS)), dtype=np.float32) / 255

    # Glow in turquoise (additive-ish screen blend).
    for g, strength in ((glow_far, 0.55), (glow_near, 0.60)):
        a = (g * strength * fade)[..., None]
        img = img + (TURQUOISE - img) * a

    # Core: turquoise at the ends, white through the spike.
    xs = np.arange(W, dtype=np.float32) / W
    w = np.exp(-(((xs - 0.52) / 0.20) ** 2))[None, :, None]
    core_color = TURQUOISE * (1 - w) + WHITE * w
    a = (core * fade)[..., None]
    img = img * (1 - a) + core_color * a

    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    out = out.resize((SIZE, SIZE), Image.LANCZOS)
    assert out.mode == "RGB" and out.size == (SIZE, SIZE)

    for p in (OUT_ASSET, OUT_PREVIEW):
        p.parent.mkdir(parents=True, exist_ok=True)
        out.save(p, "PNG", optimize=True)
        print(f"wrote {p}")


if __name__ == "__main__":
    main()
