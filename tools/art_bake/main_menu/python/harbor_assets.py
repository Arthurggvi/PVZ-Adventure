"""同一母图的必要拆层和局部水面补底；只用路径标注与既有水像素。"""
from pathlib import Path
import hashlib,json
import numpy as np
import cv2
from PIL import Image,ImageDraw


def build(workspace: Path) -> None:
    root=Path(workspace);config=json.loads((root/'config/harbor_layout.json').read_text(encoding='utf-8'))
    source=root/'master_original.png';assert hashlib.sha256(source.read_bytes()).hexdigest()==config['master_sha256']
    raw=np.asarray(Image.open(source).convert('RGB'));rgb=raw.astype(np.float32)/255
    height,width=raw.shape[:2];assert [width,height]==config['canvas'];scale=4
    target=root/'assets';target.mkdir(exist_ok=True)
    def polygon(points):
        image=Image.new('L',(width*scale,height*scale));draw=ImageDraw.Draw(image)
        draw.polygon([(round(x*scale),round(y*scale)) for x,y in points],fill=255)
        return np.asarray(image.resize((width,height),Image.Resampling.LANCZOS)).astype(np.float32)/255
    def stroke(entry):
        image=Image.new('L',(width*scale,height*scale));draw=ImageDraw.Draw(image)
        draw.line([(round(x*scale),round(y*scale)) for x,y in entry['points']],fill=255,width=round(entry['width']*scale),joint='curve')
        mask=np.asarray(image.resize((width,height),Image.Resampling.LANCZOS)).astype(np.float32)/255
        if entry.get('dark_only',False):
            mask*=np.clip((config['stroke_dark_threshold']-rgb.mean(-1))/config['stroke_dark_softness'],0,1)
        return mask
    def save(name,data):Image.fromarray(np.uint8(np.clip(data,0,1)*255+.5)).save(target/name)
    boat=np.zeros((height,width),np.float32);fixed=boat.copy()
    for points in config['boat_polygons']:boat=np.maximum(boat,polygon(points))
    for entry in config['boat_strokes']:boat=np.maximum(boat,stroke(entry))
    for points in config['fixed_polygons']:fixed=np.maximum(fixed,polygon(points))
    for entry in config['fixed_strokes']:fixed=np.maximum(fixed,stroke(entry))
    old_contact=np.zeros_like(boat)
    for entry in config['old_contact_strokes']:old_contact=np.maximum(old_contact,stroke(entry))
    key=config['water_color_key']
    water_color=np.clip((rgb[:,:,2]-rgb[:,:,0]-key['blue_minus_red'])/key['softness'],0,1)
    water_color*=np.clip((rgb[:,:,1]-rgb[:,:,0]-key['green_minus_red'])/key['softness'],0,1)
    # 上部索具/横杆在限定轮廓内按海水颜色剔底；原画窗户不受此筛选。
    upper=np.zeros_like(boat)
    for points in config['upper_capture_polygons']:upper=np.maximum(upper,polygon(points))
    for entry in config['boat_strokes']:
        if entry.get('dark_only'):upper=np.maximum(upper,stroke(dict(entry,dark_only=False)))
    upper*=polygon(config['upper_silhouette_roi'])*(1-water_color)
    boat=np.maximum(boat,upper)
    # 拒绝顶部粗标注带入的海水碎片。
    boat[:config['upper_color_key_max_y']]*=(1-water_color[:config['upper_color_key_max_y']])
    rigging=np.zeros_like(boat)
    for entry in config['boat_strokes']:
        if entry.get('dark_only'):rigging=np.maximum(rigging,stroke(dict(entry,dark_only=False)))
    rigging*=np.clip((config['rigging_luma_edge']-rgb.mean(-1))*config['rigging_luma_scale'],0,1)
    boat=np.maximum(boat,rigging)
    water_region=polygon(config['water_polygon'])
    approved_water=np.asarray(Image.open(root/'maps/water.png')).astype(np.float32)/255
    water=water_region*water_color*(1-fixed)*approved_water
    hole=np.maximum(boat,old_contact*(1-fixed))>.02
    hole=cv2.dilate(hole.astype(np.uint8),np.ones((3,3),np.uint8))>0
    hole&=fixed<.5
    avoid=cv2.dilate((boat>.01).astype(np.uint8),np.ones((config['donor_exclusion_radius']*2+1,)*2,np.uint8))>0
    donors=(water>.75)&(~avoid)&(old_contact<.01)&(fixed<.01)
    assert np.count_nonzero(donors)>1000,'Insufficient water donors'
    # 最近的真实水面像素映射；用于小幅运动露出的窄条，不能称为完整隐藏背景复原。
    _,labels=cv2.distanceTransformWithLabels((~donors).astype(np.uint8),cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
    coords=np.argwhere(donors)
    indices=np.clip(labels-1,0,len(coords)-1)
    nearest=coords[indices]
    yy,xx=np.mgrid[:height,:width]
    sx=np.where(hole,nearest[:,:,1],xx);sy=np.where(hole,nearest[:,:,0],yy)
    lookup=np.stack([(sx+.5)/width,(sy+.5)/height,hole.astype(np.float32),np.ones_like(boat)],axis=-1).astype('<f4')
    lookup.tofile(target/'clean_lookup.rgba32f')
    clean=raw[sy,sx];clean[~hole]=raw[~hole]
    Image.fromarray(clean).save(target/'clean_plate.png')
    # 用固定边界内缩的水域权重，不让岸线、码头与建筑参与扭动。
    water_with_hole=np.maximum(water,hole.astype(np.float32))*water_region*(1-fixed)
    distance=cv2.distanceTransform((water_with_hole>.5).astype(np.uint8),cv2.DIST_L2,5)
    interior=np.clip(distance/config['water_edge_fade_px'],0,1)
    interior=interior*interior*(3-2*interior)
    masks=np.stack([boat,fixed,interior,hole],axis=-1)
    save('harbor_masks.png',masks);save('boat_alpha.png',boat);save('fixed_alpha.png',fixed);save('water_weight.png',interior)
    # 前景立柱后面缺失的船身，只补有限小位移可能露出的部分。
    hidden=(boat>.02)&(fixed>.02)
    hull_donors=(boat>.98)&(fixed<.001)
    _,ship_labels=cv2.distanceTransformWithLabels((~hull_donors).astype(np.uint8),cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
    ship_coords=np.argwhere(hull_donors);near_ship=ship_coords[np.clip(ship_labels-1,0,len(ship_coords)-1)]
    tx=np.where(hidden,near_ship[:,:,1],xx);ty=np.where(hidden,near_ship[:,:,0],yy)
    # 优先同一行的船身颜色，减少跨过舷窗/船舷取样。
    for row in np.flatnonzero(np.any(hidden,axis=1)):
        donor_x=np.flatnonzero(hull_donors[row]);wanted=np.flatnonzero(hidden[row])
        if donor_x.size:
            nearest_x=donor_x[np.abs(donor_x[:,None]-wanted[None,:]).argmin(axis=0)]
            tx[row,wanted]=nearest_x;ty[row,wanted]=row
    ship_lookup=np.stack([(tx+.5)/width,(ty+.5)/height,hidden.astype(np.float32),np.ones_like(boat)],axis=-1).astype('<f4')
    ship_lookup.tofile(target/'boat_lookup.rgba32f')
    boat_rgb=raw[ty,tx]
    Image.fromarray(np.dstack([boat_rgb,np.uint8(boat*255+.5)])).save(target/'boat.png')
    Image.fromarray(np.dstack([raw,np.uint8(fixed*255+.5)])).save(target/'dock_foreground.png')
    margin=config['envelope_pixels']
    support=np.maximum(interior,cv2.dilate((boat>.001).astype(np.uint8),np.ones((2*margin+1,)*2,np.uint8)))
    save('motion_support.png',support)
    reconstruction=clean.astype(float)*(1-boat[:,:,None])+raw.astype(float)*boat[:,:,None]
    reconstruction=reconstruction*(1-fixed[:,:,None])+raw.astype(float)*fixed[:,:,None]
    Image.fromarray(np.uint8(np.clip(reconstruction,0,255))).save(target/'reconstruction_review.png')
    crop=tuple(config['crop']);montage=Image.new('RGB',((crop[2]-crop[0])*3,crop[3]-crop[1]),(80,88,96))
    for index,array in enumerate([clean,np.uint8(boat_rgb*boat[:,:,None]),np.uint8(raw*fixed[:,:,None])]):
        montage.paste(Image.fromarray(array).crop(crop),(index*(crop[2]-crop[0]),0))
    montage.resize((montage.width*2,montage.height*2)).save(root/'previews/layer_review.png')
    report={'source_sha256':config['master_sha256'],'boat_alpha_pixels':int((boat>.1).sum()),'fixed_pixels':int((fixed>.1).sum()),
      'patched_pixels':int(hole.sum()),'donor_method':'nearest approved-water pixels; live relighting sampled through UV lookup',
      'clean_outside_hole_exact':bool(np.array_equal(clean[~hole],raw[~hole])),
      'lookup_size_bytes':(target/'clean_lookup.rgba32f').stat().st_size,'motion_envelope_px':margin,
      'limitations':'Small-motion background completion only; rigid mooring line end remains occluded, no rope physics.'}
    assert report['clean_outside_hole_exact']
    (root/'reports/harbor_assets.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report),flush=True)
