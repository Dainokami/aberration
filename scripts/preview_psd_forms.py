"""Export every splice/split form from the verification PSD and print placement metadata."""
from pathlib import Path
import json
import sys

import numpy as np
from PIL import Image, ImageDraw
from psd_tools import PSDImage

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
destination.mkdir(parents=True, exist_ok=True)
psd = PSDImage.open(source)


def layer_at(path):
    layer = psd
    for index in path:
        layer = layer[index]
    return layer


def layer_image(path):
    layer = layer_at(path)
    # Hidden parent groups report an empty bbox, so composite() drops their pixels.
    # topil() reads the layer's own raster, which is what the splice sheet actually stores.
    image = layer.topil()
    if image is None:
        image = layer.composite(force=True)
    image = image.convert("RGBA")
    return image, tuple(int(v) for v in layer.bbox)


def tight(image, global_bbox):
    alpha = np.asarray(image)[..., 3]
    bounds = Image.fromarray(alpha).getbbox()
    if not bounds:
        return image, global_bbox
    cropped = image.crop(bounds)
    bbox = (
        global_bbox[0] + bounds[0],
        global_bbox[1] + bounds[1],
        global_bbox[0] + bounds[2],
        global_bbox[1] + bounds[3],
    )
    return cropped, bbox


def save_part(name, path):
    image, bbox = layer_image(path)
    image, bbox = tight(image, bbox)
    image.save(destination / f"{name}.png")
    return {"bbox": list(bbox), "size": [image.width, image.height], "name": name}


parts = {
    "head": save_part("head", [6, 1]),
    "chest": save_part("chest", [6, 0]),
    "torso_biped": save_part("torso_biped", [3, 3]),
    "arm_biped_left": save_part("arm_biped_left", [3, 1]),
    "arm_biped_right": save_part("arm_biped_right", [3, 0]),
    "legs_biped": save_part("legs_biped", [3, 2]),
    "wing_left": save_part("wing_left", [1, 1]),
    "wing_right": save_part("wing_right", [1, 0]),
    "snake_body": save_part("snake_body", [2, 0]),
    "arm_pirate_left": save_part("arm_pirate_left", [2, 1]),
    "arm_pirate_right": save_part("arm_pirate_right", [2, 2]),
    "arm_gorilla": save_part("arm_gorilla", [2, 3]),
    "arm_crawl_pirate": save_part("arm_crawl_pirate", [4, 0]),
    "arm_crawl_gorilla": save_part("arm_crawl_gorilla", [4, 1]),
    "arm_hop": save_part("arm_hop", [5, 0]),
}

# Split the combined biped-leg layer into left/right the same way the runtime already does.
legs, legs_bbox = layer_image([3, 2])
from scipy import ndimage

alpha = np.asarray(legs)[..., 3] > 8
labels, count = ndimage.label(alpha)
for label in range(1, count + 1):
    ys, xs = np.where(labels == label)
    if len(xs) < 20:
        continue
    bounds = (int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1))
    crop = legs.crop(bounds)
    global_bounds = (
        legs_bbox[0] + bounds[0],
        legs_bbox[1] + bounds[1],
        legs_bbox[0] + bounds[2],
        legs_bbox[1] + bounds[3],
    )
    crop, global_bounds = tight(crop, global_bounds)
    name = "leg_left" if global_bounds[0] < 500 else "leg_right"
    crop.save(destination / f"{name}.png")
    parts[name] = {"bbox": list(global_bounds), "size": [crop.width, crop.height], "name": name}

forms = {
    "biped_full": ["wing_left", "wing_right", "leg_left", "leg_right", "torso_biped", "chest", "arm_biped_left", "arm_biped_right", "head"],
    "biped_no_wings": ["leg_left", "leg_right", "torso_biped", "chest", "arm_biped_left", "arm_biped_right", "head"],
    "no_legs": ["torso_biped", "chest", "arm_biped_left", "arm_biped_right", "head"],
    "crawl": ["arm_crawl_gorilla", "arm_crawl_pirate", "head"],
    "hop": ["arm_hop", "head"],
    "head_only": ["head"],
    "snake": ["snake_body", "arm_gorilla", "arm_pirate_left", "head"],
    "snake_no_arms": ["snake_body", "head"],
}


def compose(names):
    canvas = Image.new("RGBA", psd.size, (0, 0, 0, 0))
    for name in names:
        part = parts[name]
        image = Image.open(destination / f"{name}.png").convert("RGBA")
        canvas.alpha_composite(image, (part["bbox"][0], part["bbox"][1]))
    alpha = np.asarray(canvas)[..., 3]
    bounds = Image.fromarray(alpha).getbbox()
    if bounds:
        canvas = canvas.crop(bounds)
    return canvas


sheet_tiles = []
for form_name, names in forms.items():
    image = compose(names)
    image.save(destination / f"form_{form_name}.png")
    preview = image.copy()
    preview.thumbnail((280, 280), Image.Resampling.LANCZOS)
    tile = Image.new("RGBA", (300, 320), (255, 255, 255, 255))
    tile.paste(preview, ((300 - preview.width) // 2, 8), preview)
    draw = ImageDraw.Draw(tile)
    draw.text((8, 296), form_name, fill=(0, 0, 0, 255))
    sheet_tiles.append(tile)

columns = 4
rows = (len(sheet_tiles) + columns - 1) // columns
sheet = Image.new("RGBA", (columns * 300, rows * 320), (230, 230, 230, 255))
for index, tile in enumerate(sheet_tiles):
    sheet.paste(tile, ((index % columns) * 300, (index // columns) * 320))
sheet.convert("RGB").save(destination / "forms_contact.png")

meta = {"canvas": list(psd.size), "body_anchor": [515, 536], "parts": parts, "forms": forms}
(destination / "forms.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(meta, ensure_ascii=False, indent=2))
