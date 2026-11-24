"""由世界几何、静态原图和原有技术分布构建局部动效数据；不重写底图/水面。"""
from pathlib import Path
import json
import math
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2] / 'assets/adventure/wonderland'
OUTPUT = ROOT / 'masks/runtime_fx'
WORLD = (1774, 887)
DENSITY = 8192 / 1774


def smooth(a, b, x):
    """连续有界的权重过渡。"""
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def low_source(layout):
    """仅逐块读取既有图块，拼一张世界密度分析图；不持有第二张8K源图。"""
    result = np.zeros((887, 1774, 3), np.uint8)
    for tile in layout['terrain']['tiles']:
        x, y = tile['core_pixel_origin']
        w, h = tile['core_pixel_size']
        ox, oy = tile['pixel_origin']
        left, top = round(x / DENSITY), round(y / DENSITY)
        right, bottom = round((x + w) / DENSITY), round((y + h) / DENSITY)
        with Image.open(ROOT / tile['path']) as bitmap:
            core = bitmap.crop((x - ox, y - oy, x - ox + w, y - oy + h))
            result[top:bottom, left:right] = np.asarray(core.resize((right-left, bottom-top), Image.Resampling.LANCZOS).convert('RGB'))
    return result.astype(np.float32) / 255


def field(bounds, density=1):
    """生成裁切纹理像素中心的世界坐标。"""
    x, y, w, h = bounds
    width, height = round(w*density), round(h*density)
    yy, xx = np.mgrid[:height, :width].astype(np.float32)
    return x+(xx+.5)*w/width, y+(yy+.5)*h/height


def sample(array, x, y):
    """世界分辨率技术图仅作分类/宽场，不冒充高清轮廓。"""
    return cv2.remap(array, x-.5, y-.5, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)


def polygon(points, bounds, density=1, feather=.8):
    """原生密度局部几何，羽化只向内部，避免污染对象边缘。"""
    x, y, w, h = bounds
    shape = np.zeros((round(h*density), round(w*density)), np.uint8)
    vertices = np.rint((np.array(points)-[x,y])*density*16).astype(np.int32)
    cv2.fillPoly(shape, [vertices], 1, shift=4)
    distance = cv2.distanceTransform(shape, cv2.DIST_L2, 5)/density
    return smooth(0, feather, distance)


def ellipse(x, y, cx, cy, rx, ry, feather=.25):
    """局部软分布，不用于孔口边缘定位。"""
    return 1-smooth(1-feather, 1, np.sqrt(((x-cx)/rx)**2+((y-cy)/ry)**2))


def protected(mask, world_margin, density=1):
    """内缩可动区，至少留出采样位移与双线性余量。"""
    binary = (mask>.15).astype(np.uint8)
    distance = cv2.distanceTransform(np.pad(binary, 1), cv2.DIST_L2, 5)[1:-1, 1:-1]/density
    return mask*smooth(world_margin, world_margin+1.5, distance)


def main():
    """写入局部技术数据和区域声明；已验收水域JSON原值逐项保留。"""
    OUTPUT.mkdir(parents=True, exist_ok=True)
    layout = json.loads((ROOT/'config/art_layout.json').read_text(encoding='utf-8'))
    config_path = ROOT/'config/fx_regions.json'
    config = json.loads(config_path.read_text(encoding='utf-8'))
    catalog = json.loads((ROOT/'config/landmarks.json').read_text(encoding='utf-8'))
    ids = np.asarray(Image.open(ROOT/catalog['hit_source'])).astype(np.float32)
    # 索引图可能使用RGB编码，当前红通道保存地区序号。
    if ids.ndim == 3:
        ids = ids[:,:,0]
    identity = {e['id']: i+1 for i,e in enumerate(catalog['landmarks'])}
    rgb = low_source(layout)
    green = smooth(.012,.07,rgb[:,:,1]-rgb[:,:,2]) * (1-smooth(.13,.25,rgb[:,:,0]-rgb[:,:,1]))
    brightness = rgb.mean(axis=2)
    gray = 1-smooth(.06,.17,np.max(rgb,axis=2)-np.min(rgb,axis=2))
    # 暗线与中性石块作为天气前景遮挡；特殊区域另有手绘排除多边形。
    ground = (1-gray*.85)*smooth(.14,.32,brightness)
    total_texels = 0
    records = {}

    def owned(name, x, y):
        return (sample(ids,x,y).round()==identity[name]).astype(np.float32)

    def save(key, kind, style, bounds, coverage, secondary=None, depth=None,
             density=1, profile=None, z=-70, event='', center=None, radii=None):
        nonlocal total_texels
        channels = [coverage, coverage if secondary is None else secondary,
                    np.zeros_like(coverage) if depth is None else depth, np.ones_like(coverage)]
        bitmap = np.rint(np.clip(np.stack(channels,axis=-1),0,1)*255).astype(np.uint8)
        path = OUTPUT/(key+'.png')
        Image.fromarray(bitmap).save(path)
        total_texels += bitmap.shape[0]*bitmap.shape[1]
        record = {'kind':kind,'enabled':True,'style':style,'mask':'masks/runtime_fx/'+key+'.png',
                  'bounds_world':bounds,'mask_origin_world':bounds[:2],'mask_extent_world':bounds[2:],
                  'mask_pixels':[bitmap.shape[1],bitmap.shape[0]],'z_index':z,
                  'profile':profile or {},'event':event}
        if center is not None:
            record['center_world']=center
            record['radii_world']=radii
        records[key]=record

    # 两处孔口按高清原画内孔描边，门框、台阶和炉壁留在R覆盖区以外。
    b=[1456,7,72,75]
    x,y=field(b,DENSITY)
    portal_points=[[1470,24],[1477,18],[1489,14],[1499,16],[1505,23],[1511,24],[1516,35],[1518,43],
                   [1518,51],[1514,59],[1510,63],[1507,62],[1506,68],[1500,69],[1498,74],
                   [1484,74],[1479,72],[1478,63],[1474,61],[1470,61],[1468,52],[1467,43],[1468,33]]
    inner=polygon(portal_points,b,DENSITY,.7)
    distance=cv2.distanceTransform((inner>.2).astype(np.uint8),cv2.DIST_L2,5)/DENSITY
    rim=inner*(1-smooth(.6,2.3,distance))
    save('edgar_portal','aperture','portal',b,inner,rim,density=DENSITY,
         profile={'period_seconds':6.,'amplitude_world':.65,'strength':.7},event='portal',center=[1493,44],radii=[25,30])
    b=[1552,560,58,63]
    x,y=field(b,DENSITY)
    points=[[1572,564],[1580,563],[1589,566],[1596,573],[1600,582],[1603,592],
            [1601,601],[1597,609],[1591,614],[1585,617],[1576,616],[1572,614],
            [1571,608],[1566,603],[1562,596],[1560,586],[1562,576],[1567,568]]
    inner=polygon(points,b,DENSITY,.7)
    distance=cv2.distanceTransform((inner>.2).astype(np.uint8),cv2.DIST_L2,5)/DENSITY
    save('furnace_core','aperture','furnace',b,inner,inner*(1-smooth(.7,3,distance)),density=DENSITY,
         profile={'period_seconds':12.,'amplitude_world':.35,'strength':.8},event='furnace',center=[1582,590],radii=[22,27])
    # 瀑布的狭长水带；岸石和崖缘不参加向下纹理输运。
    b=[704,130,62,66]
    x,y=field(b,DENSITY)
    upper=polygon([[739,137],[746,137],[753,141],[757,147],[758,153],[754,160],
                   [748,162],[744,158],[742,151],[741,144]],b,DENSITY,.7)
    lower=polygon([[730,166],[737,165],[746,165],[744,170],[738,173],[735,180],
                   [729,186],[724,188],[721,185],[724,178],[726,172]],b,DENSITY,.7)
    stream=np.maximum(upper,lower)
    save('waterfall','waterfall','fall',b,stream,stream,np.clip((y-136)/53,0,1),density=DENSITY,
         profile={'period_seconds':3.2,'amplitude_world':.5,'strength':.4})

    # 树冠优先分配重叠像素，并留出双线性边界，避免菇缘再次盖回静态原图。
    canopy_occupied = np.zeros((WORLD[1], WORLD[0]), np.uint8)
    # 草地内部权重由颜色与现有候选图共同限定，根部/道路/建筑安全内缩。
    for key,old,b,style,amplitude in [
        ('grass','grass_wind',[380,220,1030,450],'grass',.5),
        ('canopy','canopy_wind',[0,175,540,370],'canopy',.4),
        ('mushroom_rim','mushroom_rim_wind',[0,210,430,220],'mushroom',.18)]:
        x,y=field(b)
        oldmask=np.asarray(Image.open(ROOT/('masks/environment/'+old+'.png')).convert('L')).astype(np.float32)/255
        mask=sample(oldmask,x,y)
        if style!='mushroom':
            mask*=sample(green,x,y)
        mask*=owned('resting_plain' if style=='grass' else 'mushroom_forest',x,y)
        mask=protected(mask,2 if style!='mushroom' else .8)
        if style=='canopy':
            canopy_occupied[b[1]:b[1]+b[3],b[0]:b[0]+b[2]]=(mask>0).astype(np.uint8)
            canopy_occupied=cv2.dilate(canopy_occupied,np.ones((3,3),np.uint8))
        elif style=='mushroom':
            mask=protected(mask*(1-sample(canopy_occupied,x,y)),.8)
        # 菇柄/树干与区域下缘权重趋零，不移动巨大主体外轮廓。
        root_weight=.35+.65*(.5+.5*np.sin(x*.045+y*.03))
        save(key,'wind',style,b,mask,mask*root_weight,profile={'period_seconds':9.,'amplitude_world':amplitude,'strength':1.})
    b=[1040,210,240,145]
    x,y=field(b,2)
    mask=sample(green,x,y)*owned('garden_airship',x,y)
    mask*=np.maximum(ellipse(x,y,1156,260,112,44),ellipse(x,y,1070,310,26,33))
    mask=protected(mask,1.3,2)
    save('garden_foliage','wind','garden',b,mask,mask, density=2,z=9,
         profile={'period_seconds':8.,'amplitude_world':.35,'strength':1.})
    b=[558,624,333,118]
    x,y=field(b,2)
    mask=protected(sample(green,x,y)*owned('abandoned_school',x,y),1.3,2)
    save('school_grass','wind','grass',b,mask,mask,density=2,profile={'period_seconds':9.,'amplitude_world':.4,'strength':1.})

    # 宽场只在自身地区内部绘制；暖光与云影使用混合层，不盖回静态原图。
    b=[390,216,1045,570]
    x,y=field(b)
    mask=protected(owned('resting_plain',x,y)*sample(green,x,y),1.5)
    save('plain_light','atmosphere','sunset',b,mask,profile={'period_seconds':46.,'strength':.065})
    b=[1380,197,394,235]
    x,y=field(b,2)
    zone=owned('zombie_church',x,y)
    distance=cv2.distanceTransform((zone>.5).astype(np.uint8),cv2.DIST_L2,5)/2
    darkness=smooth(0,18,distance)*ellipse(x,y,1600,322,207,133,.35)
    save('church_darkness','atmosphere','darkness',b,darkness,density=2,z=20,
         profile={'period_seconds':60.,'strength':.9},event='church')
    b=[1586,289,17,28]
    x,y=field(b,DENSITY)
    light=polygon([[1592,294],[1595,292],[1598,296],[1598,310],[1591,310],[1591,300]],b,DENSITY,.6)
    save('church_window','atmosphere','window',b,light,density=DENSITY,z=21,
         profile={'period_seconds':12.,'strength':.06},event='church')

    def weather(key,landmark,b,style,count,strength,period,color,size,speed,low=False):
        x,y=field(b)
        mask=owned(landmark,x,y)
        if low:
            mask*=sample(ground,x,y)
        mask=protected(mask,1.2)
        background=mask*sample(smooth(.32,.62,brightness)*(1-green*.8),x,y) if style=='snow' else mask
        save(key,'particle',style,b,mask,background,profile={'period_seconds':period,'strength':strength,'count':count,
             'size_world':size,'speed_world':speed,'color':color},z=12)
        return mask,x,y

    weather('snow','snow_mountains',[0,0,766,273],'snow',96,.62,14,[.85,.93,1.],.38,10)
    weather('tundra_snow','frozen_tundra',[737,0,509,234],'ground_snow',32,.38,12,[.8,.88,.94],.32,8,True)
    weather('spores','mushroom_forest',[0,230,560,345],'spore',38,.48,14,[.81,.84,.54],.45,2.4,True)
    weather('dust','badlands',[900,400,874,487],'dust',26,.22,28,[.72,.57,.36],.65,5,True)
    weather('school_leaves','abandoned_school',[565,645,330,90],'leaf',5,.6,20,[.61,.39,.17],.85,6,True)
    weather('garden_petals','garden_airship',[1040,230,290,190],'petal',6,.65,17,[.96,.65,.57],.65,4,False)
    # 雾使用独立局部发射条带；结构遮挡由材质同一mask在片元端裁切。
    for key,landmark,b,style,strength in [
        ('forest_mist','mushroom_forest',[15,320,480,200],'mist',.085),
        ('tundra_mist','frozen_tundra',[760,40,460,185],'ice_mist',.075),
        ('badlands_haze','badlands',[930,490,810,390],'dust_mist',.06),
        ('church_mist','zombie_church',[1385,340,385,90],'mist',.07),
        ('ridge_snow','snow_mountains',[0,0,740,230],'ridge',.12)]:
        x,y=field(b)
        mask=owned(landmark,x,y)*sample(ground,x,y)
        if style=='ridge':
            mask=owned(landmark,x,y)*sample(smooth(.56,.8,brightness),x,y)
        mask=protected(mask,1.2)
        save(key,'atmosphere',style,b,mask,profile={'period_seconds':18.,'strength':strength},z=11)
    b=[714,154,49,42]
    x,y=field(b,2)
    foam=np.maximum(ellipse(x,y,750,162,10,4,.55),ellipse(x,y,729,188,10,4,.55))
    save('fall_mist','atmosphere','mist',b,foam,density=2,profile={'period_seconds':5.,'strength':.16},z=11)
    save('fall_spray','particle','spray',b,foam,density=2,z=12,
         profile={'period_seconds':3.2,'strength':.55,'count':12,'size_world':.28,'speed_world':4.,'color':[.76,.89,.95]})
    b=[1553,562,57,61]
    x,y=field(b,2)
    embers=polygon(points,b,2,.8)
    save('furnace_embers','particle','ember',b,embers,density=2,z=12,center=[1582,590],radii=[22,27],
         profile={'period_seconds':7.,'strength':.8,'count':8,'size_world':.5,'speed_world':2.,'color':[1.,.5,.12]})
    b=[1575,405,85,100]
    x,y=field(b)
    smoke=np.maximum(ellipse(x,y,1595,440,15,30),ellipse(x,y,1643,478,10,22))
    save('furnace_smoke','atmosphere','smoke',b,smoke,profile={'period_seconds':14.,'strength':.09},z=11)
    # 每次重建只替换本工具管理的非水域；不触碰已验收水体字典。
    for key,record in records.items():
        config['regions'][key]=record
    config['implementation_status']='Water baseline preserved; localized environment surfaces, atmosphere and deterministic particles enabled; full airship articulation requires accepted clean layers.'
    config['environment_data']={'revision':1,'mask_channels':'R coverage; G response/rim; B depth; A one',
        'texture_bytes_rgba8':total_texels*4,'full_airship_enabled':False,
        'full_airship_reason':'Legacy extracted parts and backing do not match the preserved 8K silhouette and rigging.'}
    config_path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'effects':len(records),'texture_bytes_rgba8':total_texels*4,
                      'png_bytes':sum(p.stat().st_size for p in OUTPUT.glob('*.png'))}))


if __name__=='__main__':
    main()
