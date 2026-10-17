#!/usr/bin/env python3
"""Import 1015 source PNGs unchanged; separate art components and record recipes."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

PACK = "scene_pack_20261015"


def clean_components(image: Image.Image) -> tuple[Image.Image, list[dict]]:
    pixels = np.array(image.convert("RGBA"))
    labels, _ = ndimage.label(pixels[:, :, 3] >= 32)
    components = []
    for label, slices in enumerate(ndimage.find_objects(labels), 1):
        if slices is None:
            continue
        count = int((labels[slices] == label).sum())
        if count >= 128:
            components.append({"label": label, "pixels": count,
                               "bounds": [slices[1].start, slices[0].start,
                                          slices[1].stop, slices[0].stop]})
    keep = np.isin(labels, [part["label"] for part in components])
    # Retain antialiased outlines adjoining the main components, discard stray alpha.
    keep = ndimage.binary_dilation(keep, iterations=2)
    pixels[~keep, 3] = 0
    return Image.fromarray(pixels), sorted(components, key=lambda p: p["pixels"], reverse=True)


def component_image(image: Image.Image, part: dict) -> Image.Image:
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).rectangle(part["bounds"], fill=255)
    result = image.copy()
    result.putalpha(Image.fromarray(np.minimum(np.array(image.getchannel("A")), np.array(mask))))
    return result


def slot(image: Image.Image, *, crop: list[int] | None = None) -> tuple[Image.Image, dict]:
    """Proportional fit to a shared 512-square; source pixels are never enlarged."""
    crop = crop or list(image.getbbox())
    cut = image.crop(crop)
    cut.thumbnail((504, 504), Image.Resampling.LANCZOS)
    output = Image.new("RGBA", (512, 512))
    offset = [(512 - cut.width) // 2, 508 - cut.height]
    output.alpha_composite(cut, tuple(offset))
    # Extend edge colours in transparent pixels to avoid dark mipmap fringes.
    rgba = np.array(output)
    transparent = rgba[:, :, 3] == 0
    nearest = ndimage.distance_transform_edt(transparent, return_distances=False, return_indices=True)
    rgba[transparent, :3] = rgba[nearest[0][transparent], nearest[1][transparent], :3]
    return Image.fromarray(rgba), {"crop": crop, "canvas": [512, 512],
                                 "fit": list(cut.size), "offset": offset,
                                 "pivot": [0.5, 508 / 512], "upscale": False}


def prepare(project: Path, supplied: Path) -> dict:
    source = project / "assets/source_art" / PACK
    derived = project / "assets/derived_art" / PACK
    source.mkdir(parents=True, exist_ok=True)
    derived.mkdir(parents=True, exist_ok=True)
    input_specs = [(f"traction_rock_{i:02d}", f"牵引岩块/牵引岩块_{i:02d}_512.png") for i in range(1, 6)]
    input_specs += [
        ("clinging_wall", "攀附岩壁/攀附岩壁_512.png"),
        ("fissured_rock_intact", "裂隙风化岩/裂隙风化岩（完整态）_512.png"),
        ("fissured_rock_sheet", "裂隙风化岩/裂隙风化岩（破损与独立落石）_512.png"),
    ]
    sources, cleaned, pieces = [], {}, {}
    for source_id, relative in input_specs:
        data = (supplied / relative).read_bytes()
        saved = source / f"{source_id}.png"
        if saved.exists() and saved.read_bytes() != data:
            raise ValueError(f"Existing immutable source differs: {saved}")
        if not saved.exists():
            saved.write_bytes(data)
        original = Image.open(saved).convert("RGBA")
        image, components = clean_components(original)
        cleaned[source_id], pieces[source_id] = image, components
        sources.append({"id": source_id, "supplied_path": relative,
                        "source": f"{source_id}.png", "sha256": hashlib.sha256(data).hexdigest(),
                        "pixels": list(original.size), "components": components})
    entries = []

    def add(asset_id: str, name: str, source_id: str, image: Image.Image,
            row: int, size: list[float], kind: str, crop: list[int] | None = None,
            component: dict | None = None) -> None:
        output, recipe = slot(image, crop=crop)
        if component is not None:
            recipe["component"] = component
        output.save(derived / f"{asset_id}.png")
        entries.append({"id": asset_id, "name": name, "source_id": source_id,
                        "output": f"{asset_id}.png", "spec_row": row,
                        "world_size": size, "kind": kind, "recipe": recipe})

    for i in range(1, 6):
        key = f"traction_rock_{i:02d}"
        add("painted_" + key, f"牵引岩块·{i:02d}", key, cleaned[key], 13, [2, 2, 2], "traction")
    add("painted_clinging_wall", "攀附岩壁", "clinging_wall", cleaned["clinging_wall"],
        15, [2, 2, 0.16], "wall")
    # Keep one crop for both rock states so the remaining wall never shifts.
    shared = list(cleaned["fissured_rock_intact"].getbbox())
    add("painted_fissured_rock", "裂隙风化岩", "fissured_rock_intact",
        cleaned["fissured_rock_intact"], 14, [2, 2, 2], "breakable", crop=shared)
    components = pieces["fissured_rock_sheet"]
    if len(components) != 4:
        raise ValueError("Expected a damaged wall and three independent falling rocks")
    sheet = cleaned["fissured_rock_sheet"]
    add("painted_fissured_rock_damaged", "裂隙风化岩·破损岩体", "fissured_rock_sheet",
        component_image(sheet, components[0]), 14, [2, 2, 2], "decoration",
        crop=shared, component=components[0])
    # Match each loose rock to the common crop's pixel scale, not one 2m cube per pebble.
    for i, part in enumerate(sorted(components[1:], key=lambda c: c["bounds"][1]), 1):
        height = round((part["bounds"][3] - part["bounds"][1]) / (shared[3] - shared[1]) * 2, 4)
        add(f"painted_fissured_rock_fragment_{i:02d}", f"裂隙落石·{i:02d}", "fissured_rock_sheet",
            component_image(sheet, part), 14, [height, height, height], "fragment", component=part)
    manifest = {"version": 1, "pack": PACK, "spec_workbook": "2m单元格_4K场景素材绘制规格.xlsx",
                "mechanism_workbook": "场景机制物件_加入情况核对.xlsx",
                "sources": sources, "entries": entries,
                "limitations": ["512px sources are below the rock specification; no added detail",
                                "single-view PNGs lack separate side/top faces",
                                "existing carry/climb/damage interfaces do not complete all Excel mechanics"]}
    (derived / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    review = Image.new("RGB", (1024, 256 * 3), "#303239")
    draw = ImageDraw.Draw(review)
    for index, entry in enumerate(entries):
        art = Image.open(derived / entry["output"])
        art.thumbnail((230, 216), Image.Resampling.LANCZOS)
        x, y = (index % 4) * 256, (index // 4) * 256
        review.paste(art, (x + (256 - art.width) // 2, y), art)
        draw.text((x + 4, y + 224), entry["id"].replace("painted_", ""), fill="white")
    review.save(derived / "review_objects.png")
    exemplar = (project / "assets/derived_art/scene_pack_20261014/objects/rock_frontface.png.import").read_text()
    params = exemplar.split("[params]", 1)[1]
    for png in derived.glob("*.png"):
        settings = png.with_name(png.name + ".import")
        if not settings.exists():
            settings.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n'
                                '\n[deps]\nsource_file="res://' + png.relative_to(project).as_posix()
                                + '"\n\n[params]' + params)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--source", type=Path)
    args = parser.parse_args()
    result = prepare(args.project, args.source or args.project.parent / "1015素材")
    print(f"Prepared {len(result['sources'])} immutable inputs and {len(result['entries'])} placeable images.")
