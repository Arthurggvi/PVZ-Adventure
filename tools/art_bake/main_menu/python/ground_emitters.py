"""可复用确定性构建器；输入为工作目录，导入模块不执行任何文件操作。"""
from pathlib import Path
import hashlib,json
import numpy as np
import cv2
from PIL import Image,ImageDraw

def build(workspace: Path) -> None:
    R=Path(workspace)
    C=json.loads((R/'config/finish_config.json').read_text(encoding='utf-8'))
    S=json.loads((R/'config/scene_config.json').read_text(encoding='utf-8'))
    assert hashlib.sha256((R/'master_original.png').read_bytes()).hexdigest()==C['source_sha256']
    raw=np.asarray(Image.open(R/'working_base.png').convert('RGB'));rgb=raw.astype(np.float32)/255
    H,W=rgb.shape[:2];assert [W,H]==C['canvas'];Y,X=np.mgrid[:H,:W]
    M=R/'finish_maps';M.mkdir(exist_ok=True)

    def save(name,v):Image.fromarray(np.uint8(np.clip(v,0,1)*255+.5)).save(M/(name+'.png'))
    def mapfile(name):return np.asarray(Image.open(R/'maps'/f'{name}.png')).astype(np.float32)/255

    def polygon(points):
        im=Image.new('L',(W*3,H*3));ImageDraw.Draw(im).polygon([(x*3,y*3) for x,y in points],fill=255)
        return np.asarray(im.resize((W,H),Image.Resampling.LANCZOS)).astype(np.float32)/255

    def feather(mask,width):
        if width<=0:return mask
        d=cv2.distanceTransform((mask>.5).astype(np.uint8),cv2.DIST_L2,5)
        t=np.clip(d/width,0,1);return t*t*(3-2*t)

    vegetation=mapfile('vegetation');sky=mapfile('sky');water=mapfile('water')
    objects=np.zeros((H,W),np.float32)
    for name in {s['group'] for s in S['surfaces']} - {'terrain'}:objects=np.maximum(objects,mapfile('region_'+name))
    g=C['ground'];allowed=feather(polygon(g['allowed_polygon']),g['edge_feather'])
    allowed*=np.clip(1-vegetation*g['vegetation_rejection'],0,1)*(1-objects)
    allowed[allowed<1/255]=0
    # Catmull-Rom 只控制现有地表的宽缓色值，不增加砖块或道具。
    def ribbon(path):
        points=np.asarray(path['points'],np.float32);widths=path['widths'];pts=np.vstack([points[0],points,points[-1]])
        canvas=np.zeros((H,W),np.float32)
        for i in range(len(points)-1):
            p0,p1,p2,p3=pts[i:i+4]
            for t in np.linspace(0,1,24):
                q=.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
                radius=(widths[i]*(1-t)+widths[i+1]*t)*.5
                cv2.circle(canvas,(round(float(q[0])),round(float(q[1]))),round(radius),1,-1,cv2.LINE_AA)
        return cv2.GaussianBlur(canvas,(0,0),g['route_blur'])
    routes=np.zeros((H,W),np.float32)
    for path in g['routes']:routes=np.maximum(routes,ribbon(path))
    routes*=allowed
    plaza=feather(polygon(g['central_plaza']['polygon']),g['central_plaza']['feather'])*allowed
    forecourt=np.zeros_like(routes);tint=np.zeros_like(rgb)
    for area in g['forecourts']:
        m=feather(polygon(area['polygon']),area['feather'])*allowed
        forecourt=np.maximum(forecourt,m);tint+=m[:,:,None]*np.asarray(area['tint'],np.float32)
    low=cv2.GaussianBlur(rgb,(0,0),g['detail_sigma']);detail=rgb-low
    retention=1-routes*(1-g['route_detail_retention'])
    retention*=1-plaza*(1-g['central_plaza']['detail_retention'])
    result=low+detail*retention[:,:,None]
    result+=routes[:,:,None]*np.asarray(g['route_color_lift'])
    result+=plaza[:,:,None]*np.asarray(g['central_plaza']['tint'])+tint
    # 区域外逐像素保留；没有把低通滤波扩散到建筑。
    finished=np.uint8(np.clip(result,0,1)*255+.5);finished[allowed==0]=raw[allowed==0]
    Image.fromarray(finished).save(R/'ground_finished.png')
    for name,m in [('ground_allowed',allowed),('ground_routes',routes),('ground_plaza',plaza),('ground_forecourts',forecourt)]:save(name,m)
    alpha=np.uint8(np.maximum.reduce([routes,plaza,forecourt])*255+.5)
    Image.fromarray(np.dstack([finished,alpha])).save(R/'ground_patch.png')
    # 窗灯与光晕仍沿用 S5；旧十二光斑不属于当前运行管线，直接删除其构建路径。
    L=C['lighting'];order=L['group_order']
    emission=np.zeros((H,W,4),np.float32);halos=emission.copy()
    base_groups=np.zeros((H,W),np.float32)
    for index,group in enumerate(order):
        src=mapfile('windows_'+group);params=L['groups'][group]
        base_groups=np.maximum(base_groups,src)
        emission[:,:,index]=src*params['emission_scale']
        halos[:,:,index]=cv2.GaussianBlur(src,(0,0),params['halo_sigma'])*params['halo_gain']*(1-src)
    halos*=1-sky[:,:,None];halos*=1-water[:,:,None]
    for a in [emission,halos]:a[a<1/255]=0
    save('local_emission',emission);save('source_halo',halos);save('base_group_emission',base_groups)
    for i,group in enumerate(order):
        save('emit_'+group,emission[:,:,i]);save('halo_'+group,halos[:,:,i])
    report={'source_sha256':C['source_sha256'],'ground_changed_pixels':int(np.any(finished!=raw,axis=-1).sum()),
     'ground_outside_allowed_max_delta':int(np.abs(finished.astype(int)-raw.astype(int))[allowed==0].max()),
     'ground_mean_abs_channel_delta':float(np.abs(finished.astype(int)-raw.astype(int))[allowed>.1].mean()),
     'local_groups':order,'receiver_source':'attenuation_config only',
     'method':'ground and emitters only; local receivers owned by the unified float attenuation stage',
     'generated_props':0,'global_image_displacement':False}
    assert report['ground_outside_allowed_max_delta']==0
    (R/'finish_build_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))
