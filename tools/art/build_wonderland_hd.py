"""从 sRGB 8K 原图生成大陆资源；飞艇保留原图完整结构，仅允许安全内区微动。"""
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from build_wonderland_hover import build_hover


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--color-profile", type=Path, required=True, help="HDR 转换工具生成的 .color.json，校验源件及显示图身份")
    parser.add_argument("--recolor-only", action="store_true", help="只重建颜色资源，保留已经验收的技术蒙版与动画配置")
    parser.add_argument("--ship-backing", type=Path, required=True, help="只用于码头布幔覆盖的小区域")
    parser.add_argument("--school-backing", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    color_profile = json.loads(args.color_profile.read_text(encoding="utf-8"))
    # 防止把旧版 SDR 缓存误当作最新的 HDR 显示映射；两份身份必须同时匹配。
    for path, field in [(args.original, "source_sha256"), (args.source, "display_sha256")]:
        with path.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != color_profile[field]:
                raise ValueError(f"色彩来源校验失败: {path}")
    cv2.setRNGSeed(0)
    root = args.root / "assets/adventure/wonderland"
    layout_path = root / "config/art_layout.json"
    layout = json.loads(layout_path.read_text(encoding="utf-8"))
    source = Image.open(args.source).convert("RGB")
    assert source.size == (8192, 4096), "必须使用原生 8K 原图"
    density = 8192 / 1774
    output = root / "hd"
    for folder in ["terrain", "subjects", "masks/hover"]:
        (output / folder).mkdir(parents=True, exist_ok=True)

    # 只发布实际显示的三块采样层；原图的桨、藤蔓、阴影、塔架与绳索不重复绘制。
    layout["subjects"] = {name: layout["subjects"][name] for name in ["airship_body", "school_flag", "dock_banner"]}
    cloth_masks = {}
    for name, spec in layout["subjects"].items():
        old = Image.open(root / "subjects" / (name + ".png")).convert("RGBA")
        size = tuple(round(v * density) for v in spec["size"])
        origin = tuple(round(v * density) for v in spec["origin"])
        box = (*origin, origin[0] + size[0], origin[1] + size[1])
        alpha = old.getchannel("A").resize(size, Image.Resampling.LANCZOS)
        subject = source.crop(box).convert("RGBA")
        if name == "airship_body":
            if args.recolor_only:
                # 艇体采样颜色来自新显示图，轮廓和安全运动区保持既有像素。
                subject.save(output / "subjects" / (name + ".png"), compress_level=6)
                continue
            # 完整 RGB 留作局部重采样，透明覆盖范围由专门的安全内区蒙版决定。
            silhouette = alpha.copy()
            silhouette.save(output / "masks/airship_hover.png")
            solid = (np.asarray(silhouette) > 235).astype(np.uint8)
            distance = cv2.distanceTransform(solid, cv2.DIST_L2, 5)
            safe = np.clip((distance - 6*density) / (6*density), 0, 1)
            envelope = Image.new("L", size)
            # 只允许气囊内部变化，不覆盖叶缘、桨轴、吊舱栏杆、索具与塔架连接处。
            points = [(1065,283),(1080,263),(1130,242),(1205,231),(1248,251),
                      (1260,277),(1228,307),(1155,328),(1100,327),(1068,313)]
            ImageDraw.Draw(envelope).polygon([(round(x*density)-origin[0],round(y*density)-origin[1]) for x,y in points],fill=255)
            envelope = envelope.filter(ImageFilter.GaussianBlur(2*density))
            mask = Image.fromarray((safe * np.asarray(envelope)).astype(np.uint8))
            mask.save(output / "masks/airship_motion.png")
            spec["alpha_nonzero"] = int(np.count_nonzero(np.asarray(mask)))
        else:
            cloth_masks[name] = (origin, alpha.copy())
            if args.recolor_only:
                alpha = Image.open(output / "subjects" / (name + ".png")).getchannel("A")
                assert alpha.size == size, "重着色不得改变分件尺寸"
            else:
                seed = np.asarray(alpha)
                core = cv2.erode((seed > 220).astype(np.uint8), np.ones((11,11),np.uint8))
                margin = cv2.dilate((seed > 20).astype(np.uint8), np.ones((13,13),np.uint8))
                trimap = np.where(seed > 128, cv2.GC_PR_FGD, cv2.GC_PR_BGD).astype(np.uint8)
                trimap[margin == 0] = cv2.GC_BGD
                trimap[core != 0] = cv2.GC_FGD
                cv2.grabCut(np.array(subject.convert("RGB")),trimap,None,np.zeros((1,65)),np.zeros((1,65)),2,cv2.GC_INIT_WITH_MASK)
                alpha = Image.fromarray(np.where((trimap==cv2.GC_FGD)|(trimap==cv2.GC_PR_FGD),255,0).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
            subject.putalpha(alpha)
            spec["alpha_nonzero"] = int(np.count_nonzero(np.asarray(alpha)))
        subject.save(output / "subjects" / (name + ".png"), compress_level=6)
        spec["path"] = "hd/subjects/" + name + ".png"
        spec["texture_size"] = list(size)

    # 全图原样保留，唯一擦除对象是两片独立布料；不能以飞艇旧轮廓挖掉原始地形。
    terrain = source.copy()
    for name, crop, backing_path in [
        ("dock_banner", (4520,800,6380,2000), args.ship_backing),
        ("school_flag", (2780,2470,3130,2820), args.school_backing),
    ]:
        size = (crop[2]-crop[0], crop[3]-crop[1])
        origin, alpha = cloth_masks[name]
        mask = Image.new("L", size)
        mask.paste(alpha.point(lambda v: 255 if v > 3 else 0), (origin[0]-crop[0],origin[1]-crop[1]))
        mask = mask.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(1))
        backing = Image.open(backing_path).convert("RGB").resize(size, Image.Resampling.LANCZOS)
        bounds = mask.getbbox()
        center = ((bounds[0]+bounds[2])//2,(bounds[1]+bounds[3])//2)
        blended = cv2.seamlessClone(np.array(backing),np.array(source.crop(crop)),np.array(mask),center,cv2.NORMAL_CLONE)
        terrain.paste(Image.fromarray(blended),(crop[0],crop[1]),mask)

    tiles = []
    for row in range(2):
        for column in range(4):
            # 二十四像素采样边覆盖最多四世界单位折射及色散所需的二十一像素预算。
            x0, y0 = max(0,column*2048-24), max(0,row*2048-24)
            x1, y1 = min(8192,(column+1)*2048+24), min(4096,(row+1)*2048+24)
            path = f"hd/terrain/tile_{column}_{row}.png"
            terrain.crop((x0,y0,x1,y1)).save(root/path,compress_level=6)
            tiles.append({"path":path,"pixel_origin":[x0,y0],"pixel_size":[x1-x0,y1-y0],
                          "core_pixel_origin":[column*2048,row*2048],"core_pixel_size":[2048,2048]})

    # 修色不得重新设定已验收的动效参数、交互身份或物理图集。
    if args.recolor_only:
        layout["terrain"] = {"texture_size":[8192,4096],"pixels_per_world":density,"tiles":tiles}
        layout["color_pipeline"] = color_profile
        layout["art_revision"] = "V5_8K_PQ_BT2390_perceptual"
        layout["zoom"]["visible_world_height"] = 336.0
        layout["release_note"] = "Native 8K SDR derivative rebuilt from original PQ HDR with BT.2390 and perceptual gamut mapping. Native-detail framing at 1440p; approved masks and animation retained."
        layout["notes"][0] = "Original BT.2020/PQ HDR preserved externally; game uses full-resolution, perceptually tone-mapped sRGB SDR tiles, not native HDR output."
        write_json(layout_path, layout)
        print(json.dumps({"tiles": len(tiles), "recolor_only": True, "color_revision": color_profile["revision"]}))
        return
    layout.update({
        "schema_version":3,
        "source_filename":args.original.name,
        "source_sha256":hashlib.sha256(args.original.read_bytes()).hexdigest(),
        "sources":{"original":"User supplied AVIF; preserved externally","repaired":"Only cloth backing; airship area is original source"},
        "terrain":{"texture_size":[8192,4096],"pixels_per_world":density,"tiles":tiles},
        "moving_hover_source":"hd/masks/airship_hover.png",
        "airship_motion_mask":"hd/masks/airship_motion.png",
        "static_occluders":[],
        "art_revision":"V5_8K_PQ_BT2390_perceptual",
        "color_pipeline":color_profile,
        "zoom":{"visible_world_height":336.0,"initial_center_world":[270,620],
                "edge_margin_px":28.0,"pan_screen_px_per_second":480.0,
                "drag_threshold_px":6.0,"hold_milliseconds":180.0},
        "motion_defaults":{"ship_seconds":8.4,"hull_amplitude_px":0.5,"cloth_seconds":8.055365778435367,
                           "cloth_amplitude_px":4.0,"ship_phase_radians":0.0,"cloth_phase_radians":0.0},
        "movement_limits":{"airship_body":{"interior_deformation_px":0.5,"silhouette_displacement_px":0.0},
                           "school_flag":{"tip_deformation_px":4},"dock_banner":{"tip_deformation_px":4}},
        "release_note":"Native 8K SDR derivative rebuilt from original PQ HDR with BT.2390 and perceptual gamut mapping. Native-detail framing at 1440p; complete original airship silhouette with safe interior motion.",
        "notes":["Original BT.2020/PQ HDR preserved externally; game uses full-resolution, perceptually tone-mapped sRGB SDR tiles, not native HDR output.",
                 "Airship terrain is original RGB, without generated replacement geometry or whole-subject drift.",
                 "Motion mask is inset at least 6 world pixels; deformation is limited to 0.5 world pixels.",
                 "Original stage IDs, CPU hit masks and world coordinates remain unchanged."],
    })
    write_json(layout_path,layout)
    # 完整制作直接从权威世界轮廓生成原生密度hover，不再放大旧包络图；修色分支已提前返回。
    build_hover(args.root)
    print(json.dumps({"tiles":len(tiles),"airship_mode":"original silhouette, interior-only deformation", "world_size":layout["original_size"]}))


if __name__ == "__main__":
    main()
