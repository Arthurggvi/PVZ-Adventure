"""可复用确定性构建器；输入为工作目录，导入模块不执行任何文件操作。"""
from pathlib import Path
import hashlib,json
import numpy as np
import cv2
from PIL import Image,ImageDraw

def build(workspace: Path) -> None:
    R=Path(workspace)
    C=json.loads((R/'config/scene_config.json').read_text(encoding='utf-8'))
    source=R/'master_original.png'
    assert hashlib.sha256(source.read_bytes()).hexdigest()==C['source_sha256']
    original=np.asarray(Image.open(source).convert('RGB'));rgb=original.astype(np.float32)/255
    H,W=rgb.shape[:2];assert [W,H]==C['canvas'];S=C['supersampling']
    Y,X=np.mgrid[:H,:W];out=R/'maps';out.mkdir(exist_ok=True)

    def save(name,data):
        Image.fromarray(np.uint8(np.clip(data,0,1)*255+.5)).save(out/(name+'.png'))

    def shape(spec):
        image=Image.new('L',(W*S,H*S));draw=ImageDraw.Draw(image)
        if 'polygon' in spec:draw.polygon([(x*S,y*S) for x,y in spec['polygon']],fill=255)
        elif 'ellipse' in spec:draw.ellipse([v*S for v in spec['ellipse']],fill=255)
        else:raise ValueError('Unknown shape')
        return np.asarray(image.resize((W,H),Image.Resampling.LANCZOS)).astype(np.float32)/255

    def selector(name):
        entry=C['selectors'][name];terms=entry.get('all',[entry]);result=np.ones((H,W),np.float32)
        for term in terms:result*=np.clip(np.sum(rgb*np.array(term['dot']),axis=-1)*term['gain']+term['bias'],0,1)
        return result.astype(np.float32)

    def feather(mask,width):
        if not width:return mask
        t=np.minimum(cv2.distanceTransform((mask>.5).astype('uint8'),cv2.DIST_L2,5)/width,1)
        return t*t*(3-2*t)

    selected={name:selector(name) for name in C['selectors']}
    normal=np.broadcast_to(np.array(C['defaults']['normal'],np.float32),(H,W,3)).copy()
    weight=np.full((H,W),C['defaults']['normal_weight'],np.float32)
    exposure=np.full((H,W),C['defaults']['exposure'],np.float32)
    masks={};groups={};object_union=np.zeros((H,W),np.float32)
    for surface in C['surfaces']:
        m=shape(surface['shape'])
        if surface.get('exclude'):m*=1-selected[surface['exclude']]
        masks[surface['id']]=m
        group=surface['group'];groups[group]=np.maximum(groups.get(group,np.zeros_like(m)),m)
        if group!='terrain':object_union=np.maximum(object_union,m)
        if 'curve' in surface:
            p=surface['curve'];x0,y0,x1,y1=p['box']
            nx=(X-(x0+x1)/2)/((x1-x0)/2)*p['x_scale']
            ny=-(Y-(y0+y1)/2)/((y1-y0)/2)*p['y_scale']+p['y_bias']
            nz=np.sqrt(np.clip(1-nx*nx-ny*ny,p['z_min_squared'],1))
            n=np.stack([nx,ny,nz],axis=-1);n/=np.linalg.norm(n,axis=-1,keepdims=True)
        else:
            n=np.array(surface['normal'],np.float32);n/=np.linalg.norm(n)
        normal=normal*(1-m[:,:,None])+n*m[:,:,None]
        weight=weight*(1-m)+surface['weight']*m
        exposure=exposure*(1-m)+surface['exposure']*m
    A=C['atmosphere']
    sky=shape({'polygon':A['sky_polygon']})*selected['sky']*(1-object_union)
    water=shape({'polygon':A['water_polygon']})*selected['water']*(1-object_union)*(1-sky)
    far=shape({'polygon':A['distant_polygon']})*(1-object_union)*(1-water)*(1-sky)
    vegetation=cv2.GaussianBlur(selected['green'],(3,3),C['defaults']['green_blur'])*(1-sky)*(1-water)
    # 植被仅低频统一朝向；不让每片叶纹引入法线噪声。
    foliage_n=np.array(A['foliage_normal'],np.float32);foliage_n/=np.linalg.norm(foliage_n)
    normal=normal*(1-vegetation[:,:,None])+foliage_n*vegetation[:,:,None]
    weight=weight*(1-vegetation)+A['foliage_weight']*vegetation
    weight*=1-sky
    weight*=1-water*.82
    normal/=np.maximum(np.linalg.norm(normal,axis=-1,keepdims=True),1e-8)
    cloud=np.clip((np.sum(rgb*np.array([.2126,.7152,.0722]),axis=-1)-A['cloud_luma_start'])/A['cloud_luma_span'],0,1)
    # 灯窗和溢光分别累计，玻璃选择器只在已标注窗洞中使用。
    emission=np.zeros((H,W),np.float32);spill=emission.copy()
    window_groups={}
    for window in C['windows']:
        m=shape(window['shape'])*selected[window['selector']]*window['power']
        emission=np.maximum(emission,m)
        window_groups[window['group']]=np.maximum(window_groups.get(window['group'],np.zeros_like(m)),m)
        spill=np.maximum(spill,cv2.GaussianBlur(m,(0,0),window['blur'])*window['spill_gain'])
    for spot in C['spots']:
        cx,cy=spot['center'];rx,ry=spot['radius']
        field=np.exp(-(((X-cx)/rx)**2+((Y-cy)/ry)**2)*C['defaults']['ground_spot_exponent'])*spot['strength']
        spill=np.maximum(spill,field)
    spill*=1-emission;spill*=1-sky;spill*=1-water
    # 修整是可撤销派生底图；母图始终原样保留。
    gain=np.ones((H,W),np.float32)
    for repair in C['repairs']:
        m=masks[repair['surface']].copy() if 'surface' in repair else shape(repair['shape'])
        m=feather(m,repair.get('feather',0))
        if repair.get('selector'):m*=selected[repair['selector']]
        if 'bright_start' in repair:m*=np.clip((rgb.mean(-1)-repair['bright_start'])*repair['bright_gain'],0,1)
        gain+=m*repair['gain']
    working=np.uint8(np.clip(rgb*gain[:,:,None],0,1)*255+.5)
    Image.fromarray(working).save(R/'working_base.png')
    repair_weight=np.clip(np.abs(gain-1),0,1)
    for name,data in [('normal',normal*.5+.5),('structure',weight),('exposure',exposure),('emissive',emission),('spill',spill),('sky',sky),('water',water),('distant',far),('cloud',cloud*sky),('vegetation',vegetation),('repair_weight',repair_weight)]:save(name,data)
    save('controls',np.stack([weight,exposure,emission],-1))
    save('environment',np.stack([sky,water,far,cloud],-1))
    for name,data in groups.items():save('region_'+name,data)
    for name,data in window_groups.items():save('windows_'+name,data)
    # 语义总览只用于审阅，不进入游戏渲染。
    colors=[[.9,.4,.3],[.2,.8,.7],[.6,.5,1],[1,.7,.2],[.4,.8,.4],[.2,.6,1],[.8,.5,.7],[.8,.8,.4]]
    review=rgb.copy()
    for i,(name,m) in enumerate(groups.items()):
        if name=='terrain':continue
        a=m*.2;review=review*(1-a[:,:,None])+np.array(colors[i%len(colors)])*a[:,:,None]
    Image.fromarray(np.uint8(np.clip(review,0,1)*255+.5)).save(R/'region_review.png')
    report={'source_sha256':C['source_sha256'],'size':[W,H],'surfaces':len(C['surfaces']),'window_shapes':len(C['windows']),
     'groups':{k:int(np.count_nonzero(v>.1)) for k,v in groups.items()},'sky_pixels':int(np.count_nonzero(sky>.1)),
     'water_pixels':int(np.count_nonzero(water>.1)),'normal_unit_max_error':float(np.abs(np.linalg.norm(normal,axis=-1)-1).max()),
     'repair_gain_range':[float(gain.min()),float(gain.max())], 'source_unchanged':hashlib.sha256(source.read_bytes()).hexdigest()==C['source_sha256'],
     'method':'shared config-driven builder; authored low frequency surface normals; no generated variants or geometry reconstruction'}
    (R/'build_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))
