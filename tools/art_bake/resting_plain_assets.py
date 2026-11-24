"""安息平原地面正式烘焙：在原图613像素终点以前完成连续草地衔接。"""
from pathlib import Path
from random import Random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2] / "assets" / "adventure" / "wonderland" / "battle" / "resting_plain"
SOURCE = ROOT / "board.webp"
OUTPUT = ROOT / "board_final.webp"
HEIGHT = 800
SEED = 260112


def smoothstep(value):
    """在0..1之间提供连续一阶导数的混合曲线。"""
    t = np.clip(value, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def build_meadow(width, height):
    """生成不含棋格与重复贴片边框的暖色手绘草地底材。"""
    rng = np.random.default_rng(SEED)
    x = np.arange(width, dtype=np.float32)
    rolling = smoothstep((x - 1150.0) / 710.0)
    left_halo = 7.0 * (1.0 - smoothstep(x / 410.0))

    # 两种相关噪声代表真实草地的成片明暗，细噪声只承担草叶笔触。
    low = Image.fromarray(rng.integers(50, 196, size=(19, 51), dtype=np.uint8), "L")
    mid = Image.fromarray(rng.integers(65, 185, size=(110, 294), dtype=np.uint8), "L")
    low = np.asarray(low.resize((width, height), Image.Resampling.BICUBIC), dtype=np.float32)
    mid = np.asarray(mid.resize((width, height), Image.Resampling.BILINEAR), dtype=np.float32)
    texture = (low - 124.0) * 0.14 + (mid - 124.0) * 0.10
    texture += rng.normal(0.0, 1.1, (height, width)).astype(np.float32)

    rgb = np.empty((height, width, 3), dtype=np.uint8)
    rgb[:, :, 0] = np.clip(111.0 + left_halo + rolling * 25.0 + texture, 0, 255)
    rgb[:, :, 1] = np.clip(129.0 + left_halo * 0.36 + rolling * 13.0 + texture * 0.85, 0, 255)
    rgb[:, :, 2] = np.clip(34.0 + rolling * 7.0 + texture * 0.32, 0, 255)
    underpainting = Image.fromarray(rgb, "RGB").convert("RGBA")

    # 小尺寸柔和笔触而不是一张张矩形草纹补丁，不会出现横竖重复拼缝。
    strokes = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(strokes)
    stroke_rng = Random(SEED)
    palette = [(177, 173, 66, 36), (78, 119, 31, 28), (193, 179, 82, 20),
               (75, 110, 37, 27), (160, 165, 65, 30)]
    for _ in range(16500):
        px = stroke_rng.randrange(width)
        py = stroke_rng.randrange(450, height)
        stem = stroke_rng.randrange(2, 8)
        bend = stroke_rng.randrange(-3, 4)
        draw.line((px, py, px + bend, py - stem),
                  fill=palette[stroke_rng.randrange(len(palette))],
                  width=stroke_rng.randrange(1, 3))
    strokes = strokes.filter(ImageFilter.GaussianBlur(0.25))
    return Image.alpha_composite(underpainting, strokes)


def bake():
    """原画与无格草地连续融合，确保素材最后一行不产生突变。"""
    source = np.asarray(Image.open(SOURCE).convert("RGBA"), dtype=np.float32)
    source_h, width = source.shape[:2]
    under = np.asarray(build_meadow(width, HEIGHT), dtype=np.float32)
    result = np.zeros((HEIGHT, width, 4), dtype=np.uint8)
    result[:, :, :3] = under[:, :, :3].astype(np.uint8)

    # 垂直过渡在原图结束前结束：不再在第613行突然把原图切成新贴图。
    x = np.arange(width, dtype=np.float32)
    wave = 5.5 * np.sin(x * 0.022) + 5.5 * np.sin(x * 0.006 + 0.5)
    end = 606.0 + 2.0 * np.sin(x * 0.004 + 1.0)
    beginning = 542.0 + wave

    for y in range(HEIGHT):
        if y >= source_h:
            alpha = np.zeros(width, dtype=np.float32)
        else:
            alpha = source[y, :, 3] / 255.0
            alpha *= (1.0 - smoothstep((float(y) - beginning) / (end - beginning)))
        if y < source_h:
            result[y, :, :3] = np.clip(
                source[y, :, :3] * alpha[:, None] +
                under[y, :, :3] * (1.0 - alpha[:, None]), 0, 255).astype(np.uint8)

        # 下方始终是草地，顶部保留原素材天然透明以便 Skybox 透出。
        reveal = smoothstep((float(y) - 400.0) / 125.0)
        if y < source_h:
            original_alpha = source[y, :, 3] / 255.0
            result[y, :, 3] = np.clip(255.0 * (
                alpha + (1.0 - alpha) * reveal), 0, 255).astype(np.uint8)
        else:
            result[y, :, 3] = 255

    # 顶部原画里多余的非透明彩色带需仅改动 alpha，不伤害栅栏主体。
    for y in range(0, 30):
        cut = max(0.0, min(1.0, (y - 12.0) / 18.0))
        result[y, 485:, 3] = (result[y, 485:, 3] * cut).astype(np.uint8)

    Image.fromarray(result, "RGBA").save(OUTPUT, format="WEBP", quality=96, method=6)
    # 定量验收：原资源终点613左右的行亮度与alpha差。
    rgb = result[:, :, :3].astype(np.int16)
    for a, b in ((589, 590), (605, 606), (612, 613), (613, 614)):
        gap = np.abs(rgb[a] - rgb[b]).mean(axis=1)
        print("ROW_DIFF", a, b, "mean", round(float(gap.mean()), 3),
              "max_bin_avg", round(float(np.max(np.convolve(gap, np.ones(90) / 90, 'valid'))), 3))
    print("BAKED", OUTPUT, OUTPUT.stat().st_size)


if __name__ == "__main__":
    bake()
