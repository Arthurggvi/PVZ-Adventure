## 时间驱动的可复现阵风场；仅返回偏转与强度，不依赖天气阶段。
extends RefCounted
class_name RainWindField

## 根据游戏时间与幅度返回风矢量，x 表示雨斜率，y 表示暴雨雨帘密度加成。
## [param seconds] 天气自身的运行时间（秒）。
## [param strength] 当前关卡预设允许的阵风幅度。
func sample(seconds: float, strength: float) -> Vector2:
    var base: float = 0.22 * sin(seconds * 0.33 + 0.8)
    var gust: float = pow(maxf(0.0, sin(seconds * 0.54 - 0.8)), 3.0)
    var pulse: float = 0.12 * sin(seconds * 1.9 + 1.1)
    return Vector2((base + 0.72 * gust + pulse) * strength,
        clampf((0.15 + 0.9 * gust) * strength, 0.0, 1.7))
