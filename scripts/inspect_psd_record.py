from psd_tools import PSDImage
import sys

psd = PSDImage.open(sys.argv[1])
layer = psd[3]
print(type(layer._record), getattr(layer._record, '_fields', None))
for attr in dir(layer._record):
    if not attr.startswith('_'):
        try:
            print(attr, repr(getattr(layer._record, attr)))
        except Exception:
            pass
