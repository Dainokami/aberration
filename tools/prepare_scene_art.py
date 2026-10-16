#!/usr/bin/env python3
"""Prepare the supplied scene-art packs without modifying archive/source bytes.

Requires Pillow, numpy and scipy. All image edits are recorded in manifest.json;
running again verifies immutable sources and deterministically rebuilds derivatives.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
from zipfile import ZipFile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from scipy.spatial import ConvexHull

PACK_ID = "scene_pack_20261014"
TERRAIN_NAMES = {
    "草地": "grass", "草坪": "meadow", "土面": "earth",
    "悬崖边": "cliff", "斜坡": "slope", "侧": "block_reference",
    "拐角": "corner_reference", "拐角2": "corner_color_reference",
    "小场景": "detail_sheet",
}
PACKS = {
    "素材_PNG.zip": "terrain",
    "素材.zip": "objects",
    "独立PNG素材_带碎渣版_45件.zip": "details",
}


def black_to_alpha(image: Image.Image, threshold: int = 8,
                   protect: Image.Image | None = None) -> Image.Image:
    """Remove only border-connected black. An explicit mask wins over inference.

    Exact black composited against exact black art is mathematically ambiguous.
    Existing brown/black outlines above the threshold and enclosed lines survive.
    We deliberately do not globally unpremultiply RGB or invent lost edge colours.
    """
    rgba = np.array(image.convert("RGBA"))
    candidate = rgba[:, :, :3].max(axis=2) <= threshold
    if protect is not None:
        candidate &= np.asarray(protect.convert("L").resize(image.size)) < 128
    seeds = np.zeros(candidate.shape, dtype=bool)
    seeds[0, :] = candidate[0, :]
    seeds[-1, :] = candidate[-1, :]
    seeds[:, 0] = candidate[:, 0]
    seeds[:, -1] = candidate[:, -1]
    background = ndimage.binary_propagation(seeds, mask=candidate)
    rgba[background, 3] = 0
    # RGB in zero-alpha pixels is irrelevant at full resolution, but extending
    # neighbouring colours prevents black contamination when mipmaps are built.
    if background.any() and not background.all():
        nearest = ndimage.distance_transform_edt(background, return_distances=False,
                                                 return_indices=True)
        rgb = rgba[:, :, :3].copy()
        rgba[background, :3] = rgb[nearest[0][background], nearest[1][background]]
    return Image.fromarray(rgba)


def trim(image: Image.Image, padding: int = 4) -> tuple[Image.Image, list[int]]:
    box = image.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox()
    if not box:
        raise ValueError("Cannot import an empty image")
    cropped = image.crop(box)
    result = Image.new("RGBA", (cropped.width + padding * 2,
                                cropped.height + padding * 2))
    result.paste(cropped, (padding, padding))
    return result, list(box)


def face_quad(image: Image.Image) -> list[list[float]]:
    """Fit four silhouette corners, preserving painted perspective coordinates."""
    alpha = np.asarray(image.getchannel("A")) > 160
    labels, count = ndimage.label(alpha)
    if not count:
        raise ValueError("No opaque face")
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    alpha = labels == sizes.argmax()
    edge = alpha & ~ndimage.binary_erosion(alpha)
    ys, xs = np.where(edge)
    points = np.column_stack((xs, ys))
    hull = points[ConvexHull(points).vertices].astype(float).tolist()
    # Simplify a convex silhouette by deleting the least significant triangle.
    while len(hull) > 4:
        areas = []
        for i, p in enumerate(hull):
            a, b, c = np.array(hull[i - 1]), np.array(p), np.array(hull[(i + 1) % len(hull)])
            v, w = b - a, c - a
            areas.append(abs(v[0] * w[1] - v[1] * w[0]))
        del hull[int(np.argmin(areas))]
    # Winding: top-left, top-right, bottom-right, bottom-left.
    start = min(range(4), key=lambda i: hull[i][0] / image.width + hull[i][1] / image.height)
    hull = hull[start:] + hull[:start]
    if hull[1][0] < hull[-1][0]:
        hull = [hull[0], hull[3], hull[2], hull[1]]
    return [[round(x / image.width, 6), round(y / image.height, 6)] for x, y in hull]


def rectify(image: Image.Image, quad: list[list[float]], size: int = 1024) -> Image.Image:
    # PIL QUAD is TL, BL, BR, TR. Rectification removes the perspective painted
    # into the source; the 3D camera then contributes the perspective exactly once.
    xy = [(x * image.width, y * image.height) for x, y in quad]
    coords = [value for i in [0, 3, 2, 1] for value in xy[i]]
    result = image.transform((size, size), Image.Transform.QUAD, coords,
                             Image.Resampling.BICUBIC)
    rgba = np.array(result)
    transparent = rgba[:, :, 3] < 240
    if transparent.any() and not transparent.all():
        near = ndimage.distance_transform_edt(transparent, return_distances=False,
                                              return_indices=True)
        rgba[transparent, :3] = rgba[near[0][transparent], near[1][transparent], :3]
    rgba[:, :, 3] = 255  # A solid cube must not show holes at its seams.
    return Image.fromarray(rgba)


def atlas(entries: list[dict], derived: Path, name: str, page_size: int = 2048) -> dict:
    page = Image.new("RGBA", (page_size, page_size))
    x = y = row_height = 0
    variants = []
    for entry in entries:
        image = Image.open(derived / entry["output"]).convert("RGBA")
        image.thumbnail((512, 512), Image.Resampling.LANCZOS)
        border = 8
        w, h = image.width + border * 2, image.height + border * 2
        if x + w > page_size:
            x, y, row_height = 0, y + row_height, 0
        if y + h > page_size:
            raise ValueError(f"Atlas {name} is full; split the detail set")
        # Duplicate edge pixels around each region, including alpha, to prevent
        # adjacent regions leaking at normal mip levels.
        padded = np.pad(np.array(image), ((border, border), (border, border), (0, 0)), mode="edge")
        page.paste(Image.fromarray(padded), (x, y))
        variants.append({
            "id": entry["id"], "name": entry["original_name"].removesuffix(".png"),
            "rect": [x + border, y + border, image.width, image.height],
            "size_m": entry["size_m"], "pivot": [0.5, 1.0] if name == "upright" else [0.5, 0.5],
        })
        x += w
        row_height = max(row_height, h)
    output = f"{name}_atlas.png"
    page.save(derived / output)
    return {"image": output, "size": [page_size, page_size], "variants": variants}


def decoded_name(info) -> str:
    if info.flag_bits & 0x800:
        return info.filename
    raw = info.filename.encode("cp437")
    for encoding in ["utf-8", "gbk"]:
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            pass
    return info.filename


def prepare(project: Path, archives: Path) -> dict:
    source = project / "assets/source_art" / PACK_ID
    derived = project / "assets/derived_art" / PACK_ID
    derived.mkdir(parents=True, exist_ok=True)
    entries = []
    for archive_name, group in PACKS.items():
        with ZipFile(archives / archive_name) as archive:
            for info in archive.infolist():
                original_name = Path(decoded_name(info)).name
                if info.is_dir() or not original_name.lower().endswith(".png"):
                    continue
                stem = Path(original_name).stem
                asset_id = (TERRAIN_NAMES[stem] if group == "terrain" else
                            f"detail_{stem[:2]}" if group == "details" else stem.lower())
                relative = f"{group}/{asset_id}.png"
                original = source / relative
                raw = archive.read(info)
                digest = hashlib.sha256(raw).hexdigest()
                original.parent.mkdir(parents=True, exist_ok=True)
                if original.exists() and hashlib.sha256(original.read_bytes()).hexdigest() != digest:
                    raise ValueError(f"Source collision: {original}")
                if not original.exists():
                    original.write_bytes(raw)
                image = Image.open(io.BytesIO(raw)).convert("RGBA")
                recipe = {"version": 1, "black_threshold": None, "crop": None}
                entry = {"id": asset_id, "group": group, "archive": archive_name,
                         "original_name": original_name, "source": relative,
                         "sha256": digest, "source_size": list(image.size), "recipe": recipe}
                if group == "terrain" and asset_id not in ["grass", "meadow", "earth", "corner_color_reference"]:
                    image = black_to_alpha(image)
                    recipe["black_threshold"] = 8
                if group == "terrain" and asset_id in ["grass", "meadow", "earth"]:
                    image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
                    entry["kind"] = "ground"
                    entry["size_m"] = [8.0, 8.0]
                elif group == "terrain" and asset_id == "corner_color_reference":
                    # A reviewed, bounded colour mask isolates the brown closed
                    # outline; filling it retains the green interior and notch.
                    rgb = np.asarray(image)[:, :, :3].astype(float)
                    brown = (rgb[:, :, 0] > rgb[:, :, 1] * 1.12) & (rgb[:, :, 1] > rgb[:, :, 2] * 1.15)
                    roi = np.zeros(brown.shape, bool)
                    roi[150:825, 65:945] = True
                    labels, _ = ndimage.label(brown & roi)
                    sizes = np.bincount(labels.ravel())
                    sizes[0] = 0
                    mask = ndimage.binary_fill_holes(labels == sizes.argmax())
                    mask_image = Image.fromarray(np.uint8(mask) * 255)
                    (derived / "masks").mkdir(exist_ok=True)
                    mask_image.save(derived / "masks/corner_color_reference.png")
                    image.putalpha(mask_image)
                    recipe["mask"] = "masks/corner_color_reference.png"
                    recipe["mask_recipe"] = {"roi_xyxy": [65, 150, 945, 825],
                                             "r_over_g": 1.12, "g_over_b": 1.15,
                                             "largest_component": True, "fill_holes": True, "dilate": 0}
                    image, recipe["crop"] = trim(image)
                    image.thumbnail((512, 512), Image.Resampling.LANCZOS)
                    entry["kind"] = "reference"
                    entry["note"] = "专用灰度遮罩已剥离彩色构图背景；地形转角使用套件几何，不重复投射整张透视图。"
                elif group == "objects" and "face" in asset_id and not asset_id.startswith("climbing"):
                    quad = face_quad(image)
                    recipe["quad"] = quad
                    image = rectify(image, quad)
                    entry["kind"] = "face"
                    entry["size_m"] = [2.0, 2.0]
                elif group == "objects" and asset_id.startswith("treasurebox"):
                    # Identical crop/scale for both states, preserving their
                    # shared ground contact rather than centring each sprite.
                    recipe["crop"] = [260, 240, 2010, 1730]
                    image = image.crop(tuple(recipe["crop"]))
                    image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
                    entry["kind"] = "state"
                    entry["size_m"] = [1.75, 1.49]
                else:
                    image, box = trim(image)
                    recipe["crop"] = box
                    if group == "details":
                        number = int(asset_id[-2:])
                        entry["kind"] = "upright" if 7 <= number <= 31 else "flat"
                        width = min(2.0, (box[2] - box[0]) / 256)
                        if number >= 32:
                            width *= 0.65
                        entry["size_m"] = [round(width, 4), round(width * image.height / image.width, 4)]
                        image.thumbnail((512, 512), Image.Resampling.LANCZOS)
                    elif group == "objects":
                        entry["kind"] = "wall" if asset_id.startswith("climbing") else "card"
                        height = 4.0 if asset_id.startswith("bigtree") or asset_id == "pillar" else 2.0 if asset_id == "biggrass" else 1.0
                        if entry["kind"] == "wall":
                            entry["size_m"] = [2.0, round(2.0 * image.height / image.width, 4)]
                        else:
                            entry["size_m"] = [round(height * image.width / image.height, 4), height]
                        image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
                    else:
                        entry["kind"] = "cliff" if asset_id == "cliff" else "slope" if asset_id == "slope" else "reference"
                        entry["size_m"] = [4.0, 2.0]
                        image.thumbnail((1024, 512), Image.Resampling.LANCZOS)
                output = f"{group}/{asset_id}.png"
                (derived / group).mkdir(exist_ok=True)
                image.save(derived / output)
                entry.update(output=output, output_size=list(image.size))
                entries.append(entry)
    atlases = {}
    for name in ["flat", "upright"]:
        atlases[name] = atlas([e for e in entries if e["kind"] == name], derived, name)
    modules = prepare_modules(source, derived, entries)
    manifest = {"version": 2, "pack": PACK_ID, "entries": entries, "atlases": atlases, "modules": modules}
    (derived / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    contact_sheets(entries, derived)
    enable_mipmaps(derived)
    return manifest


def enable_mipmaps(derived: Path) -> None:
    """Terrain, details and props are minified in 3D: generate mipmaps and stop
    the editor's 3D auto-detection from silently changing import settings.
    Existing .import files keep their UID; run the editor once to reimport."""
    for image in derived.rglob("*.png"):
        if image.name.startswith("review_") or image.parent.name == "masks":
            continue
        settings = image.with_name(image.name + ".import")
        if not settings.exists():
            continue
        text = settings.read_text()
        patched = text.replace("mipmaps/generate=false", "mipmaps/generate=true") \
            .replace("detect_3d/compress_to=1", "detect_3d/compress_to=0")
        if patched != text:
            settings.write_text(patched)


def grass_fringe(strip: Image.Image) -> tuple[Image.Image, dict]:
    """Cut only the painted hanging grass band (and its outline) out of the cliff.

    The soil behind the band stays transparent, so the strip overlays any wall
    instead of repeating a horizontal brown seam along every edge.
    """
    rgba = np.array(strip)
    c = rgba.astype(int)
    r, g, b, a = c[..., 0], c[..., 1], c[..., 2], c[..., 3]
    ground = int(np.argmax((a > 200).mean(axis=1) > 0.98))
    grass = (a > 128) & (g - b > 40) & (g - r > 15)
    labels, _ = ndimage.label(grass)
    probe = slice(ground + 5, ground + 25)
    band_ids = sorted(set(np.unique(labels[probe][grass[probe]]).tolist()) - {0})
    keep = np.isin(labels, band_ids)
    above = np.zeros_like(keep)
    above[:ground] = True
    keep |= (a > 128) & above
    keep = ndimage.binary_fill_holes(keep)
    dark = (a > 128) & (np.maximum(np.maximum(r, g), b) < 95)
    keep |= ndimage.binary_dilation(keep, iterations=10) & dark
    rows = int(np.where(keep.any(axis=1))[0].max()) + 3
    rgba[..., 3] = np.where(keep, rgba[..., 3], 0)
    recipe = {"grass_rule": "g-b>40 and g-r>15", "ground_row": ground,
              "band_components": len(band_ids), "outline_dilate": 10, "outline_max_rgb": 95,
              "rows": rows}
    return Image.fromarray(rgba[:rows]), recipe


def _wrap_seam(a: np.ndarray, overlap: int) -> np.ndarray:
    """Make rows wrap by stitching the bottom strip onto the top along the
    minimum-difference seam (image quilting); no cross-fade, so line art never
    doubles into ghost outlines."""
    h, w, _ = a.shape
    top, bottom = a[:overlap], a[h - overlap:]
    alpha_top, alpha_bottom = top[..., 3:] / 255.0, bottom[..., 3:] / 255.0
    cost = (((top[..., :3] * alpha_top - bottom[..., :3] * alpha_bottom) ** 2).sum(axis=2)
            + (top[..., 3] - bottom[..., 3]) ** 2)
    acc = cost.copy()
    back = np.zeros(cost.shape, dtype=np.int64)
    rows = np.arange(overlap)
    for x in range(1, w):
        previous = acc[:, x - 1]
        options = np.stack([np.r_[np.inf, previous[:-1]], previous, np.r_[previous[1:], np.inf]])
        choice = options.argmin(axis=0)
        acc[:, x] += options[choice, rows]
        back[:, x] = rows + choice - 1
    seam = np.zeros(w, dtype=np.int64)
    seam[-1] = int(acc[:, -1].argmin())
    for x in range(w - 1, 0, -1):
        seam[x - 1] = back[seam[x], x]
    from_bottom = rows[:, None] < seam[None, :]
    stitched = np.where(from_bottom[..., None], bottom, top)
    return np.concatenate([stitched, a[overlap:h - overlap]], axis=0)


def seamless(image: Image.Image, overlap_x: int, overlap_y: int) -> Image.Image:
    a = np.array(image.convert("RGBA")).astype(np.float64)
    if overlap_y:
        a = _wrap_seam(a, overlap_y)
    if overlap_x:
        a = _wrap_seam(a.transpose(1, 0, 2), overlap_x).transpose(1, 0, 2)
    return Image.fromarray(np.clip(np.rint(a), 0, 255).astype(np.uint8))


CLIFF_PX_PER_M = 256  # Excel 环境模块密度；整条约 7.6m × 2.05m，与 2m 侧壁吻合。


def prepare_modules(source: Path, derived: Path, entries: list[dict]) -> dict:
    # Work from the full-resolution cut-out, not the 1024px preview copy.
    cliff_entry = next(entry for entry in entries if entry["id"] == "cliff")
    strip = black_to_alpha(Image.open(source / cliff_entry["source"]).convert("RGBA"))
    strip = strip.crop(tuple(cliff_entry["recipe"]["crop"]))
    columns = [50, strip.width - 46]
    rim, rim_recipe = grass_fringe(strip.crop((columns[0], 0, columns[1], strip.height)))
    rim = seamless(rim, 200, 0)
    rim.save(derived / "terrain/rim_grass.png")
    # Only the exposed top edge receives the grass fringe. Walls use the rock
    # body under the band, made seamless both ways at its painted proportion,
    # so stacked 2m layers form one continuous cliff without a mid-height cap.
    wall_crop = [columns[0], 182, columns[1], 488]
    body = seamless(strip.crop(tuple(wall_crop)), 200, 48)
    body.save(derived / "terrain/cliff_body.png")
    ppm = CLIFF_PX_PER_M
    ground = rim_recipe["ground_row"]
    front = Image.open(source / "objects/climbingrock_frontface.png").convert("RGBA")
    front = rectify(front, face_quad(front), 512)
    grips_source = Image.open(source / "objects/climbingrock_topface.png").convert("RGBA")
    grips = rectify(grips_source, face_quad(grips_source), 512)
    rgba = np.array(grips)
    # The supplied white paint is the climbing cue; retain its own colour.
    white = rgba[:, :, :3].min(axis=2) > 210
    # Separate the individual white marks from the solid border stripe.
    solid_rows = np.where(white.mean(axis=1) > 0.65)[0]
    cutoff = int(solid_rows[0]) if len(solid_rows) else 430
    white[max(0, cutoff - 6):] = False
    rgba[:, :, 3] = np.uint8(white) * 255
    labels, _ = ndimage.label(white)
    components = sorted(ndimage.find_objects(labels),
                        key=lambda s: (s[0].stop - s[0].start) * (s[1].stop - s[1].start)
                        if s else 0, reverse=True)
    placements = [[100, 85], [310, 115], [200, 200], [345, 285], [80, 310], [235, 410]]
    for i, (x, y) in enumerate(placements):
        region = components[i % min(6, len(components))]
        marks = Image.fromarray(rgba[region]).transpose(Image.Transpose.ROTATE_90)
        marks = marks.resize((65, 25), Image.Resampling.LANCZOS)
        front.alpha_composite(marks, (x, y))
    front.save(derived / "objects/climb_grips.png")
    return {
        "rim_grass": {"source": "terrain/cliff.png", "columns": columns, "cutout": rim_recipe,
                      "seamless_overlap": [200, 0], "px_per_m": ppm,
                      "span_m": round(rim.width / ppm, 4),
                      "rise_m": round(ground / ppm, 4),
                      "drop_m": round((rim.height - ground) / ppm, 4),
                      "output": "terrain/rim_grass.png"},
        "cliff_body": {"source": "terrain/cliff.png", "crop": wall_crop,
                       "seamless_overlap": [200, 48], "px_per_m": ppm,
                       "span_m": [round(body.width / ppm, 4), round(body.height / ppm, 4)],
                       "output": "terrain/cliff_body.png"},
        "climb_grips": {"sources": ["objects/climbingrock_frontface.png", "objects/climbingrock_topface.png"],
                        "white_threshold": 210, "stripe_cutoff": cutoff,
                        "mark_size": [65, 25], "rotate": 90,
                        "placements": placements, "output": "objects/climb_grips.png"},
    }


def contact_sheets(entries: list[dict], directory: Path) -> None:
    for group in PACKS.values():
        items = [entry for entry in entries if entry["group"] == group]
        width, height, columns = 220, 210, 5
        sheet = Image.new("RGB", (width * columns, height * ((len(items) + columns - 1) // columns)), "#303239")
        draw = ImageDraw.Draw(sheet)
        for i, entry in enumerate(items):
            x, y = (i % columns) * width, (i // columns) * height
            for cy in range(0, height - 30, 12):
                for cx in range(0, width - 8, 12):
                    colour = "#b8b8b8" if (cx // 12 + cy // 12) % 2 else "#e8e8e8"
                    draw.rectangle((x + cx, y + cy, x + cx + 11, y + cy + 11), fill=colour)
            image = Image.open(directory / entry["output"]).convert("RGBA")
            image.thumbnail((width - 16, height - 45), Image.Resampling.LANCZOS)
            sheet.paste(image, (x + (width - image.width) // 2, y + 4), image)
            draw.text((x + 4, y + height - 24), entry["id"], fill="white")
        sheet.save(directory / f"review_{group}.png")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--archives", type=Path)
    args = parser.parse_args()
    result = prepare(args.project, args.archives or args.project.parent)
    print(f"Prepared {len(result['entries'])} images and {len(result['atlases'])} atlases.")
