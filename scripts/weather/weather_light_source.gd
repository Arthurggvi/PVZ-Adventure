## 静态背景光源与动态实体共用的可复用光照描述。
extends Resource
class_name WeatherLightSource

## 在权威战场背景纹理中的归一化锚点位置。
@export var background_uv: Vector2 = Vector2(0.5, 0.5)
## 对雨/雾/水珠有效的光色。
@export var color: Color = Color(0.75, 0.85, 1.0)
## 受光半径（屏幕像素）。
@export_range(4.0, 280.0, 1.0) var radius_px: float = 100.0
## 在光场中发出的亮度。
@export_range(0.0, 3.0, 0.02) var intensity: float = 1.0
## 灯光随机微闪幅度；月亮等稳定光源设为 0。
@export_range(0.0, 0.4, 0.01) var flicker: float = 0.0
