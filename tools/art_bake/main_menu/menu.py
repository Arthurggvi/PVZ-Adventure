"""主菜单美术单入口：配置构建→真实渲染→预览。只写指定工作目录。"""
from pathlib import Path
import argparse, hashlib, importlib, json, os, shutil, subprocess, sys


def fingerprint(paths: list[Path]) -> str:
    digest=hashlib.sha256()
    expanded=[]
    for item in paths:
        expanded.extend(sorted(p for p in item.rglob('*') if p.is_file()) if item.is_dir() else [item])
    for path in sorted(set(expanded)):
        if not path.is_file():raise FileNotFoundError(path)
        digest.update(path.name.encode());digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def build(work: Path, force: bool=False) -> None:
    code=Path(__file__).resolve().parent
    cache=work/'reports/build_cache.json';state=json.loads(cache.read_text()) if cache.exists() else {}
    plan=[
      ('base','base_maps',[work/'master_original.png',work/'config/scene_config.json'],['working_base.png','maps']),
      ('ground','ground_emitters',[work/'config/finish_config.json',work/'working_base.png',work/'maps'],['ground_finished.png','finish_maps']),
      ('light','light_field',[work/'config/attenuation_config.json',work/'config/scene_config.json',work/'master_original.png',work/'maps'],['attenuation_maps']),
      ('harbor','harbor_assets',[work/'config/harbor_layout.json',work/'master_original.png',work/'ground_finished.png',work/'maps/water.png',code/'python/harbor_matte.py'],['assets'])]
    record=[]
    for name,module,inputs,outputs in plan:
        source=code/'python'/f'{module}.py';key=fingerprint(inputs+[source])
        targets=[]
        for relative in outputs:
            path=work/relative
            targets.extend(sorted(p for p in path.rglob('*') if p.is_file()) if path.is_dir() else [path])
        entry=state.get(name,{})
        same_set=set(str(p.relative_to(work)) for p in targets)==set(entry.get('outputs',{}))
        intact=same_set and all(p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==entry.get('outputs',{}).get(str(p.relative_to(work))) for p in targets)
        if not force and key==entry.get('input') and intact:
            record.append({'stage':name,'status':'cached'});print(name+': cached',flush=True);continue
        importlib.import_module('python.'+module).build(work)
        targets=[]
        for relative in outputs:
            path=work/relative
            targets.extend(sorted(p for p in path.rglob('*') if p.is_file()) if path.is_dir() else [path])
        state[name]={'input':key,'outputs':{str(p.relative_to(work)):hashlib.sha256(p.read_bytes()).hexdigest() for p in targets}}
        cache.write_text(json.dumps(state,indent=2),encoding='utf-8')
        record.append({'stage':name,'status':'built'});print(name+': built',flush=True)
    (work/'reports/last_build.json').write_text(json.dumps(record,indent=2),encoding='utf-8')


def stage_runtime(work: Path) -> None:
    source=Path(__file__).resolve().parent/'godot';target=work/'runtime';target.mkdir(exist_ok=True)
    for path in source.iterdir():
        if path.suffix not in {'.gd','.gdshader'}:continue
        shutil.copy2(path,target/path.name)
    (target/'SOURCE_NOTICE.txt').write_text('派生执行副本：不要在此调参或修改源码。源码入口是 tools/art_bake/main_menu。\n',encoding='utf-8')


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['build','render','preview','workfile','all'])
    parser.add_argument('--workspace',type=Path,required=True)
    parser.add_argument('--tools-config',type=Path,required=True)
    parser.add_argument('--force',action='store_true')
    args=parser.parse_args();work=args.workspace.resolve(strict=True)
    (work/'reports').mkdir(exist_ok=True)
    manifest=json.loads((work/'config/pipeline.json').read_text(encoding='utf-8'))
    tools=json.loads(args.tools_config.read_text(encoding='utf-8-sig'))
    assert hashlib.sha256((work/'master_original.png').read_bytes()).hexdigest()==manifest['master_sha256'],'Mother image changed'
    if args.action in ['build','render','all']:build(work,args.force)
    stage_runtime(work)
    if args.action in ['render','all']:
        launcher=args.tools_config.parent/'artctl.py'
        subprocess.run([tools['python'],str(launcher),'godot',str(work/'runtime/capture.gd'),'--run-dir',str(work)],check=True)
    if args.action in ['preview','all']:importlib.import_module('python.previews').build(work,manifest)
    if args.action in ['workfile','all']:
        source=Path(__file__).resolve().parent/'python/workfile.py'
        subprocess.run([tools['python'],str(args.tools_config.parent/'artctl.py'),'gimp',str(source),'--run-dir',str(work)],check=True)
    print('MENU_PIPELINE_OK',flush=True)


if __name__=='__main__':
    try:main()
    except (OSError,ValueError,KeyError,AssertionError,subprocess.CalledProcessError) as error:
        print('MENU_PIPELINE_FAILED: '+str(error),file=sys.stderr);raise SystemExit(1)
