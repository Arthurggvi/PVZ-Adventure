"""港口重做：通道软选区、去底色、预乘透明部件、连续补底与明确遮挡。"""
from pathlib import Path
import hashlib,json
import cv2
import numpy as np
from PIL import Image
from .harbor_matte import derive,decontaminate,dilate,erode,nearest_indices,blend_hidden


def build(workspace: Path) -> None:
    root=Path(workspace);c=json.loads((root/'config/harbor_layout.json').read_text(encoding='utf-8'))
    assert c['schema_version']==2,'Old polygon-only extraction is retired'
    source=root/'master_original.png'
    assert hashlib.sha256(source.read_bytes()).hexdigest()==c['master_sha256']
    raw=np.asarray(Image.open(source).convert('RGB'));rgb=raw.astype(np.float32)/255
    h,w=raw.shape[:2];y,x=np.mgrid[:h,:w];out=root/'assets';out.mkdir(exist_ok=True)
    part=derive(rgb,c);alpha=part['boat'];fixed=part['fixed'];geometry=part['geometry']
    hidden=part['hidden'];body=part['body'];chroma=part['chroma']
    def save(name,data):Image.fromarray(np.uint8(np.clip(data,0,1)*255+.5)).save(out/name)
    def floats(name,data):np.asarray(data,dtype='<f4').tofile(out/name)
    # 水域已在前阶段审查；色差只用于确定真实海水样本，不直接当整船透明度。
    old_water=np.asarray(Image.open(root/'maps/water.png')).astype(np.float32)/255
    donors=(chroma>c['channel']['water_chroma_min'])&(old_water>.1)&(~dilate((alpha>.01)|(fixed>.01),3))
    by,bx=nearest_indices(donors);background_sample=rgb[by,bx]
    foreground=decontaminate(rgb,alpha,background_sample)
    # 柱后窄带只用同一船身材质带克隆；不把邻近舷窗/柱子颜色拉成条纹。
    solid=(alpha>.95)&(~dilate(part['fixed_binary'],5))&body
    fy,fx=nearest_indices(solid)
    foreground[hidden]=rgb[fy,fx][hidden]
    ty=y.copy();tx=x.copy()
    for fill in c['hidden_fills']:
        x0,y0,x1,y1=fill['region'];area=np.zeros((h,w),bool);area[y0:y1,x0:x1]=True
        use=area&hidden;dx,dy=fill['offset']
        sx=np.clip(x+dx,0,w-1);sy=np.clip(y+dy,0,h-1)
        foreground[use]=rgb[sy[use],sx[use]];ty[use]=sy[use];tx[use]=sx[use]
    foreground=blend_hidden(foreground,hidden,alpha)
    # 边界受光从其所属物体内部继承，不使用掺了海色的原边界来算比值。
    safe=(alpha>.98)&(~hidden);ey,ex=nearest_indices(safe)
    edge=(alpha<.98)&(alpha>.001)&(~hidden);ty[edge]=ey[edge];tx[edge]=ex[edge]
    boat_uv=np.stack([(tx+.5)/w,(ty+.5)/h,np.ones_like(alpha),np.ones_like(alpha)],-1)
    boat_pm=np.dstack([foreground*alpha[:,:,None],alpha])
    floats('boat_premult.rgba32f',boat_pm);floats('boat_light_uv.rgba32f',boat_uv)
    save('boat.png',np.dstack([foreground,alpha]));save('boat_alpha.png',alpha)
    # 连续修补现有背景；只在待移走部件的狭窄区域内改像素，无生成模型。
    hole=dilate(alpha>.01,c['inpaint']['hole_margin'])&(fixed<.5)
    # 海水补底只接受海水样本，不能从柱子、船漆或木板向内扩散颜色。
    x0,y0,x1,y1=c['crop'];sea=raw.copy()
    sea[y0:y1,x0:x1]=cv2.inpaint(raw[y0:y1,x0:x1],(~donors[y0:y1,x0:x1]).astype(np.uint8)*255,c['inpaint']['radius'],cv2.INPAINT_TELEA)
    clean=raw.copy();clean[hole]=sea[hole]
    sample_x=bx.copy();sample_y=by.copy()
    for patch in c['background_clones']:
        area=geometry.polygon(patch['polygon'])&hole;dx,dy=patch['offset']
        px=np.clip(x+dx,0,w-1);py=np.clip(y+dy,0,h-1)
        # 从每行相邻的原码头边界反射取样，保持接缝颜色连续，避免复制一块远处灰石/柱子。
        for row in np.flatnonzero(np.any(area,axis=1)):
            target_x=np.flatnonzero(area[row]);first=int(target_x.min())
            known=np.flatnonzero((~hole[row,:first])&(fixed[row,:first]<.01))
            if known.size:
                anchor=int(known[-1]);px[row,target_x]=np.maximum(0,2*anchor-target_x)
                py[row,target_x]=row
        clean[area]=raw[py[area],px[area]];sample_x[area]=px[area];sample_y[area]=py[area]
    clean[~hole]=raw[~hole]
    save('clean_plate.png',clean.astype(np.float32)/255)
    # UV只传递同材质受光比值；连续颜色来自已清理的独立底层。
    clean_uv=np.stack([(sample_x+.5)/w,(sample_y+.5)/h,hole.astype(np.float32),np.ones_like(alpha)],-1)
    floats('clean_light_uv.rgba32f',clean_uv)
    # 前景柱与栏绳有自己的真实透明颜色，先清理背景混色再预乘。
    py,px=nearest_indices(fixed<.001);under=rgb[py,px]
    fixed_rgb=decontaminate(rgb,fixed,under)
    qy,qx=nearest_indices(fixed>.98);fixed_uv=np.stack([(qx+.5)/w,(qy+.5)/h,np.ones_like(alpha),np.ones_like(alpha)],-1)
    own=fixed>.98;fixed_uv[:,:,0][own]=(x[own]+.5)/w;fixed_uv[:,:,1][own]=(y[own]+.5)/h
    floats('fixed_premult.rgba32f',np.dstack([fixed_rgb*fixed[:,:,None],fixed]))
    floats('fixed_light_uv.rgba32f',fixed_uv);save('dock_foreground.png',np.dstack([fixed_rgb,fixed]));save('fixed_alpha.png',fixed)
    water=geometry.polygon(c['water_polygon'])*(old_water>.05)*(fixed<.01)
    water|=hole
    distance=cv2.distanceTransform(water.astype(np.uint8),cv2.DIST_L2,5)
    weight=np.clip(distance/c['water_edge_fade_px'],0,1);weight=weight*weight*(3-2*weight)
    save('water_weight.png',weight);save('harbor_masks.png',np.stack([alpha,fixed,weight,hole],-1))
    support=np.maximum(weight,dilate(alpha>.001,c['envelope_pixels']));support=np.maximum(support,fixed>0)
    save('motion_support.png',support)
    # 黑/白/灰底同时检查可见边缘；把边缘污染与单纯透明区分开。
    box=tuple(c['crop']);tilew=box[2]-box[0];tileh=box[3]-box[1]
    board=Image.new('RGB',(tilew*3,tileh))
    for i,tone in enumerate([.08,.5,.93]):
        view=foreground*alpha[:,:,None]+tone*(1-alpha[:,:,None])
        board.paste(Image.fromarray(np.uint8(np.clip(view,0,1)*255+.5)).crop(box),(i*tilew,0))
    board.resize((tilew*6,tileh*2)).save(root/'previews/matte_review.png')
    report={'master_sha256':c['master_sha256'],'method':'semantic trimap + chroma/luma + closed-body fill + source-over decontamination + premultiplied float RGBA',
     'foreground_ownership':c['ownership'],'boat_pixels':int((alpha>.1).sum()),'fixed_pixels':int((fixed>.1).sum()),
     'clean_outside_hole_exact':bool(np.array_equal(clean[~hole],raw[~hole])),
     'background_method':'bounded deterministic inpainting; actual existing pixels only; light UV carries transfer ratio, not nearest RGB',
     'hidden_repair_pixels':int((hidden&(alpha>.01)).sum()),'premultiplied_zero_alpha_rgb_zero':bool(np.all(boat_pm[alpha==0,:3]==0)),
     'runtime_float_textures':['boat_premult','boat_light_uv','fixed_premult','fixed_light_uv','clean_light_uv'],
     'note':'Boat interior wooden bollard moves with its deck; dock guard posts are separate fixed foreground. Fine-tether endpoint remains occluded by fixed post.'}
    assert report['clean_outside_hole_exact'] and report['premultiplied_zero_alpha_rgb_zero']
    (root/'reports/harbor_assets.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'channel_matte_built':True,'hidden_pixels':report['hidden_repair_pixels'],'no_generated_images':True}),flush=True)
