#!/usr/bin/env python3
"""Rectify the unused climbing faces without rebuilding existing scene-pack art."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from prepare_scene_art import PACK_ID, face_quad, rectify


CLIMB_FACES = [
    "climbingrock_frontface", "climbingrock_sideface2", "climbingrock_sideface3",
    "climbingrock_topface", "climbingrock_topface2",
]


def preview(faces: dict[str, Image.Image], top: str) -> Image.Image:
    """A library thumbnail assembled from the actual rectified face textures."""
    canvas = np.zeros((512, 512, 4), dtype=np.uint8)
    ys, xs = np.mgrid[:512, :512]
    points = np.stack((xs + 0.5, ys + 0.5), axis=-1)
    quads = {
        "left": [(36, 170), (36, 350), (256, 478), (256, 298)],
        "right": [(256, 298), (256, 478), (476, 350), (476, 170)],
        "top": [(256, 42), (36, 170), (256, 298), (476, 170)],
    }
    for name, quad in quads.items():
        texture = faces[top if name == "top" else
                        "climbingrock_frontface" if name == "left" else
                        "climbingrock_sideface3"]
        origin = np.array(quad[0], dtype=float)
        axes = np.column_stack((np.subtract(quad[3], quad[0]),
                                np.subtract(quad[1], quad[0])))
        uv = (points - origin) @ np.linalg.inv(axes).T
        inside = (uv >= 0).all(axis=-1) & (uv < 1).all(axis=-1)
        sample = (uv[inside] * [texture.width, texture.height]).astype(int)
        canvas[inside] = np.array(texture)[sample[:, 1], sample[:, 0]]
    return Image.fromarray(canvas)


def prepare(project: Path) -> dict:
    source = project / "assets/source_art" / PACK_ID
    derived = project / "assets/derived_art" / PACK_ID
    base = json.loads((derived / "manifest.json").read_text())
    entries = {entry["id"]: entry for entry in base["entries"]}
    output_dir = derived / "remaining_objects"
    output_dir.mkdir(exist_ok=True)
    images = {}
    recipes = []
    for asset_id in CLIMB_FACES:
        entry = entries[asset_id]
        original = source / entry["source"]
        if hashlib.sha256(original.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError(f"Source hash mismatch: {original}")
        image = Image.open(original).convert("RGBA")
        quad = face_quad(image)
        prepared = rectify(image, quad, 1024)
        output = f"remaining_objects/{asset_id}.png"
        prepared.save(derived / output)
        images[asset_id] = prepared
        recipes.append({
            "id": asset_id, "source": entry["source"], "sha256": entry["sha256"],
            "output": output, "size_m": [2, 2],
            "recipe": {"quad": quad, "output_size": [1024, 1024],
                       "opaque_seams": True, "perspective_removed": True},
        })
    for suffix, top in [("", "climbingrock_topface"), ("_alt", "climbingrock_topface2")]:
        preview(images, top).save(output_dir / f"climbingrock{suffix}_preview.png")
    sheet = Image.new("RGB", (1024, 512), "#303239")
    for index, suffix in enumerate(["", "_alt"]):
        image = Image.open(output_dir / f"climbingrock{suffix}_preview.png")
        sheet.paste(image, (index * 512, 0), image)
    sheet.save(output_dir / "review_climbingrock.png")
    result = {
        "version": 1, "pack": PACK_ID,
        "base_manifest": "manifest.json", "entries": recipes,
        "variants": {
            "painted_climbingrock": "climbingrock_topface",
            "painted_climbingrock_alt": "climbingrock_topface2",
            "painted_rock_alt": "rock_topface",
            "painted_decayrock_alt": "decayrock_topface",
        },
        "note": "Climbing volumes use solid rock collision; attach painted_climb_surface for climbing.",
    }
    (derived / "remaining_objects_manifest.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    # Seed import flags before the first Godot import, without changing existing UIDs.
    exemplar = (derived / "objects/rock_frontface.png.import").read_text()
    parameters = exemplar.split("[params]", 1)[1]
    for image in output_dir.glob("*.png"):
        settings = image.with_name(image.name + ".import")
        if not settings.exists():
            settings.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n'
                                '\n[deps]\nsource_file="res://' +
                                image.relative_to(project).as_posix() +
                                '"\n\n[params]' + parameters)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    result = prepare(args.project)
    print(f"Prepared {len(result['entries'])} remaining faces for {len(result['variants'])} variants.")
