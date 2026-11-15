## 可复用的风沙视觉预设；颜色与层次属于资源，强度与触发时机属于天气时间轴。
extends Resource
class_name SandVisualProfile

## 背光沙墙的赭色，避免把晴天营地简单染成黄色。
@export var shadow_color: Color = Color(0.46, 0.29, 0.12, 1.0)
## 受光沙脊及近景砂粒的暖金色。
@export var sunlit_color: Color = Color(0.93, 0.72, 0.38, 1.0)
## 背景沙墙的最大混合量；角色在该层之后绘制。
@export_range(0.0, 1.0, 0.01) var wall_opacity: float = 0.72
## 前景扬尘最大混合量；棋盘中央会额外衰减以保留可读性。
@export_range(0.0, 0.6, 0.01) var veil_opacity: float = 0.3
## 风从右向左扫过营地的基础速度，单位为底图像素/秒。
@export_range(10.0, 300.0, 1.0) var wind_speed: float = 95.0
## 阵风对流速、密度的额外影响，0 表示匀速。
@export_range(0.0, 1.0, 0.01) var gust_strength: float = 0.8
## 近景可辨认的砂粒密度，0..1。
@export_range(0.0, 1.0, 0.01) var grain_density: float = 0.62
## 原图中需要保持清晰的战斗区域，以归一化位置和尺寸表示。
@export var clear_bounds: Rect2 = Rect2(0.17, 0.16, 0.54, 0.78)
