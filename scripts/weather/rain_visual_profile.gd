## 各关卡复用的分层降雨视觉预设；不包含天气开始/结束的逻辑。
extends Resource
class_name RainVisualProfile

## 三层雨幕的雨线密度（每层着色器独立取样）。
@export_range(0.0, 1.0, 0.01) var far_density: float = 0.76
@export_range(0.0, 1.0, 0.01) var middle_density: float = 0.66
@export_range(0.0, 1.0, 0.01) var near_density: float = 0.38
## 各层雨线的亮度混合系数。
@export_range(0.0, 1.0, 0.01) var far_opacity: float = 0.18
@export_range(0.0, 1.0, 0.01) var middle_opacity: float = 0.34
@export_range(0.0, 1.0, 0.01) var near_opacity: float = 0.48
## 雨滴速度倍率、阵风幅度与地面溅射强度。
@export_range(0.1, 3.0, 0.05) var speed: float = 1.25
@export_range(0.0, 2.0, 0.05) var gust_strength: float = 1.0
@export_range(0.0, 2.0, 0.05) var splash_strength: float = 1.1
## 所有雨线的偏冷主色。
@export var rain_color: Color = Color(0.71, 0.82, 0.91, 1.0)
## 地面溅射区域，相对 Rain 场景矩形的 0..1 UV。
@export var ground_bounds: Rect2 = Rect2(0.27, 0.17, 0.47, 0.81)
## 高雨量时压暗环境，避免明月晴空削弱暴雨观感。
@export_range(0.0, 0.35, 0.01) var storm_dim: float = 0.12
