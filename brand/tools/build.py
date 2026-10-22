"""Build the Erst logo assets: vector marks and thermal renders.

The mark is an "e" drawn with three concentric rings. The rendered version
reads like a heat camera on one flat ground: the strokes heat from a coral rim
to a butter core.

Usage: uv run --with numpy --with pillow --with scipy python brand/tools/build.py
"""
import math
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

OUT = Path(__file__).resolve().parents[1] / "logo"
RNG = np.random.default_rng(7)

# Geometry in the unit square [-1, 1], y pointing down.
RADII = (0.84, 0.56, 0.28)
STROKE = 0.13
APERTURE_DEG = 38

# Palette. GROUND is the cold background, the rest is the heat ramp.
INK = "#121212"
GROUND = "#111111"
CORAL, ORANGE, BUTTER, CREAM = "#EF7A68", "#F6A563", "#F8D677", "#FBEDBE"

ICON = 1024
ICON_BODY = 824 / 1024


# ---------------------------------------------------------------- geometry


def mark(X, Y, radii=RADII):
    r = np.hypot(X, Y)
    theta = np.degrees(np.arctan2(Y, X))
    half = STROKE / 2
    ring = np.zeros_like(X, dtype=bool)
    for radius in radii:
        ring |= np.abs(r - radius) <= half
    top = Y < -half
    bottom = (Y > half) & ~((theta > 0) & (theta < APERTURE_DEG))
    bar = (np.abs(Y) <= half) & (np.abs(X) <= max(radii) + half)
    return (ring & (top | bottom)) | bar


def svg(color):
    """The mark as SVG, viewBox 0 0 200 200."""

    def u(v):
        return round(100 + v * 100, 2)

    a = math.radians(APERTURE_DEG)
    d = ""
    for r in RADII:
        R = round(r * 100, 2)
        d += f"M{u(-r)} 100A{R} {R} 0 0 1 {u(r)} 100"
        d += f"M{u(-r)} 100A{R} {R} 0 0 0 {u(r * math.cos(a))} {u(r * math.sin(a))}"
    w = round(STROKE * 100, 2)
    reach = RADII[0] + STROKE / 2
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">'
        f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}"/>'
        f'<rect x="{u(-reach)}" y="{u(-STROKE / 2)}" width="{round(reach * 200, 2)}" height="{w}" fill="{color}"/>'
        "</svg>\n"
    )


# ---------------------------------------------------------------- raster helpers


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = np.asarray(t, dtype=np.float32)
    return a + (b - a) * (t[..., None] if t.ndim == 2 else t)


def resize(a, w, h, method):
    return np.asarray(Image.fromarray(a.astype(np.float32), "F").resize((w, h), method))


def blur(a, sigma):
    """Gaussian blur of a 2D array. Large sigmas run on a smaller copy."""
    if sigma <= 10:
        return ndi.gaussian_filter(a, sigma)
    f = sigma / 5
    h, w = a.shape
    small = resize(a, max(2, int(w / f)), max(2, int(h / f)), Image.BOX)
    return resize(ndi.gaussian_filter(small, 5), w, h, Image.BICUBIC)


def grid(w, h, scale, cx, cy, ss=1):
    """Unit coordinates: the shorter side spans [-1, 1] / scale."""
    n = min(w, h)
    xs = ((np.arange(w * ss) + 0.5) / ss - w / 2) / (n / 2) / scale + cx
    ys = ((np.arange(h * ss) + 0.5) / ss - h / 2) / (n / 2) / scale + cy
    return np.meshgrid(xs.astype(np.float32), ys.astype(np.float32))


def coverage(fn, w, h, scale=1.0, cx=0.0, cy=0.0, ss=3):
    X, Y = grid(w, h, scale, cx, cy, ss)
    return fn(X, Y).astype(np.float32).reshape(h, ss, w, ss).mean(axis=(1, 3))


def grain(h, w, amount):
    return ndi.gaussian_filter(RNG.normal(0, amount, (h, w)).astype(np.float32), 0.6)[..., None]


def save(img, path, alpha=None):
    img = np.clip(img, 0, 1)
    if alpha is not None:
        img = np.dstack([img, np.clip(alpha, 0, 1)])
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA" if alpha is not None else "RGB").save(path, optimize=True)
    print(path.relative_to(OUT.parents[1]), f"{path.stat().st_size / 1024:.0f} KB")


# ---------------------------------------------------------------- thermal render


def thermal(w, h, scale, cx, cy, ground=GROUND, radii=RADII):
    """Heat-camera render of the mark, full bleed on one ground color."""
    m = coverage(lambda X, Y: mark(X, Y, radii), w, h, scale, cx, cy)
    n = min(w, h)
    t = np.clip(blur(m, n * 0.02) * 1.08 + blur(m, n * 0.09) * 0.16, 0, 0.9)
    col = np.ones((h, w, 3), np.float32) * rgb(ground)
    col = mix(col, rgb(CORAL), smooth(0.16, 0.42, t) * 0.85)
    col = mix(col, rgb(ORANGE), smooth(0.40, 0.62, t))
    col = mix(col, rgb(BUTTER), smooth(0.58, 0.84, t))
    col = mix(col, rgb(CREAM), smooth(0.88, 1.02, t))
    return col + grain(h, w, 0.016)


def icon(path, ground=GROUND):
    def body(X, Y):
        return np.abs(X / ICON_BODY) ** 5 + np.abs(Y / ICON_BODY) ** 5 <= 1

    a = coverage(body, ICON, ICON)
    content = thermal(ICON, ICON, 0.56, 0.0, 0.0, ground)

    # A faint rim, slightly brighter at the top, and a
    # faint top-down lift, so the icon separates from any dark background.
    inset = ICON_BODY - 3.0 / (ICON / 2)

    def inner(X, Y):
        return np.abs(X / inset) ** 5 + np.abs(Y / inset) ** 5 <= 1

    _, Y = grid(ICON, ICON, 1.0, 0.0, 0.0)
    rim = np.clip(a - coverage(inner, ICON, ICON), 0, 1)
    content = content + (rim * (0.06 + 0.16 * smooth(0.7, -0.9, Y)))[..., None]
    content = content + (0.03 * smooth(0.4, -1.0, Y) * a)[..., None]
    shadow = 0.30 * np.roll(blur(a, 22), 18, axis=0) + 0.16 * np.roll(blur(a, 3), 4, axis=0)
    alpha = a + shadow * (1 - a)
    save(content * (a / np.maximum(alpha, 1e-6))[..., None], path, alpha)


def thermal_mark(path, size=1024, scale=0.62):
    """The thermal mark on a transparent ground, for the app's own dark surfaces.

    The heat ramp is the same as `thermal`, but the cold ground becomes transparency: the coral
    rim fades out into a faint halo instead of into ink, so the mark sits on any dark surface
    without a tile around it.
    """
    m = coverage(mark, size, size, scale)
    t = np.clip(blur(m, size * 0.02) * 1.08 + blur(m, size * 0.09) * 0.16, 0, 0.9)
    col = np.ones((size, size, 3), np.float32) * rgb(CORAL)
    col = mix(col, rgb(ORANGE), smooth(0.40, 0.62, t))
    col = mix(col, rgb(BUTTER), smooth(0.58, 0.84, t))
    col = mix(col, rgb(CREAM), smooth(0.88, 1.02, t))
    alpha = smooth(0.06, 0.42, t)
    col = col + grain(size, size, 0.016)
    # Crop to the glow, so a view sizes the mark by its frame and not by empty margin.
    rows = np.flatnonzero(alpha.max(axis=1) > 1 / 255)
    cols = np.flatnonzero(alpha.max(axis=0) > 1 / 255)
    top, bottom = max(rows[0] - 4, 0), min(rows[-1] + 5, size)
    left, right = max(cols[0] - 4, 0), min(cols[-1] + 5, size)
    save(col[top:bottom, left:right], path, alpha[top:bottom, left:right])


def main():
    OUT.mkdir(exist_ok=True)
    for name, color in (("mark.svg", INK), ("mark-white.svg", "#FFFFFF")):
        (OUT / name).write_text(svg(color))
        print((OUT / name).relative_to(OUT.parents[1]))
    icon(OUT / "icon-1024.png")
    save(thermal(1600, 1800, 0.62, 0.32, 0.0, radii=RADII + (1.12,)), OUT / "hero.png")
    # Large e cut by the right and bottom edges, so the text sits on clean ink at the left.
    save(thermal(1280, 640, 1.24, -0.6, 0.33, radii=RADII + (1.12,)), OUT / "social-card-bg.png")
    # Last, so the grain of the assets above stays exactly as it was.
    thermal_mark(OUT / "mark-thermal.png")


if __name__ == "__main__":
    main()
