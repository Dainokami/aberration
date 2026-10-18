"""Write traceability for the existing import, validating each copied source."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source_art/monsters_20261018"
DEST = ROOT / "assets/derived_art/monsters_20261018"
PSD = {"zhangyu":"octopus","bianfu":"bat","emoquan":"demon_dog","e":"goose",
       "daishu1":"kangaroo","daishu2":"kangaroo_front"}
FOLDERS = {"沙鼠":"gerbil","狼":"wolf","猩猩-侧":"gorilla","猩猩-正":"gorilla_front",
           "长臂猿":"gibbon","鸵鸟":"ostrich"}

def sha(payload):
    return hashlib.sha256(payload).hexdigest()

def decoded(info):
    if info.flag_bits & 0x800:
        return info.filename
    raw = info.filename.encode("cp437")
    for encoding in ("utf-8","gb18030"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            pass
    return info.filename

def main():
    manifest = json.loads((DEST / "manifest.json").read_text())
    result = {"version":1, "archives":manifest["archives"], "source_members":[],
              "derived_assets":{}}
    for archive_name, wanted in manifest["archives"].items():
        archive_path = ROOT.parent / archive_name
        assert sha(archive_path.read_bytes()) == wanted, archive_name
        with zipfile.ZipFile(archive_path) as archive:
            for entry in archive.infolist():
                if entry.is_dir() or entry.filename.startswith("__MACOSX/"):
                    continue
                member = decoded(entry)
                payload = archive.read(entry)
                stem = Path(member).stem
                if member.endswith(".psd"):
                    monster = PSD[stem]
                    copied = SOURCE / (stem + ".psd")
                else:
                    monster = FOLDERS[member.split("/")[-2]]
                    name = stem if stem.isascii() else "part_" + sha(payload)[:12]
                    copied = SOURCE / monster / (name + Path(member).suffix)
                assert sha(copied.read_bytes()) == sha(payload), member
                result["source_members"].append({"monster_id":monster, "archive":archive_name,
                    "member":member, "sha256":sha(payload),
                    "copied_path":"res://" + copied.relative_to(ROOT).as_posix(),
                    "copy_verified":True})
    for monster, asset in manifest["assets"].items():
        paths = [asset["image"]] + [part["path"] for part in asset["parts"]]
        result["derived_assets"][monster] = {"canvas":asset["canvas"],
            "crop":asset["crop"], "contact":[0.5,1.0],
            "image_height_m":1.1 if monster in ["gerbil","bat","demon_dog"] else 1.8,
            "files":{path:sha((ROOT/path.removeprefix("res://")).read_bytes()) for path in paths}}
    (DEST / "source_trace.json").write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print("Verified",len(result["source_members"]),"original members and",
          len(result["derived_assets"]),"derived views")

if __name__ == "__main__":
    main()
