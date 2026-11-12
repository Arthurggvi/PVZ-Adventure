"""风动的原像素控制资产：保边树冠、固定边布料、船局部旗帜；导入不执行。"""
from pathlib import Path
import hashlib,json
import cv2
import numpy as np
from PIL import Image,ImageDraw
from .harbor_matte import Geometry,nearest_indices,decontaminate,dilate,erode
from .cloth_matte import alpha_from_source


def build(workspace: Path) -> None:
    root=Path(workspace);c=json.loads((root/'config/wind_layout.json').read_text(encoding='utf-8'))
    source=root/'master_original.png';assert hashlib.sha256(source.read_bytes()).hexdigest()==c['master_sha256']
    raw=np.asarray(Image.open(source).convert('RGB'));rgb=raw.astype(np.float32)/255
    h,w=raw.shape[:2];assert [w,h]==c['canvas'];y,x=np.mgrid[:h,:w]
    geom=Geometry(c['canvas']);out=root/'wind_assets';out.mkdir(exist_ok=True)
    def save(name,value):Image.fromarray(np.uint8(np.clip(value,0,1)*255+.5)).save(out/(name+'.png'))
    def floats(name,value):np.asarray(value,dtype='<f4').tofile(out/(name+'.rgba32f'))
    # 叶色通道只负责语义范围内的叶面，树干、建筑和外轮廓以硬保护距离排除。
    hsv=cv2.cvtColor(raw,cv2.COLOR_RGB2HSV);sel=c['leaf_selector']
    leaves=(hsv[:,:,0]>=sel['hsv_h_min'])&(hsv[:,:,0]<=sel['hsv_h_max'])&(hsv[:,:,1]>=sel['minimum_saturation'])
    leaves&=(rgb[:,:,1]-(rgb[:,:,0]+rgb[:,:,2])*.5)>sel['minimum_green_difference']
    canopy=[];protect=np.zeros((h,w),bool)
    for region in c['canopies']:
        mask=geom.polygon(region['polygon'])&leaves
        for polygon in region['exclude']:
            forbidden=geom.polygon(polygon);mask&=~forbidden;protect|=forbidden
        dist=cv2.distanceTransform(mask.astype(np.uint8),cv2.DIST_L2,5)
        t=np.clip((dist-region['safe_border_px'])/region['ramp_px'],0,1)
        weight=t*t*(3-2*t);canopy.append(weight)
        save('canopy_'+region['id'],weight)
    canopy_map=np.stack([canopy[0],canopy[1],np.zeros_like(canopy[0])],axis=-1)
    save('canopy_weights',canopy_map)
    # 遮阳棚：多边形约束trimap，用原图颜色分布在窄带内细化，蓝窗不作为布料。
    a=c['awning'];x0,y0,x1,y1=a['crop']
    alpha=alpha_from_source(raw,rgb,geom,a);seed=alpha>.5
    # 固定边斜线决定每个像素的垂直离墙距离；同一公式由shader使用。
    p0=np.array(a['anchor_start']);p1=np.array(a['anchor_end']);slope=(p1[1]-p0[1])/(p1[0]-p0[0])
    depth=y-(p0[1]+(x-p0[0])*slope)
    span=p1-p0;outward=np.array(a['outward_vector'])
    local_u=((x-p0[0])*outward[1]-(y-p0[1])*outward[0])/(span[0]*outward[1]-span[1]*outward[0])
    side=np.clip(local_u/a['side_anchor_uv'],0,1)*np.clip((1-local_u)/a['side_anchor_uv'],0,1)
    pin=(depth<=a['pin_band_px'])|(side<=0);protect|=pin&dilate(seed,3)
    weight=np.clip((depth-a['pin_band_px'])/(a['cloth_depth_px']-a['pin_band_px']),0,1)
    weight=weight*weight*(3-2*weight)
    safe_background=~dilate(alpha>.001,a['donor_guard_px']);dy,dx=nearest_indices(safe_background);under=rgb[dy,dx]
    decontaminated=decontaminate(rgb,alpha,under)
    # 只修补运动会露出的轮廓窄带；内部布面原像素仍被活动层完整覆盖。
    dist=cv2.distanceTransform((alpha>.001).astype(np.uint8),cv2.DIST_L2,5)
    band=dilate(alpha>.001,a['outside_band_px'])&(dist<a['allowed_displacement_px']+a['hole_margin'])&(~pin)
    # 背景是带竖直窗框的平面；最近二维像素会把窗框拉成分叉，保持x列只向下取已见背景。
    plate_y=y.copy();plate_x=x.copy()
    for column in range(x0,x1):
        covered=np.flatnonzero(alpha[:,column]>.001)
        if covered.size:
            donor=min(h-1,int(covered[-1])+a['donor_guard_px'])
            plate_y[band[:,column],column]=donor
    plate=raw.copy();plate[band]=raw[plate_y[band],plate_x[band]]
    Image.fromarray(plate).save(out/'awning_plate.png')
    guide=np.stack([(plate_x+.5)/w,(plate_y+.5)/h,band.astype(np.float32),np.ones_like(alpha)],-1)
    floats('awning_plate_uv',guide)
    iy,ix=nearest_indices(alpha>.98);edge=(alpha<.98)&(alpha>0)
    tx=x.copy();ty=y.copy();tx[edge]=ix[edge];ty[edge]=iy[edge]
    floats('awning_light_uv',np.stack([(tx+.5)/w,(ty+.5)/h,np.ones_like(alpha),np.ones_like(alpha)],-1))
    floats('awning_premult',np.dstack([decontaminated*alpha[:,:,None],alpha]))
    save('awning',np.dstack([decontaminated,alpha]));save('awning_alpha',alpha);save('awning_pin',pin*alpha)
    awning_support=dilate(alpha>0,round(a['allowed_displacement_px'])+3)&(~pin)
    save('awning_support',awning_support)
    # 船旗完全沿用已通过船体资产，旗杆固定；区域外不重新解释或重抠船身。
    f=c['flag'];flag=geom.polygon(f['polygon'])
    flag=dilate(flag,2)&(x>f['pole_protect_x'])
    boat=np.fromfile(root/'assets/boat_premult.rgba32f',dtype='<f4').reshape(h,w,4)
    flag_alpha=boat[:,:,3]*flag
    flag_rgb=boat[:,:,:3]*flag[:,:,None]
    floats('flag_premult',np.dstack([flag_rgb,flag_alpha]));save('flag_select',flag.astype(float))
    floats('boat_without_flag',boat*(1-flag[:,:,None])) # 在原像素上划分预乘分量，不能在采样后用硬开关相减。
    save('flag',np.dstack([flag_rgb/np.maximum(flag_alpha[:,:,None],.001),flag_alpha]))
    flag_support=dilate(flag_alpha>0,round(f['maximum_tip_px'])+5)
    save('flag_support',flag_support);save('protected_anchors',protect)
    whole=np.maximum.reduce([canopy[0]>0,canopy[1]>0,awning_support,flag_support])
    save('wind_support',whole)
    # 黑/灰/白底只显示原素材的透明边缘，不是重新生成美术。
    board=Image.new('RGB',((x1-x0)*3,y1-y0),(40,40,40))
    for i,tone in enumerate([.08,.50,.93]):
        im=decontaminated*alpha[:,:,None]+tone*(1-alpha[:,:,None])
        board.paste(Image.fromarray(np.uint8(np.clip(im,0,1)*255+.5)).crop(tuple(a['crop'])),(i*(x1-x0),0))
    board.resize((board.width*2,board.height*2)).save(root/'previews/awning_matte_review.png')
    report={'master_sha256':c['master_sha256'],'canopy_pixels':[int((m>0).sum()) for m in canopy],
     'awning_pixels':int((alpha>.1).sum()),'flag_pixels':int((flag_alpha>.1).sum()),'fixed_anchor_pixels':int(protect.sum()),
     'canopy_mode':'interior only; silhouette/trunk/building contacts pinned','boat_assets_modified':False,
     'premult_zero_alpha_rgb_zero':bool(np.all((decontaminated*alpha[:,:,None])[alpha==0]==0)),
     'awning_background':'narrow silhouette strip extended along original vertical window structure; no cross-column nearest RGB and no generated image',
     'source_unchanged':hashlib.sha256(source.read_bytes()).hexdigest()==c['master_sha256']}
    assert report['source_unchanged'] and report['premult_zero_alpha_rgb_zero']
    (root/'reports/wind_assets.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report),flush=True)
