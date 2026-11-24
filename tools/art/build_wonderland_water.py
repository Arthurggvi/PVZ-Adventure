"""校准水岸安全带与世界流场；仅生成技术纹理，不重绘用户底图。"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw


def smooth(value):
    value = np.clip(value, 0, 1)
    return value * value * (3 - 2 * value)


def refresh_color_shore(root):
    """复用完整湿域；R保留既有位移保护，G为体色覆盖，B为0至64世界单位岸距。"""
    out = root / "masks/water/runtime"
    path = out / "ocean_mask.png"
    movement = np.asarray(Image.open(path).convert("RGB"))[:, :, 0].copy()
    flow = np.asarray(Image.open(out / "water_flow_field_rgba.png"))
    wet = flow[:, :, 2] > 0
    distance = cv2.distanceTransform(wet.astype(np.uint8), cv2.DIST_L2, 5)
    # B速度通道保留完整湿域及海河份额，不能从内缩后的运动蒙版反推实际岸边。
    ocean_speed = round(.72 * 255)
    ownership = np.clip((255.0 - flow[:, :, 2].astype(np.float32)) / (255 - ocean_speed), 0, 1)
    coverage = smooth((distance - .5) / 1.5) * ownership * wet
    packed = np.stack((movement, np.rint(coverage * 255).astype(np.uint8),
                       np.rint(np.clip(distance / 64.0, 0, 1) * 255).astype(np.uint8)), axis=-1)
    Image.fromarray(packed).save(path)
    print(json.dumps({"color_shore_channels": "R movement; G wet ocean coverage; B shore distance / 64",
                      "movement_channel_preserved": bool(np.array_equal(movement, packed[:, :, 0])),
                      "color_pixels": int(np.count_nonzero(packed[:, :, 1])),
                      "mask_bytes": path.stat().st_size}))


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--preview", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--refresh-color-shore", action="store_true", help="只更新海洋体色岸距通道，保留既有位移蒙版和流场")
    args = parser.parse_args()
    root = args.root / "assets/adventure/wonderland"
    if args.refresh_color_shore:
        refresh_color_shore(root)
        return
    if args.source is None:
        parser.error("--source is required unless --refresh-color-shore is used")
    out = root / "masks/water/runtime"
    out.mkdir(parents=True, exist_ok=True)
    rgb = Image.open(args.source).convert("RGB").resize((1774, 887), Image.Resampling.LANCZOS)
    colors = np.asarray(rgb).astype(np.float32)
    old_ocean = np.asarray(Image.open(root / "masks/water/ocean_mask.png")) > 127
    old_river = np.asarray(Image.open(root / "masks/water/river_mask.png")) > 127

    # 中心线只限制搜索区域和指示下游方向，实际水岸仍由原图颜色与旧精确蒙版确定。
    line = np.array([(723,194),(695,207),(709,225),(727,236),(713,247),(655,258),
                     (618,266),(616,286),(600,298),(564,314),(551,326),(558,343),
                     (591,359),(611,379),(618,391),(598,406),(572,420),(559,438),
                     (558,454),(550,485),(526,503),(478,517),(421,531),(383,548),
                     (358,565),(354,581),(374,596),(400,607),(409,624),(408,640),
                     (393,656),(373,665),(338,676)], dtype=np.float32)
    corridor = Image.new("L", (1774,887))
    draw = ImageDraw.Draw(corridor)
    for index in range(len(line)-1):
        width = 28 if index < 15 else 50
        draw.line([tuple(line[index]),tuple(line[index+1])], fill=255, width=width)
        x,y = line[index]
        draw.ellipse((x-width/2,y-width/2,x+width/2,y+width/2), fill=255)
    blue = (colors[:,:,2]-colors[:,:,0]>9) & (colors[:,:,1]-colors[:,:,0]>6) & (colors[:,:,2]>=colors[:,:,1]-18)
    river = (blue & (np.asarray(corridor)>0)) | old_river
    # 小孔填补保留水中亮纹；桥面与岩石的大面积非水域仍作为静止障碍。
    river = cv2.morphologyEx(river.astype(np.uint8),cv2.MORPH_CLOSE,np.ones((3,3),np.uint8)) > 0
    ocean = old_ocean & (blue | (cv2.erode(old_ocean.astype(np.uint8),np.ones((7,7),np.uint8))>0))
    water = ocean | river
    distance = cv2.distanceTransform(water.astype(np.uint8),cv2.DIST_L2,5)
    # 非零位移至少离可见边界2.5世界单位；体色使用独立湿域和岸距，不套用此安全留白。
    safety = smooth((distance-2.5)/4.5)
    yy,xx = np.indices((887,1774),dtype=np.float32)
    points = np.column_stack((xx[water],yy[water]))
    best = np.full(len(points),np.inf,dtype=np.float32)
    direction = np.zeros((len(points),2),dtype=np.float32)
    remaining = np.zeros(len(points),dtype=np.float32)
    segments = np.diff(line,axis=0)
    lengths = np.linalg.norm(segments,axis=1)
    suffix = np.cumsum(lengths[::-1])[::-1]
    for index,segment in enumerate(segments):
        offset = points-line[index]
        parameter = np.clip((offset @ segment)/(lengths[index]**2),0,1)
        closest = line[index]+parameter[:,None]*segment
        squared = np.sum((points-closest)**2,axis=1)
        take = squared<best
        best[take] = squared[take]
        direction[take] = segment/lengths[index]
        remaining[take] = suffix[index]-parameter[take]*lengths[index]
    # 入海口使用总权重不超过1的平滑交接，避免海河边界出现硬线或双倍亮度。
    river_share = np.zeros((887,1774),dtype=np.float32)
    river_share[water] = smooth(remaining/65.0)
    river_share *= river.astype(np.float32)
    ocean_weight = safety*(1-river_share)
    river_weight = safety*river_share
    ocean_direction = np.stack((-(yy-760),xx-170),axis=-1)
    ocean_direction /= np.maximum(np.linalg.norm(ocean_direction,axis=-1,keepdims=True),1)
    ocean_direction = ocean_direction*.65+np.array([-.45,.72])
    ocean_direction /= np.maximum(np.linalg.norm(ocean_direction,axis=-1,keepdims=True),1e-4)
    river_direction = np.zeros_like(ocean_direction)
    river_direction[water] = direction
    vectors = ocean_direction*(1-river_share[:,:,None])+river_direction*river_share[:,:,None]
    vectors /= np.maximum(np.linalg.norm(vectors,axis=-1,keepdims=True),1e-4)
    flow = np.zeros((887,1774,4),dtype=np.uint8)
    flow[:,:,:2] = np.rint((vectors*.5+.5)*255).astype(np.uint8)
    flow[:,:,2] = np.rint(np.where(water,.72+.28*river_share,0)*255).astype(np.uint8)
    flow[:,:,3] = np.rint(safety*255).astype(np.uint8)
    masks = {"ocean":np.floor(ocean_weight*255).astype(np.uint8),"river":np.floor(river_weight*255).astype(np.uint8)}
    for name,mask in masks.items():
        Image.fromarray(mask).save(out/(name+"_mask.png"))
    Image.fromarray(flow).save(out/"water_flow_field_rgba.png")
    refresh_color_shore(root)
    path = root / "config/fx_regions.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    layout = json.loads((root / "config/art_layout.json").read_text(encoding="utf-8"))
    density = float(layout["terrain"]["pixels_per_world"])
    for name in ["ocean","river"]:
        entry = data["regions"][name]
        entry.update({"enabled":True,"mask":f"masks/water/runtime/{name}_mask.png",
                      "flow":"masks/water/runtime/water_flow_field_rgba.png",
                      "surface_state":"masks/water/runtime/water_state_atlas.exr",
                      "surface_state_info":{"frame_size":[384,360],"atlas_grid":[8,8],
                                            "frame_count":64,"padding":2,"origin_world":[0,168],
                                            "extent_world":[768,720],"slope_range":.45,"height_range":1.5},
                      "active_tiles":[]})
        for index,tile in enumerate(layout["terrain"]["tiles"]):
            x,y = tile["core_pixel_origin"]
            w,h = tile["core_pixel_size"]
            area = masks[name][max(0,int(y/density)-1):min(887,int(np.ceil((y+h)/density))+1),
                               max(0,int(x/density)-1):min(1774,int(np.ceil((x+w)/density))+1)]
            if np.any(area):
                entry["active_tiles"].append(index)
        entry["profile"] = {"water":{"pattern":"drift","period_seconds":18.0,
                                     "phase_radians":0.0,"transverse_ratio":.32,
                                     "shimmer_scale":[37.0,9.0,21.0]},
                            "amplitude_world":3.2 if name=="ocean" else 1.7,
                            "wavelength_world":[20.0,11.0] if name=="ocean" else [14.0,9.0],
                            "shimmer_strength":.045 if name=="ocean" else .032,
                            "aurora_strength":.38 if name=="ocean" else 0.0,
                            "spectral_strength":.42 if name=="ocean" else 0.0,
                            "dream_strength":.9 if name=="ocean" else 0.0,
                            "film_thickness_nm":520.0,
                            "aurora_scale_world":[90.0,38.0],"swirl_strength":.35 if name=="ocean" else 0.0,
                            "swirl_center_world":[170.0,760.0]}
    data["regions"]["ocean"]["display_name"] = "致幻洋流"
    data["water_data"] = {"resolution":[1774,887],"flow_channels":"RG direction encoded [0,1]; B speed weight; A shore safety",
                          "shore_guard_world":2.5,"shore_fade_world":4.5,"max_displacement_world":4.0,
                          "ownership":"ocean + river <= 1, shared shore distance and estuary crossfade"}
    data["implementation_status"] = "Ocean and river retain the existing explicit-clock shallow-water state atlas; ocean combines advected spectral gain, three-depth Beer-Lambert body color, caustics and shared-tint Fresnel/GGX reflection in one linear-light path, while dream_strength=0 preserves legacy water and other regions remain placeholders."
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    if args.preview:
        preview = colors*(1-safety[:,:,None]*.45)
        preview += np.array([235,55,175])*ocean_weight[:,:,None]*.45
        preview += np.array([45,255,165])*river_weight[:,:,None]*.45
        Image.fromarray(np.clip(preview,0,255).astype(np.uint8)).save(args.preview)
    print(json.dumps({"ocean_pixels":int(np.count_nonzero(masks['ocean'])),"river_pixels":int(np.count_nonzero(masks['river'])),
                      "minimum_guard":float(distance[(masks['ocean']>0)|(masks['river']>0)].min()),
                      "max_combined_mask":int((masks['ocean'].astype(np.int32)+masks['river']).max()),
                      "active_tiles":{n:data['regions'][n]['active_tiles'] for n in masks}}))


if __name__ == "__main__":
    main()
