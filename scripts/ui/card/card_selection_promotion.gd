## 选卡时用种子包右上角的小纸签标记转职；每条刻线代表一次转职。
extends Control

## 共用的纸签轮廓，沿卡面右内缘对齐。
static var _tab_shape := PackedVector2Array([
	Vector2(35, 8), Vector2(47, 8), Vector2(47, 19), Vector2(41, 17), Vector2(35, 19)
])
## 已完成的转职次数；零表示不绘制纸签。
var _tier: int = 0

## 标记为纯装饰，保持卡片按钮负责全部交互。
func _init() -> void:
	name = "SelectionPromotion"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1

## 按 [param tier] 更新纸签上的刻线；卡片业务配置由外层维护。
func configure(tier: int) -> void:
	_tier = tier
	queue_redraw()

## 用一块低饱和金棕纸签与浅色刻线显示阶数，大小远小于左上星章。
func _draw() -> void:
	if _tier <= 0:
		return
	draw_colored_polygon(_tab_shape, Color("806238"))
	draw_line(Vector2(35, 8.5), Vector2(47, 8.5), Color("c2a470"), 1.0)
	for index: int in range(_tier): # 从纸签中心对称排开一至四条短刻线。
		var x: float = 41.0 + 2.5 * (float(index) - (_tier - 1) * 0.5) # 紧凑排列，刻线间留空。
		draw_line(Vector2(x, 11), Vector2(x, 15), Color("fff0c7"), 1.0, true)
