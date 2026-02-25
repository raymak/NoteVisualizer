#!/usr/bin/env python3
"""Generate NoteVisualizer app icon - pitch dots on dark background."""

from PIL import Image, ImageDraw, ImageFilter
import math
import random

SIZE = 1024
PADDING = 100

random.seed(42)  # Reproducible

img = Image.new("RGB", (SIZE, SIZE), (10, 10, 18))
draw = ImageDraw.Draw(img)

# Subtle grid lines (horizontal) representing pitch levels
grid_color = (30, 30, 50)
num_lines = 12
for i in range(num_lines + 1):
    y = PADDING + i * (SIZE - 2 * PADDING) / num_lines
    draw.line([(PADDING - 20, y), (SIZE - PADDING + 20, y)], fill=grid_color, width=1)

# Draw a flowing melody line made of colored dots
# Simulate a singing pitch contour - a smooth wave with slight vibrato
plot_w = SIZE - 2 * PADDING
plot_h = SIZE - 2 * PADDING

# Generate a smooth pitch contour (main melody)
num_dots = 180
points = []
base_pitch = 0.45  # Center-ish

for i in range(num_dots):
    t = i / num_dots
    # Main melody shape: gentle curve up then down
    pitch = base_pitch + 0.15 * math.sin(t * math.pi * 2.2 - 0.3)
    # Add slight vibrato
    pitch += 0.02 * math.sin(t * 40)
    # Add a second phrase going higher
    pitch += 0.08 * math.sin(t * math.pi * 1.1)

    x = PADDING + t * plot_w
    y = PADDING + (1.0 - pitch) * plot_h

    # Amplitude varies - louder in middle
    amp = 0.3 + 0.7 * math.sin(t * math.pi) ** 0.5

    points.append((x, y, amp, 0))

# Add a harmony line (polyphonic - second voice)
for i in range(num_dots):
    t = i / num_dots
    if t < 0.2 or t > 0.85:
        continue  # Harmony only in middle section

    pitch = base_pitch - 0.12 + 0.10 * math.sin(t * math.pi * 2.2 - 0.3)
    pitch += 0.015 * math.sin(t * 38)
    pitch += 0.06 * math.sin(t * math.pi * 1.1)

    x = PADDING + t * plot_w
    y = PADDING + (1.0 - pitch) * plot_h
    amp = 0.2 + 0.5 * math.sin((t - 0.2) / 0.65 * math.pi) ** 0.5

    points.append((x, y, amp, 1))

# Color palettes for voices (matching the app's voiceHues)
def voice_color(amp, voice):
    if voice == 0:
        # Cyan/teal (hue ~0.55)
        r = int(20 + 60 * amp)
        g = int(120 + 135 * amp)
        b = int(200 + 55 * amp)
    else:
        # Warm orange/red (hue ~0.0)
        r = int(200 + 55 * amp)
        g = int(80 + 80 * amp)
        b = int(30 + 40 * amp)
    return (r, g, b)

# Draw glow layer first (on a separate image for blur)
glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
glow_draw = ImageDraw.Draw(glow)

for x, y, amp, voice in points:
    color = voice_color(amp, voice)
    # Larger glow circles
    r = 8 + 6 * amp
    glow_draw.ellipse([x - r, y - r, x + r, y + r], fill=color)

glow = glow.filter(ImageFilter.GaussianBlur(radius=12))

# Composite glow onto base
from PIL import ImageChops
img = ImageChops.add(img, glow)
draw = ImageDraw.Draw(img)

# Draw sharp dots on top
for x, y, amp, voice in points:
    color = voice_color(amp, voice)
    r = 4 + 3 * amp
    draw.ellipse([x - r, y - r, x + r, y + r], fill=color)

# Add a subtle vertical axis line on the left
draw.line([(PADDING - 20, PADDING - 10), (PADDING - 20, SIZE - PADDING + 10)],
          fill=(60, 60, 90), width=2)

# Add small tick marks for notes on the left axis
for i in range(num_lines + 1):
    y = PADDING + i * (SIZE - 2 * PADDING) / num_lines
    draw.line([(PADDING - 28, y), (PADDING - 20, y)], fill=(80, 80, 120), width=2)

# Round corners (iOS style) - create a mask
mask = Image.new("L", (SIZE, SIZE), 0)
mask_draw = ImageDraw.Draw(mask)
corner_radius = int(SIZE * 0.22)  # iOS icon corner radius ratio
mask_draw.rounded_rectangle([0, 0, SIZE, SIZE], radius=corner_radius, fill=255)

# Apply mask
output = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
output.paste(img, mask=mask)

# Actually for App Store, provide square image - iOS applies masking automatically
# So save the unmasked version
output_path = "/Users/kardekani/Dropbox/Codes/Mobile Apps/NoteVisualizer/NoteVisualizer/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
img.save(output_path, "PNG")
print(f"Icon saved to {output_path}")
print(f"Size: {img.size}")
