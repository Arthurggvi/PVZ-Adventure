"""从本地素材包恢复干净检出所需的源文件与导入设置。"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile


LEGACY_DIRECTORIES = {
    "assets/all_reanim/", "assets/audio/", "assets/fonts/",
    "assets/image/", "assets/reanim/",
}
STAGE_MUSIC = {
    "mus_delicious_island_night_boss.mp3",
    "mus_floating_island_night_elite.mp3",
    "mus_floating_island_night_pre.mp3",
}
MANIFEST = "overlay-manifest.json"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[2]
    tracked = set(subprocess.check_output(
        ["git", "-C", str(project), "ls-files", "-z"]
    ).decode("utf-8").casefold().split("\0"))
    with zipfile.ZipFile(args.archive) as archive:
        entries = json.loads(archive.read(MANIFEST))["files"]
        names = {p.filename for p in archive.infolist() if not p.is_dir()}
        if names != set(entries) | {MANIFEST} or len(names) != len(archive.infolist()):
            raise SystemExit("素材包文件清单与 ZIP 不一致")
        destinations = {}
        # 先核对全部目标和内容，再写入缺少的文件。
        for name, record in entries.items():
            path = Path(name)
            target = (project / path).resolve()
            if not (any(name.startswith(d) for d in LEGACY_DIRECTORIES)
                    or path.parent.as_posix() == "resources/adventure/audio"
                    and path.name.removesuffix(".import") in STAGE_MUSIC):
                raise SystemExit(f"素材包包含不受支持的路径 {name}")
            if (not target.is_relative_to(project) or name.casefold() in tracked
                    or path.as_posix() != name or ".." in path.parts
                    or "\\" in name or ":" in name):
                raise SystemExit(f"素材目标与仓库路径冲突 {name}")
            key = str(target).casefold()
            if key in destinations:
                raise SystemExit(f"素材目标重复 {name}")
            destinations[key] = (name, target)
            with archive.open(name) as source:
                digest = hashlib.file_digest(source, "sha256").hexdigest()
            if digest != record["sha256"] or archive.getinfo(name).file_size != record["bytes"]:
                raise SystemExit(f"素材包内容校验失败 {name}")
            if target.exists():
                with target.open("rb") as existing:
                    if hashlib.file_digest(existing, "sha256").hexdigest() != digest:
                        raise SystemExit(f"素材与本地内容不同 {name}")
        restored = 0
        for name, target in destinations.values():
            if target.exists():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(name) as source, target.open("xb") as dest:
                shutil.copyfileobj(source, dest)
            restored += 1
    print(f"已校验 {len(entries)} 个文件，恢复 {restored} 个")


if __name__ == "__main__":
    main()
