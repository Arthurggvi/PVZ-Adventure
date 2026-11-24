"""在独立的 Godot 用户目录中生成 UID #1 的发放副本。"""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("godot", type=Path, help="本机 Godot 编辑器可执行文件")
    parser.add_argument("source", type=Path, help="已核实归属的首通者 GlobalSaveGame.json")
    parser.add_argument("destination", type=Path, help="尚未创建的发放副本目录")
    args = parser.parse_args()
    if sys.platform not in ("win32", "linux"):
        parser.error("请在 Windows 或 Linux 上运行，以隔离 Godot 的用户目录。")
    if not args.godot.is_file():
        parser.error("找不到指定的 Godot 可执行文件。")
    project = Path(__file__).resolve().parents[1]

    with tempfile.TemporaryDirectory(prefix="pvz_badge_issue_", dir=project.parent) as directory:
        env = os.environ.copy()
        env.update(APPDATA=directory, LOCALAPPDATA=directory, XDG_DATA_HOME=directory,
                   XDG_CONFIG_HOME=directory, PVZ_BADGE_ISSUE_ISOLATED=directory)
        log = Path(directory) / "godot.log"
        command = [str(args.godot.resolve()), "--headless", "--path", str(project),
                   "--log-file", str(log), "--scene", "res://tools/issue_valhalla_badge.tscn",
                   "--", str(args.source.resolve()), str(args.destination.resolve())]
        with subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as process:
            deadline = time.monotonic() + 25
            stopped = False
            while process.poll() is None:
                if time.monotonic() >= deadline or (log.exists() and log.stat().st_size > 4 * 1024 * 1024):
                    process.kill()
                    stopped = True
                    break
                time.sleep(0.05)
        if log.exists():
            with log.open("rb") as stream:
                stream.seek(max(0, log.stat().st_size - 8192))
                sys.stdout.reconfigure(encoding="utf-8")
                print(stream.read(8192).decode("utf-8", errors="replace").strip())
        if stopped:
            parser.exit(1, "Godot 运行超时或日志达到上限，发放已中止。\n")
        return process.returncode


if __name__ == "__main__":
    raise SystemExit(main())
