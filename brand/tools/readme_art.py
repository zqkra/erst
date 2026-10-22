"""Render the heat art behind the README images.

The art is developed the way the app draws its brand moments (app/Sources/ErstUI/Brand) and the
launch film draws its frames: strokes in gray on black, a Gaussian blur for diffusing heat, a gain,
zero-mean grain with a fixed seed, and the icon's thermal palette. The README images are composed
in Paper over these backgrounds.

Usage: uv run --with numpy --with pillow --with scipy python brand/tools/readme_art.py [out_dir]
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]

# HeatPalette: ground, then the ramp to butter.
STOPS = [
    (0.0, 0x0E0E0F), (0.18, 0x2A1715), (0.34, 0x72413A), (0.48, 0xC36557),
    (0.60, 0xD5745D), (0.74, 0xF4A263), (0.88, 0xFAC371), (1.0, 0xFCD27B),
]
GRAIN = 0.12
# Where nothing is hot the art shows the plain ground, without grain.
NO_HEAT = 0.002
GRAIN_FLOOR, GRAIN_FLOOR_HEAT = 0.025, 0.1

# EchoGeometry: the mark's rings in points, its stroke, and the mouth below the right horizontal.
MARK_RADII = (28, 56, 84)
MARK_STROKE = 16
MOUTH = math.radians(38)


def palette():
    """The palette as a 1024 entry lookup table of RGB floats."""
    n = 1024
    lut = np.zeros((n, 3), np.float32)
    for i in range(n):
        p = i / (n - 1)
        k = 1
        while k < len(STOPS) - 1 and STOPS[k][0] < p:
            k += 1
        (p0, c0), (p1, c1) = STOPS[k - 1], STOPS[k]
        s = (p - p0) / (p1 - p0)
        for ch, shift in enumerate((16, 8, 0)):
            a, b = (c0 >> shift) & 255, (c1 >> shift) & 255
            lut[i, ch] = (a + (b - a) * s) / 255
    return lut


def gray(heat):
    """The stroke's gray, as Core Image reads a gray canvas into its sRGB working space."""
    linear = min(max(heat, 0.0), 1.0) ** 2.2
    return 12.92 * linear if linear <= 0.0031308 else 1.055 * linear ** (1 / 2.4) - 0.055


class Canvas:
    """A gray field in pixels. Strokes combine by keeping the hotter value."""

    def __init__(self, width, height):
        self.width, self.height = width, height
        ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
        self.x, self.y = xs + 0.5, ys + 0.5
        self.field = np.zeros((height, width), np.float32)

    def stroke(self, distance, width, heat, clip=None):
        cover = np.clip(width / 2 - distance + 0.5, 0, 1)
        if clip is not None:
            cover = cover * clip
        np.maximum(self.field, cover * gray(heat), out=self.field)

    def segment(self, x0, y0, x1, y1):
        dx, dy = x1 - x0, y1 - y0
        t = np.clip(((self.x - x0) * dx + (self.y - y0) * dy) / max(dx * dx + dy * dy, 1e-6), 0, 1)
        return np.hypot(self.x - x0 - t * dx, self.y - y0 - t * dy)

    def arc(self, cx, cy, radius, mouth):
        """The upper half of a ring; with `mouth`, also the lower half up to the mouth."""
        px, py = self.x - cx, self.y - cy
        angle = np.arctan2(py, px)  # y down: the upper half is negative
        on = angle <= 0
        if mouth:
            on |= angle >= MOUTH
        ring = np.abs(np.hypot(px, py) - radius)
        ends = [(cx - radius, cy), (cx + radius, cy)]
        if mouth:
            ends[1] = (cx + radius * math.cos(MOUTH), cy + radius * math.sin(MOUTH))
        cap = np.minimum(*(np.hypot(self.x - ex, self.y - ey) for ex, ey in ends))
        return np.where(on, ring, cap)

    def rounded_rect(self, x, y, w, h, r):
        """Signed distance to a rounded rectangle: negative inside."""
        qx = np.abs(self.x - (x + w / 2)) - (w / 2 - r)
        qy = np.abs(self.y - (y + h / 2)) - (h / 2 - r)
        outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
        return outside + np.minimum(np.maximum(qx, qy), 0) - r

    def mark(self, cx, cy, unit, heat):
        width = MARK_STROKE * unit
        outer = MARK_RADII[-1] * unit
        self.stroke(self.segment(cx - outer, cy, cx + outer, cy), width, heat)
        for radius in MARK_RADII:
            self.stroke(self.arc(cx, cy, radius * unit, True), width, heat)


def falloff(first, step, count, width, coldest):
    """EchoFalloff: near echoes wide and hot, far ones thin and cold."""
    for i in range(count):
        d = i / max(count - 1, 1)
        yield first + step * i, width * (1.6 - 0.9 * d), 1 - (1 - coldest) * d**0.8


def develop(canvas, sigma, gain):
    return ndi.gaussian_filter(canvas.field, sigma, mode="nearest") * gain


def living_ground(width, height, scale, cx, cy, phase):
    """The film's ground: the mark's echoes at the scale of the frame, far out of focus."""
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    d = np.hypot(xs + 0.5 - cx, ys + 0.5 - cy) / scale

    def step(a, b, x):
        k = np.clip((x - a) / (b - a), 0, 1)
        return k * k * (3 - 2 * k)

    envelope = step(760, 1200, d) * (1 - step(2100, 2600, d))
    c = 0.5 + 0.5 * np.cos(2 * math.pi / 300 * (d - phase))
    cool = 1 - 0.38 * np.clip((d - 1150) / 1100, 0, 1)
    return ((0.07 + 0.25 * c * c) * cool * envelope).astype(np.float32)


def paint(heat, path, ground=None):
    """Screens the ground into the heat, adds the grain, and maps through the palette."""
    h, w = heat.shape
    if ground is not None:
        heat = heat + ground - heat * ground
    rng = np.random.default_rng(7)
    grain = (GRAIN / 3) * rng.random((3, h, w), dtype=np.float32).sum(axis=0) - GRAIN / 2
    k = 1 - np.clip(heat / GRAIN_FLOOR_HEAT, 0, 1)
    floor = GRAIN_FLOOR * k * k * (3 - 2 * k)
    lut = palette()
    index = np.clip(np.rint((heat + grain - floor) * (len(lut) - 1)), 0, len(lut) - 1).astype(int)
    color = lut[index]
    color[heat < NO_HEAT] = lut[0]
    Image.fromarray((color * 255 + 0.5).astype(np.uint8), "RGB").save(path, optimize=True)
    print(path, f"{path.stat().st_size / 1024:.0f} KB")


def hero(path, width=1600, height=760, horizon=232):
    """The welcome at rest, wide: echoes over a horizon with the mark at its center."""
    scale = width / 600  # the welcome is 600 points wide
    canvas = Canvas(width, height)
    cx = width / 2
    canvas.stroke(canvas.segment(0, horizon, width, horizon), 3.6 * scale, 0.6)
    for radius, stroke, heat in falloff(64, 22.8, 16, 4.2, 0.2):
        canvas.stroke(canvas.arc(cx, horizon, radius * scale, False), stroke * scale, heat)
    canvas.mark(cx, horizon, 0.42 * scale, 1.0)
    paint(develop(canvas, 2.6 * scale, 1.3), path)


def ground(path, width=1600, height=1000, phase=75.0, shift=0.0):
    """The out-of-focus echoes behind a screen, rising from below the frame."""
    scale = width / 1920  # the film is 1920 wide
    field = living_ground(width, height, scale, width / 2 + shift * scale, height + 520 * scale, phase)
    paint(np.zeros((height, width), np.float32), path, field)


def private(path, width=1600, height=1000, top=262):
    """A Mac drawn in heat, its echoes rising inside the screen and stopping at its edge."""
    s = width / 1920
    mac_w, mac_h, radius = 840 * s, 525 * s, 26 * s
    x, y = (width - mac_w) / 2, top
    base = y + mac_h + 33 * s
    canvas = Canvas(width, height)
    canvas.stroke(np.abs(canvas.rounded_rect(x, y, mac_w, mac_h, radius)), 5 * s, 0.66)
    half = mac_w / 2 + 70 * s
    canvas.stroke(canvas.segment(width / 2 - half, base, width / 2 + half, base), 12 * s, 0.55)
    notch = 64 * s
    inner = canvas.rounded_rect(x + 7 * s, y + 7 * s, mac_w - 14 * s, mac_h - 14 * s, radius - 7 * s)
    clip = np.clip(0.5 - inner, 0, 1)
    for ring_radius, stroke, heat in falloff(70, 50, 9, 6.0, 0.22):
        canvas.stroke(
            canvas.arc(width / 2, y + mac_h - 8 * s, ring_radius * s, False), stroke * s, heat, clip
        )
    art = develop(canvas, 5.2 * s, 1.3)
    # The notch is a cooler stretch of the base, so it lowers the heat there.
    notch_canvas = Canvas(width, height)
    notch_canvas.stroke(notch_canvas.segment(width / 2 - notch, base, width / 2 + notch, base), 12 * s, 1)
    art = art * (1 - 0.45 * develop(notch_canvas, 5.2 * s, 1.0))
    paint(art, path)


def pipeline(path, stations, width=1600, height=620, horizon=330):
    """A horizon where each station's echo has one ring more, until the last becomes the mark."""
    canvas = Canvas(width, height)
    canvas.stroke(canvas.segment(0, horizon, width, horizon), 4, 0.42)
    for index, x in enumerate(stations[:-1]):
        rings = index + 1
        for radius, stroke, heat in falloff(18, 17, rings, 5.5, 0.3 if rings > 1 else 1.0):
            canvas.stroke(canvas.arc(x, horizon, radius, False), stroke, heat)
    canvas.mark(stations[-1], horizon, 0.46, 1.0)
    paint(develop(canvas, 2.4, 1.3), path)


def cutout(source, path, size, radius, scale=2):
    """Cuts an overlay panel out of a snapshot: the panel is centered on a 1440 by 900 stage."""
    image = np.asarray(Image.open(source).convert("RGBA")).astype(np.float32)
    w, h = size[0] * scale, size[1] * scale
    x, y = (1440 * scale - w) / 2, (900 * scale - h) / 2
    canvas = Canvas(image.shape[1], image.shape[0])
    alpha = np.clip(0.5 - canvas.rounded_rect(x, y, w, h, radius * scale), 0, 1)
    image[..., 3] *= alpha
    crop = image[int(y) : int(y + h), int(x) : int(x + w)]
    Image.fromarray(crop.round().astype(np.uint8), "RGBA").save(path, optimize=True)
    print(path, f"{path.stat().st_size / 1024:.0f} KB")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".erst-dev" / "readme-art"
    out.mkdir(parents=True, exist_ok=True)
    hero(out / "hero.png")
    ground(out / "ground-a.png", phase=75)
    ground(out / "ground-b.png", phase=160, shift=-140)
    ground(out / "ground-c.png", phase=235, shift=120)
    ground(out / "ground-d.png", phase=115, shift=260)
    private(out / "private.png")
    pipeline(out / "pipeline.png", [240 + 280 * i for i in range(5)])
    # The real screens, from `swift run ErstSnapshots`, with the sample desktop cut away.
    snapshots = ROOT / ".erst-dev" / "snapshots"
    if snapshots.is_dir():
        panel, search, radius = (1152, 810), (936, 585), 30  # SnapshotStageMetrics, Radius.panel
        cutout(snapshots / "timeline-mid-history.png", out / "timeline.png", panel, radius)
        cutout(snapshots / "moment-search.png", out / "moment.png", panel, radius)
        cutout(snapshots / "search-results.png", out / "search.png", search, radius)


if __name__ == "__main__":
    main()
