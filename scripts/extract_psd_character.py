from pathlib import Path
import json
import sys

import numpy as np
from PIL import Image
from psd_tools import PSDImage
from scipy import ndimage


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
    image = layer.composite(force=True).convert("RGBA")
    # Hidden parent groups report an empty bbox, so composite() comes back fully transparent.
    alpha = image.getextrema()[-1]
    if alpha[1] == 0:
        raw = layer.topil()
        if raw is not None:
            image = raw.convert("RGBA")
    return image, tuple(int(v) for v in layer.bbox)


def save_tight(name, image, global_bbox=None):
    alpha = np.asarray(image)[..., 3]
    bounds = Image.fromarray(alpha).getbbox()
    if bounds:
        image = image.crop(bounds)
        if global_bbox:
            global_bbox = (
                global_bbox[0] + bounds[0], global_bbox[1] + bounds[1],
                global_bbox[0] + bounds[2], global_bbox[1] + bounds[3],
            )
    image.save(destination / name)
    return global_bbox


def merge_layers(name, paths):
    entries = [layer_image(path) for path in paths]
    x1 = min(b[0] for _, b in entries)
    y1 = min(b[1] for _, b in entries)
    x2 = max(b[2] for _, b in entries)
    y2 = max(b[3] for _, b in entries)
    canvas = Image.new("RGBA", (x2 - x1, y2 - y1), (0, 0, 0, 0))
    for image, bbox in entries:
        canvas.alpha_composite(image, (bbox[0] - x1, bbox[1] - y1))
    return save_tight(name, canvas, (x1, y1, x2, y2))


metadata = {"source": str(source), "canvas": list(psd.size), "body_anchor": [515, 536], "parts": {}}

# The visible biped setup in the PSD: head, neck/torso, two arms, two legs and two wings.
metadata["parts"]["head"] = list(save_tight("head.png", *layer_image([6, 1])))
metadata["parts"]["torso"] = list(merge_layers("torso.png", [[3, 3], [6, 0]]))
metadata["parts"]["arm_left"] = list(save_tight("arm_left.png", *layer_image([3, 1])))
metadata["parts"]["arm_right"] = list(save_tight("arm_right.png", *layer_image([3, 0])))
metadata["parts"]["wing_left"] = list(save_tight("wing_left.png", *layer_image([1, 1])))
metadata["parts"]["wing_right"] = list(save_tight("wing_right.png", *layer_image([1, 0])))
metadata["parts"]["arm_hop"] = list(save_tight("arm_hop.png", *layer_image([5, 0])))
metadata["parts"]["arm_crawl_gorilla"] = list(save_tight("arm_crawl_gorilla.png", *layer_image([4, 1])))
metadata["parts"]["arm_crawl_pirate"] = list(save_tight("arm_crawl_pirate.png", *layer_image([4, 0])))
metadata["parts"]["snake_body"] = list(save_tight("snake_body.png", *layer_image([2, 0])))
metadata["parts"]["arm_snake_gorilla"] = list(save_tight("arm_snake_gorilla.png", *layer_image([2, 3])))
metadata["parts"]["arm_snake_pirate"] = list(save_tight("arm_snake_pirate.png", *layer_image([2, 1])))

legs, legs_bbox = layer_image([3, 2])
alpha = np.asarray(legs)[..., 3] > 8
labels, count = ndimage.label(alpha)
components = []
for label in range(1, count + 1):
    ys, xs = np.where(labels == label)
    if len(xs) < 20:
        continue
    bounds = (int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1))
    crop = legs.crop(bounds)
    global_bounds = (legs_bbox[0] + bounds[0], legs_bbox[1] + bounds[1], legs_bbox[0] + bounds[2], legs_bbox[1] + bounds[3])
    name = "leg_left.png" if global_bounds[0] < 500 else "leg_right.png"
    metadata["parts"][name[:-4]] = list(save_tight(name, crop, global_bounds))

for name, bbox in metadata["parts"].items():
    x1, y1, x2, y2 = bbox
    metadata["parts"][name] = {
        "bbox": bbox,
        "center": [(x1 + x2) / 2.0, (y1 + y2) / 2.0],
        "size": [x2 - x1, y2 - y1],
    }

# Reassemble the exported pieces on the original PSD canvas as a seam check.
assembled = Image.new("RGBA", psd.size, (0, 0, 0, 0))
for name in ["wing_left", "wing_right", "leg_left", "leg_right", "torso", "arm_left", "arm_right", "head"]:
    part = metadata["parts"][name]
    image = Image.open(destination / f"{name}.png").convert("RGBA")
    assembled.alpha_composite(image, (part["bbox"][0], part["bbox"][1]))
assembled.save(destination / "assembled_parts.png")

(destination / "metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(metadata, ensure_ascii=False, indent=2))
