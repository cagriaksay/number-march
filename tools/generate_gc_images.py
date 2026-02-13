#!/usr/bin/env python3
"""
Generate Game Center achievement and leaderboard images for Number March.
Creates 1024x1024 PNG images with a notebook paper aesthetic.

Usage:
    python generate_gc_images.py
"""

import os
import math
import random
from PIL import Image, ImageDraw, ImageFont

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "gc_images")
ACH_DIR = os.path.join(OUTPUT_DIR, "achievements")
LB_DIR = os.path.join(OUTPUT_DIR, "leaderboards")

FONT_PATH = os.path.join(SCRIPT_DIR, "..", "assets", "fonts", "Caveat-Bold.ttf")

SIZE = 1024
NUM_LEVELS = 60

# Colors matching the game's paper aesthetic
PAPER_COLOR = (253, 248, 232)      # #FDF8E8 cream paper
LINE_COLOR = (168, 199, 232, 100)  # Light blue notebook lines
MARGIN_COLOR = (232, 136, 136, 80) # Red margin line
PENCIL_COLOR = (68, 68, 68)        # #444444 dark pencil
PENCIL_LIGHT = (119, 119, 119)     # #777777 lighter pencil
STAR_COLOR = (204, 180, 50)        # Gold star
STAR_OUTLINE = (160, 140, 30)      # Darker gold
GREEN_COLOR = (88, 160, 88)        # Start green
RED_COLOR = (200, 80, 80)          # End red
BLUE_COLOR = (85, 119, 170)        # Blue accent


def draw_paper_background(draw, img_size):
    """Draw notebook paper background with lines."""
    # Fill with paper color
    draw.rectangle([0, 0, img_size, img_size], fill=PAPER_COLOR)
    
    # Horizontal notebook lines
    line_spacing = 38
    for y in range(0, img_size, line_spacing):
        draw.line([(0, y), (img_size, y)], fill=LINE_COLOR, width=1)
    
    # Vertical notebook lines
    for x in range(0, img_size, line_spacing):
        draw.line([(x, 0), (x, img_size)], fill=LINE_COLOR, width=1)
    
    # Red margin line on left
    draw.line([(80, 0), (80, img_size)], fill=MARGIN_COLOR, width=2)


def draw_rounded_border(draw, img_size, radius=60, color=(100, 100, 100), width=4):
    """Draw a rounded rectangle border."""
    r = radius
    s = img_size - 1
    # Top
    draw.line([(r, 0), (s - r, 0)], fill=color, width=width)
    # Bottom
    draw.line([(r, s), (s - r, s)], fill=color, width=width)
    # Left
    draw.line([(0, r), (0, s - r)], fill=color, width=width)
    # Right
    draw.line([(s, r), (s, s - r)], fill=color, width=width)
    # Corners
    draw.arc([(0, 0), (r * 2, r * 2)], 180, 270, fill=color, width=width)
    draw.arc([(s - r * 2, 0), (s, r * 2)], 270, 360, fill=color, width=width)
    draw.arc([(0, s - r * 2), (r * 2, s)], 90, 180, fill=color, width=width)
    draw.arc([(s - r * 2, s - r * 2), (s, s)], 0, 90, fill=color, width=width)


def draw_star(draw, cx, cy, outer_r, inner_r, color, outline_color=None, rotation=0):
    """Draw a 5-pointed star."""
    points = []
    for i in range(10):
        angle = math.radians(rotation + i * 36 - 90)
        r = outer_r if i % 2 == 0 else inner_r
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    draw.polygon(points, fill=color, outline=outline_color)


def draw_wobbly_circle(draw, cx, cy, radius, color, outline_color=None, width=3, seed=42):
    """Draw a hand-drawn wobbly circle."""
    rng = random.Random(seed)
    points = []
    segments = 36
    for i in range(segments):
        angle = i / segments * 2 * math.pi
        wobble = rng.uniform(-radius * 0.04, radius * 0.04)
        r = radius + wobble
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    if color:
        draw.polygon(points, fill=color)
    if outline_color:
        for i in range(len(points)):
            draw.line([points[i], points[(i + 1) % len(points)]], fill=outline_color, width=width)


def draw_trophy(draw, cx, cy, scale=1.0, color=STAR_COLOR):
    """Draw a simple trophy icon."""
    s = scale
    # Cup body
    cup_points = [
        (cx - 50*s, cy - 40*s),
        (cx + 50*s, cy - 40*s),
        (cx + 35*s, cy + 30*s),
        (cx - 35*s, cy + 30*s),
    ]
    draw.polygon(cup_points, fill=color, outline=STAR_OUTLINE)
    
    # Stem
    draw.rectangle([cx - 10*s, cy + 30*s, cx + 10*s, cy + 60*s], fill=color, outline=STAR_OUTLINE)
    
    # Base
    draw.rectangle([cx - 30*s, cy + 55*s, cx + 30*s, cy + 70*s], fill=color, outline=STAR_OUTLINE)
    
    # Handles
    draw.arc([cx - 75*s, cy - 30*s, cx - 40*s, cy + 20*s], 90, 270, fill=STAR_OUTLINE, width=int(4*s))
    draw.arc([cx + 40*s, cy - 30*s, cx + 75*s, cy + 20*s], 270, 90, fill=STAR_OUTLINE, width=int(4*s))


def draw_number_bubble(draw, cx, cy, number, font_large, color=PENCIL_COLOR, bg_color=None, radius=60):
    """Draw a number inside a wobbly circle."""
    if bg_color:
        draw_wobbly_circle(draw, cx, cy, radius, bg_color, color, width=3, seed=number * 7)
    else:
        draw_wobbly_circle(draw, cx, cy, radius, None, color, width=3, seed=number * 7)
    
    text = str(number)
    bbox = draw.textbbox((0, 0), text, font=font_large)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    draw.text((cx - tw / 2, cy - th / 2 - 5), text, fill=color, font=font_large)


def generate_achievement_image(level_num, font_path):
    """Generate achievement image for a single level."""
    img = Image.new("RGB", (SIZE, SIZE), PAPER_COLOR)
    draw = ImageDraw.Draw(img, "RGBA")
    
    draw_paper_background(draw, SIZE)
    
    # Load fonts
    font_huge = ImageFont.truetype(font_path, 180)
    font_large = ImageFont.truetype(font_path, 72)
    font_medium = ImageFont.truetype(font_path, 52)
    
    # Star at top-left
    draw_star(draw, 160, 180, 80, 35, STAR_COLOR, STAR_OUTLINE, rotation=5)
    
    # "LEVEL" text above number
    bbox = draw.textbbox((0, 0), "Level", font=font_large)
    tw = bbox[2] - bbox[0]
    draw.text((SIZE / 2 - tw / 2, 250), "Level", fill=PENCIL_LIGHT, font=font_large)
    
    # Level number big and centered
    level_text = str(level_num)
    bbox = draw.textbbox((0, 0), level_text, font=font_huge)
    tw = bbox[2] - bbox[0]
    draw.text((SIZE / 2 - tw / 2, 330), level_text, fill=PENCIL_COLOR, font=font_huge)
    
    # Decorative wobbly circle around the number
    draw_wobbly_circle(draw, SIZE / 2, 420, 170, None, PENCIL_LIGHT, width=3, seed=level_num)
    
    # "CLEAR!" text below
    clear_text = "Clear!"
    bbox = draw.textbbox((0, 0), clear_text, font=font_large)
    tw = bbox[2] - bbox[0]
    draw.text((SIZE / 2 - tw / 2, 620), clear_text, fill=GREEN_COLOR, font=font_large)
    
    # Small decorative stars at bottom
    for i, x in enumerate([300, 512, 724]):
        size = 35 if i == 1 else 25
        inner = 15 if i == 1 else 10
        draw_star(draw, x, 800, size, inner, STAR_COLOR, STAR_OUTLINE, rotation=i * 15)
    
    draw_rounded_border(draw, SIZE, radius=50, color=PENCIL_LIGHT, width=3)
    
    return img


def generate_all_levels_achievement(font_path):
    """Generate the special 'all levels complete' achievement image."""
    img = Image.new("RGB", (SIZE, SIZE), PAPER_COLOR)
    draw = ImageDraw.Draw(img, "RGBA")
    
    draw_paper_background(draw, SIZE)
    
    font_huge = ImageFont.truetype(font_path, 120)
    font_large = ImageFont.truetype(font_path, 72)
    font_medium = ImageFont.truetype(font_path, 48)
    
    # Multiple stars across top
    star_positions = [(200, 170), (512, 140), (824, 170)]
    for i, (sx, sy) in enumerate(star_positions):
        draw_star(draw, sx, sy, 70, 30, STAR_COLOR, STAR_OUTLINE, rotation=i * 12 - 10)
    
    # "Number" text
    bbox = draw.textbbox((0, 0), "Number", font=font_huge)
    tw = bbox[2] - bbox[0]
    draw.text((SIZE / 2 - tw / 2, 260), "Number", fill=PENCIL_COLOR, font=font_huge)
    
    # "Master" text
    bbox = draw.textbbox((0, 0), "Master", font=font_huge)
    tw = bbox[2] - bbox[0]
    draw.text((SIZE / 2 - tw / 2, 400), "Master", fill=PENCIL_COLOR, font=font_huge)
    
    # Decorative circle
    draw_wobbly_circle(draw, SIZE / 2, 420, 200, None, STAR_COLOR, width=3, seed=999)
    
    # "All 60 Levels" text
    sub_text = "All 60 Levels Complete!"
    bbox = draw.textbbox((0, 0), sub_text, font=font_medium)
    tw = bbox[2] - bbox[0]
    draw.text((SIZE / 2 - tw / 2, 650), sub_text, fill=GREEN_COLOR, font=font_medium)
    
    # Bottom stars row
    for i in range(5):
        x = 200 + i * 156
        draw_star(draw, x, 820, 30, 13, STAR_COLOR, STAR_OUTLINE, rotation=i * 20)
    
    draw_rounded_border(draw, SIZE, radius=50, color=STAR_COLOR, width=4)
    
    return img


def generate_leaderboard_image(level_num, font_path):
    """Generate leaderboard image for a single level."""
    img = Image.new("RGB", (SIZE, SIZE), PAPER_COLOR)
    draw = ImageDraw.Draw(img, "RGBA")
    
    draw_paper_background(draw, SIZE)
    
    font_huge = ImageFont.truetype(font_path, 180)
    font_large = ImageFont.truetype(font_path, 72)
    font_medium = ImageFont.truetype(font_path, 48)
    
    # "LEVEL" text above number
    bbox = draw.textbbox((0, 0), "Level", font=font_large)
    tw = bbox[2] - bbox[0]
    draw.text((SIZE / 2 - tw / 2, 250), "Level", fill=PENCIL_LIGHT, font=font_large)
    
    # Level number big and centered
    level_text = str(level_num)
    bbox = draw.textbbox((0, 0), level_text, font=font_huge)
    tw = bbox[2] - bbox[0]
    draw.text((SIZE / 2 - tw / 2, 330), level_text, fill=PENCIL_COLOR, font=font_huge)
    
    # Decorative wobbly circle around level + number
    draw_wobbly_circle(draw, SIZE / 2, 420, 170, None, BLUE_COLOR, width=3, seed=level_num + 100)
    
    # "Best Score" text below
    score_text = "Best Score"
    bbox = draw.textbbox((0, 0), score_text, font=font_large)
    tw = bbox[2] - bbox[0]
    draw.text((SIZE / 2 - tw / 2, 650), score_text, fill=BLUE_COLOR, font=font_large)
    
    draw_rounded_border(draw, SIZE, radius=50, color=BLUE_COLOR, width=3)
    
    return img


def main():
    os.makedirs(ACH_DIR, exist_ok=True)
    os.makedirs(LB_DIR, exist_ok=True)
    
    font_path = os.path.abspath(FONT_PATH)
    if not os.path.exists(font_path):
        print(f"ERROR: Font not found at {font_path}")
        return
    
    print(f"Generating Game Center images...")
    print(f"  Font: {font_path}")
    print(f"  Output: {OUTPUT_DIR}")
    
    # Achievement images
    print(f"\nGenerating {NUM_LEVELS} achievement images...")
    for i in range(1, NUM_LEVELS + 1):
        img = generate_achievement_image(i, font_path)
        path = os.path.join(ACH_DIR, f"level_{i}_complete.png")
        img.save(path)
        print(f"  level_{i}_complete.png", end="  ")
        if i % 10 == 0:
            print()
    
    # All levels complete achievement
    img = generate_all_levels_achievement(font_path)
    path = os.path.join(ACH_DIR, "all_levels_complete.png")
    img.save(path)
    print(f"  all_levels_complete.png")
    
    # Leaderboard images
    print(f"\nGenerating {NUM_LEVELS} leaderboard images...")
    for i in range(1, NUM_LEVELS + 1):
        img = generate_leaderboard_image(i, font_path)
        path = os.path.join(LB_DIR, f"level_{i}_score.png")
        img.save(path)
        print(f"  level_{i}_score.png", end="  ")
        if i % 10 == 0:
            print()
    
    total = NUM_LEVELS * 2 + 1
    print(f"\nDone! Generated {total} images.")
    print(f"  Achievements: {ACH_DIR} ({NUM_LEVELS + 1} files)")
    print(f"  Leaderboards: {LB_DIR} ({NUM_LEVELS} files)")


if __name__ == "__main__":
    main()
