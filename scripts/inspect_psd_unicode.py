from psd_tools import PSDImage
from psd_tools.constants import Tag
import sys

psd = PSDImage.open(sys.argv[1])

def walk(layer, path):
    block = layer._record.tagged_blocks.get(Tag.UNICODE_LAYER_NAME)
    print(path, repr(layer.name), repr(block.data) if block else None)
    if hasattr(layer, '__iter__'):
        for i, child in enumerate(layer):
            walk(child, path + [i])

for i, layer in enumerate(psd):
    walk(layer, [i])
