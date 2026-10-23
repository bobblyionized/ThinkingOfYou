"""Generates Thinking Of You's 1024x1024 app icon (opaque RGB PNG, no alpha).

A deep pink heart on a dark gray background, nothing else. The heart has a
soft top-to-bottom gradient and a faint highlight so it doesn't look flat.
Pure Pillow, no assets.
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


GRAY_TOP, GRAY_BOTTOM = hexrgb(0x2B282B), hexrgb(0x1C1A1C)
PINK_TOP, PINK_BOTTOM = hexrgb(0xC2185B), hexrgb(0x8C0F45)
SHADOW = hexrgb(0x0E0C0E)


def vertical(top, bottom):
    strip = Image.new("RGB", (1, 256))
    for y in range(256):
        strip.putpixel((0, y), lerp(top, bottom, y / 255))
    return strip.resize((N, N), Image.BICUBIC)


# ---------------------------------------------------------------- background
img = vertical(GRAY_TOP, GRAY_BOTTOM)


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

# Soft shadow below the heart.
shadow = heart.filter(ImageFilter.GaussianBlur(N * 0.03))
shadow = ImageChops.offset(shadow, 0, int(N * 0.025)).point(lambda v: int(v * 0.6))
img = Image.composite(Image.new("RGB", (N, N), SHADOW), img, shadow)

# Heart body: deep pink gradient.
img = Image.composite(vertical(PINK_TOP, PINK_BOTTOM), img, heart)

# Faint highlight on the upper-left lobe, clipped to the heart.
gloss = Image.new("L", (N, N), 0)
gx, gy = cx - scale * 7.2, cy - scale * 6.4
ImageDraw.Draw(gloss).ellipse([gx - scale * 4.6, gy - scale * 2.9, gx + scale * 4.6, gy + scale * 2.9], fill=70)
gloss = gloss.rotate(28, center=(gx, gy), resample=Image.BICUBIC)
gloss = gloss.filter(ImageFilter.GaussianBlur(N * 0.02))
gloss = ImageChops.multiply(gloss, heart)
img = Image.composite(Image.new("RGB", (N, N), hexrgb(0xE04E86)), img, gloss)

out = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")
out.save(sys.argv[1], "PNG", optimize=True)
print("wrote", sys.argv[1], out.size, out.mode)
