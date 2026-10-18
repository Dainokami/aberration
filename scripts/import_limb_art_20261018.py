"""Copy the two 2026-10-18 limb handoffs without changing their PNG bytes.

Usage: python scripts/import_limb_art_20261018.py MONSTER_ZIP UPPER_ZIP
"""

from __future__ import annotations

import hashlib
import json
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "source_art" / "limbs_20261018"

# Archive 1 was made on macOS with UTF-8 entry names but without the UTF-8 ZIP flag.
# The numbers in the original names have no semantic meaning; these correspondences
# were checked against the transparent layers and assembled examples.
MONSTER_FILES = {
    "未命名作品 2.PNG": "ostrich_leg/preview.png",
    "未命名作品 3.PNG": "gerbil_leg/feet.png",
    "未命名作品 4.PNG": "gerbil_leg/preview.png",
    "未命名作品 5.PNG": "kangaroo_leg/body.png",
    "未命名作品 6.PNG": "kangaroo_leg/preview.png",
    "未命名作品-1 2.PNG": "wolf_leg/feet.png",
    "未命名作品-1 3.PNG": "ostrich_leg/body.png",
    "未命名作品-1 4.PNG": "ostrich_leg/feet.png",
    "未命名作品-1 5.PNG": "gerbil_leg/body.png",
    "未命名作品-1 6.PNG": "kangaroo_leg/tail.png",
    "未命名作品-1 7.PNG": "kangaroo_leg/forelimbs.png",
    "未命名作品-1.PNG": "wolf_leg/body.png",
    "未命名作品-2.PNG": "kangaroo_leg/feet.png",
    "未命名作品.PNG": "wolf_leg/preview.png",
}

OTHER_FILES = {
    "bianfu": ("bat_wing", "primary"),
    "chuanshanjia": ("pangolin_claw_unmapped", "primary"),
    "laoying": ("eagle_wing", "primary"),
    "laoying_white": ("eagle_wing", "white"),
    "shiren_yu": ("fish_tail", "primary"),
    "xintianweng": ("albatross_wing", "primary"),
    "xintianweng_white": ("albatross_wing", "white"),
}


def copy_entries(archive: Path, kind: str) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    seen: set[str] = set()
    with zipfile.ZipFile(archive) as zf:
        for entry in zf.infolist():
            if entry.is_dir() or not entry.filename.lower().endswith(".png"):
                continue
            if "__MACOSX" in entry.filename or entry.filename.split("/")[-1].startswith("._"):
                continue
            original = entry.filename.encode("cp437").decode("utf-8" if kind == "monster" else "gbk")
            basename = original.split("/")[-1]
            if kind == "monster":
                rel = MONSTER_FILES.get(basename)
            else:
                stem = basename.removesuffix(".png").removesuffix(".PNG")
                preview = stem.endswith(" preview")
                stem = stem.removesuffix(" preview")
                mapped = OTHER_FILES.get(stem)
                rel = f"{mapped[0]}/{mapped[1] + '_preview' if preview and mapped[1] != 'primary' else 'preview' if preview else mapped[1]}.png" if mapped else None
            if rel is None:
                raise ValueError(f"Unmapped PNG in {archive.name}: {original}")
            if rel in seen:
                raise ValueError(f"Duplicate destination: {rel}")
            seen.add(rel)
            content = zf.read(entry)
            dest = OUT / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.exists() and dest.read_bytes() != content:
                raise ValueError(f"Refusing to overwrite changed source art: {dest}")
            dest.write_bytes(content)
            rows.append({
                "archive": archive.name,
                "original_entry": original,
                "asset": "res://assets/source_art/limbs_20261018/" + rel,
                "sha256": hashlib.sha256(content).hexdigest(),
                "bytes": len(content),
            })
    expected = 14
    if len(rows) != expected:
        raise ValueError(f"Expected {expected} usable PNGs in {archive}, got {len(rows)}")
    return rows


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    rows = copy_entries(Path(sys.argv[1]), "monster") + copy_entries(Path(sys.argv[2]), "other")
    (OUT / "source_trace.json").write_text(
        json.dumps({"files": rows}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Copied {len(rows)} original PNGs to {OUT}")


if __name__ == "__main__":
    main()
