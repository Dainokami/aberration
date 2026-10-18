"""Import supplied monster art without changing source archives."""
from io import BytesIO
from pathlib import Path
import hashlib
import json
import sys
import zipfile

import numpy as np
from PIL import Image
from scipy import ndimage
from psd_tools import PSDImage

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source_art/monsters_20261018"
DEST = ROOT / "assets/derived_art/monsters_20261018"
PSD_MAP = {"zhangyu": "octopus", "bianfu": "bat", "emoquan": "demon_dog",
           "e": "goose", "daishu1": "kangaroo", "daishu2": "kangaroo_front"}
FOLDERS = {"沙鼠": "gerbil", "狼": "wolf", "猩猩-侧": "gorilla",
           "猩猩-正": "gorilla_front", "长臂猿": "gibbon", "鸵鸟": "ostrich"}
COMPOSITES = {"gerbil": "511ec7", "gorilla": "fb587e", "gorilla_front": "4f6831",
              "gibbon": "6252dc", "ostrich": "0db685"}
CATALOG = [
    ("wolf", "荒原狼", ["grass"], "land", True, False, "pounce", 40, 14, 5.6, .62, 3),
    ("ostrich", "鸵鸟", ["desert"], "land", False, False, "peck", 40, 14, 8.4, 1.15, 4),
    ("gerbil", "沙鼠", ["desert"], "land", False, True, "bite", 20, 8, 8.4, 1.15, 5),
    ("gibbon", "长臂猿", ["grass", "rock"], "land", False, False, "stone", 40, 14, 8.4, .34, 7),
    ("gorilla", "猩猩", ["rock"], "land", True, False, "swing", 80, 22, 5.6, .62, 8),
    ("kangaroo", "袋鼠", ["grass"], "land", False, False, "kick", 40, 14, 5.6, .62, 10),
    ("demon_dog", "恶魔犬", ["grass"], "land", True, True, "bite", 20, 8, 5.6, .34, 11),
    ("goose", "鹅", ["grass", "ocean"], "amphibious", True, False, "swing", 20, 8, 5.6, .62, 12),
    ("octopus", "章鱼", ["grass", "ocean"], "amphibious", False, False, "tentacle", 40, 14, 5.6, .62, 14),
    ("bat", "蝙蝠", ["rock"], "air", True, True, "bite", 20, 8, 5.6, .62, 19),
    ("albatross", "信天翁", ["rock"], "air", False, False, "peck", 40, 14, 5.6, .62, 20),
    ("eagle", "老鹰", ["desert"], "air", False, False, "peck", 40, 22, 8.4, .62, 22),
    ("piranha", "食人鱼", ["ocean"], "aquatic", True, True, "bite", 40, 8, 5.6, .62, 25),
    ("water_snake", "水蛇", ["ocean"], "aquatic", True, False, "bite", 40, 14, 5.6, .62, 26),
]

def decoded(info):
    if info.flag_bits & 0x800:
        return info.filename
    raw = info.filename.encode("cp437")
    for encoding in ("utf-8", "gb18030"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            pass
    return info.filename

def clean(im):
    rgba = np.array(im.convert("RGBA"))
    if im.mode != "RGBA":
        mask = (rgba[:, :, :3].min(axis=2) > 235)
        seeds = np.zeros(mask.shape, dtype=bool)
        seeds[[0, -1], :] = mask[[0, -1], :]
        seeds[:, [0, -1]] = mask[:, [0, -1]]
        outside = ndimage.binary_propagation(seeds, mask=mask)
        rgba[outside, 3] = 0
    return Image.fromarray(rgba)

def res(path):
    return "res://" + path.relative_to(ROOT).as_posix()

def trace_record(archive, member, payload, copied):
    return {"archive": archive, "member": member,
            "sha256": hashlib.sha256(payload).hexdigest(), "copied_path": res(copied)}

def export(monster, composite, layers, origin):
    folder = DEST / monster
    folder.mkdir(parents=True)
    box = composite.getchannel("A").getbbox()
    if box is None:
        raise ValueError("empty artwork " + monster)
    composite.crop(box).save(folder / "composite.png")
    parts = []
    for index, (label, layer) in enumerate(layers):
        cropped = layer.crop(box)
        if cropped.getchannel("A").getbbox() is None:
            continue
        path = folder / f"part_{index:02d}.png"
        cropped.save(path)
        parts.append({"path": res(path), "name": label, "order": index})
    return {"image": res(folder / "composite.png"), "parts": parts,
            "canvas": list(composite.size), "crop": list(box), "source": origin}

def main():
    if DEST.exists() or SOURCE.exists():
        raise SystemExit("Import destination exists; refusing to overwrite.")
    source_base = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent
    SOURCE.mkdir(parents=True)
    DEST.mkdir(parents=True)
    manifest = {"version": 1, "archives": {}, "assets": {}}
    for archive_name in ("小怪.zip", "怪物角色肢体-呸呸.zip"):
        archive_path = source_base / archive_name
        manifest["archives"][archive_name] = hashlib.sha256(archive_path.read_bytes()).hexdigest()
        with zipfile.ZipFile(archive_path) as archive:
            images = {}
            image_sources = {}
            for entry in archive.infolist():
                if entry.is_dir() or entry.filename.startswith("__MACOSX/"):
                    continue
                member = decoded(entry)
                payload = archive.read(entry)
                stem = Path(member).stem
                if member.endswith(".psd"):
                    monster = PSD_MAP[stem]
                    copied = SOURCE / (stem + ".psd")
                    copied.write_bytes(payload)
                    psd = PSDImage.open(BytesIO(payload))
                    layers = []
                    for group in psd:
                        if not group.visible or not group.is_group():
                            continue
                        for layer in group:
                            if layer.visible:
                                canvas = Image.new("RGBA", psd.size)
                                raw = layer.topil()
                                if raw is not None:
                                    canvas.alpha_composite(raw.convert("RGBA"), (layer.left, layer.top))
                                    layers.append((layer.name, canvas))
                    composite = Image.new("RGBA", psd.size)
                    for _, layer in layers:
                        composite.alpha_composite(layer)
                    # Compare exported layers against the flattened source preview.
                    reference = Image.open(BytesIO(payload)).convert("RGBA")
                    error = float(np.abs(np.array(composite).astype(float) -
                                         np.array(reference).astype(float)).mean())
                    manifest["assets"][monster] = export(monster, composite, layers, member)
                    manifest["assets"][monster]["composite_mean_error"] = error
                    manifest["assets"][monster]["source_members"] = [
                        trace_record(archive_name, member, payload, copied)]
                else:
                    folder = member.split("/")[-2]
                    monster = FOLDERS[folder]
                    target = SOURCE / monster
                    target.mkdir(exist_ok=True)
                    filename = stem if stem.isascii() else "part_" + hashlib.sha256(payload).hexdigest()[:12]
                    copied = target / (filename + Path(member).suffix)
                    copied.write_bytes(payload)
                    images.setdefault(monster, []).append((stem, clean(Image.open(BytesIO(payload)))))
                    image_sources.setdefault(monster, []).append(
                        trace_record(archive_name, member, payload, copied))
            for monster, entries in images.items():
                if monster == "wolf":
                    layers = entries
                    composite = Image.new("RGBA", entries[0][1].size)
                    for _, layer in layers:
                        composite.alpha_composite(layer)
                else:
                    prefix = COMPOSITES[monster]
                    composite = next(im for stem, im in entries if stem.startswith(prefix))
                    layers = []  # Alternate art is preserved, not guessed as animation frames.
                manifest["assets"][monster] = export(monster, composite, layers, monster)
                manifest["assets"][monster]["source_members"] = image_sources[monster]
    for monster, art in manifest["assets"].items():
        art["contact"] = [0.5, 1.0]
        art["image_height_m"] = 1.1 if monster in ["gerbil", "bat", "demon_dog"] else 1.8
        art["background_processing"] = "border-connected white removal for opaque images only"
    (DEST / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    catalog_dir = ROOT / "data/monsters"
    catalog_dir.mkdir(exist_ok=True)
    for monster, name, eco, movement, aggressive, group, attack, hp, damage, speed, interval, row in CATALOG:
        art = manifest["assets"].get(monster, {})
        value = ['[gd_resource type="Resource" script_class="MonsterDefinition" format=3]',
                 '[ext_resource type="Script" path="res://scripts/encounters/monster_definition.gd" id="1"]',
                 '[resource]', 'script = ExtResource("1")',
                 f'monster_id = "{monster}"', f'display_name = "{name}"',
                 f'ecosystems = PackedStringArray({", ".join(json.dumps(x) for x in eco)})',
                 f'movement = "{movement}"', f'source_aggressive = {str(aggressive).lower()}',
                 f'group_living = {str(group).lower()}', f'attack = "{attack}"',
                 f'max_health = {float(hp)}', f'damage = {float(damage)}', f'speed = {speed}',
                 f'attack_interval = {interval}', f'source_row = {row}',
                 f'image_height = {1.1 if monster in ["gerbil", "bat", "demon_dog"] else 1.8}',
                 f'drops = PackedStringArray("{monster}_limb")',
                 'source_manifest = "res://assets/derived_art/monsters_20261018/manifest.json"']
        if art:
            value.append('image_path = "' + art["image"] + '"')
            part_text = ["{\n" + ",\n".join(f'"{k}": {json.dumps(v, ensure_ascii=False)}'
                         for k, v in part.items()) + "\n}" for part in art["parts"]]
            value.append("parts = Array[Dictionary]([" + ", ".join(part_text) + "])")
        if monster == "gibbon":
            value.append("attack_reach = 6.0")
        (catalog_dir / (monster + ".tres")).write_text("\n".join(value) + "\n")
    print("Imported", len(manifest["assets"]), "views; catalog", len(CATALOG))
    print({k: v.get("composite_mean_error") for k, v in manifest["assets"].items()})

if __name__ == "__main__":
    main()
