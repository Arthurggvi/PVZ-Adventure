"""把批准的美术工作目录无损发布为原生资源；不把生成脚本或外部路径带入游戏。"""
from pathlib import Path
import hashlib,json,shutil,subprocess


def publish(workspace: Path, tools_config: Path) -> None:
    code=Path(__file__).resolve().parents[1]
    repo=code.parents[2]
    spec=json.loads((code/'runtime_inputs.json').read_text(encoding='utf-8'))
    assert hashlib.sha256((workspace/'master_original.png').read_bytes()).hexdigest()==spec['master_sha256']
    for relative in spec['files']:
        if not (workspace/relative).is_file():raise FileNotFoundError(workspace/relative)
    destination=repo/'assets/adventure/main_menu/coastal'
    (destination/'config').mkdir(parents=True,exist_ok=True)
    for name in spec['configs']:
        shutil.copy2(workspace/'config'/f'{name}.json',destination/'config'/f'{name}.json')
    # daily_cycle/ui_layout属于运行配置，不能被旧工作目录里的归档副本覆盖。
    for name in ['daily_cycle','ui_layout']:
        if not (destination/'config'/f'{name}.json').is_file():raise FileNotFoundError('Runtime config missing: '+name)
    report_dir=workspace/'reports';report_dir.mkdir(exist_ok=True)
    request={'source':str(workspace),'output':str(destination),'files':spec['files'],'report':str(report_dir/'native_resources.json')}
    request_path=report_dir/'publish_runtime_request.json'
    request_path.write_text(json.dumps(request,indent=2),encoding='utf-8')
    tools=json.loads(tools_config.read_text(encoding='utf-8-sig'))
    log=report_dir/'publish_runtime.log'
    with log.open('wb') as stream:
        result=subprocess.run([tools['godot'],'--headless','--path',str(tools_config.parent/'godot'),'--script',str(code/'godot/publish_runtime_pack.gd'),'--',str(request_path)],stdout=stream,stderr=subprocess.STDOUT,timeout=120)
    output=log.read_text(encoding='utf-8',errors='replace')
    if result.returncode!=0 or 'ERROR:' in output or 'NATIVE_MENU_PACK_OK' not in output:
        raise RuntimeError('Native resource publishing failed: '+output[-6000:])
    print('RUNTIME_ASSETS_PUBLISHED',destination,flush=True)
