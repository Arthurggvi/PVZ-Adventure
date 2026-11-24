"""Bake original animated star Shader into deterministic RGBA atlases.

Usage: python tools/adventure/bake_star_badges.py
Shipping game reads only atlas PNG and manifest JSON; never executes this script.
"""
from __future__ import annotations
import hashlib
import json
import math
from pathlib import Path
from PIL import Image
from star_badge_bake_math import composite, source_art

PROJECT = Path(__file__).resolve().parents[2]
SOURCE = PROJECT / "assets/adventure/ui/star_badges"
OUT = SOURCE / "baked"
TILE = 96  # 2x supersampling of the full 45px graphic; transparent gutter prevents bleeding.
INNER = 90
GUTTER = (TILE - INNER) // 2
PERIOD = {5: 8.0, 6: 8.0, 7: 8.0, 8: 8.0, 9: 8.0, 10: 16.0}
RESAMPLE = Image.Resampling.LANCZOS


def time_points(rank: int) -> list[float]:
    """Allocate most samples around rapid 0.8s sweeps and 1.8s glints."""
    times = {0.0}
    if rank < 10:
        # One ~30 fps sweep, no wasteful frames during the long static hold.
        times.update(round(i / 30.0, 6) for i in range(25))
        times.add(.800001)
        if rank >= 7:
            times.update(round(1.0 + i / 30.0, 6) for i in range(25))
            times.add(1.800001)
        times.add(7.99999)
    else:
        # Ten-star continuously changes hue across 16 seconds.
        times.update(round(i / 8.0, 6) for i in range(128))
        # Both eight-second sweeps and glint windows need higher sampling.
        for offset in (0.0, 8.0):
            for i in range(25):
                times.add(round(offset + i / 30.0, 6))
            times.add(offset + .800001)
            for i in range(25):
                times.add(round(offset + 1.0 + i / 30.0, 6))
            times.add(offset + 1.800001)
        # One short 16-second crown burst also needs a smooth brightness curve.
        times.update(round(1.6 + i / 30.0, 6) for i in range(44))
        times.add(15.99999)
    return sorted(t for t in times if 0.0 <= t < PERIOD[rank])


def tile_image(original: Image.Image) -> Image.Image:
    """Downsample supersampled 45x45 display to 60px and keep 2px alpha gutter."""
    tile = Image.new("RGBA", (TILE, TILE))
    frame = original.resize((INNER, INNER), RESAMPLE)
    tile.paste(frame, (GUTTER, GUTTER))
    return tile


def save_rank(rank: int) -> dict:
    """Build one lazily loadable atlas per rank and return its shared timeline."""
    times = time_points(rank)
    count = len(times)
    cols = min(16, math.ceil(math.sqrt(count)) + 1)
    rows = math.ceil(count / cols)
    canvas = Image.new("RGBA", (cols * TILE, rows * TILE))
    art = source_art(SOURCE, rank)
    for i, seconds in enumerate(times):
        cell = tile_image(composite(rank, seconds, art))
        canvas.paste(cell, ((i % cols) * TILE, (i // cols) * TILE))
    name = f"star_{rank:02d}_atlas.png"
    path = OUT / name
    canvas.save(path, optimize=True, compress_level=8)
    checksum = hashlib.sha256(path.read_bytes()).hexdigest()
    print(f"{name}: {count} frames, {canvas.width}x{canvas.height}, "
          f"{path.stat().st_size} B, sha256={checksum[:12]}")
    return {
        "period": PERIOD[rank], "atlas": name,
        "tile": TILE, "gutter": GUTTER, "inner": INNER,
        "columns": cols, "times": times, "frames": count,
    }


def main() -> None:
    """Generate exactly 5..10 stars, avoiding runtime shader or save dependencies."""
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {str(rank): save_rank(rank) for rank in range(5, 11)}
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("frames:", sum(value["frames"] for value in manifest.values()))


if __name__ == "__main__":
    main()
