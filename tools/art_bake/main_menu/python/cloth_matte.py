"""固定视角布料选区：暖色面/蓝窗排除＋区域trimap，轮廓填充避免内部透明针孔。"""
import cv2
import numpy as np
from .harbor_matte import dilate,erode


def alpha_from_source(raw, rgb, geometry, config):
    h,w=raw.shape[:2];polygon=geometry.polygon(config['polygon'])
    warm=(rgb[:,:,0]-rgb[:,:,2]>.105)&(rgb[:,:,0]-rgb[:,:,1]>.005)
    blue=(rgb[:,:,2]-rgb[:,:,0]>.025)&(rgb[:,:,1]-rgb[:,:,0]>.015)
    green=(rgb[:,:,1]-rgb[:,:,0]>.055)
    labels=np.full((h,w),cv2.GC_BGD,np.uint8)
    vicinity=dilate(polygon,config['trimap_margin'])
    labels[vicinity]=cv2.GC_PR_BGD;labels[polygon]=cv2.GC_PR_FGD
    labels[erode(polygon,config['trimap_core'])&warm]=cv2.GC_FGD
    labels[vicinity&(blue|green)]=cv2.GC_BGD
    x0,y0,x1,y1=config['crop'];local=labels[y0:y1,x0:x1].copy()
    bg=np.zeros((1,65),np.float64);fg=bg.copy()
    cv2.grabCut(raw[y0:y1,x0:x1].copy(),local,None,bg,fg,config['grabcut_iterations'],cv2.GC_INIT_WITH_MASK)
    seed=np.zeros((h,w),np.uint8);seed[y0:y1,x0:x1]=((local==cv2.GC_FGD)|(local==cv2.GC_PR_FGD)).astype(np.uint8)
    seed[blue|green]=0
    seed=cv2.morphologyEx(seed,cv2.MORPH_CLOSE,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(3,3)))
    seed=dilate(seed,config['outline_pixels']).astype(np.uint8) # 原有黑描边随布面，不能残留在静态窗户上。
    contours,_=cv2.findContours(seed,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
    contour=max(contours,key=cv2.contourArea)
    contour=cv2.approxPolyDP(contour,.45,True).reshape(-1,2)
    # 单一无孔布面，边界AA来自原像素坐标；不把蓝窗纹理作为碎透明区。
    alpha=geometry.polygon(contour.tolist(),True)
    return alpha
