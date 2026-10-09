from pathlib import Path
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

path = Path(sys.argv[1])
image = Image.open(path).convert("RGBA")
alpha = np.asarray(image)[..., 3] > 8
labels, count = ndimage.label(alpha)
print("size", image.size, "components", count)
for i in range(1, count + 1):
    ys, xs = np.where(labels == i)
    if len(xs) > 20:
        top_y = int(ys.min())
        top_xs = xs[ys <= top_y + 12]
        print(i, "pixels", len(xs), "bbox", (int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)), "top_center", float(np.mean(top_xs)))
