"""整理实际 GPU 帧为手机 MP4/GIF/静帧，并核对基线与受保护区域。"""
from pathlib import Path
import hashlib,json,shutil,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont


def build(workspace: Path, manifest: dict) -> None:
    root=Path(workspace);out=root/'previews';out.mkdir(exist_ok=True)
    render=json.loads((root/'reports/render.json').read_text(encoding='utf-8'))
    count=render['frames_per_state'];period=float(render['loop_seconds'])
    if count<2:raise ValueError('先在 pipeline.json 开启 capture.animate，再渲染完整循环')
    fps=count/period
    ffmpeg=shutil.which('ffmpeg')
    if not ffmpeg:raise FileNotFoundError('Existing ffmpeg executable not found')
    def image(path):return Image.open(path).convert('RGB')
    def pixels(path):return np.asarray(image(path))
    def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
    def encode(folder,destination,scale=False):
        paths=sorted(folder.glob('frame_*.png'))
        assert len(paths)==count,(folder,len(paths),count)
        cmd=[ffmpeg,'-hide_banner','-loglevel','error','-y','-framerate',str(fps),'-i',str(folder/'frame_%04d.png')]
        if scale:cmd+=['-vf','scale=iw*2:ih*2:flags=lanczos']
        subprocess.run(cmd+['-c:v','libx264','-preset','medium','-crf',str(manifest['preview']['full_video_crf']),'-pix_fmt','yuv420p','-movflags','+faststart','-an',str(destination)],check=True)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24)
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
    for state in ['day','night']:
        encode(root/'frames'/state,out/f'{state}_harbor_full.mp4')
        encode(root/'frames'/f'harbor_{state}',out/f'{state}_harbor_closeup.mp4',True)
        image(root/'renders'/f'{state}_phase_25.png').save(out/f'{state}_preview.jpg',quality=96,subsampling=0,optimize=True)
        image(root/'renders'/f'{state}_ui.png').save(out/f'{state}_ui.jpg',quality=94,subsampling=0,optimize=True)
    # 同相位的昼/夜近景并排，全部来自真实 GPU 帧，量化只用于手机 GIF。
    selected=np.linspace(0,count-1,min(manifest['preview']['gif_frames'],count),dtype=int)
    pair_frames=[]
    for index in selected:
        day=image(root/'frames/harbor_day'/f'frame_{index:04d}.png')
        night=image(root/'frames/harbor_night'/f'frame_{index:04d}.png')
        size=(day.width*2,day.height*2);day=day.resize(size,Image.Resampling.LANCZOS);night=night.resize(size,Image.Resampling.LANCZOS)
        pair=Image.new('RGB',(size[0]*2,size[1]+46),(25,30,35));draw=ImageDraw.Draw(pair)
        draw.text((14,9),'白天｜实际港口动态',font=font,fill=(239,238,228))
        draw.text((size[0]+14,9),'夜晚｜同一素材与相位',font=font,fill=(239,238,228))
        pair.paste(day,(0,46));pair.paste(night,(size[0],46));pair_frames.append(pair)
    palette=Image.fromarray(np.concatenate([np.asarray(f)[::3,::3] for f in pair_frames[::6]],axis=0)).quantize(colors=256,method=Image.Quantize.MEDIANCUT)
    frames=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in pair_frames]
    frames[0].save(out/'harbor_day_night.gif',save_all=True,append_images=frames[1:],duration=round(period*1000/len(frames)),loop=0,disposal=2,optimize=False)
    pair_frames[len(pair_frames)//4].save(out/'harbor_day_night.jpg',quality=96,subsampling=0,optimize=True)
    # 全景静帧对照供手机浏览，局部真实运动以视频为准。
    sheet=Image.new('RGB',(1200,1470),(25,30,35));draw=ImageDraw.Draw(sheet)
    for index,state in enumerate(['day','night']):
        draw.text((18,12+index*720),'白天港口动态静帧' if state=='day' else '夜晚港口动态静帧',font=font,fill=(239,238,228))
        draw.text((18,45+index*720),'同一母图；水面、船体与接触波纹，UI和码头不参与位移。',font=small,fill=(180,195,204))
        sheet.paste(image(root/'renders'/f'{state}_phase_25.png').resize((1200,675),Image.Resampling.LANCZOS),(0,75+index*720))
    sheet.save(out/'full_day_night.jpg',quality=94,subsampling=0,optimize=True)
    support=np.asarray(Image.open(root/'assets/motion_support.png'))>0
    fixed=np.asarray(Image.open(root/'assets/fixed_alpha.png'))==255
    result={'master_sha256':digest(root/'master_original.png'),'states':{},'actual_gpu_frames':count*2,'duration_per_state':period,
      'fps':fps,'image_generation_used':False,'test_suites_run':False,'boats_repainted':False}
    for state in ['day','night']:
        static=pixels(root/'renders'/f'{state}_disabled.png')
        baseline=pixels(root/'baseline'/f'{state}.png')
        assert np.array_equal(static,baseline),'Static baseline changed: '+state
        outside=0;fixed_error=0
        for phase in ['00','25','50','75']:
            current=pixels(root/'renders'/f'{state}_phase_{phase}.png')
            delta=np.abs(current.astype(int)-static.astype(int))
            outside=max(outside,int(delta[~support].max()));fixed_error=max(fixed_error,int(delta[fixed].max()))
        start=pixels(root/'renders'/f'{state}_phase_00.png').astype(int)
        end=pixels(root/'renders'/f'{state}_loop_end.png').astype(int)
        loop_error=int(np.abs(start-end).max())
        assert outside<=1 and fixed_error<=1 and loop_error<=1,(state,outside,fixed_error,loop_error)
        result['states'][state]={'disabled_matches_S6':True,'outside_support_max_delta':outside,'fixed_dock_max_delta':fixed_error,'loop_endpoint_max_delta':loop_error}
    previous=root/'reports/baseline_protection.json'
    if previous.exists():
        protected=json.loads(previous.read_text())['files']
        assert all(digest(Path(path))==sha for path,sha in protected.items())
        result['previous_files_unchanged']=len(protected)
    result['videos']=[{'file':p.name,'bytes':p.stat().st_size,'sha256':digest(p)} for p in out.glob('*.mp4')]
    (root/'reports/delivery_checks.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result),flush=True)
