"""真实建筑交互预览：独立工程manifest/user目录，复用原游戏代码与已导入资源。"""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,time


def run(workspace: Path, tools_config: Path, smoke: bool=False, verbose: bool=False) -> None:
    root=Path(workspace).resolve() # 资产工作目录。
    repo=Path(__file__).resolve().parents[4] # 权威游戏工程，不修改其project.godot。
    project=root/'native_project';project.mkdir(exist_ok=True)
    cache=project/'.godot';cache.mkdir(exist_ok=True)
    settings=json.loads(tools_config.read_text(encoding='utf-8-sig')) # 当前原生Godot路径。
    source_project=repo/'project.godot'
    if not source_project.is_file():raise FileNotFoundError('需要在原游戏工程的tools/art_bake/main_menu运行此原生入口')
    original_hash=hashlib.sha256(source_project.read_bytes()).hexdigest()
    for name in ['assets','resources','scenes','scripts','animation','data','addons','shaders','shader_material','tools']:
        target=project/name;source=repo/name
        if source.is_dir() and not target.exists():
            subprocess.run(['cmd','/c','mklink','/J',str(target),str(source)],capture_output=True,check=True)
    for name in ['global_script_class_cache.cfg','uid_cache.bin','scene_groups_cache.cfg']:
        source=repo/'.godot'/name
        if source.is_file():shutil.copy2(source,cache/name)
    if not (cache/'imported').exists():
        subprocess.run(['cmd','/c','mklink','/J',str(cache/'imported'),str(repo/'.godot/imported')],capture_output=True,check=True)
    for name in ['default_bus_layout.tres','pvz_icon.ico','icon.svg','icon.svg.import']:
        if (repo/name).is_file():shutil.copy2(repo/name,project/name)
    text=source_project.read_text(encoding='utf-8') # 只改隔离副本中的运行入口与用户目录。
    text=re.sub(r'(?m)^config/name=.*','config/name="PVZ Menu 9A Preview"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="PVZ-Menu9A-Isolated-20261112"',text)
    text=re.sub(r'(?m)^run/main_scene=.*','run/main_scene="res://menu_entry_preview.tscn"',text)
    text+='\n[menu_entry_preview]\nworkspace="'+root.as_posix()+'"\nisolated_profile=true\n'
    (project/'project.godot').write_text(text,encoding='utf-8')
    scene='[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tools/art_bake/main_menu/godot/entry_preview_root.gd" id="1"]\n[node name="EntryPreview" type="Control" groups=["adventure_toolbar_surface"]]\nlayout_mode=3\nanchors_preset=15\nanchor_right=1.0\nanchor_bottom=1.0\ngrow_horizontal=2\ngrow_vertical=2\nscript=ExtResource("1")\n'
    (project/'menu_entry_preview.tscn').write_text(scene,encoding='utf-8')
    mode='smoke' if smoke else 'record';log=root/'reports'/('native_'+mode+'.log')
    command=[settings['godot'],'--path',str(project),'--resolution','1066x600','--position','80,80','--audio-driver','Dummy','--','--record-entries']
    if smoke:command.append('--entry-smoke')
    if verbose:command.insert(1,'--verbose')
    failure=''
    with log.open('wb') as output:
        process=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT,cwd=project)
        start=time.monotonic()
        while process.poll() is None:
            time.sleep(.4)
            current=log.read_text(encoding='utf-8',errors='replace')
            if 'SCRIPT ERROR:' in current or 'SHADER ERROR:' in current:failure='原生脚本/材质错误，详见日志'
            if time.monotonic()-start>360:failure='原生录像超时'
            if failure:
                subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True);process.wait();break
    result=log.read_text(encoding='utf-8',errors='replace')
    if failure or process.returncode!=0 or 'ENTRY_RECORD_COMPLETE' not in result or 'ERROR:' in result:
        raise RuntimeError((failure or '原生录像未干净完成')+'\n'+result[-9000:])
    assert hashlib.sha256(source_project.read_bytes()).hexdigest()==original_hash
    evidence={'project_manifest':str(project/'project.godot'),'production_project_sha256':original_hash,'production_startup_unchanged':True,'isolated_user_directory':'PVZ-Menu9A-Isolated-20261112','real_game_services':True,'mode':mode,'runtime_errors':False}
    (root/'reports'/('native_'+mode+'_environment.json')).write_text(json.dumps(evidence,indent=2),encoding='utf-8')
    print('NATIVE_ENTRY_PREVIEW_COMPLETE',json.dumps(evidence),flush=True)
