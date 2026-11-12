"""可复用确定性构建器；输入为工作目录，导入模块不执行任何文件操作。"""
from pathlib import Path
import hashlib,json
import numpy as np
import cv2
from PIL import Image,ImageDraw

def build(workspace: Path) -> None:
    R=Path(workspace)
    C=json.loads((R/'config/attenuation_config.json').read_text(encoding='utf-8'))
    S=json.loads((R/'config/scene_config.json').read_text(encoding='utf-8'))
    assert hashlib.sha256((R/'master_original.png').read_bytes()).hexdigest()==C['source_sha256']
    W,H=C['canvas'];Y,X=np.mgrid[:H,:W].astype(np.float32)
    OUT=R/'attenuation_maps';OUT.mkdir(exist_ok=True)

    def polygon(points):
        im=Image.new('L',(W*3,H*3));ImageDraw.Draw(im).polygon([(x*3,y*3) for x,y in points],fill=255)
        return np.asarray(im.resize((W,H),Image.Resampling.LANCZOS)).astype(np.float32)/255

    def shape(spec):
        if 'polygon' in spec:return polygon(spec['polygon'])
        im=Image.new('L',(W*3,H*3));ImageDraw.Draw(im).ellipse([v*3 for v in spec['ellipse']],fill=255)
        return np.asarray(im.resize((W,H),Image.Resampling.LANCZOS)).astype(np.float32)/255

    def mapfile(name):return np.asarray(Image.open(R/'maps'/f'{name}.png')).astype(np.float32)/255

    def preview(name,data):
        Image.fromarray(np.uint8(np.clip(data,0,1)*255+.5)).save(OUT/(name+'.png'))

    surfaces={p['id']:shape(p['shape']) for p in S['surfaces']}
    solid=np.zeros((H,W),np.float32)
    for surface in S['surfaces']:
        if surface['group']!='terrain':solid=np.maximum(solid,surfaces[surface['id']])
    # 接收范围是全局可见地表与物体边界，不代表某盏灯的照明半径。
    ground=polygon(C['ground_polygon'])*(1-solid)*(1-mapfile('sky'))*(1-mapfile('water'))
    normal=mapfile('normal')*2-1;normal/=np.maximum(np.linalg.norm(normal,axis=-1,keepdims=True),1e-8)
    ground_normal=np.array(C['ground_normal'],np.float32);ground_normal/=np.linalg.norm(ground_normal)
    emissive=mapfile('emissive')
    field=np.zeros((H,W,4),np.float32)
    source_reports=[]
    for light in C['lights']:
        sx,sy,sz=light['position'];range2=light['range']**2
        vector=np.stack([sx-X,Y-sy,np.full_like(X,sz)],axis=-1)
        distance2=np.sum(vector*vector,axis=-1)
        direction=vector/np.sqrt(np.maximum(distance2,1e-8))[:,:,None]
        # 有限软核心只避免近点奇异值；远场按平方反比，范围边缘光值与斜率平滑归零。
        window=np.maximum(1-(distance2/range2)**2,0)
        attenuation=light['intensity']*window*window/(distance2+C['core_radius']**2)
        wall=np.zeros((H,W),np.float32)
        for name in light['surfaces']:wall=np.maximum(wall,surfaces[name])
        wall=cv2.GaussianBlur(wall,(0,0),C['surface_mask_blur'])
        floor=ground*(1-wall) if light['ground'] else np.zeros_like(wall)
        wall_cos=np.maximum(np.sum(normal*direction,axis=-1),0)
        ground_cos=np.maximum(np.sum(ground_normal*direction,axis=-1),0)
        contribution=attenuation*(wall*wall_cos+floor*ground_cos)*(1-emissive)
        field[:,:,C['group_order'].index(light['group'])]+=contribution
        source_reports.append({'id':light['id'],'peak_contribution':float(contribution.max()),'range':light['range']})
    assert np.isfinite(field).all() and (field>=0).all()
    # 不截顶、不剪掉弱光尾部；运行时读取这一份线性浮点场。
    raw=OUT/'receivers.rgba32f';field.astype('<f4').tofile(raw)
    assert np.array_equal(np.fromfile(raw,dtype='<f4').reshape(H,W,4),field)
    maximum=float(field.max());scale=max(1.0,float(np.ceil(maximum)))
    preview('receivers_preview',field/scale)
    preview('ground_receiver',ground)
    for index,name in enumerate(C['group_order']):preview('receive_'+name,field[:,:,index]/scale)
    # 采样固定的解析距离曲线，仅用于记录衰减函数；未新增或运行测试套件。
    curve=[]
    for f in [0,.25,.5,.75,.9,.99,1,1.1]:
        d=f*300;v=max(1-(d/300)**4,0)**2/(d*d+C['core_radius']**2)
        curve.append({'distance_over_range':f,'unit_intensity_attenuation':v})
    report={'formula':C['formula'],'source_sha256':C['source_sha256'],'size':[W,H],
     'lights':source_reports,'light_count':len(C['lights']),'data_format':'little-endian float32 H,W,RGBA; no color transform',
     'field_maximum':maximum,'pixels_above_one':int(np.any(field>1,axis=-1).sum()),'field_clamped':False,
     'normalized_preview_scale':scale,'float_readback_exact':True,'float_file_bytes':raw.stat().st_size,
     'normal_response':'max(N dot L,0); no direct light floor','per_light_ground_cutout':False,
     'ground_material_rejection':False,'unit_curve':curve,
     'limitations':'Fixed-view proxy source positions and existing surface normals; no full 3D geometry or dynamic shadows.'}
    (R/'attenuation_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({'lights':len(C['lights']),'maximum':maximum,'float_roundtrip_exact':True,'preview_scale':scale,'pixels_over_1':report['pixels_above_one']}))
