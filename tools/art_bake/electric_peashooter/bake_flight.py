"""将现有电球分层、渐隐裁尾和方向电光烘成一张共享遮罩图集。

依赖 Pillow 和 NumPy。红、绿、蓝保存主电色、亮芯、辅色的权重，
透明度单独保存，所有转职配色共用同一图集。
"""

import math

import numpy as np
from PIL import Image, ImageDraw

from bake import ATLASES, GAME, REGIONS, decode


# 飞行循环的原时间轴标签与项目实际球心半径，次序与运行时一致。
VARIANTS = (("animation", 16), ("animation2", 24), ("animation3", 32))
# 图集列数、每种球的行数及左侧尾迹留白，单位为源图像像素。
COLUMNS = 10
ROWS = 6
TAIL_ROOM = 22
# 每轴用两个采样点重现原贴图插值并降低旋转锯齿。
SUPERSAMPLE = 2
# 主球面保留 Godot 分层场景 Rig 的统一缩放。
RIG_SCALE = 0.7
# 游戏中原始图集所在的目录，也是派生生产图集的输出位置。
ART = GAME / "assets/adventure/plants/electric_peashooter"


def smoothstep(low, high, value):
    """按现有着色器的曲线插值，适用于采样数组和标量。"""
    # 先限制归一化距离，再完成三次插值。
    t = np.clip((value - low) / (high - low), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def composite(canvas, weights, alpha):
    """按原图层顺序执行普通 alpha 混合，累计三个颜色通道的预乘权重。"""
    # 后一层通过自身 alpha 遮挡已有权重和透明度。
    canvas[..., :3] *= (1.0 - alpha[..., None])
    canvas[..., :3] += weights * alpha[..., None]
    canvas[..., 3] *= 1.0 - alpha
    canvas[..., 3] += alpha


def sample(image, u, v):
    """从原 AtlasTexture 区域双线性采样，夹紧到区域最外侧像素。"""
    # 在 texel 中心插值；源 quad 的范围检查由调用方执行。
    height, width = image.shape[:2]
    x = np.clip(u - 0.5, 0, width - 1)
    y = np.clip(v - 0.5, 0, height - 1)
    left, top = x.astype(np.intp), y.astype(np.intp)
    right, bottom = np.minimum(left + 1, width - 1), np.minimum(top + 1, height - 1)
    tx, ty = (x - left)[..., None], (y - top)[..., None]
    return (
        (image[top, left] * (1.0 - tx) + image[top, right] * tx) * (1.0 - ty)
        + (image[bottom, left] * (1.0 - tx) + image[bottom, right] * tx) * ty
    )


def body_frame(layers, regions, x, y, radius):
    """以球心为原点逐层应用现有裁尾和高光映射，再合成整帧。"""
    # 球面材质使用场景根坐标，因此收束半径不乘 Rig 缩放。
    coverage = 1.0 - smoothstep(radius, radius * 1.24, np.hypot(x, y))
    canvas = np.zeros((*x.shape, 4), dtype=np.float32)
    for region, transform, tint, additive in layers:
        # 当前素材只使用普通混合，色调乘数的 RGB 三通道相同。
        assert not additive and tint[0] == tint[1] == tint[2]
        a, c, b, d, tx, ty = (component * RIG_SCALE for component in transform)
        det = a * d - c * b
        if abs(det) < 1e-8 or tint[3] <= 0.0:
            continue
        # 逆变换从目标采样位置找回源图集区域坐标。
        u = (d * (x - tx) - c * (y - ty)) / det
        v = (a * (y - ty) - b * (x - tx)) / det
        image = regions[region]
        height, width = image.shape[:2]
        inside = (coverage > 0) & (u >= 0) & (u < width) & (v >= 0) & (v < height)
        if not np.any(inside):
            continue
        source = sample(image, u[inside], v[inside])
        # 源明度决定主色强度，近白像素逐步转向白芯。
        rgb = source[..., :3]
        white = smoothstep(0.58, 0.96, rgb.min(axis=-1))
        edge = 0.38 + 0.62 * smoothstep(0.06, 0.90, rgb.max(axis=-1))
        weights = np.stack((edge * (1.0 - white), white, np.zeros_like(white)), axis=-1) * tint[0]
        alpha = source[..., 3] * coverage[inside] * tint[3]
        picked = canvas[inside]
        composite(picked, weights, alpha)
        canvas[inside] = picked
    return canvas


def accent_frame(shape, x, origin, radius, age, child):
    """烘制方向尾迹、亮芯及出膛光，尾迹以每种球的正常飞行状态定形。"""
    # 颜色写到三个遮罩通道，运行时由同一等阶材质还原。
    canvas = np.zeros((*shape, 4), dtype=np.float32)
    rim, core, glow = np.eye(3, dtype=np.float32)
    strength = 0.70 if child else 1.0
    onset = smoothstep(0.0, 0.10, age)
    tail_root = radius * 0.80
    tail_length = tail_root + 25.0 * onset
    scene_center_x, scene_center_y = origin

    def paint(color, opacity, draw):
        """将单个抗锯齿辅助图元合并到当前透明帧。"""
        # 附加色 alpha 可为常量或尾迹渐隐数组。
        mask = Image.new("L", (shape[1], shape[0]))
        draw(ImageDraw.Draw(mask))
        composite(canvas, color, np.asarray(mask, dtype=np.float32) * (opacity * strength / 255.0))

    def point(x_pos, y_pos):
        """将球心相对坐标转换到高分辨率贴图网格。"""
        return ((x_pos + scene_center_x) * SUPERSAMPLE, (y_pos + scene_center_y) * SUPERSAMPLE)

    def line(points, width, color, opacity):
        """描一段短电光，传入参数均以世界像素表示。"""
        paint(color, opacity, lambda pen: pen.line(
            [point(*p) for p in points], fill=255, width=max(1, round(width * SUPERSAMPLE))))

    def arc(distance, start, finish, width, color, opacity):
        """以球心描出一段与局部正方向对齐的弧形。"""
        paint(color, opacity, lambda pen: pen.arc(
            (point(-distance, -distance), point(distance, distance)),
            math.degrees(start), math.degrees(finish), fill=255, width=max(1, round(width * SUPERSAMPLE))))

    if onset > 0.01:
        # 尾迹底层和两道细线都从尾尖渐隐，不遮挡球面细节。
        tail_fade = np.clip((x + tail_length) / (tail_length - tail_root), 0.0, 1.0)
        paint(rim, 0.13 * tail_fade, lambda pen: pen.polygon(
            [point(-tail_length, 0), point(-tail_root, -2), point(-tail_root + 3, 0), point(-tail_root, 2)],
            fill=255))
        line([(-tail_length, -0.6), (-tail_root, -1.8)], 0.75, core, 0.62 * onset * tail_fade)
        line([(-tail_root - (tail_length - tail_root) * 0.78, 2.5), (-tail_root, 3.2)],
             0.65, glow, 0.46 * onset * tail_fade)
        line([(-tail_root - (tail_length - tail_root) * offset, height) for offset, height in
              ((0.74, -0.6), (0.55, -1.7), (0.30, 0.6), (0.0, -0.4))], 0.8, rim, 0.43)
    # 稳定白芯和球面边缘延续原有角度和大小。
    paint(core, 0.72, lambda pen: pen.ellipse((point(-3, -3), point(3, 3)), fill=255))
    arc(radius * 0.74, -1.10, 0.72, 0.8, rim, 0.48)
    arc(radius * 0.64, -2.65, -1.82, 0.7, core, 0.65)
    duration = 0.11 if child else 0.16
    if age < duration:
        # 出生脉冲仍按各自时长外扩、快速淡出，并保留三道定向火花。
        progress = age / duration
        fade = (1.0 - progress) ** 2
        bloom_radius = radius * (0.72 + ((1.04 if child else 1.18) - 0.72) * progress)
        arc(bloom_radius, -1.20, 1.20, 1.0, rim, 0.55 * fade)
        arc(bloom_radius * 0.83, 1.90, 3.65, 0.9, glow, 0.36 * fade)
        for index in range(3):
            # 每根火花沿固定角度推进，与飞行方向一起旋转。
            angle = -0.90 + index * 0.90
            cosine, sine = math.cos(angle), math.sin(angle)
            line([(distance * cosine, distance * sine)
                  for distance in (bloom_radius - 1, bloom_radius + 3 - progress * 2)],
                 0.8, core, 0.65 * fade)
    return canvas


def write_tile(atlas, canvas, position, width, height):
    """先缩小预乘遮罩，再输出着色器读取的普通 RGB 权重和透明度。"""
    # box 降采样先求覆盖率，半透明边缘不会混入透明黑色。
    averaged = canvas.reshape(height, SUPERSAMPLE, width, SUPERSAMPLE, 4).mean(axis=(1, 3))
    alpha = averaged[..., 3:4]
    np.divide(averaged[..., :3], alpha, out=averaged[..., :3], where=alpha > 0.0)
    tile = Image.fromarray(np.clip(np.rint(averaged * 255.0), 0, 255).astype(np.uint8))
    atlas.paste(tile, position)


def bake():
    """生成一张图集，段落依次为小、中、大电球。"""
    # 每段的 tile 正方部分围住裁切后的球面；额外左边界只容纳方向尾迹。
    sizes = [2 * math.ceil(radius * 1.24) + 4 for _, radius in VARIANTS]
    atlas = Image.new("RGBA", (COLUMNS * (max(sizes) + TAIL_ROOM), ROWS * sum(sizes)))
    fps, decoded = decode("ELECTRIC_PEASHOOTER_ELECTROBALL", (195, 195))
    # 输入图集按原区域裁分，每块素材转换为浮点色值供双线性采样。
    parents = {item[1]["parent"] for item in REGIONS.items()}
    source = {name: Image.open(ART / ATLASES[name]).convert("RGBA") for name in parents}
    names = {layer[0] for clip, _ in VARIANTS for frame in decoded[clip] for layer in frame}
    regions = {}
    for name in names:
        region = REGIONS[name]
        left, top, width, height = [region[key] for key in ("ax", "ay", "aw", "ah")]
        regions[name] = np.asarray(source[region["parent"]].crop((left, top, left + width, top + height)),
                                   dtype=np.float32) / 255.0
    # 段内前 40 格为球面，随后依次为普通出膛、分裂、两种稳定尾迹。
    assert fps == 30
    row = 0
    for (clip, radius), height in zip(VARIANTS, sizes):
        width = height + TAIL_ROOM
        origin = width - height // 2, height // 2
        y, x = np.mgrid[:height * SUPERSAMPLE, :width * SUPERSAMPLE].astype(np.float32)
        x, y = (x + 0.5) / SUPERSAMPLE - origin[0], (y + 0.5) / SUPERSAMPLE - origin[1]
        assert len(decoded[clip]) == 40
        for index, layers in enumerate(decoded[clip]):
            write_tile(atlas, body_frame(layers, regions, x, y, radius),
                       (index % COLUMNS * width, row + index // COLUMNS * height), width, height)
        accent_ages = ([(frame / 60, False) for frame in range(10)]
                       + [(frame / 60, True) for frame in range(7)] + [(1.0, False), (1.0, True)])
        for index, (age, child) in enumerate(accent_ages, 40):
            write_tile(atlas, accent_frame(x.shape, x, origin, radius, age, child),
                       (index % COLUMNS * width, row + index // COLUMNS * height), width, height)
        row += height * ROWS
    atlas.save(ART / "flight_atlas.png", optimize=True)


if __name__ == "__main__":
    bake()
