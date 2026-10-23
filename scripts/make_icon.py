"""Generates Thinking Of You's 1024x1024 app icon (opaque RGB PNG, no alpha).

A glossy cream heart with a soft drop shadow on a rose -> coral diagonal
gradient. Pure Pillow, no assets.
Usage: python3 make_icon.py <output.png>
"""
import math
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 3              # supersampling factor
N = 1024 * S


def hexrgb(h):
    return ((h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF)


def lerp(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


CORAL, ROSE, DEEP = hexrgb(0xFFA48C), hexrgb(0xF2668B), hexrgb(0xC9426E)
CREAM_TOP, CREAM_BOTTOM = hexrgb(0xFFFBF5), hexrgb(0xFFE4DC)
SHADOW = hexrgb(0x9E2F57)

# ---------------------------------------------------------------- background
# Diagonal gradient: coral at the top-left, rose at the bottom-right. Drawn on
# a small canvas and upscaled (smooth and fast), then a faint vignette.
small = 256
bg = Image.new("RGB", (small, small))
px = bg.load()
for y in range(small):
    for x in range(small):
        t = (x + y) / (2 * (small - 1))
        c = lerp(CORAL, ROSE, min(1.0, t * 1.15)) if t < 0.87 else lerp(ROSE, DEEP, (t - 0.87) / 0.13 * 0.5)
        px[x, y] = c
img = bg.resize((N, N), Image.BICUBIC)

glow = Image.new("L", (N, N), 0)
ImageDraw.Draw(glow).ellipse([-N * 0.25, -N * 0.30, N * 0.85, N * 0.70], fill=90)
glow = glow.filter(ImageFilter.GaussianBlur(N * 0.12))
img = Image.composite(Image.new("RGB", (N, N), hexrgb(0xFFD3C2)), img, glow)

# ---------------------------------------------------------------- heart shape
def heart_points(cx, cy, scale, steps=720):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * scale, cy - y * scale))
    return pts


cx, cy = N / 2, N * 0.50
scale = N * 0.0215
heart = Image.new("L", (N, N), 0)
ImageDraw.Draw(heart).polygon(heart_points(cx, cy, scale), fill=255)

# Soft drop shadow below the heart.
shadow = heart.filter(ImageFilter.GaussianBlur(N * 0.03))
shadow = ImageChops.offset(shadow, 0, int(N * 0.028)).point(lambda v: int(v * 0.45))
img = Image.composite(Image.new("RGB", (N, N), SHADOW), img, shadow)

# Heart body: vertical cream gradient.
fill = Image.new("RGB", (1, 256))
for y in range(256):
    fill.putpixel((0, y), lerp(CREAM_TOP, CREAM_BOTTOM, y / 255))
fill = fill.resize((N, N), Image.BICUBIC)
img = Image.composite(fill, img, heart)

# Inner rim: a slightly rosier edge so the heart reads as rounded.
rim = ImageChops.subtract(heart, heart.filter(ImageFilter.GaussianBlur(N * 0.02)))
rim = rim.point(lambda v: min(255, int(v * 1.4)))
img = Image.composite(Image.new("RGB", (N, N), hexrgb(0xF6B3B8)), img, rim)

# Gloss: a white highlight on the upper-left lobe, clipped to the heart.
gloss = Image.new("L", (N, N), 0)
gx, gy = cx - scale * 7.2, cy - scale * 6.4
ImageDraw.Draw(gloss).ellipse([gx - scale * 4.6, gy - scale * 2.9, gx + scale * 4.6, gy + scale * 2.9], fill=235)
gloss = gloss.rotate(28, center=(gx, gy), resample=Image.BICUBIC)
gloss = gloss.filter(ImageFilter.GaussianBlur(N * 0.012))
gloss = ImageChops.multiply(gloss, heart)
img = Image.composite(Image.new("RGB", (N, N), (255, 255, 255)), img, gloss)

# Small sparkle dot next to the gloss.
dot = Image.new("L", (N, N), 0)
dx, dy, dr = cx + scale * 6.6, cy - scale * 8.2, scale * 1.15
ImageDraw.Draw(dot).ellipse([dx - dr, dy - dr, dx + dr, dy + dr], fill=200)
dot = ImageChops.multiply(dot.filter(ImageFilter.GaussianBlur(N * 0.004)), heart)
img = Image.composite(Image.new("RGB", (N, N), (255, 255, 255)), img, dot)

out = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")
out.save(sys.argv[1], "PNG", optimize=True)
print("wrote", sys.argv[1], out.size, out.mode)
