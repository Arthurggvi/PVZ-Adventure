"""整理9B真实菜单截图/录像；保留来源、状态与像素核对，不生成新场景。"""
from pathlib import Path
import hashlib,json,shutil,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont


def build(workspace: Path) -> None:
    root=Path(workspace);out=root/'previews';out.mkdir(exist_ok=True)
    report=json.loads((root/'reports/runtime_walkthrough.json').read_text(encoding='utf-8'))
    boot=json.loads((root/'reports/boot.json').read_text(encoding='utf-8'))
    resource=json.loads((root/'reports/native_resources.json').read_text(encoding='utf-8'))
    assert resource['texture_count']==31 and all(x['pixels_equal'] for x in resource['entries'])
    events={e['name']:e for e in report['events']}
    for name in ['real_almanac','real_settings','profile_B_research_locked','profile_A_real_research','actual_map_entered','returned_to_new_menu','exit_confirmation']:
        assert name in events,name
    assert events['real_settings']['modal']=='settings' and events['exit_confirmation']['dialogs']=='exit'
    assert events['profile_B_research_locked']['research']['unlocked'] is False
    assert events['profile_A_real_research']['modal']=='research'
    assert events['returned_to_new_menu']['scene']=='res://scenes/main/01StartMenuCoastal.tscn'
    assert report['extra']['old_menu_host_released_on_map'] and report['extra']['return_profile_unchanged']
    def image(name):return Image.open(root/'renders'/name).convert('RGB')
    def pixels(name):return np.asarray(image(name)).astype(int)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24)
    title=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',29)
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
    def board(items,heading,subtitle,filename):
        cell_width=640;cell_height=360;label=43;header=86
        rows=(len(items)+1)//2
        canvas=Image.new('RGB',(1280,header+rows*(cell_height+label)),(24,29,34));draw=ImageDraw.Draw(canvas)
        draw.text((18,10),heading,font=title,fill=(241,238,229))
        draw.text((18,52),subtitle,font=small,fill=(188,200,207))
        for index,(name,caption) in enumerate(items):
            x=index%2*640;y=header+index//2*(cell_height+label)
            draw.text((x+14,y+8),caption,font=font,fill=(235,232,220))
            picture=image(name);picture.thumbnail((cell_width,cell_height),Image.Resampling.LANCZOS)
            canvas.paste(picture,(x+(cell_width-picture.width)//2,y+label+(cell_height-picture.height)//2))
        canvas.save(out/filename,quality=95,subsampling=0,optimize=True)
    board([('cycle_dawn.png','06:00 黎明'),('cycle_morning.png','07:30 清晨'),('cycle_day.png','12:00 白天'),('cycle_dusk.png','18:30 黄昏'),('cycle_night.png','21:30 夜晚'),('cycle_midnight.png','00:00 午夜')],
          '完整日周期 · 正式菜单实际截图','同一母图与动态管线；示例时刻是可编辑美术配置，不是天文日出。','daily_cycle_overview.jpg')
    board([('profile_selector_B.png','原档案选择器'),('profile_B_research_locked.png','切换档案后：真实锁定条件'),('real_settings.png','桌面设置窗口'),('exit_confirmation.png','系统窗口退出确认'),('actual_map_entered.png','实际进入僵尸岛地图'),('returned_to_new_menu.png','返回新主菜单')],
          '真实功能与返回流程','使用隔离演示档案录制，未读取或改写正式玩家存档。','runtime_ui_overview.jpg')
    board([('cycle_morning.png','清晨'),('cycle_night.png','夜晚')],
          '新主菜单 · 清晨与夜晚','档案入口和工具栏均可交互，建筑支持悬停高亮与点击进入。','morning_night.jpg')
    for name in ['cycle_dawn','cycle_morning','cycle_day','cycle_dusk','cycle_night','local_time_runtime','morning_library_hover','returned_to_new_menu','exit_confirmation']:
        image(name+'.png').save(out/(name+'.jpg'),quality=96,subsampling=0,optimize=True)
    ffmpeg=shutil.which('ffmpeg');assert ffmpeg
    for folder,name,pattern,expected in [('day_cycle','daily_cycle.mp4','frame_%04d.png',240),('walkthrough','runtime_walkthrough.mp4','frame_%05d.png',report['frames'])]:
        frames=sorted((root/'frames'/folder).glob('frame_*.png'));assert len(frames)==expected,(folder,len(frames),expected)
        subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-framerate','24','-i',str(root/'frames'/folder/pattern),'-c:v','libx264','-preset','medium','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart','-an',str(out/name)],check=True)
    midnight=int(np.abs(pixels('cycle_before_midnight.png')-pixels('cycle_after_midnight.png')).max())
    assert midnight==0,midnight
    packaged={}
    for state in ['day','night']:
        if (root/'renders'/f'pack_{state}.png').exists():
            error=int(np.abs(pixels(f'pack_{state}.png')-pixels(f'scene_{state}.png')).max())
            assert error<=1,(state,error)
            packaged[state]=error
    result={'real_ui_flow_recorded':True,'midnight_crossing_max_channel_delta':midnight,'native_texture_roundtrip_count':31,
      'native_pack_vs_runtime_scene_max_delta':packaged,'day_cycle_frames':240,'walkthrough_frames':report['frames'],
      'old_host_freed':report['extra']['old_menu_host_released_on_map'],'local_hour_at_boot':boot['local_hour'],
      'renderer':boot['adapter'],'performance':report['extra'].get('performance',{}),'native_clock_changes_do_not_change_animation':report['extra'].get('injected_clock_resync',{}),
      'tests_run':False,'image_generation_used':False,'full_executable_exported':False,
      'videos':[{'file':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in out.glob('*.mp4')]}
    (root/'reports/runtime_delivery.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result),flush=True)
