"""从原生 BT.2020/PQ AVIF 制作保留局部对比度的 SDR 显示图，不改变画幅或锐化原画。"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


# 全分辨率处理；libplacebo 内部浮点完成 PQ、色调和色域映射，最终才抖动至 RGB8。
# 不启用 deband，防止原画的细小笔触被当作色带抹除。
DISPLAY_FILTER = (
    "libplacebo=format=rgba:colorspace=gbr:color_primaries=bt709:"
    "color_trc=iec61966-2-1:range=pc:tonemapping=bt.2390:"
    "gamut_mode=perceptual:peak_detect=1:smoothing_period=0:percentile=100:"
    "contrast_recovery=0.3:deband=0:dithering=blue,format=rgb24"
)


def digest(path):
    """流式计算文件身份，避免再复制完整 8K 文件到内存。"""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=90)
    args = parser.parse_args()
    # 元数据查询限时且仅输出一个视频流；AVIF 原件始终只读。
    ffprobe = args.ffmpeg.with_name("ffprobe" + args.ffmpeg.suffix)
    probe = subprocess.run(
        [str(ffprobe), "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height,pix_fmt,color_range,color_space,color_transfer,color_primaries",
         "-of", "json", str(args.source)],
        capture_output=True, timeout=15, check=True,
    )
    source_info = json.loads(probe.stdout)["streams"][0]
    required = {"width": 8192, "height": 4096, "color_primaries": "bt2020",
                "color_transfer": "smpte2084", "color_space": "bt2020nc", "color_range": "pc"}
    if any(source_info.get(key) != value for key, value in required.items()):
        raise ValueError(f"源文件不是预期的原生 8K BT.2020/PQ 全范围 AVIF: {source_info}")
    if args.output.resolve() == args.source.resolve():
        raise ValueError("不得覆盖原始 HDR 素材")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # 中间 PNG 与输出同目录；完成后原子替换，失败时清理本次临时文件。
    with tempfile.TemporaryDirectory(prefix="hdr_convert_", dir=args.output.parent) as temporary:
        candidate = Path(temporary) / "display.png"
        subprocess.run(
            [str(args.ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin",
             "-threads", "4", "-filter_threads", "2", "-i", str(args.source),
             "-map", "0:v:0", "-vf", DISPLAY_FILTER, "-frames:v", "1", "-update", "1",
             "-y", str(candidate)], timeout=args.timeout, check=True,
        )
        candidate.replace(args.output)
    profile = {
        "revision": "pq_bt2390_perceptual_v1",
        "source_filename": args.source.name,
        "source_sha256": digest(args.source),
        "source_encoding": source_info,
        "display_sha256": digest(args.output),
        "display_encoding": "8192x4096 RGB8 sRGB / Rec.709; SDR display derivative",
        "ffmpeg_filter": DISPLAY_FILTER,
        "tone_mapping": "BT.2390 with same-frame source peak detection, 100th percentile",
        "gamut_mapping": "perceptual",
        "contrast_recovery": 0.3,
        "spatial_resize": False,
        "sharpening": False,
        "debanding": False,
        "native_hdr_output": False,
    }
    profile_path = args.output.with_suffix(".color.json")
    profile_path.write_text(json.dumps(profile, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output), "profile": str(profile_path),
                      "bytes": args.output.stat().st_size}, ensure_ascii=False))


if __name__ == "__main__":
    main()
