"""从世界坐标权威轮廓同时生成地区悬停索引及8K裁切显示蒙版；不改底图或水体。"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ORDER = ["resting_plain", "snow_mountains", "frozen_tundra", "edgar_mountain",
         "mushroom_forest", "badlands", "abandoned_school", "zombie_church",
         "john_furnace", "garden_airship", "psychedelic_current"]


def raster_region(spec, origin, extent, pixels, ocean):
    """同一多边形在指定裁切范围直接栅格化；禁止把旧低清 hover 放大当新边界。"""
    width, height = pixels
    ratio = np.array([width / extent[0], height / extent[1]], np.float32)
    output = np.zeros((height, width), np.uint8)
    if spec.get("source") == "ocean_coverage":
        x, y = origin
        crop = ocean[y:y + extent[1], x:x + extent[0]]
        output = cv2.resize(crop, pixels, interpolation=cv2.INTER_LINEAR)
        return (output >= 128).astype(np.uint8) * 255
    for field, value in [("polygons", 255), ("holes", 0)]:
        for polygon in spec.get(field, []):
            # 四位小数的亚像素坐标保留斜边精度，显示密度不改变世界几何。
            vertices = np.rint((np.asarray(polygon, np.float32) - np.asarray(origin)) * ratio * 16).astype(np.int32)
            cv2.fillPoly(output, [vertices], value, lineType=cv2.LINE_8, shift=4)
    return output


def build_hover(project, preview_source=None, preview_path=None):
    """只重建既有hover路径、索引与地标几何；原图、动效mask及关卡注册不写入。"""
    root = project / "assets/adventure/wonderland"
    master_path = project / "tools/art/wonderland_hover_regions.json"
    master = json.loads(master_path.read_text(encoding="utf-8"))
    catalog_path = root / "config/landmarks.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    layout = json.loads((root / "config/art_layout.json").read_text(encoding="utf-8"))
    world = tuple(master["world_size"])
    if world != tuple(catalog["source_size"]) or set(master["regions"]) != set(ORDER):
        raise ValueError("权威轮廓必须与11个地区和世界范围一致")
    density = float(layout["terrain"]["pixels_per_world"])
    regions = master["regions"]
    entries = {entry["id"]: entry for entry in catalog["landmarks"]}
    identity = {entry["id"]: index + 1 for index, entry in enumerate(catalog["landmarks"])}
    # 只读原始PNG技术通道，避免透明边缘导入修补影响完整湿域识别。
    flow = np.asarray(Image.open(root / "masks/water/runtime/water_flow_field_rgba.png"))
    wet = (flow[:, :, 2] > 0).astype(np.uint8) * 255
    ocean = np.asarray(Image.open(root / "masks/water/runtime/ocean_mask.png"))[:, :, 1]
    atlas = np.zeros((world[1], world[0]), np.uint8)
    for region_id in ORDER:
        coverage = raster_region(regions[region_id], (0, 0), world, world, ocean)
        if region_id != "psychedelic_current":
            coverage[wet > 0] = 0
        atlas[coverage > 0] = identity[region_id]
    # ID与各区显示都按同一优先级消除覆盖；主体院落在广域地形之上，水域沿真实湿域。
    Image.fromarray(atlas).save(root / catalog["hit_source"])
    output_bytes = 0
    native_texels = 0
    for order_index, region_id in enumerate(ORDER):
        entry = entries[region_id]
        owned = (atlas == identity[region_id]).astype(np.uint8)
        if not np.any(owned):
            raise ValueError(f"地区轮廓被完全覆盖: {region_id}")
        ys, xs = np.nonzero(owned)
        minimum = np.array([xs.min(), ys.min()])
        maximum = np.array([xs.max() + 1, ys.max() + 1])
        origin = np.maximum(minimum - 4, 0).astype(int)
        end = np.minimum(maximum + 4, world).astype(int)
        extent = (end - origin).astype(int)
        pixels = np.rint(extent * density).astype(int)
        high = raster_region(regions[region_id], origin, extent, tuple(pixels), ocean)
        if region_id != "psychedelic_current":
            x, y = origin
            wet_crop = wet[y:y + extent[1], x:x + extent[0]]
            high[cv2.resize(wet_crop, tuple(pixels), interpolation=cv2.INTER_LINEAR) >= 128] = 0
        for above_id in ORDER[order_index + 1:]:
            above = raster_region(regions[above_id], origin, extent, tuple(pixels), ocean)
            high[above > 0] = 0
        # 只向区域内部羽化，不把亮边扩散到岸石、院外或邻区。单次只持有一张裁切高图。
        distance = cv2.distanceTransform((high > 0).astype(np.uint8), cv2.DIST_L2, 5)
        width = max(float(regions[region_id].get("feather_world", 1.0)) * density, 0.5)
        alpha = np.clip(distance / width, 0, 1)
        alpha = np.rint(alpha * alpha * (3 - 2 * alpha) * 255).astype(np.uint8)
        relative = "hd/masks/hover/" + region_id + ".png"
        output = root / relative
        Image.fromarray(alpha).save(output)
        output_bytes += output.stat().st_size
        native_texels += int(np.prod(pixels))
        # 旧制作目录继续保存同几何的世界分辨率派生件，不能反向作为高清权威源。
        low = owned[origin[1]:end[1], origin[0]:end[0]] * 255
        Image.fromarray(low).save(root / "masks/interaction/hover" / (region_id + ".png"))
        interior = cv2.distanceTransform(np.pad(owned, 1), cv2.DIST_L2, 5)[1:-1, 1:-1]
        sample_y, sample_x = np.unravel_index(np.argmax(interior), interior.shape)
        entry.update({"bbox": [int(minimum[0]), int(minimum[1]), int(maximum[0]), int(maximum[1])],
                      "pixel_area": int(np.count_nonzero(owned)), "hover_mask_origin": origin.tolist(),
                      "hover_mask_size": extent.tolist(), "hover_mask_path": relative,
                      "hit_sample_world": [int(sample_x), int(sample_y)], "interaction": "hover_only"})
        entry.pop("moving_subject", None)
    catalog["hit_resolution"] = "world_hover_only"
    catalog["click_on_empty"] = False
    catalog["notes"] = [
        "Regions only provide hover illumination; stage navigation belongs to independent stage buttons.",
        "World ID and native-density hover masks share tools/art/wonderland_hover_regions.json.",
        "Airship and its docking compound are one static hover region; moving_source is retained only as a legacy resource.",
    ]
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # 可选单张工作预览使用已有缩略图，不复制原8K底图。
    if preview_source is not None and preview_path is not None:
        canvas = np.asarray(Image.open(preview_source).convert("RGB").resize(world)).astype(np.float32)
        palette = np.array([[230,100,120], [100,180,240], [190,135,235], [105,215,125],
                            [240,205,100], [245,140,65], [90,220,215], [225,160,190],
                            [140,160,240], [210,180,130], [240,125,95]], np.float32)
        for entry in catalog["landmarks"]:
            mask = atlas == identity[entry["id"]]
            canvas[mask] = canvas[mask] * .82 + palette[identity[entry["id"]] - 1] * .18
            contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            cv2.drawContours(canvas, contours, -1, tuple(palette[identity[entry["id"]] - 1].tolist()), 1)
        Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8)).save(preview_path)
    print(json.dumps({"regions": len(ORDER), "hover_only": True, "mask_png_bytes": output_bytes,
                      "native_mask_texels": native_texels,
                      "source_geometry": str(master_path), "terrain_and_water_unchanged": True}))
    return catalog


if __name__ == "__main__":
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--preview-source", type=Path)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    build_hover(args.root, args.preview_source, args.preview)
