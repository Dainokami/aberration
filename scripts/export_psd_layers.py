from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont
from psd_tools import PSDImage


def safe_name(index, layer):
    return f"{index:02d}_{layer.kind}_{layer.bbox[0]}_{layer.bbox[1]}_{layer.bbox[2]}_{layer.bbox[3]}"


def flatten(layer):
    try:
        return layer.composite(force=True)
    except TypeError:
        return layer.composite()


source = Path(sys.argv[1])
destination = Path(sys.argv[2])
destination.mkdir(parents=True, exist_ok=True)
psd = PSDImage.open(source)

psd.composite().save(destination / "full_composite.png")
manifest = [f"canvas={psd.size}"]
images = []


def visit(layer, path):
    index = "_".join(str(i) for i in path)
    name = safe_name(int(path[-1]), layer)
    try:
        image = flatten(layer)
        if image is not None and image.width and image.height:
            out = destination / f"layer_{index}_{name}.png"
            image.save(out)
            images.append((out, path, layer.name, layer.visible, layer.bbox))
            manifest.append(f"{index}\t{layer.kind}\t{layer.visible}\t{layer.bbox}\t{layer.name!r}\t{out.name}")
    except Exception as exc:
        manifest.append(f"{index}\tERROR\t{exc!r}\t{layer.name!r}")
    if hasattr(layer, "__iter__"):
        for child_index, child in enumerate(layer):
            visit(child, path + [child_index])


for top_index, top in enumerate(psd):
    visit(top, [top_index])

(destination / "manifest.tsv").write_text("\n".join(manifest), encoding="utf-8")

# Contact sheet uses the full canvas so the original placement is visible.
thumbs = []
for out, path, name, visible, bbox in images:
    image = Image.open(out).convert("RGBA")
    image.thumbnail((256, 256), Image.Resampling.LANCZOS)
    tile = Image.new("RGB", (300, 310), "white")
    tile.paste(image, ((300 - image.width) // 2, 8), image)
    draw = ImageDraw.Draw(tile)
    draw.text((8, 270), f"{'.'.join(map(str, path))} {name}", fill="black")
    draw.text((8, 288), f"visible={visible} bbox={bbox}", fill="black")
    thumbs.append(tile)

columns = 3
rows = (len(thumbs) + columns - 1) // columns
sheet = Image.new("RGB", (columns * 300, rows * 310), "#dddddd")
for i, tile in enumerate(thumbs):
    sheet.paste(tile, ((i % columns) * 300, (i // columns) * 310))
sheet.save(destination / "contact_sheet.png")
print(f"exported={len(images)} destination={destination}")
