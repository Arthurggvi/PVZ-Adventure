"""Rebuild the single-source menu canopy and transparent underlay reproducibly.
Build-only requirements: Pillow, NumPy, OpenCV. Godot does not import these Python modules.
"""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[1] / "assets/adventure"
foliage = root / "environment_fx/v2/art/foliage"
out = foliage / "main_menu"
patch_out = root / "environment_fx/v4/art/foliage/main_menu"
out.mkdir(parents=True, exist_ok=True)
patch_out.mkdir(parents=True, exist_ok=True)

w, h = 840, 320
leaf_mask = np.asarray(Image.open(foliage / "masks/main_menu_leaf_wind_mask.png").convert("L"), np.float32)[:h, :w] / 255
yy, xx = np.mgrid[:h, :w].astype(np.float32)
y_falloff = np.clip((270.0 - yy) / 50.0, 0.0, 1.0)
x_falloff = np.clip((820.0 - xx) / 50.0, 0.0, 1.0)
alpha = np.clip((leaf_mask - 0.025) / 0.93, 0.0, 1.0) * y_falloff * x_falloff
alpha[alpha > .98] = 1.0

sources = {
    "clean": root / "environment_fx/v1/sky_cleanup_v1/backgrounds/main_menu_sky_clean_1920x1080.png",
    "original": root / "main_menu/v6/background/coastal_yard.png"
}
for key, path in sources.items():
    source = np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)[:h, :w]
    holes = (alpha > .90).astype(np.uint8) * 255
    holes = cv2.dilate(holes, np.ones((3, 3), dtype=np.uint8))
    inpainted = cv2.inpaint(cv2.cvtColor(source, cv2.COLOR_RGB2BGR), holes, 5, cv2.INPAINT_TELEA)
    inpainted = cv2.cvtColor(inpainted, cv2.COLOR_BGR2RGB)
    blend = np.clip((alpha - .89) / .10, 0.0, 1.0)
    underlay = np.round(source*(1.0-blend[:,:,None]) + inpainted*blend[:,:,None]).astype(np.uint8)
    rgba = np.dstack((source, np.round(alpha*255).astype(np.uint8)))
    Image.fromarray(rgba, "RGBA").save(out / f"tree_leaves_{key}.png", optimize=True)

    # The original RGB underlay masked all moving clouds within an 840x320 rectangle.
    # Patch only the original tree-leaf footprint (plus displacement margin).
    footprint = (rgba[:,:,3] > 2).astype(np.uint8)
    footprint = cv2.dilate(footprint, cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(39,39)))
    patch_alpha = cv2.GaussianBlur(footprint.astype(np.float32), (11,11), 3.0)
    patch_alpha = np.round(np.clip(patch_alpha,0,1)*255).astype(np.uint8)
    assert not np.any(patch_alpha[:,815:]), "repair alpha must not cover the old vertical sky boundary"
    patch = np.dstack((underlay,patch_alpha))
    Image.fromarray(patch,"RGBA").save(patch_out/f"tree_underlay_{key}_alpha.png", optimize=True)
    print(key,"leaf_pixels:",int(np.count_nonzero(rgba[:,:,3])),
          "repair_pixels:",int(np.count_nonzero(patch_alpha)))
