#!/usr/bin/env python3
"""Unwrap supplied rock surfaces onto the explicit 2m collision cube."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from prepare_scene_art import rectify

PACK = "scene_pack_20261015"
# Source-pixel quads: TL, TR, BR, BL. Painted top/front/side perspective is
# removed once before the real cube contributes perspective in Godot.
ROCK_QUADS = {
    "traction_rock_01": {
        "top": [[144, 173], [235, 173], [390, 236], [182, 241]],
        "front": [[180, 279], [394, 280], [402, 340], [203, 349]],
        "left": [[124, 179], [171, 261], [193, 364], [70, 339]],
        "right": [[420, 250], [450, 287], [450, 342], [421, 354]],
    },
    "traction_rock_02": {
        "top": [[215, 118], [308, 169], [349, 224], [241, 237]],
        "front": [[182, 223], [314, 260], [363, 363], [171, 377]],
        "left": [[182, 149], [203, 209], [145, 360], [106, 346]],
        "right": [[340, 245], [366, 226], [417, 342], [366, 375]],
    },
    "traction_rock_03": {
        "top": [[141, 143], [239, 117], [366, 166], [331, 237]],
        "front": [[180, 218], [330, 245], [356, 373], [185, 397]],
        "left": [[136, 157], [176, 216], [163, 385], [90, 344]],
        "right": [[345, 250], [391, 211], [429, 342], [365, 382]],
    },
    "traction_rock_04": {
        "top": [[107, 211], [176, 191], [221, 248], [154, 256]],
        "front": [[218, 271], [319, 270], [348, 317], [199, 326]],
        "left": [[103, 222], [191, 262], [162, 333], [65, 305]],
        "right": [[359, 268], [430, 239], [449, 284], [390, 324]],
    },
    "traction_rock_05": {
        "top": [[151, 177], [291, 143], [395, 211], [269, 264]],
        "front": [[194, 250], [343, 293], [345, 344], [184, 353]],
        "left": [[145, 187], [178, 239], [158, 367], [106, 332]],
        "right": [[364, 288], [412, 238], [422, 304], [367, 353]],
    },
}


def prepare(project: Path) -> dict:
    source = project / "assets/source_art" / PACK
    derived = project / "assets/derived_art" / PACK
    base = json.loads((derived / "manifest.json").read_text())
    inputs = {item["id"]: item for item in base["sources"]}
    output_dir = derived / "volume_faces"
    output_dir.mkdir(exist_ok=True)
    entries = []
    previews = []
    for asset_id in [f"painted_traction_rock_{i:02d}" for i in range(1, 6)] + [
        "painted_fissured_rock", "painted_fissured_rock_damaged",
    ]:
        key = asset_id.removeprefix("painted_")
        if key.startswith("traction"):
            source_id = key
            quads = ROCK_QUADS[key]
            image = Image.open(source / f"{source_id}.png").convert("RGBA")
        else:
            source_id = "fissured_rock_sheet" if key.endswith("damaged") else "fissured_rock_intact"
            image = Image.open(source / f"{source_id}.png").convert("RGBA")
            # Both states use the same wall coordinates. The left edge retains
            # the attached chunks on the intact state and its gouges on the damaged state.
            quads = {
                "front": [[274, 26], [473, 48], [474, 476], [259, 485]],
                "left": [[273, 50], [448, 71], [451, 470], [268, 466]],
                "right": [[291, 37], [471, 52], [472, 460], [286, 478]],
                "top": [[277, 27], [470, 48], [469, 194], [276, 198]],
            }
        original = source / inputs[source_id]["source"]
        if hashlib.sha256(original.read_bytes()).hexdigest() != inputs[source_id]["sha256"]:
            raise ValueError(f"Source hash mismatch: {original}")
        faces = {}
        for face, quad in quads.items():
            normalized = [[x / image.width, y / image.height] for x, y in quad]
            prepared = rectify(image, normalized, 512)
            # Cube edges need continuous painted outlines after the freeform
            # silhouette has been remapped. Use the source's darkest line colour.
            pixels = np.array(image)
            opaque = pixels[pixels[:, :, 3] > 200, :3]
            dark = opaque[np.max(opaque, axis=1) < 50]
            outline = tuple(np.median(dark, axis=0).astype(int)) + (255,)
            ImageDraw.Draw(prepared).rectangle((0, 0, 511, 511), outline=outline, width=4)
            filename = f"volume_faces/{asset_id}_{face}.png"
            prepared.save(derived / filename)
            faces[face] = filename
        faces["back"] = faces["front"]
        faces["bottom"] = faces["front"]
        entries.append({
            "id": asset_id, "size_m": [2, 2, 2], "source_id": source_id,
            "source_sha256": inputs[source_id]["sha256"], "faces": faces,
            "recipe": {"quads_px": quads, "output_size": [512, 512], "opaque_faces": True,
                       "edge_outline_px": 4, "edge_colour": "source_dark_line_median",
                       "back_reuses": "front", "bottom_reuses": "front",
                       "geometry_matches_collision": True},
        })
        preview = _preview(derived, faces)
        preview.save(output_dir / f"{asset_id}_preview.png")
        entries[-1]["preview"] = f"volume_faces/{asset_id}_preview.png"
        previews.append((asset_id, preview))
    review = Image.new("RGB", (1024, 512), "#303239")
    draw = ImageDraw.Draw(review)
    for i, (asset_id, image) in enumerate(previews):
        x, y = i % 4 * 256, i // 4 * 256
        image.thumbnail((240, 220), Image.Resampling.LANCZOS)
        review.paste(image, (x + 8, y), image)
        draw.text((x + 4, y + 232), asset_id.removeprefix("painted_"), fill="white")
    review.save(output_dir / "review_volume.png")
    result = {"version": 1, "pack": PACK, "base_manifest": "manifest.json",
              "entries": entries, "note": "Seven visual cubes align exactly with 2m dimensions; source art unchanged."}
    (derived / "volume_manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    params = (derived / "painted_traction_rock_01.png.import").read_text().split("[params]", 1)[1]
    for png in output_dir.glob("*.png"):
        settings = png.with_name(png.name + ".import")
        if not settings.exists():
            settings.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n'
                                '\n[deps]\nsource_file="res://' + png.relative_to(project).as_posix()
                                + '"\n\n[params]' + params)
    return result


def _preview(derived: Path, faces: dict) -> Image.Image:
    rgba = np.zeros((512, 512, 4), dtype=np.uint8)
    ys, xs = np.mgrid[:512, :512]
    points = np.stack((xs + 0.5, ys + 0.5), axis=-1)
    quads = {
        "front": [[18, 90], [128, 148], [128, 240], [18, 182]],
        "right": [[128, 148], [238, 90], [238, 182], [128, 240]],
        "top": [[128, 32], [238, 90], [128, 148], [18, 90]],
    }
    for name, quad in quads.items():
        quad = np.array(quad) * 2
        image = np.array(Image.open(derived / faces[name]))
        axes = np.column_stack((np.subtract(quad[1], quad[0]), np.subtract(quad[3], quad[0])))
        uv = (points - quad[0]) @ np.linalg.inv(axes).T
        inside = (uv >= 0).all(axis=-1) & (uv < 1).all(axis=-1)
        sample = (uv[inside] * [image.shape[1], image.shape[0]]).astype(int)
        rgba[inside] = image[sample[:, 1], sample[:, 0]]
    return Image.fromarray(rgba)


if __name__ == "__main__":
    result = prepare(Path(__file__).resolve().parents[1])
    print(f"Prepared {len(result['entries'])} collision-sized cube textures.")
