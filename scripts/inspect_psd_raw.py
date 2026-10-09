from psd_tools import PSDImage
import sys

psd = PSDImage.open(sys.argv[1])
for i, layer in enumerate(psd):
    print(i, repr(layer.name), repr(layer._record))
