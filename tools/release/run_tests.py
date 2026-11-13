"""运行 Adventure 测试场景并记录隔离档案、退出码与 Godot 日志。"""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


GRAPHICAL = {
    "test_battle_uid_binding", "test_black_general_native_rig", "test_cheat_pointer",
    "test_destination_picker", "test_island_flow", "test_research_preview",
    "test_scene_transition_frames", "test_toolbar_smoke",
}
ERROR = re.compile(r"^(?:SCRIPT ERROR:|SHADER ERROR:|ERROR:|FAIL\b)")
MARKER = re.compile(r"^(?:PASS\b|ALL_STAR_ORIGINAL_|[A-Z0-9_]+_(?:PASS|OK)|Tab\+O_HIT_PASS)")
PROFILE = re.compile(r'OS\.get_user_data_dir\(\)\.contains\("([^"]+)"\)')


def run_case(engine: Path, project: Path, output: Path, scene: Path) -> dict:
    name = scene.stem
    script = re.search(r'path="res://([^"]+\.gd)"', scene.read_text(encoding="utf-8"))
    source = (project / script[1]).read_text(encoding="utf-8") if script else ""
    profile_guard = PROFILE.search(source)
    suffix = "-" + profile_guard[1] if profile_guard else ""
    profile = output / "profiles" / (name + suffix)
    profile.mkdir(parents=True)
    mode = ["--resolution", "1066x600", "--max-fps", "60"] if name in GRAPHICAL else ["--headless"]
    command = [str(engine), "--path", str(project), *mode, "--scene", f"res://{scene.relative_to(project).as_posix()}"]
    log_name = name + ".log"
    log = output / log_name
    start = time.monotonic()
    with log.open("wb") as stream:
        try:
            status = subprocess.run(
                command, env=dict(os.environ, APPDATA=str(profile)), cwd=project,
                stdout=stream, stderr=subprocess.STDOUT, timeout=140, check=False,
            ).returncode
        except subprocess.TimeoutExpired:
            status = "timeout"
    lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    errors = [line for line in lines if ERROR.search(line)]
    markers = [line for line in lines if MARKER.search(line)]
    verdict = "PASS" if status == 0 and not errors else "FAIL"
    print(f"{verdict} {name} ({status}, {len(errors)} errors)", flush=True)
    return {
        "name": name, "command": command, "exit": status, "status": verdict,
        "seconds": round(time.monotonic() - start, 2),
        "log": log_name, "errors": errors, "markers": markers,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot", type=Path)
    parser.add_argument("cases", nargs="*")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[2]
    engine = args.godot.resolve(strict=True)
    if not (project / ".godot" / "global_script_class_cache.cfg").exists():
        parser.error("请先导入当前检出目录")
    cases = {p.stem: p for p in sorted((project / "tests" / "adventure").glob("*.tscn"))}
    if unknown := set(args.cases) - cases.keys():
        parser.error("未知测试 " + ", ".join(sorted(unknown)))
    release = project / ".release"
    release.mkdir(exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="tests-", dir=release))
    print(output, flush=True)
    summary_path = output / "summary.json"
    results = []
    for name in args.cases or list(cases):
        results.append(run_case(engine, project, output, cases[name]))
        summary_path.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    return int(any(result["status"] == "FAIL" for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
