"""Import the supplied mechanical art and strips; preserve every input byte.

Usage: python3 scripts/import_mechanical_monsters.py ART_DIR ANIMATION_PACKAGE
Requires Pillow, NumPy and SciPy. Does not edit gameplay definitions or old art.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source_art/mechanical_monsters_20261020"
STATIC = ROOT / "assets/derived_art/mechanical_monsters_20261020"
ANIMATION = ROOT / "assets/animations/mechanical_monsters_20261019"
NAMES = {"wolf": "狼", "gerbil": "沙鼠", "gibbon": "长臂猿", "gorilla": "猩猩",
         "ostrich": "鸵鸟", "eagle": "老鹰", "albatross": "信天翁"}


def res(path):
    return "res://" + path.relative_to(ROOT).as_posix()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cutout(image, checker=False):
    rgb = np.array(image.convert("RGB"), dtype=np.int16)
    darkest = rgb.min(axis=2)
    chroma = rgb.max(axis=2) - darkest
    # Eagle is an opaque screenshot of a checkerboard. Select neutral paper
    # connected to the border, keeping the bird's enclosed white metal panels.
    paper = ((darkest > 115) & (chroma < 20)) if checker else (darkest > 235)
    border = np.zeros(paper.shape, dtype=bool)
    border[[0, -1], :] = paper[[0, -1], :]
    border[:, [0, -1]] = paper[:, [0, -1]]
    outside = ndimage.binary_propagation(border, mask=paper)
    solid = ~outside
    # Large enclosed pure-white spaces between limbs/tail are also paper.
    labels, count = ndimage.label(paper & solid)
    for label, region in enumerate(ndimage.find_objects(labels), 1):
        if region is None:
            continue
        area = labels[region] == label
        if area.sum() > 1400 and rgb[region][area].mean(axis=0).min() > 242:
            solid[region][area] = False
    labels, count = ndimage.label(solid)
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    solid = labels == sizes.argmax()
    alpha = Image.fromarray(np.uint8(solid) * 255)
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(.45))
    result = image.convert("RGBA")
    result.putalpha(alpha)
    box = alpha.getbbox()
    if box is None:
        raise ValueError("Empty artwork")
    return result.crop(box), box


def sprite_frames(monster, spec):
    lines = ['[gd_resource type="SpriteFrames" load_steps=28 format=3]']
    states = ("walk", "attack", "death")
    for state in states:
        lines.append(f'[ext_resource type="Texture2D" path="{res(ANIMATION / monster / (state + ".png"))}" id="{state}"]')
    for state in states:
        for index in range(8):
            lines.extend([
                f'[sub_resource type="AtlasTexture" id="{state}_{index}"]',
                f'atlas = ExtResource("{state}")',
                f'region = Rect2({index * 384}, 0, 384, 384)',
                'filter_clip = true',
            ])
    lines += ['[resource]', 'animations = [']
    for state in states:
        frames = ', '.join('{"duration": 1.0, "texture": SubResource("%s_%d")}' % (state, i) for i in range(8))
        lines.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %.1f},'
                     % (frames, str(state == "walk").lower(), state, spec["fps"][state]))
    lines.append(']')
    (ANIMATION / monster / "frames.tres").write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("art", type=Path)
    parser.add_argument("package", type=Path)
    args = parser.parse_args()
    for folder in (SOURCE, STATIC, ANIMATION):
        folder.mkdir(parents=True, exist_ok=True)
    package_anim = args.package / "assets/animations/mechanical_monsters_20261019"
    manifest = json.loads((package_anim / "manifest.json").read_text())
    specs = {item["id"]: item for item in manifest["monsters"]}
    assert set(specs) == set(NAMES) - {"wolf"}
    trace = {"version": 1, "static_source": args.art.name,
             "animation_source": args.package.name, "assets": {}}
    for monster, name in NAMES.items():
        source = args.art / name / (name + "-整体.jpg")
        copy = SOURCE / (monster + ".jpg")
        shutil.copyfile(source, copy)
        image, box = cutout(Image.open(copy), checker=monster == "eagle")
        image.save(STATIC / (monster + ".png"))
        item = {"source": res(copy), "source_sha256": sha(source), "crop": box,
                "static": res(STATIC / (monster + ".png")),
                "static_sha256": sha(STATIC / (monster + ".png")),
                "faces_left": monster != "eagle", "animations": {}}
        if monster in specs:
            spec = specs[monster]
            dest = ANIMATION / monster
            dest.mkdir(exist_ok=True)
            for state in ("walk", "attack", "death"):
                original = package_anim / monster / (state + ".png")
                target = dest / original.name
                strip = Image.open(original)
                assert strip.mode == "RGBA" and strip.size == (3072, 384)
                if state == "death":
                    assert strip.crop((2688, 0, 3072, 384)).getbbox() is None
                shutil.copyfile(original, target)
                item["animations"][state] = {"path": res(target), "sha256": sha(target)}
            sprite_frames(monster, spec)
            walk = Image.open(dest / "walk.png")
            heights = []
            for i in range(8):
                bounds = walk.crop((i * 384, 0, (i + 1) * 384, 384)).getbbox()
                heights.append(bounds[3] - bounds[1])
            item["animation_height_pixels"] = max(heights)
            item["animation_anchor_y"] = 304 if spec["air"] else 365
        trace["assets"][monster] = item
        print(monster, image.size, item.get("animation_height_pixels", "static"))
    # Preserve the package's provenance and reproducible source separately.
    shutil.copytree(args.package / "assets/source_art/mechanical_monsters_20261019",
                    ROOT / "assets/source_art/mechanical_monsters_20261019", dirs_exist_ok=True)
    for name in ("manifest.json", "README.md"):
        shutil.copyfile(package_anim / name, ANIMATION / name)
    shutil.copyfile(args.package / "scripts/build_mechanical_monster_animations.py",
                    ROOT / "scripts/build_mechanical_monster_animations.py")
    (STATIC / "manifest.json").write_text(json.dumps(trace, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
