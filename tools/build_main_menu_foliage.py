"""Extract original-art foliage and produce matching reversible background patches.
Requires: pillow, numpy, opencv-python-headless (build tool only, not game runtime).
"""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[1] / "assets/adventure"
foliage = root / "environment_fx/v2/art/foliage"
out = foliage / "main_menu"
out.mkdir(exist_ok=True)
w, h = 840, 320
leaf_mask = np.asarray(Image.open(foliage / "masks/main_menu_leaf_wind_mask.png").convert("L"), np.float32)[:h, :w] / 255
yy, xx = np.mgrid[:h, :w].astype(np.float32)

# Limit the animation to the mature tree; retain the bushes near the path.
y_falloff = np.clip((270.0 - yy) / 50.0, 0.0, 1.0)
x_falloff = np.clip((820.0 - xx) / 50.0, 0.0, 1.0)
alpha = np.clip((leaf_mask - 0.025) / 0.93, 0.0, 1.0) * y_falloff * x_falloff
# Full opacity for painted interiors; slight feathering only on silhouette edges.
alpha[alpha > .98] = 1.0

sources = {
    "clean": root / "environment_fx/v1/sky_cleanup_v1/backgrounds/main_menu_sky_clean_1920x1080.png",
    "original": root / "main_menu/v6/background/coastal_yard.png"
}

for key, path in sources.items():
    source = np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)[:h, :w]
    # The retained trunk/branches are excluded from the canonical leaf mask.
    holes = (alpha > 0.90).astype(np.uint8) * 255
    holes = cv2.dilate(holes, np.ones((3, 3), dtype=np.uint8))
    clean = cv2.inpaint(cv2.cvtColor(source, cv2.COLOR_RGB2BGR), holes, 5, cv2.INPAINT_TELEA)
    clean = cv2.cvtColor(clean, cv2.COLOR_BGR2RGB)

    # Preserve antialiased pixels at fractional-alpha edges for exact rest reconstruction.
    blend = np.clip((alpha - .89) / .10, 0.0, 1.0)
    underlay = np.round(source * (1.0 - blend[:, :, None]) + clean * blend[:, :, None]).astype(np.uint8)
    rgba = np.dstack((source, np.round(alpha * 255).astype(np.uint8)))
    Image.fromarray(underlay, "RGB").save(out / f"tree_underlay_{key}.png", optimize=True)
    Image.fromarray(rgba, "RGBA").save(out / f"tree_leaves_{key}.png", optimize=True)
    reconstruction = rgba[:,:,:3].astype(np.float32) * alpha[:,:,None] + underlay.astype(np.float32) * (1-alpha[:,:,None])
    delta = np.abs(reconstruction - source.astype(np.float32))
    print(key, "mean error", round(float(delta.mean()), 4), "max", round(float(delta.max()), 3),
          "pixels > 3", int((delta.max(axis=2)>3).sum()))
print("assets", [(p.name, p.stat().st_size) for p in out.iterdir() if p.suffix==".png"])
