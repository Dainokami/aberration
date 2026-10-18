"""Import the 15 JPEG layers in 肢体-呸呸.zip and make transparent game icons.

Usage: python scripts/import_limb_art_peipei.py PATH_TO_ZIP

The ZIP stores GBK filenames without a reliable encoding flag. Read the raw
local-header names so the mapping stays reproducible across ZIP readers.
"""

from __future__ import annotations

import hashlib
import io
import json
import struct
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source_art/limbs_peipei_20261018"
DERIVED = ROOT / "assets/derived_art/limbs_peipei_20261018"

# The role names describe source layers, not new part IDs or abilities.
FILES = {
    "大鹅翅膀/181ca38d8d523fa2a724e2e8dc73b255.jpg": ("goose_wing", "primary"),
    "大鹅翅膀/b87682345ab721640c88689df61fbc35.jpg": ("goose_wing", "feather"),
    "大鹅脚蹼/2ee5c96ad39509fce563db58c69ddf7c.jpg": ("goose_foot", "primary"),
    "大鹅脚蹼/40ffa74896a1bc3450bc03894094739a.jpg": ("goose_foot", "other_foot"),
    "大鹅脚蹼/f9d57feb86a8046f9287aba4f1f540a0.jpg": ("goose_foot", "body_layer"),
    "犬/051f0a2e613b51ff95acc6f87dd7152a.jpg": ("demon_dog_leg", "full_body_primary"),
    "犬/5b203fe34ec86f87304e2ba03f21cd95.jpg": ("demon_dog_leg", "full_body_alternate"),
    "猩猩/88c22bbfeea87533e1e6b41b9bf7217a.jpg": ("gorilla_arm", "hand"),
    "猩猩/d29b6591e686d9f7f525458b9ba2a354.jpg": ("gorilla_arm", "primary"),
    "猩猩白化/1822eab4bd8d1f505f71827b42c44361.jpg": ("gorilla_arm", "white_hand"),
    "猩猩白化/f896b92ec07fbbee006c2e164ee4e2df.jpg": ("gorilla_arm", "white_primary"),
    "章鱼/ac7872874951355cfa8728b164b41b0a.jpg": ("octopus_tentacle", "primary"),
    "章鱼/f6257436057765ff8966edfab8d94be9.jpg": ("octopus_tentacle", "alternate"),
    "章鱼白化/0cb2ca28b1d31dcb11763bb1dcf8e000.jpg": ("octopus_tentacle", "white_alternate"),
    "章鱼白化/81db7d39d6d78d7063b2a4361b5fe1f7.jpg": ("octopus_tentacle", "white_primary"),
}


def original_name(archive_file: io.BufferedReader, entry: zipfile.ZipInfo) -> str:
    archive_file.seek(entry.header_offset)
    header = archive_file.read(30)
    if len(header) != 30 or header[:4] != b"PK\x03\x04":
        raise ValueError("Invalid ZIP local header")
    name_length, _ = struct.unpack_from("<HH", header, 26)
    return archive_file.read(name_length).decode("gbk")


def cutout(jpeg: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(jpeg)).convert("RGB")
    rgb = np.asarray(image)
    # Only the near-white area connected to the canvas edge is background.
    # This keeps white feathers and the white gorilla arm inside their outlines.
    near_white = np.all(rgb >= 245, axis=2)
    region = Image.fromarray(np.where(near_white, 255, 0).astype("uint8"), "L").copy()
    ImageDraw.floodfill(region, (0, 0), 128, thresh=0)
    background = np.asarray(region) == 128
    alpha = np.where(background, 0, 255).astype("uint8")

    # Feather only the first foreground pixel next to the removed white matte.
    beside = np.zeros_like(background)
    beside[1:] |= background[:-1]
    beside[:-1] |= background[1:]
    beside[:, 1:] |= background[:, :-1]
    beside[:, :-1] |= background[:, 1:]
    edge = beside & ~background
    lightness = np.min(rgb, axis=2).astype("int16")
    alpha[edge] = np.minimum(255, (255 - lightness[edge]) * 5).astype("uint8")

    ys, xs = np.where(alpha > 0)
    if len(xs) == 0:
        raise ValueError("No artwork found in JPEG")
    box = (max(0, int(xs.min()) - 8), max(0, int(ys.min()) - 8),
           min(image.width, int(xs.max()) + 9), min(image.height, int(ys.max()) + 9))
    rgba = image.convert("RGBA")
    rgba.putalpha(Image.fromarray(alpha, "L"))
    return rgba.crop(box)


def save_unchanged(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.read_bytes() != content:
            raise ValueError(f"Refusing to overwrite changed art: {path}")
        return
    path.write_bytes(content)


def main(archive: Path) -> None:
    rows = []
    seen = set()
    with zipfile.ZipFile(archive) as zf, archive.open("rb") as raw:
        for entry in zf.infolist():
            if entry.is_dir():
                continue
            name = original_name(raw, entry)
            if name not in FILES or name in seen:
                raise ValueError(f"Unexpected or duplicate ZIP entry: {name}")
            seen.add(name)
            category, role = FILES[name]
            content = zf.read(entry)
            source = SOURCE / category / f"{role}.jpg"
            derived = DERIVED / category / f"{role}.png"
            cutout_image = cutout(content)
            output = io.BytesIO()
            cutout_image.save(output, format="PNG")
            save_unchanged(source, content)
            save_unchanged(derived, output.getvalue())
            rows.append({
                "archive": archive.name,
                "original_entry": name,
                "source": "res://" + source.relative_to(ROOT).as_posix(),
                "cutout": "res://" + derived.relative_to(ROOT).as_posix(),
                "sha256": hashlib.sha256(content).hexdigest(),
                "bytes": len(content),
                "cutout_size": list(cutout_image.size),
            })
    if seen != FILES.keys():
        raise ValueError(f"Expected {len(FILES)} JPEGs, found {len(seen)}")
    (SOURCE / "source_trace.json").write_text(
        json.dumps({"files": rows}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Imported {len(rows)} JPEGs and cutouts")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(Path(sys.argv[1]))
