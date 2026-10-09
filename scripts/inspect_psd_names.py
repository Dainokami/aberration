from psd_tools import PSDImage
import sys

psd = PSDImage.open(sys.argv[1])

def walk(layer, path):
    print(path, repr(layer.name), type(layer).__name__)
    if hasattr(layer, '__iter__'):
        for i, child in enumerate(layer):
            walk(child, path + [i])

for i, layer in enumerate(psd):
    walk(layer, [i])
