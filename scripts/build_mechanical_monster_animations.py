"""Build transparent sprite strips from the six supplied mechanical-monster sheets.

The input JPEGs are preserved in assets/source_art/mechanical_monsters_20261019.
Run with the project's bundled Python/Pillow/Numpy; no online service is needed.
"""

from __future__ import annotations

from collections import deque
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "source_art" / "mechanical_monsters_20261019"
OUT = ROOT / "assets" / "animations" / "mechanical_monsters_20261019"
SIZE = 384
FRAMES = 8

# Rectangles stop before the printed frame numbers. The original art is the source
# of each pose; movement/attack timing and smoke are generated separately.
SPECS = {
    "eagle": {
        "name": "机械鹰", "accent": "#f6c741", "air": True,
        "source": "eagle_reference.jpg", "grid": (4, 2),
        "rows": [(10, 505), (580, 1070)], "x_edges": [0, 420, 840, 1260, 1680],
        "horizontal_bleed": 26,
        "walk_pick": [0, 1, 2, 3, 2, 1, 0, 1],
        "attack_pick": [0, 1, 2, 3, 3, 2, 1, 0],
        "max_box": (346, 330), "action": "俯冲抓击",
    },
    "albatross": {
        "name": "机械信天翁", "accent": "#50b9e8", "air": True,
        "source": "albatross_reference.jpg",
        # Wings cross the printed frame columns: overlap the crops and retain
        # the largest connected bird instead of shearing each wing at a seam.
        "walk_rects": [(max(0, i * 221 - 36), 658,
                        min(1768, (i + 1) * 221 + 36), 795) for i in range(8)],
        "attack_rects": [(max(0, 15 + i * 120 - 22), 1015,
                          min(1768, 135 + i * 120 + 22), 1160) for i in range(6)],
        "walk_pick": list(range(8)), "attack_pick": [0, 1, 2, 2, 1, 0, 1, 0],
        "max_box": (348, 260), "action": "俯冲突袭",
    },
    "gorilla": {
        "name": "机械猩猩", "accent": "#b99475", "air": False,
        "source": "gorilla_reference.jpg", "grid": (4, 2),
        "rows": [(12, 455), (545, 982)], "x_edges": [0, 294, 588, 882, 1176],
        "horizontal_bleed": 30,
        "walk_pick": list(range(8)), "attack_pick": [0, 1, 2, 2, 3, 2, 1, 0],
        "max_box": (344, 345), "action": "前冲重拳",
    },
    "gibbon": {
        "name": "机械长臂猿", "accent": "#e0ab72", "air": False,
        "source": "gibbon_reference.jpg", "grid": (4, 2),
        "rows": [(10, 455), (540, 975)], "x_edges": [0, 293, 586, 879, 1173],
        "horizontal_bleed": 34,
        "walk_pick": list(range(8)), "attack_pick": [0, 1, 2, 3, 3, 2, 1, 0],
        "max_box": (310, 345), "action": "前扑挥臂",
    },
    "ostrich": {
        "name": "机械鸵鸟", "accent": "#ead05c", "air": False,
        "source": "ostrich_reference.jpg", "grid": (4, 3),
        "rows": [(0, 345), (392, 735), (785, 1120)], "x_edges": [0, 231, 462, 693, 924],
        "horizontal_bleed": 18,
        "walk_pick": [0, 1, 2, 3, 4, 5, 6, 7],
        "attack_pick": [0, 1, 2, 3, 6, 3, 1, 0],
        "max_box": (278, 350), "action": "前踢",
    },
    "gerbil": {
        "name": "机械沙鼠", "accent": "#e8bc95", "air": False,
        "source": "gerbil_reference.jpg",
        "walk_rects": [(190, 710, 370, 862), (397, 710, 578, 862),
                       (612, 710, 795, 862), (827, 710, 1020, 862),
                       (1044, 710, 1258, 862), (1278, 710, 1495, 862),
                       (1498, 710, 1738, 862)],
        "attack_rects": [(215 + i * 259, 850, 215 + (i + 1) * 259, 1032) for i in range(6)],
        "walk_pick": [0, 1, 2, 3, 4, 5, 6, 5],
        "attack_pick": [0, 1, 2, 3, 4, 5, 3, 0],
        "max_box": (284, 268), "action": "前掌挥击",
    },
}


def rects_for(spec: dict) -> list[tuple[int, int, int, int]]:
    if "walk_rects" in spec:
        return spec["walk_rects"]
    result = []
    bleed = spec.get("horizontal_bleed", 0)
    sheet_width = spec["x_edges"][-1]
    for y0, y1 in spec["rows"]:
        for x0, x1 in zip(spec["x_edges"][:-1], spec["x_edges"][1:]):
            result.append((max(0, x0 - bleed), y0, min(sheet_width, x1 + bleed), y1))
    return result


def _fill_exterior(seed: np.ndarray) -> np.ndarray:
    """Treat the light background connected to the crop border as transparent."""
    height, width = seed.shape
    exterior = np.zeros((height, width), dtype=np.uint8)
    q: deque[tuple[int, int]] = deque()
    for x in range(width):
        if not seed[0, x]:
            exterior[0, x] = 1
            q.append((0, x))
        if not seed[height - 1, x]:
            exterior[height - 1, x] = 1
            q.append((height - 1, x))
    for y in range(height):
        if not seed[y, 0]:
            exterior[y, 0] = 1
            q.append((y, 0))
        if not seed[y, width - 1]:
            exterior[y, width - 1] = 1
            q.append((y, width - 1))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width and not seed[ny, nx] and not exterior[ny, nx]:
                exterior[ny, nx] = 1
                q.append((ny, nx))
    return exterior == 0


def _largest_object(mask: np.ndarray) -> np.ndarray:
    height, width = mask.shape
    seen = np.zeros_like(mask, dtype=np.uint8)
    best: list[tuple[int, int]] = []
    ys, xs = np.where(mask)
    for start_y, start_x in zip(ys, xs):
        if seen[start_y, start_x]:
            continue
        component = [(int(start_y), int(start_x))]
        seen[start_y, start_x] = 1
        q = deque(component)
        while q:
            y, x = q.popleft()
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = 1
                    component.append((ny, nx))
                    q.append((ny, nx))
        if len(component) > len(best):
            best = component
    result = np.zeros_like(mask, dtype=np.uint8)
    if best:
        ys2, xs2 = zip(*best)
        result[ys2, xs2] = 255
    return result


def _remove_enclosed_paper(mask: np.ndarray, seed: np.ndarray, rgb: np.ndarray) -> np.ndarray:
    """Open large white gaps enclosed by legs without hollowing pale body parts."""
    holes = mask & ~seed
    seen = np.zeros_like(holes, dtype=np.uint8)
    height, width = holes.shape
    ys, xs = np.where(holes)
    for start_y, start_x in zip(ys, xs):
        if seen[start_y, start_x]:
            continue
        component = [(int(start_y), int(start_x))]
        seen[start_y, start_x] = 1
        q = deque(component)
        while q:
            y, x = q.popleft()
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < height and 0 <= nx < width and holes[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = 1
                    component.append((ny, nx))
                    q.append((ny, nx))
        if len(component) < 1500:
            continue
        cy, cx = zip(*component)
        colors = rgb[cy, cx]
        if colors.mean(axis=0).min() >= 242:
            mask[cy, cx] = False
    return mask


def cutout(sheet: Image.Image, rect: tuple[int, int, int, int]) -> Image.Image:
    source = sheet.crop(rect).convert("RGB")
    rgb = np.asarray(source, dtype=np.uint8)
    brightest = rgb.max(axis=2).astype(np.int16)
    darkest = rgb.min(axis=2).astype(np.int16)
    chroma = brightest - darkest
    # Saturated paint and the dark ink/mechanical joints survive, while white or
    # gray paper/checkerboard and the soft screenshot shadows are excluded.
    seed = (darkest < 107) | ((chroma > 19) & (darkest < 236))
    seed_image = Image.fromarray((seed.astype(np.uint8) * 255), "L")
    seed = np.asarray(seed_image.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))) > 0
    solid = _remove_enclosed_paper(_fill_exterior(seed), seed, rgb)
    alpha = Image.fromarray(_largest_object(solid), "L")
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.45))
    # Screen captures include bright paper in the anti-aliased outline. Fade only
    # near-white pixels in the outer two-pixel rim, leaving light body paint intact.
    alpha_array = np.asarray(alpha, dtype=np.float32)
    interior = np.asarray(alpha.filter(ImageFilter.MinFilter(7))) > 250
    paper_lightness = np.clip((darkest - 205) / 50, 0, 1)
    paper_neutrality = np.clip((24 - chroma) / 24, 0, 1)
    paper_edge = paper_lightness * paper_neutrality * ~interior
    alpha = Image.fromarray(np.uint8(np.clip(alpha_array * (1 - 0.95 * paper_edge), 0, 255)), "L")
    bbox = alpha.getbbox()
    if bbox is None or (bbox[2] - bbox[0]) * (bbox[3] - bbox[1]) < 500:
        raise ValueError(f"No character isolated in crop {rect}")
    image = source.convert("RGBA")
    image.putalpha(alpha)
    return image.crop(bbox)


def place(sprite: Image.Image, box: tuple[int, int], airborne: bool,
          dx: int = 0, dy: int = 0, angle: float = 0, opacity: float = 1) -> Image.Image:
    width, height = sprite.size
    scale = min(box[0] / width, box[1] / height)
    resized = sprite.resize((max(1, round(width * scale)), max(1, round(height * scale))), Image.Resampling.LANCZOS)
    if angle:
        resized = resized.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    if opacity < 1:
        alpha = resized.getchannel("A").point(lambda value: round(value * opacity))
        resized.putalpha(alpha)
    canvas = Image.new("RGBA", (SIZE, SIZE))
    bottom = 304 if airborne else 365
    x = (SIZE - resized.width) // 2 + dx
    y = bottom - resized.height + dy
    canvas.alpha_composite(resized, (x, y))
    return canvas


def attack_effect(frame: Image.Image, monster_id: str, index: int, accent: str) -> None:
    if index not in (3, 4, 5):
        return
    layer = Image.new("RGBA", frame.size)
    draw = ImageDraw.Draw(layer)
    alpha = {3: 85, 4: 180, 5: 65}[index]
    color = tuple(bytes.fromhex(accent.lstrip("#")))
    if monster_id in ("eagle", "albatross"):
        points = [(246, 258), (282, 290), (318, 311), (348, 315)]
        draw.line(points, fill=color + (alpha,), width=5)
        draw.line([(290, 307), (326, 325)], fill=(255, 255, 255, alpha // 2), width=2)
    elif monster_id == "gorilla":
        draw.arc((222, 281, 359, 383), 35, 160, fill=color + (alpha,), width=6)
        for x, y in ((280, 360), (314, 350), (343, 365)):
            draw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=color + (alpha // 2,))
    elif monster_id == "gibbon":
        draw.arc((216, 190, 357, 347), 295, 80, fill=color + (alpha,), width=5)
    elif monster_id == "ostrich":
        draw.arc((237, 276, 378, 368), 150, 318, fill=color + (alpha,), width=5)
    else:
        draw.arc((221, 206, 341, 331), 270, 72, fill=color + (alpha,), width=4)
    frame.alpha_composite(layer)


def death_frame(sprite: Image.Image, spec: dict, index: int) -> Image.Image:
    opacity = [1, 1, .82, .32, 0, 0, 0, 0][index]
    frame = place(sprite, spec["max_box"], spec["air"], dy=-index * 2, opacity=opacity)
    if index < 2:
        return frame
    cloud = Image.new("RGBA", frame.size)
    draw = ImageDraw.Draw(cloud)
    strength = [0, 0, 115, 210, 205, 158, 86, 0][index]
    base_y = 205 if spec["air"] else 260
    outward = max(0, index - 3) * 10
    lift = max(0, index - 2) * 13
    for puff in range(23):
        phase = puff * 2.39996
        ring = math.sqrt((puff + .5) / 23)
        cx = SIZE / 2 + math.cos(phase) * (55 * ring + outward)
        cy = base_y + math.sin(phase) * (67 * ring + outward * .45) - lift
        radius = (12 + (puff % 5) * 2) * (1 + .21 * min(index - 2, 3))
        alpha = round(strength * (.52 + (puff % 4) * .08))
        shade = 140 + (puff % 3) * 14
        draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                     fill=(shade, shade + 1, shade + 12, alpha))
    cloud = cloud.filter(ImageFilter.GaussianBlur(2.5))
    frame.alpha_composite(cloud)
    return frame


def build(monster_id: str, spec: dict) -> dict:
    source = Image.open(SOURCE / spec["source"]).convert("RGB")
    walk = [cutout(source, rect) for rect in rects_for(spec)]
    attacks = [cutout(source, rect) for rect in spec.get("attack_rects", rects_for(spec))]
    if len(walk) < max(spec["walk_pick"]) + 1 or len(attacks) < max(spec["attack_pick"]) + 1:
        raise ValueError(f"Insufficient source poses for {monster_id}")
    arrays: dict[str, list[Image.Image]] = {"walk": [], "attack": [], "death": []}
    for i, pick in enumerate(spec["walk_pick"]):
        arrays["walk"].append(place(walk[pick], spec["max_box"], spec["air"]))
    offsets = [0, 3, 10, 20, 34, 23, 8, 0]
    y_offsets = [0, -2, -3, 1, 5, 3, 0, 0]
    for i, pick in enumerate(spec["attack_pick"]):
        dx = offsets[i] if monster_id != "gerbil" else 0
        dy = y_offsets[i] if monster_id != "gerbil" else 0
        angle = (-2 if i in (3, 4) and monster_id in ("eagle", "albatross") else 0)
        frame = place(attacks[pick], spec["max_box"], spec["air"], dx, dy, angle)
        attack_effect(frame, monster_id, i, spec["accent"])
        arrays["attack"].append(frame)
    for i in range(FRAMES):
        arrays["death"].append(death_frame(walk[0], spec, i))
    dest = OUT / monster_id
    dest.mkdir(parents=True, exist_ok=True)
    for state, frames in arrays.items():
        strip = Image.new("RGBA", (SIZE * FRAMES, SIZE))
        for index, frame in enumerate(frames):
            strip.alpha_composite(frame, (index * SIZE, 0))
        strip.save(dest / f"{state}.png", optimize=True)
    return {"id": monster_id, "name": spec["name"], "accent": spec["accent"],
            "air": spec["air"], "action": spec["action"], "frame_size": SIZE,
            "frames": FRAMES, "fps": {"walk": 9 if monster_id != "ostrich" else 11,
                                      "attack": 12, "death": 9},
            "source": f"res://assets/source_art/mechanical_monsters_20261019/{spec['source']}"}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    catalog = []
    for monster_id, spec in SPECS.items():
        catalog.append(build(monster_id, spec))
        print(f"built {monster_id}: walk / attack / death", flush=True)
    (OUT / "manifest.json").write_text(json.dumps({"monsters": catalog}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
