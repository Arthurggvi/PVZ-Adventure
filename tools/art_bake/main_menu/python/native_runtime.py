"""正式菜单隔离预览；只写指定工作目录和明确隔离user目录。"""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,time


def run(workspace: Path, tools_config: Path, smoke: bool=False, quick: bool=False, verbose: bool=False) -> None:
    W=Path(workspace).resolve()
    R=Path(__file__).resolve().parents[4]
    P=W/'native_project';P.mkdir(exist_ok=True);cache=P/'.godot';cache.mkdir(exist_ok=True)
    for name in ['assets','resources','scenes','scripts','animation','data','addons','shaders','shader_material','tools']:
     if (R/name).is_dir() and not (P/name).exists():subprocess.run(['cmd','/c','mklink','/J',str(P/name),str(R/name)],check=True,capture_output=True)
    for name in ['global_script_class_cache.cfg','uid_cache.bin','scene_groups_cache.cfg']:
     if (R/'.godot'/name).exists():shutil.copy2(R/'.godot'/name,cache/name)
    if not (cache/'imported').exists():subprocess.run(['cmd','/c','mklink','/J',str(cache/'imported'),str(R/'.godot/imported')],check=True,capture_output=True)
    for name in ['default_bus_layout.tres','pvz_icon.ico','icon.svg','icon.svg.import']:
     if (R/name).exists():shutil.copy2(R/name,P/name)
    text=(R/'project.godot').read_text(encoding='utf-8')
    text=re.sub(r'(?m)^config/name=.*','config/name="PVZ 9B Runtime Review"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="PVZ-Menu9B-Isolated-20261112"',text)
    text=re.sub(r'(?m)^run/main_scene=.*','run/main_scene="res://scenes/main/01StartMenuCoastal.tscn"',text)
    # recorder必须在已有autoload之后初始化，才能通过原服务创建临时档案。
    match=re.search(r'(?ms)(\[autoload\]\n)(.*?)(?=\n\[|\Z)',text)
    assert match
    text=text[:match.end()]+ '\nRuntimeReview="*res://tools/art_bake/main_menu/godot/runtime_record.gd"\n'+text[match.end():]
    text+='\n[menu_runtime_preview]\nworkspace="'+W.as_posix()+'"\n'
    (P/'project.godot').write_text(text,encoding='utf-8')
    settings=json.loads(tools_config.read_text(encoding='utf-8-sig'))
    log=W/'reports'/('runtime_smoke.log' if smoke else 'runtime_record.log')
    command=[settings['godot'],'--path',str(P),'--resolution','1066x600','--position','80,80','--audio-driver','Dummy','--']
    if smoke:command+=['--runtime-smoke']
    if verbose:command.insert(1,'--verbose')
    if quick:command.append('--runtime-quick')
    failure=''
    with log.open('wb') as out:
     process=subprocess.Popen(command,stdout=out,stderr=subprocess.STDOUT,cwd=P);start=time.monotonic()
     while process.poll() is None:
      time.sleep(.4);current=log.read_text(encoding='utf-8',errors='replace')
      if any(k in current for k in ['SCRIPT ERROR:','SHADER ERROR:','Parse Error:']):failure='Native script/shader error'
      if time.monotonic()-start>(90 if smoke else 480):failure='Native recording timeout'
      if failure:
       subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True);process.wait();break
    result=log.read_text(encoding='utf-8',errors='replace')
    if failure or process.returncode!=0 or 'ERROR:' in result or ('MENU9B_BOOT_OK' if smoke else 'MENU9B_RECORD_OK') not in result:
     raise RuntimeError((failure or 'Missing completion')+'\n'+result[-14000:])
    print(result[-6000:],flush=True)
    print('NATIVE_RUNTIME_REVIEW_COMPLETE',flush=True)
