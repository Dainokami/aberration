"""Read-only source import. Explicit mapping was checked against six user images."""
import hashlib
import json
import shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "assets/source_art/scene_pack_20261016"
DERIVED = ROOT / "assets/derived_art/scene_pack_20261016"
NAMES = {"ocean": "海洋", "desert": "沙漠", "grass": "草原", "rock": "岩石"}
KINDS = {"remains": ("散落遗骸", 18), "chest": ("遗落宝箱", 21),
         "thorns": ("刺棘丛", 11), "fruit_tree": ("垂蔓果树", 12),
         "bubbles": ("浮升气泡柱", 17), "quicksand": ("卷吸流沙", 10),
         "vine": ("悬崖垂藤", 13), "resource": ("自然资源簇", 19)}

def main():
    PACK.mkdir(parents=True, exist_ok=True)
    DERIVED.mkdir(parents=True, exist_ok=True)
    entries = []
    mapping = {}
    for serial, eco in zip(range(1534, 1538), ["ocean", "desert", "grass", "rock"]):
        mapping[serial] = ("remains", [eco], [1, 1], "")
    for serial, eco in zip(range(1538, 1542), ["grass", "desert", "rock", "ocean"]):
        mapping[serial] = ("chest", [eco], [1, 1], "")
    for serial, eco in zip(range(1542, 1546), ["desert", "grass", "rock", "ocean"]):
        mapping[serial] = ("remains", [eco], [2, 2], "")
    for serial, eco in zip(range(1546, 1550), ["rock", "ocean", "desert", "grass"]):
        mapping[serial] = ("remains", [eco], [2, 1], "")
    mapping.update({1550: ("thorns", ["grass"], [1, 1], "用户图三"),
                    1551: ("thorns", ["grass"], [2, 2], "用户图一"),
                    1552: ("thorns", ["grass"], [3, 1], "用户图二"),
                    1553: ("fruit_tree", ["grass"], [2, 2], "用户图四，4格视图"),
                    1554: ("fruit_tree", ["grass"], [2, 2], "用户图六，3格视图"),
                    1555: ("fruit_tree", ["grass"], [2, 2], "用户图五，4格视图")})
    for path in sorted((ROOT.parent / "场景素材").glob("*.png")):
        serial = int(path.stem.split("_")[-2])
        kind, ecosystems, layout, view = mapping[serial]
        entries.append(make_entry(path, kind, ecosystems, layout, str(serial), view))
    leaf = ROOT.parent / "场景物件美术资产_叶子"
    for path in sorted(leaf.glob("*.png")):
        prefix, layout_name = path.stem.rsplit("_", 1)
        kind, ecosystems = {
            "fushengqipaozhu": ("bubbles", ["ocean"]),
            "juanxiliusha": ("quicksand", ["desert"]),
            "xuanyachuiteng": ("vine", ["grass", "rock"]),
            "ziranziyuancu": ("resource", ["rock", "ocean"]),
        }[prefix]
        layout = list(map(int, layout_name.split("x")))
        entries.append(make_entry(path, kind, ecosystems, layout, layout_name,
                                  "竖向画布；地面布局1×3" if kind == "bubbles" and layout_name == "1x3" else ""))
    assert len(entries) == 31
    manifest = {"pack": "scene_pack_20261016", "spec": "畸变_场景机制设计.xlsx",
                "grid_m": 2, "pixels_per_grid": 256, "entries": entries,
                "parameter_note": "减速、伤害、吸附、氧气恢复数值在原表未量化，使用可调默认值。"}
    (DERIVED / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print("Imported 31 PNGs with original SHA-256 and explicit classification.")

def make_entry(path, kind, ecosystems, layout, variant, view):
    asset_id = f"scene1016_{kind}_{variant}"
    if kind in ["bubbles", "quicksand", "vine", "resource"]:
        asset_id = f"scene1016_{kind}_{variant}"
    raw = PACK / (asset_id + ".png")
    shutil.copyfile(path, raw)
    image = Image.open(path).convert("RGBA")
    original_size = list(image.size)
    if kind == "fruit_tree":
        image = image.resize((512, 512), Image.Resampling.LANCZOS)
    output = DERIVED / (asset_id + ".png")
    image.save(output)
    bbox = image.getchannel("A").getbbox()
    spatial = [[x * 2, 0, z * 2] for z in range(layout[1]) for x in range(layout[0])]
    if kind == "fruit_tree":
        spatial = [[0, 0, 0], [2, 0, 0], [2, 0, 2]]
    label, row = KINDS[kind]
    return {"id": asset_id, "source_directory": path.parent.name, "source_file": path.name,
            "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "original": "res://" + str(raw.relative_to(ROOT)),
            "image": "res://" + str(output.relative_to(ROOT)),
            "original_pixels": original_size, "output_pixels": list(image.size),
            "image_size_m": [image.width / 128, image.height / 128],
            "pivot": [0.5, bbox[3] / image.height],
            "kind": kind, "category": label, "ecosystems": ecosystems, "layout": layout,
            "display_name": label + "·" + "/".join(NAMES[e] for e in ecosystems) + "·" + variant,
            "spec_row": row, "view": view, "spatial_cells_m": spatial,
            "cell_size_m": [2, image.height / 128 if kind == "bubbles" else 2, 2],
            "requires_seabed": ecosystems == ["ocean"],
            "solid_collision": kind == "fruit_tree",
            "parameters": {"speed_multiplier": 0.5, "damage_per_second": 1.0} if kind == "thorns"
            else {"pull_speed_mps": 1.0} if kind == "quicksand"
            else {"rise_speed_mps": 1.5, "oxygen_per_second": 10.0} if kind == "bubbles" else {}}

if __name__ == "__main__":
    main()
