"""9A交付整理：真实GUI录像、悬停/窗口截图、状态与隔离目录核对，不伪造界面。"""
from pathlib import Path
import hashlib,json,shutil,subprocess
from PIL import Image,ImageDraw,ImageFont


def build(workspace: Path) -> None:
    root=Path(workspace);out=root/'previews';out.mkdir(exist_ok=True) # 单一派生预览目录。
    record=json.loads((root/'reports/entry_record.json').read_text(encoding='utf-8')) # 当前原生录像记录。
    events={item['name']:item for item in record['events']} # 同次实际输入的关键截图状态。
    required={'almanac_open':'almanac','research_open':'research','keyboard_almanac_open':'almanac'}
    for name,feature in required.items():
        assert events[name]['modal']==feature and events[name]['blocked'],name
    assert events['map_open']['navigation_open'] and events['map_open']['blocked']
    for name in ['modal_blocks_background','ui_blocks_background','drag_cancelled']:
        assert events[name]['hovered']=='',name
    assert events['drag_cancelled']['modal']==''
    assert events['foreground_covers_pressed_entry']['hovered']==''
    assert events['covered_release_cancelled']['modal']=='' and events['covered_release_cancelled']['hovered']==''
    guard=json.loads((root/'reports/pointer_capture_guard.json').read_text())
    assert not guard['accepted_background_action'],'Captured mouse release leaked through foreground UI'
    assert events['research_locked']['hovered']=='research' and not events['research_locked']['research']['unlocked']
    for name in ['day_library_hover','day_research_hover','day_harbor_hover','night_library_hover','night_research_hover','night_harbor_hover','keyboard_library_focus']:
        assert events[name]['hovered'],name
    denied=[item['entry'] for item in record['actions'] if not item['accepted']]
    assert all(name in denied for name in ['home','shop','research'])
    accepted=[item['entry'] for item in record['actions'] if item['accepted']]
    assert accepted==['library','research','harbor','library'],accepted
    assert 'PVZ-Menu9A-Isolated-20261112' in record['user_data_dir']
    assert all(item['hovered']=='library' for item in record['layout_review'])
    paths=sorted((root/'entry_frames').glob('frame_*.png'));assert len(paths)==record['frames']
    ffmpeg=shutil.which('ffmpeg');assert ffmpeg,'ffmpeg missing from current environment'
    command=[ffmpeg,'-hide_banner','-loglevel','error','-y','-framerate',str(record['fps']),'-i',str(root/'entry_frames/frame_%05d.png')]
    subprocess.run(command+['-c:v','libx264','-preset','medium','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart','-an',str(out/'building_interaction.mp4')],check=True)
    start=max(0,int(events['night_library_hover']['frame'])-38) # 夜间悬停段，保持原帧速和真实时间顺序。
    end=int(events['night_shop_hover']['frame'])
    subprocess.run(command+['-vf',f'trim=start_frame={start}:end_frame={end},setpts=PTS-STARTPTS','-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart','-an',str(out/'night_building_hover.mp4')],check=True)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24) # 仅用于标题栅格化，不交付字体。
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
    def screenshot(name):return Image.open(root/'entry_renders'/f'{name}.png').convert('RGB')
    def sheet(items,title,filename):
        width=1066;row=640;page=Image.new('RGB',(width,60+row*len(items)),(23,29,34));draw=ImageDraw.Draw(page)
        draw.text((18,12),title,font=font,fill=(241,237,225))
        for index,(name,caption) in enumerate(items):
            y=60+row*index;draw.text((18,y+8),caption,font=small,fill=(213,220,223))
            image=screenshot(name);image.thumbnail((1066,600),Image.Resampling.LANCZOS);page.paste(image,(0,y+40))
        page.save(out/filename,quality=94,subsampling=0,optimize=True)
    sheet([('day_library_hover','白天：图书馆 → 图鉴'),('night_research_hover','夜晚：研究室 → 合成 / 强化 / 转职')],'建筑悬停 · 同一母图的实际渲染','hover_day_night.jpg')
    sheet([('almanac_open','图书馆点击后：原生冒险图鉴'),('research_open','研究室点击后：原生研究界面'),('map_open','港口点击后：原生地区选择')],'真实功能入口 · 隔离演示档案','real_function_windows.jpg')
    sheet([('research_locked','已实现但未解锁：显示真实任务条件，点击拒绝'),('shop_unavailable','功能未开放：不绕回旧商店')],'锁定与未开放分别处理','locked_and_unavailable.jpg')
    for name in events:
        screenshot(name).save(out/(name+'.jpg'),quality=96,subsampling=0,optimize=True)
    for item in record['layout_review']:
        name='layout_%dx%d'%tuple(item['window']);screenshot(name).save(out/(name+'.jpg'),quality=94,subsampling=0,optimize=True)
    protection=root/'reports/approved_source_protection.json'
    count=0
    if protection.exists():
        protected=json.loads(protection.read_text())
        for filename,digest in protected.items():assert hashlib.sha256(Path(filename).read_bytes()).hexdigest()==digest,filename
        count=len(protected)
    report={'actual_input_frames':len(paths),'fps':record['fps'],'duration_seconds':len(paths)/record['fps'],'real_windows_opened':['almanac','research','map'],
      'keyboard_uses_same_almanac':True,'denied_entries':denied,'drag_cancelled_without_open':True,'covered_release_cancelled_without_open':True,'ui_hover_blocked':True,'native_layouts':record['layout_review'],
      'master_sha256':hashlib.sha256((root/'master_original.png').read_bytes()).hexdigest(),'approved_source_files_unchanged':count,
      'isolated_user_data_dir':record['user_data_dir'],'startup_menu_replaced':False,'image_generation_used':False,'game_test_suite_run':False,
      'limits':'Preview uses explicit isolated demo unlock/discovery records; no crafting, level entry, or actual player save modification performed.'}
    (root/'reports/entry_delivery.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False),flush=True)
