## 2D 天气镜头的独立表现参数；关卡逻辑不依赖具体 Shader。
extends Resource
class_name WeatherLensProfile

## 全局柔焦混合系数。
@export_range(0.0, 1.0, 0.01) var soft_focus: float = 0.36
## 亮部泛光的强度系数。
@export_range(0.0, 1.0, 0.01) var bloom_strength: float = 0.62
## 水汽散射雾化系数。
@export_range(0.0, 0.5, 0.005) var haze_strength: float = 0.19
## 镜头水汽的偏冷散射颜色。
@export var haze_color: Color = Color(0.67, 0.76, 0.85)
## 可选光学环境数据；没有光源地图继续使用兼容旧渲染。
@export var light_profile: WeatherLightProfile
## 近景水珠存在感。
@export_range(0.0, 1.0, 0.01) var droplet_strength: float = 0.95
## 镜头水珠的下滑速度倍率。
@export_range(0.1, 3.0, 0.05) var droplet_speed: float = 0.86
## 水珠对背景的光学折射倍率。
@export_range(0.0, 2.0, 0.05) var refraction_strength: float = 1.0
## 鼠标擦拭半径，单位视口像素。
@export_range(10.0, 100.0, 1.0) var wipe_radius: float = 58.0
## 指数擦痕恢复时间常数，单位秒。
@export_range(0.3, 8.0, 0.1) var wipe_recovery_seconds: float = 2.6
## 闪电瞬间的冷白照明幅度，0 为关闭。
@export_range(0.0, 1.0, 0.05) var lightning_strength: float = 0.72
