"""港口混合选区：语义范围＋色差/明度通道＋封闭体＋亚像素透明边缘。"""
import cv2
import numpy as np
from PIL import Image,ImageDraw


def dilate(mask, radius):
    return cv2.dilate(mask.astype(np.uint8),np.ones((radius*2+1,)*2,np.uint8))>0


def erode(mask, radius):
    return cv2.erode(mask.astype(np.uint8),np.ones((radius*2+1,)*2,np.uint8))>0


def nearest_indices(known):
    """返回明确已知像素坐标；映射表使用OpenCV实际标签，不假设标签顺序。"""
    assert np.any(known),'No valid source pixels'
    _,labels=cv2.distanceTransformWithLabels((~known).astype(np.uint8),cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
    y,x=np.nonzero(known);size=int(labels.max())+1
    ly=np.zeros(size,np.int32);lx=ly.copy()
    ly[labels[y,x]]=y;lx[labels[y,x]]=x
    return ly[labels],lx[labels]


class Geometry:
    """保持原图坐标；多边形只限定部件归属，边缘另由通道决定。"""
    def __init__(self, size):
        self.width,self.height=size
    def polygon(self, points, antialias=False):
        factor=4 if antialias else 1
        image=Image.new('L',(self.width*factor,self.height*factor))
        ImageDraw.Draw(image).polygon([(round(x*factor),round(y*factor)) for x,y in points],fill=255)
        if antialias:image=image.resize((self.width,self.height),Image.Resampling.LANCZOS)
        result=np.asarray(image).astype(np.float32)/255
        return result if antialias else result>.5
    def line(self, points, width):
        image=np.zeros((self.height,self.width),np.uint8)
        cv2.polylines(image,[np.asarray(points,np.int32)],False,255,int(width),cv2.LINE_8)
        return image>0


def solve_alpha(seed, channel, controls):
    """在窄trimap内用色差通道估计覆盖率，内部不把蓝色窗户误删。"""
    foreground=erode(seed,controls['matte_erode'])
    background=~dilate(seed,controls['matte_dilate'])
    fy,fx=nearest_indices(foreground);by,bx=nearest_indices(background)
    fg=channel[fy,fx];bg=channel[by,bx]
    alpha=np.clip((bg-channel)/np.maximum(bg-fg,controls['minimum_channel_separation']),0,1)
    alpha[foreground]=1;alpha[background]=0
    return alpha.astype(np.float32)


def derive(rgb, config):
    """返回船/码头前景透明度和被遮挡船身范围；不修改原始RGB。"""
    geom=Geometry(config['canvas']);c=config['channel']
    chroma=(rgb[:,:,1]+rgb[:,:,2])*.5-rgb[:,:,0]
    body=geom.polygon(config['body'])
    seed=(chroma<c['foreground_chroma_max'])&dilate(body,c['search_margin'])
    seed|=erode(body,c['solid_erode'])
    flooded=seed.astype(np.uint8).copy();cv2.floodFill(flooded,None,(0,0),1)
    seed|=(flooded==0)
    exclusion=geom.polygon(config['dock_exclusion']);seed&=~exclusion
    fixed=np.zeros_like(seed);fixed_limit=np.zeros_like(seed);post_core=np.zeros_like(seed)
    post_alpha=np.zeros(seed.shape,np.float32)
    wood=(rgb[:,:,1]-rgb[:,:,2]>.035)|(rgb.mean(-1)<.23)
    for points in config['fixed_posts']:
        shape=geom.polygon(points);limit=dilate(shape,1);core=erode(shape,2)
        fixed|=(wood&limit)|core;fixed_limit|=limit;post_core|=core
        post_alpha=np.maximum(post_alpha,geom.polygon(points,True))
    for points in config['fixed_ropes']:
        limit=geom.line(points,6);fixed|=wood&limit;fixed_limit|=dilate(limit,1)
    ff=erode(fixed,1)|post_core;bb=~dilate(fixed,2)
    fy,fx=nearest_indices(ff);by,bx=nearest_indices(bb)
    foreground_rgb=rgb[fy,fx];background_rgb=rgb[by,bx]
    direction=foreground_rgb-background_rgb
    fixed_alpha=np.clip(np.sum((rgb-background_rgb)*direction,axis=-1)/np.maximum(np.sum(direction*direction,axis=-1),.002),0,1)
    fixed_alpha[ff]=1;fixed_alpha[bb]=0;fixed_alpha*=fixed_limit
    fixed_alpha=np.maximum(fixed_alpha,post_alpha)
    fixed=fixed_alpha>.5
    seed&=~fixed;seed|=body&fixed
    upper=np.zeros_like(seed)
    for points in config['upper_rois']:upper|=geom.polygon(points)
    for points in config['rigging']:upper|=geom.line(points,c['rigging_width'])
    upper|=geom.polygon(config['lantern_roi'])
    seed|=upper&((chroma<c['foreground_chroma_max'])|(rgb.mean(-1)<c['dark_max']))
    seed|=geom.line(config['mooring'],c['rope_width'])&(chroma<c['foreground_chroma_max'])
    alpha=solve_alpha(seed,chroma,c)
    alpha[erode(body,c['solid_erode'])]=1
    hidden=dilate(fixed_limit,c['post_hidden_guard'])&dilate(body,2) # 所有语义柱帽/栏绳边缘归固定层，不能把分类不确定像素留在船上。
    body_aa=geom.polygon(config['body'],True)
    alpha[hidden]=body_aa[hidden];alpha[exclusion]=0
    low=c['lower_hull_boundary_y']
    alpha[low:]*=geom.polygon(config['body'],True)[low:] # 下船沿外的旧栏绳/柱帽色不能随船移动。
    # 前景轮廓单独处理，不能把船身按一个大多边形固定回盖。
    count,labels,stats,_=cv2.connectedComponentsWithStats((alpha>.01).astype(np.uint8),8)
    for label in range(1,count):
        if stats[label,cv2.CC_STAT_AREA]<12 and stats[label,cv2.CC_STAT_TOP]>380:
            alpha[labels==label]=0
    fixed_alpha=np.asarray(fixed_alpha,np.float32)
    return {'boat':alpha,'fixed':fixed_alpha,'hidden':hidden,'body':body,
            'fixed_binary':fixed,'chroma':chroma,'geometry':geom}


def decontaminate(rgb, alpha, background):
    """反解 source-over 移除已烘焙海水底色；透明RGB不参与后续滤波。"""
    foreground=(rgb-background*(1-alpha[:,:,None]))/np.maximum(alpha[:,:,None],.01)
    foreground=np.clip(foreground,0,1)
    foreground[alpha>.98]=rgb[alpha>.98]
    return foreground


def blend_hidden(foreground, hidden, alpha, iterations=120):
    """在船身有效域内连续延拓被柱遮挡的颜色，拒绝拿海水/柱色当边界。"""
    unknown=hidden&(alpha>.001)
    rows,cols=np.nonzero(unknown)
    if not len(rows):return foreground
    y0=max(0,int(rows.min())-8);y1=min(alpha.shape[0],int(rows.max())+9)
    x0=max(0,int(cols.min())-8);x1=min(alpha.shape[1],int(cols.max())+9)
    values=foreground[y0:y1,x0:x1].copy();seed=values.copy()
    active=unknown[y0:y1,x0:x1];domain=alpha[y0:y1,x0:x1]>.001
    for _ in range(iterations):
        sums=np.zeros_like(values);weights=np.zeros(domain.shape,np.float32)
        for dy,dx in [(1,0),(-1,0),(0,1),(0,-1)]:
            valid=np.roll(domain,(dy,dx),(0,1))
            if dy==1:valid[0]=False
            if dy==-1:valid[-1]=False
            if dx==1:valid[:,0]=False
            if dx==-1:valid[:,-1]=False
            sums+=np.roll(values,(dy,dx),(0,1))*valid[:,:,None];weights+=valid
        target=(sums+.03*seed)/np.maximum(weights[:,:,None]+.03,.03)
        values[active]=target[active]
    result=foreground.copy();result[y0:y1,x0:x1]=values
    return result
