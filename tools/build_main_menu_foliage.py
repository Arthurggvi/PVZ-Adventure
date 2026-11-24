"""Rebuild safe foliage interior mask without altering original menu painting.
Build-only dependencies: pillow, numpy, opencv-python-headless.
The source hand-painted menu background is never cut, erased or overwritten.
"""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[1] / "assets/adventure/environment_fx"
source = root / "v2/art/foliage/masks/main_menu_leaf_wind_mask.png"
output = root / "v5/art/foliage/main_menu/foliage_motion_core.png"
output.parent.mkdir(parents=True, exist_ok=True)

mask = np.asarray(Image.open(source).convert("L"), np.uint8)
solid = np.uint8(mask >= 185)
distance = cv2.distanceTransform(solid, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
progress = np.clip((distance - 12.0) / 15.0, 0.0, 1.0)
progress = progress * progress * (3.0 - 2.0 * progress)
core = np.uint8(np.round(progress * 255))
assert core.shape == (1080, 1920)
assert not np.any(core[:, 820:]) and not np.any(core[280:, :])
assert np.count_nonzero(core > 128) > 5000
Image.fromarray(core, "L").save(output, optimize=True)
print("safe-motion pixels:", np.count_nonzero(core), "output:", output)
