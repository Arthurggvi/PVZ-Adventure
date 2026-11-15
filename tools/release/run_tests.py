"""运行 Adventure 测试场景并记录隔离档案、退出码与 Godot 日志。"""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time


GRAPHICAL = {
    "test_battle_uid_binding", "test_black_general_native_rig", "test_boot_to_menu", "test_cheat_pointer",
    "test_destination_picker", "test_island_flow", "test_research_preview",
    "test_scene_transition_frames", "test_threaded_battle_route", "test_toolbar_smoke",
}
ERROR = re.compile(r"^(?:SCRIPT ERROR:|SHADER ERROR:|ERROR:|FAIL\b)")
MARKER = re.compile(r"^(?:PASS\b|ALL_STAR_ORIGINAL_|[A-Z0-9_]+_(?:PASS|OK)|Tab\+O_HIT_PASS)")
FIXTURES = {"test_loading_target"}
LOG_LIMIT = 3 * 1024 * 1024
TIMEOUT = 140
PROFILE = re.compile(r'OS\.get_user_data_dir\(\)\.contains\("([^"]+)"\)')


def run_bounded(command: list[str], project: Path, env: dict, log: Path, engine_log: Path) -> int | str:
    deadline = time.monotonic() + TIMEOUT
    occurrences = Counter()
    pending = b""
    reason = None
    with log.open("wb") as stream, log.open("rb") as reader:
        process = subprocess.Popen(command, cwd=project, env=env, stdout=stream, stderr=subprocess.STDOUT)
        while process.poll() is None:
            if time.monotonic() >= deadline:
                reason = "timeout"
            elif log.stat().st_size > LOG_LIMIT or (
                engine_log.is_file() and engine_log.stat().st_size > LOG_LIMIT
            ):
                reason = "log limit"
            else:
                lines = (pending + reader.read(65536)).split(b"\n")
                pending = lines.pop()
                for line in lines:
                    decoded = line.decode("utf-8", errors="replace").strip()
                    if ERROR.search(decoded):
                        occurrences[decoded] += 1
                        if occurrences[decoded] > 20:
                            reason = "repeated diagnostic"
                            break
            if reason:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=6, check=False)
                if process.poll() is None:
                    process.kill()
                break
            time.sleep(0.1)
        status = process.wait(timeout=10)

    if engine_log.is_file() and engine_log.stat().st_size > LOG_LIMIT:
        reason = reason or "log limit"
    if log.stat().st_size > LOG_LIMIT:
        reason = reason or "log limit"
        with log.open("r+b") as stream:
            stream.truncate(LOG_LIMIT)
    # Windows may still have the file open just after terminating Godot.
    for _ in range(10):
        try:
            engine_log.unlink(missing_ok=True)
            break
        except PermissionError:
            time.sleep(0.1)
    else:
        print(f"保留暂时被占用的引擎日志 {engine_log}", flush=True)
    return reason or status


def run_case(engine: Path, project: Path, output: Path, scene: Path) -> dict:
    name = scene.stem
    script = re.search(r'path="res://([^"]+\.gd)"', scene.read_text(encoding="utf-8"))
    source = (project / script[1]).read_text(encoding="utf-8") if script else ""
    profile_guard = PROFILE.search(source)
    suffix = "-" + profile_guard[1] if profile_guard else ""
    profile = output / "profiles" / (name + suffix)
    profile.mkdir(parents=True)
    local = profile / "local"
    temp = profile / "tmp"
    local.mkdir()
    temp.mkdir()
    mode = ["--resolution", "1066x600", "--max-fps", "60"] if name in GRAPHICAL else ["--headless"]
    engine_log = profile / "engine.log"
    command = [
        str(engine), "--path", str(project), "--log-file", str(engine_log), *mode,
        "--scene", f"res://{scene.relative_to(project).as_posix()}",
    ]
    log_name = name + ".log"
    log = output / log_name
    start = time.monotonic()
    env = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(local), TEMP=str(temp), TMP=str(temp))
    status = run_bounded(command, project, env, log, engine_log)
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
    cases = {
        p.stem: p for p in sorted((project / "tests" / "adventure").glob("*.tscn"))
        if p.stem not in FIXTURES
    }
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
