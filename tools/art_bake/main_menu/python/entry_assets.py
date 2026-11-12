"""建筑入口独立可见蒙版；点击轮廓另存配置，不从明暗或透明纹理猜测功能。"""
from pathlib import Path
import json,hashlib
import cv2
import numpy as np
from PIL import Image,ImageDraw


def build(workspace: Path) -> None:
    root=Path(workspace) # 唯一资产工作目录。
    config=json.loads((root/'config/entries.json').read_text(encoding='utf-8')) # 入口配置。
    raw=np.asarray(Image.open(root/'master_original.png').convert('RGB')) # 已批准原像素。
    rgb=raw.astype(np.float32)/255 # 只用于排除遮挡的植物颜色。
    width,height=config['canvas'];out=root/'entry_assets';out.mkdir(exist_ok=True)
    def polygon(points):
        image=Image.new('L',(width*4,height*4)) # 四倍采样抗锯齿。
        ImageDraw.Draw(image).polygon([(round(x*4),round(y*4)) for x,y in points],fill=255)
        return np.asarray(image.resize((width,height),Image.Resampling.LANCZOS)).astype(np.float32)/255
    green=np.clip((rgb[:,:,1]-rgb[:,:,0]*.88-rgb[:,:,2]*.13)*14+.4,0,1) # 和现有材质一致的受限叶色判别。
    report={} # 记录各入口支持像素；不是视觉合格的替代证明。
    review=raw.copy();draw_image=Image.fromarray(review);draw=ImageDraw.Draw(draw_image)
    for entry in config['entries']:
        mask=np.zeros((height,width),np.float32) # 每个建筑单独蒙版，避免通道串色。
        for points in entry['shape']:mask=np.maximum(mask,polygon(points))
        if entry['exclude_green']:mask*=1-green
        for points in entry['exclude']:mask*=1-polygon(points)
        if entry.get('include_boat'):
            boat=np.asarray(Image.open(root/'assets/boat_alpha.png')).astype(np.float32)/255 # 沿用通过的精细船部件。
            fixed=np.asarray(Image.open(root/'assets/fixed_alpha.png')).astype(np.float32)/255
            mask=np.maximum.reduce([mask,boat,fixed])
        # 内部细碎纹理不是轮廓；保留可见遮挡，但不对纹理逐像素描边。
        edge_seed=cv2.GaussianBlur(mask,(0,0),.7)
        mask=np.minimum(mask,np.clip(edge_seed*1.18,0,1))
        width_gate=int(config['style']['outline_min_width_px']) # 细索具保留轻度填色，不形成闪亮描边。
        broad=cv2.morphologyEx((mask>.5).astype(np.uint8),cv2.MORPH_OPEN,np.ones((width_gate,width_gate),np.uint8))
        thin_fill=float(entry.get('thin_structure_fill',1.0)) # 配置决定细结构是否接受整体提亮，不改变实际物体像素。
        assert 0.0<=thin_fill<=1.0
        width_support=cv2.GaussianBlur(broad.astype(np.float32),(0,0),.8) # 宽物体边界平滑保留，孤立索具不被加成亮线。
        mask*=thin_fill+(1.0-thin_fill)*width_support
        distance=cv2.distanceTransform(broad,cv2.DIST_L2,5)
        rim=np.clip(1-distance/(float(config['style']['inner_edge_width_px'])+1),0,1)*(distance>0)*mask
        packed=np.stack([mask,rim,np.zeros_like(mask)],axis=-1)
        Image.fromarray(np.uint8(np.clip(packed,0,1)*255+.5)).save(out/(entry['id']+'.png'))
        Image.fromarray(np.uint8(np.clip(mask,0,1)*255+.5)).save(out/(entry['id']+'_alpha.png'))
        for points in entry['hit']:draw.line([tuple(p) for p in points+[points[0]]],fill=(245,210,105),width=3)
        report[entry['id']]={'feature':entry['feature'],'mask_pixels':int((mask>.01).sum()),'stable_hit_polygons':len(entry['hit'])}
    draw_image.save(root/'previews/entry_hit_review.png')
    (root/'reports/entry_assets.json').write_text(json.dumps({'source_sha256':hashlib.sha256((root/'master_original.png').read_bytes()).hexdigest(),'entries':report,'mask_and_hit_are_distinct':True},indent=2),encoding='utf-8')
    print('ENTRY_MASKS_READY',json.dumps(report),flush=True)
