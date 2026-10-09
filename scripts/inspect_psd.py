from pathlib import Path
import sys

from psd_tools import PSDImage


def walk(layer, depth=0):
    indent = "  " * depth
    print(f"{indent}{layer.name!r} kind={layer.kind} visible={layer.visible} bbox={layer.bbox} size={layer.size}")
    if hasattr(layer, "__iter__"):
        for child in layer:
            walk(child, depth + 1)


path = Path(sys.argv[1])
psd = PSDImage.open(path)
print(f"size={psd.size} depth={psd.depth} color_mode={psd.color_mode} layers={len(psd)}")
walk(psd)
