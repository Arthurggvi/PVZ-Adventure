"""Offline CPU recreation of the original badge shader; no runtime dependency."""
from __future__ import annotations
import math
from pathlib import Path
import numpy as np
from PIL import Image

SIZE = 90  # 2x render of the original 45-pixel halo footprint.
BODY_SIZE = 62  # 31-pixel star body at matching scale.
BODY_ORIGIN = 14
RESAMPLE = Image.Resampling.LANCZOS

def rgba(path: Path, size: tuple[int, int]) -> Image.Image:
    """Load original art with enough subpixel detail for final downsampling."""
    with Image.open(path) as source:
        return source.convert("RGBA").resize(size, RESAMPLE)

def mask(path: Path) -> np.ndarray:
    """Original 512px shader masks become UV-aligned float samples."""
    with Image.open(path) as source:
        return np.asarray(source.convert("L").resize(
            (BODY_SIZE, BODY_SIZE), RESAMPLE), dtype=np.float32) / 255.0

def image(rgb: np.ndarray, alpha: np.ndarray) -> Image.Image:
    """Convert straight-alpha shader color back to CPU RGBA pixels."""
    channels = np.concatenate([rgb, alpha[..., None]], axis=2)
    return Image.fromarray(np.uint8(np.round(np.clip(channels, 0, 1) * 255)), "RGBA")

def smoothstep(a: float, b: float, value: float) -> float:
    """Smooth Hermite interpolation from the shipped GLSL source."""
    v = float(np.clip((value - a) / (b - a), 0, 1))
    return v * v * (3 - 2 * v)

def body_frame(base: Image.Image, rank: int, t: float, masks: dict) -> Image.Image:
    """Recreate the sweep, guarded rainbow and 10-star highlight verbatim."""
    raw = np.asarray(base, dtype=np.float32) / 255.0
    rgb, alpha = raw[..., :3].copy(), raw[..., 3]
    coords = (np.arange(BODY_SIZE, dtype=np.float32) + .5) / BODY_SIZE
    u, v = np.meshgrid(coords, coords)
    guard = 1.0 - masks["guard"]
    if rank == 10:
        angle = math.tau * (t % 16.0) / 16.0
        axis = np.array([1.0 / math.sqrt(3)] * 3, dtype=np.float32)
        rotated = rgb * math.cos(angle) + np.cross(axis, rgb) * math.sin(angle)
        rotated += axis * np.sum(rgb * axis, axis=2, keepdims=True) * (1 - math.cos(angle))
        region = masks["rainbow"] * guard * .52
        rgb += (np.clip(rotated, 0, 1) - rgb) * region[..., None]
    phase = t % 8.0
    center = -0.45 + 1.90 * min(phase / .80, 1.0)
    distance = (u + .38 * v - center) / .085
    sweep = np.exp(-distance * distance) * float(phase < .80)
    sweep *= masks["sweep"] * guard * alpha * .46
    rgb += (np.array([1.0, .97, .83]) - rgb) * sweep[..., None]
    if rank == 10:
        burst = math.exp(-((t % 16.0 - 2.3) / .38) ** 2)
        spot = np.exp(-((u - .50)**2 + (v - .18)**2) * 45.0)
        flash = spot * burst * guard * .42
        rgb += (np.array([1.0, .97, .80]) - rgb) * flash[..., None]
    return image(rgb, alpha)

def composite(rank: int, t: float, art: dict) -> Image.Image:
    """Match Godot draw order: halo, star body, then optional glints."""
    output = Image.new("RGBA", (SIZE, SIZE))
    if rank == 10:
        raw = np.asarray(art["halo"], dtype=np.float32) / 255.0
        ambient = .17 + .07 * (.5 + .5 * math.sin(t * .79))
        burst = math.exp(-((t % 16.0 - 2.3) / .48) ** 2)
        alpha = np.minimum(1.0, raw[..., 3] * (ambient + .48 * burst))
        output.alpha_composite(image(raw[..., :3], alpha))
    output.alpha_composite(body_frame(art["body"], rank, t, art["masks"]),
                           (BODY_ORIGIN, BODY_ORIGIN))
    if rank >= 7:
        phase = t % 8.0
        glint = smoothstep(1.0, 1.1, phase) * (1.0 - smoothstep(1.5, 1.8, phase))
        if glint > .0001:
            raw = np.asarray(art["sparkle"], dtype=np.float32) / 255.0
            rgb = raw[..., :3] + (1.0 - raw[..., :3]) * glint * .35
            alpha = np.minimum(1.0, raw[..., 3] * glint * 1.8)
            glint_image = image(rgb, alpha)
            origins = [(0.22, 0.30)] + ([(0.79, 0.33)] if rank >= 8 else [])
            for x, y in origins:
                px = round((7 + x * 31 - 7.5) * 2)
                py = round((7 + y * 31 - 7.5) * 2)
                output.alpha_composite(glint_image, (px, py))
    return output

def source_art(root: Path, rank: int) -> dict:
    """Resolve and cache the same PNGs as the shipping GDScript."""
    data = {
        "body": rgba(root / "static/256" / f"star_{rank:02d}.png",
                     (BODY_SIZE, BODY_SIZE)),
        "masks": {
            "sweep": mask(root / "masks" / f"star_{rank:02d}_sweep_mask.png"),
            "guard": mask(root / "masks" / f"star_{rank:02d}_number_guard.png"),
        },
    }
    if rank >= 7:
        data["sparkle"] = rgba(root / "fx/sparkle_shared.png", (30, 30))
    if rank == 10:
        data["masks"]["rainbow"] = mask(root / "masks/star_10_color_mask.png")
        data["halo"] = rgba(root / "fx/star_10_halo.png", (SIZE, SIZE))
    return data
