"""局部线性浅水波预计算：岸线无通量、变深度波速、流场输运和同场光学数据。"""
import argparse
import json
from pathlib import Path
import subprocess

import cv2
import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--ffmpeg', default='ffmpeg', help='支持 EXR half 编码的 FFmpeg 可执行文件')
    args = parser.parse_args()
    root = args.root / 'assets/adventure/wonderland'
    out = root / 'masks/water/runtime'
    width, height, cell = 384, 360, 2.0
    frames, substeps, period, padding = 64, 4, 18.0, 2
    dt, gravity = period / (frames * substeps), 18.0
    yy, xx = np.indices((height, width), dtype=np.float32)
    world_x, world_y = (xx + .5) * cell, 168 + (yy + .5) * cell

    # 用原水色恢复渲染安全带外的实际湿域；模拟边界不能沿内缩蒙版截断窄河。
    # 海洋蒙版新增体色G/B通道，物理湿域种子只读取保留不变的运动R通道。
    seed = np.maximum(np.array(Image.open(out/'ocean_mask.png').convert('RGB'))[:, :, 0],
                      np.array(Image.open(out/'river_mask.png').convert('RGB'))[:, :, 0]) > 0
    source = np.asarray(Image.open(args.source).convert('RGB').resize((1774, 887), Image.Resampling.LANCZOS)).astype(np.float32)
    blue = (source[:,:,2]-source[:,:,0] > 9) & (source[:,:,1]-source[:,:,0] > 6) & (source[:,:,2] >= source[:,:,1]-18)
    neighborhood = cv2.dilate(seed.astype(np.uint8), np.ones((15,15), np.uint8)) > 0
    raw = ((blue & neighborhood) | seed).astype(np.uint8)
    raw = cv2.morphologyEx(raw, cv2.MORPH_CLOSE, np.ones((3,3), np.uint8))
    # 桥下水道在物理域连续，显示仍由原蒙版遮住桥面，绝不移动桥的像素。
    cv2.line(raw, (557,459), (548,491), 1, 8)
    cropped = np.pad(raw[168:887,:768], ((0,1),(0,0)), mode='edge')
    wet = cv2.resize(cropped.astype(np.float32), (width,height), interpolation=cv2.INTER_AREA) > .4
    distance = cv2.distanceTransform(wet.astype(np.uint8), cv2.DIST_L2, 5) * cell
    depth = (.7 + 5.3 * (1 - np.exp(-distance/30.0))) * wet
    c2 = gravity * depth

    # 面系数使用调和平均，固体面系数为零，从而实现零法向波通量。
    east = 2*c2*np.roll(c2,-1,axis=1) / np.maximum(c2+np.roll(c2,-1,axis=1), 1e-6)
    south = 2*c2*np.roll(c2,-1,axis=0) / np.maximum(c2+np.roll(c2,-1,axis=0), 1e-6)
    east[:,-1], south[-1,:] = 0, 0
    west, north = np.roll(east,1,axis=1), np.roll(south,1,axis=0)
    west[:,0], north[0,:] = 0, 0

    # 背景缓流沿岸切向投影；只负责输运，波传播仍由浅水方程决定。
    flow = np.array(Image.open(out/'water_flow_field_rgba.png')).astype(np.float32)/255
    cropped_flow = np.pad(flow[168:887,:768], ((0,1),(0,0),(0,0)), mode='edge')
    flow = cv2.resize(cropped_flow, (width,height), interpolation=cv2.INTER_AREA)
    weight = cv2.GaussianBlur(wet.astype(np.float32), (0,0), 1.3)
    velocity = np.stack([cv2.GaussianBlur((flow[:,:,i]*2-1)*wet, (0,0), 1.3)/np.maximum(weight,.01) for i in range(2)],axis=-1)
    velocity /= np.maximum(np.linalg.norm(velocity,axis=-1,keepdims=True), .01)
    dy, dx = np.gradient(distance, cell)
    normal = np.stack((dx,dy),axis=-1)
    normal /= np.maximum(np.linalg.norm(normal,axis=-1,keepdims=True), .01)
    velocity -= normal * np.sum(velocity*normal,axis=-1,keepdims=True) * np.exp(-distance[:,:,None]/9.0)
    speed = np.minimum(1.1 + np.clip((flow[:,:,2]-.72)/.28,0,1)*1.6, np.sqrt(c2)*.45)
    velocity *= speed[:,:,None]
    sample_x = np.clip(xx - velocity[:,:,0]*dt/cell, 0,width-1).astype(np.float32)
    sample_y = np.clip(yy - velocity[:,:,1]*dt/cell, 0,height-1).astype(np.float32)
    sampled_wet = cv2.remap(wet.astype(np.float32), sample_x,sample_y, cv2.INTER_LINEAR)

    def transport(field):
        # 湿邻点归一化避免回溯插值混入陆地零值，防止岸边虚假吸波。
        moved = cv2.remap(field*wet, sample_x,sample_y,cv2.INTER_LINEAR)
        return np.where(sampled_wet>.001, moved/np.maximum(sampled_wet,.001), field)*wet

    def wet_gradient(field):
        # 固体邻点和域外使用自身值作ghost，差分不跨岸或卷到另一侧。
        right = np.where(np.roll(wet,-1,axis=1), np.roll(field,-1,axis=1), field)
        left = np.where(np.roll(wet,1,axis=1), np.roll(field,1,axis=1), field)
        bottom = np.where(np.roll(wet,-1,axis=0), np.roll(field,-1,axis=0), field)
        top = np.where(np.roll(wet,1,axis=0), np.roll(field,1,axis=0), field)
        right[:,-1], left[:,0] = field[:,-1], field[:,0]
        bottom[-1,:], top[0,:] = field[-1,:], field[0,:]
        return (right-left)/(2*cell), (bottom-top)/(2*cell)

    # 分布风压与开口内缘入射波都用低频周期驱动，64帧采样最高0.278Hz。
    rng = np.random.default_rng(80619)
    forces = []
    for harmonic in [2,3,3,4,4,5,5,2,4,3]:
        angle = rng.uniform(-.8,.7)
        omega = 2*np.pi*harmonic/period
        k = omega/np.sqrt(gravity*6.0)
        spatial = (world_x*np.cos(angle)+world_y*np.sin(angle))*k + rng.uniform(0,2*np.pi)
        envelope = (.3 + .7*(1-np.exp(-distance/14.0))) * wet
        envelope *= .55 + .45*np.cos(world_x/170.0+world_y/113.0+rng.uniform(0,6.28))**2
        forces.append((np.cos(spatial)*envelope, np.sin(spatial)*envelope, omega))
    incoming = np.exp(-((world_x-42)/16)**2) * (world_y>620) * wet
    inlet = np.exp(-((world_x-702)**2+(world_y-218)**2)/400) * wet
    # 开口吸收条带位于入射源之外，岸石边界仍保留反射。
    damping = .12 + 1.1*np.exp(-(world_x/20)**2) + 1.1*np.exp(-((888-world_y)/20)**2)
    decay = np.exp(-damping*dt)
    elevation = np.zeros((height,width),np.float32)
    rate = np.zeros_like(elevation)
    # 连续状态保留为浮点，避免八位量化的坡度与焦散台阶被高光放大。
    atlas = np.zeros(((height+2*padding)*8,(width+2*padding)*8,4),np.float32)
    peak_height, peak_slope = 0.0, 0.0
    last_cycle_start = None
    # 固定8个周期预热后保留第9周期；输出只有最终图集，不落盘逐帧缓存。
    for step in range(9*frames*substeps + 1):
        time = step*dt
        elevation, rate = transport(elevation), transport(rate)
        laplacian = (east*(np.roll(elevation,-1,axis=1)-elevation) + west*(np.roll(elevation,1,axis=1)-elevation)
                     + south*(np.roll(elevation,-1,axis=0)-elevation) + north*(np.roll(elevation,1,axis=0)-elevation))/(cell*cell)
        forcing = np.zeros_like(elevation)
        for cosine,sine,omega in forces:
            forcing += .035*(cosine*np.cos(omega*time)+sine*np.sin(omega*time))
        forcing += incoming*.11*np.sin(2*np.pi*3*time/period-world_y*.045)
        forcing += inlet*.10*np.sin(2*np.pi*4*time/period)
        forcing -= forcing[wet].mean()*wet
        rate = (rate + dt*(laplacian+forcing))*decay*wet
        elevation = (elevation + dt*rate)*wet
        elevation -= elevation[wet].mean()*wet
        if step == 8*frames*substeps:
            last_cycle_start = elevation.copy()
        if 8*frames*substeps <= step < 9*frames*substeps and step % substeps == 0:
            frame = (step-8*frames*substeps)//substeps
            gx, gy = wet_gradient(elevation)
            # 对近轴Snell落点q=x+bend(x)*grad(h)直接求导，包含变水深的梯度项。
            optical_depth = np.minimum(depth*3,16)
            bend = optical_depth*(1-1/1.333)
            shift_x, shift_y = bend*gx, bend*gy
            dxx, dxy = wet_gradient(shift_x)
            dyx, dyy = wet_gradient(shift_y)
            determinant = (1+dxx)*(1+dyy) - dxy*dyx
            caustic = np.clip(1/np.maximum(np.abs(determinant),.4),.4,2.2)
            caustic = cv2.GaussianBlur(caustic.astype(np.float32),(0,0),.6)
            channels = np.stack((gx/.45*.5+.5,gy/.45*.5+.5,elevation/1.5*.5+.5,(caustic-.4)/1.8),axis=-1)
            pixels = np.clip(channels,0,1).astype(np.float32)
            pixels = np.pad(pixels,((padding,padding),(padding,padding),(0,0)),mode='edge')
            y,x = (frame//8)*(height+padding*2),(frame%8)*(width+padding*2)
            atlas[y:y+pixels.shape[0],x:x+pixels.shape[1]] = pixels
            peak_height=max(peak_height,float(np.abs(elevation).max()))
            peak_slope=max(peak_slope,float(np.maximum(np.abs(gx),np.abs(gy)).max()))
    # 保持线性技术数据；FFmpeg 的浮点平面输入次序为 G、B、R、A。
    atlas_path = out/'water_state_atlas.exr'
    planes = np.ascontiguousarray(atlas[:,:,[1,2,0,3]].transpose(2,0,1), dtype='<f4')
    # A 是独立焦散数据，不是透明度；仅以元数据标签阻止 FFmpeg 自动预乘 RGB，技术值本身不做预乘。
    # setsar 明确方形像素，使 EXR 写出 TinyEXR 要求的 pixelAspectRatio 属性。
    # 编码器限时四十五秒，错误输出交给外层有界作业统一保存，不生成 raw 帧文件。
    subprocess.run([str(args.ffmpeg), '-hide_banner', '-loglevel', 'error', '-nostdin',
                    '-f', 'rawvideo', '-pixel_format', 'gbrapf32le',
                    '-video_size', f'{atlas.shape[1]}x{atlas.shape[0]}', '-i', 'pipe:0',
                    '-vf', 'setparams=alpha_mode=premultiplied,setsar=1',
                    '-frames:v', '1', '-c:v', 'exr', '-format', 'half',
                    '-compression', 'zip16', '-gamma', '1', '-update', '1', '-y', str(atlas_path)],
                   input=planes.tobytes(), timeout=45, check=True)
    print(json.dumps({'grid':[width,height],'frames':frames,'period_seconds':period,'dt':dt,
                      'courant_2d':float(np.sqrt(c2.max())*dt/cell*np.sqrt(2)),
                      'wet_cells':int(wet.sum()),'peak_height':peak_height,'peak_slope':peak_slope,
                      'end_vs_start_rms':float(np.sqrt(np.mean((elevation[wet]-last_cycle_start[wet])**2))),
                      'atlas_format':'RGBA half EXR, ZIP16 lossless',
                      'atlas_bytes':atlas_path.stat().st_size}))


if __name__ == '__main__':
    main()
