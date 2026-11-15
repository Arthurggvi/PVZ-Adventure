## 各天气时间轴复用的降雨混音预设，以当前雨势驱动两层循环。
extends Resource
class_name RainAudioProfile

## 可选暴雨音轨，素材应开启循环。
@export var storm_stream: AudioStream
## 横轴为雨势，纵轴为暴雨混合权重，范围均为 0..1。
@export var storm_mix_curve: Curve
## 暴雨权重为 1 时，原版雨声保留的线性增益比例。
@export_range(0.0, 1.0, 0.01) var base_gain_at_full_mix: float = 1.0
## 暴雨权重为 1 时，暴雨音轨的线性增益。
@export_range(0.0, 1.0, 0.01) var storm_gain_at_full_mix: float = 1.0


## 返回两层雨声的线性增益，x 为原版雨声，y 为暴雨层。
## [param intensity] 归一化雨势，0 时静音，未配暴雨音轨或曲线时沿用原版雨声。
func sample(intensity: float) -> Vector2:
    var level: float = clampf(intensity, 0.0, 1.0) # 用于底层音量及曲线查询的雨势。
    if level == 0.0 or storm_stream == null or storm_mix_curve == null:
        return Vector2(level, 0.0)
    var storm_mix: float = clampf(storm_mix_curve.sample(level), 0.0, 1.0) # 预设在当前雨势下的暴雨权重。
    return Vector2(level * lerpf(1.0, base_gain_at_full_mix, storm_mix), storm_gain_at_full_mix * storm_mix)
