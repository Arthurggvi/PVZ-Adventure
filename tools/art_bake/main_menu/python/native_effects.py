"""在空工程演示正式效果接口；只复制菜单运行资源，不加载玩家业务或修改默认配置。"""
from pathlib import Path
import json,shutil,subprocess


def run(workspace: Path, tools_config: Path) -> None:
    code=Path(__file__).resolve().parents[1]
    repo=code.parents[2]
    native=workspace/'effects_native'
    native.mkdir(parents=True,exist_ok=True)
    (workspace/'reports').mkdir(exist_ok=True)
    (native/'project.godot').write_text('config_version=5\n[application]\nconfig/name="Menu Effect Review"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="Menu-Effects-Isolated"\n[display]\nwindow/size/viewport_width=1066\nwindow/size/viewport_height=600\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
    for folder in ['scripts/ui/start_menu/coastal','shaders/ui/main_menu','assets/adventure/main_menu/coastal']:
        shutil.copytree(repo/folder,native/folder,dirs_exist_ok=True)
    script=native/'effect_review.gd'
    shutil.copy2(code/'godot/effect_review.gd',script)
    tools=json.loads(tools_config.read_text(encoding='utf-8-sig'))
    log=workspace/'reports/effect_review.log'
    with log.open('wb') as stream:
        result=subprocess.run([tools['godot'],'--path',str(native),'--script',str(script),'--',str(workspace)],stdout=stream,stderr=subprocess.STDOUT,timeout=150)
    output=log.read_text(encoding='utf-8',errors='replace')
    if result.returncode!=0 or 'ERROR:' in output or 'EFFECT_REVIEW_COMPLETE' not in output:
        raise RuntimeError(output[-12000:])
    print(output,flush=True)
