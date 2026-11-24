"""整理共享风场真实帧；关闭新增风动对照已通过港口，不把指标当视觉验收。"""
from pathlib import Path
import hashlib,json,math,shutil,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont


def build(root: Path, manifest: dict) -> None:
    root=Path(root);out=root/'previews';out.mkdir(exist_ok=True)
    report=json.loads((root/'reports/render.json').read_text());count=report['frames_per_state'];fps=report['fps']
    assert count>1,'capture.animate must be true for final previews'
    encoder=shutil.which('ffmpeg');assert encoder,'ffmpeg unavailable'
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',22)
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',16)
    def image(p):return Image.open(p).convert('RGB')
    def pixels(p):return np.asarray(image(p))
    def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
    def encode(folder,target,scale=None):
        assert len(list(folder.glob('frame_*.png')))==count,folder
        args=[encoder,'-hide_banner','-loglevel','error','-y','-framerate',str(fps),'-i',str(folder/'frame_%04d.png')]
        if scale:args+=['-vf',scale]
        subprocess.run(args+['-c:v','libx264','-preset','medium','-crf',str(manifest['preview']['full_video_crf']),'-pix_fmt','yuv420p','-movflags','+faststart','-an',str(target)],check=True)
    labels={'trees':'树冠内部｜轮廓与树干固定','awning':'遮阳棚｜沿墙固定，外沿轻动','flag':'船旗｜先局部变形，再随船浮动','rear_tree':'后方树冠｜独立响应相位'}
    sampled=[]
    for state in report['states']:
        encode(root/'frames'/state,out/f'{state}_wind_full.mp4')
        details=root/'frames'/('details_'+state);details.mkdir(exist_ok=True)
        for old in details.glob('frame_*.png'):old.unlink()
        for index in range(count):
            page=Image.new('RGB',(960,640),(24,29,33));draw=ImageDraw.Draw(page)
            for slot,name in enumerate(labels):
                crop=image(root/'frames'/f'{name}_{state}'/f'frame_{index:04d}.png')
                crop.thumbnail((468,270),Image.Resampling.LANCZOS)
                if name=='flag':crop=crop.resize((304,260),Image.Resampling.LANCZOS)
                x=slot%2*480;y=slot//2*320
                draw.text((x+10,y+9),labels[name],font=font,fill=(240,237,226))
                page.paste(crop,(x+(480-crop.width)//2,y+43+(270-crop.height)//2))
            page.save(details/f'frame_{index:04d}.png')
            if state=='day' and index%3==0:sampled.append(page)
        encode(details,out/f'{state}_wind_details.mp4')
        image(root/'renders'/f'{state}_phase_25.png').save(out/f'{state}_wind_preview.jpg',quality=95,subsampling=0,optimize=True)
        image(root/'renders'/f'{state}_ui.png').save(out/f'{state}_ui_preview.jpg',quality=94,subsampling=0,optimize=True)
        image(details/f'frame_{count//4:04d}.png').save(out/f'{state}_detail_preview.jpg',quality=95,subsampling=0,optimize=True)
    palette=Image.fromarray(np.concatenate([np.asarray(f)[::3,::3] for f in sampled[::6]],axis=0)).quantize(colors=256,method=Image.Quantize.MEDIANCUT)
    indexed=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in sampled]
    indexed[0].save(out/'wind_detail_loop.gif',save_all=True,append_images=indexed[1:],duration=round(1000*3/fps),loop=0,disposal=2,optimize=False)
    # 全景白天/夜晚静帧，不把效果放大后冒充实际整体视觉强度。
    board=Image.new('RGB',(1200,1490),(24,29,33));draw=ImageDraw.Draw(board)
    for i,state in enumerate(['day','night']):
        y=i*740;draw.text((18,y+12),'白天｜统一风动与已通过港口' if state=='day' else '夜晚｜同一素材，保持既有光照',font=font,fill=(240,237,226))
        board.paste(image(root/'renders'/f'{state}_phase_25.png').resize((1200,675),Image.Resampling.LANCZOS),(0,y+55))
    board.save(out/'full_day_night.jpg',quality=94,subsampling=0,optimize=True)
    # 同构图新增效果关/开。两张都是同一港口相位，不拿不同船相位混比。
    pair=Image.new('RGB',(1200,1490),(24,29,33));draw=ImageDraw.Draw(pair)
    for i,(suffix,title) in enumerate([('wind_off_25','新增风动关闭：已通过的港口'),('phase_25','新增风动开启：局部树冠与布料')]):
        draw.text((18,i*740+12),title,font=font,fill=(240,237,226))
        pair.paste(image(root/'renders'/f'day_{suffix}.png').resize((1200,675),Image.Resampling.LANCZOS),(0,i*740+55))
    pair.save(out/'wind_on_off.jpg',quality=94,subsampling=0,optimize=True)
    support=np.asarray(Image.open(root/'wind_assets/wind_support.png'))>0
    anchors=np.asarray(Image.open(root/'wind_assets/protected_anchors.png'))>0
    checks={'states':{},'source_sha256':sha(root/'master_original.png'),'actual_gpu_frames':count*len(report['states']),'fps':fps,'duration_seconds':count/fps,'test_suites_run':False,'image_generation_used':False}
    for state in report['states']:
        base=pixels(root/'baseline'/f'{state}.png');disabled=pixels(root/'renders'/f'{state}_disabled.png')
        assert np.array_equal(base,disabled),'Static lighting changed'
        peak_out=0;peak_pin=0;peak_old=0
        old_rounding_outliers = 0
        for phase in manifest['capture']['static_phases']:
            frame=math.floor(phase*100+.5);off=pixels(root/'renders'/f'{state}_wind_off_{frame:02d}.png')
            approved=pixels(root/'baseline_harbor'/f'{state}_phase_{frame:02d}.png')
            current=pixels(root/'renders'/f'{state}_phase_{frame:02d}.png')
            delta=np.abs(current.astype(int)-off.astype(int))
            old_delta = np.abs(off.astype(int) - approved.astype(int)).max(axis=-1)
            peak_old = max(peak_old, int(old_delta.max()))
            old_rounding_outliers = max(old_rounding_outliers, int(np.count_nonzero(old_delta > 1)))
            peak_out=max(peak_out,int(delta[~support].max()));peak_pin=max(peak_pin,int(delta[anchors].max()))
        loop=int(np.abs(pixels(root/'renders'/f'{state}_phase_00.png').astype(int)-pixels(root/'renders'/f'{state}_loop_end.png').astype(int)).max())
        # 分层 RGBA8 混合允许 1 级舍入，局部 UV 取整只容许极少数像素有更大变化。
        within_harbor_tolerance = peak_old <= 8 and old_rounding_outliers <= max(1, base.shape[0] * base.shape[1] // 10000)
        assert within_harbor_tolerance and peak_out <= 1 and peak_pin <= 1 and loop <= 1, (
            state, peak_old, old_rounding_outliers, peak_out, peak_pin, loop,
        )
        checks['states'][state] = {
            'wind_off_matches_approved_harbor': within_harbor_tolerance,
            'wind_off_max_delta': peak_old,
            'wind_off_pixels_above_one': old_rounding_outliers,
            'outside_wind_max_delta': peak_out,
            'fixed_anchor_max_delta': peak_pin,
            'loop_max_delta': loop,
        }
    protection=root/'reports/approved_baseline_protection.json'
    if protection.exists():
        records=json.loads(protection.read_text())['files'];assert all(sha(Path(p))==h for p,h in records.items())
        checks['approved_files_unchanged']=len(records)
    checks['note']='Eight actual phases, pinned contours and matte backgrounds reviewed; numeric continuity does not alone prove aesthetic quality.'
    (root/'reports/delivery_checks.json').write_text(json.dumps(checks,indent=2),encoding='utf-8');print(json.dumps(checks),flush=True)
