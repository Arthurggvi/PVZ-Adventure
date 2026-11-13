## 条纹遮阳棚装饰；矢量绘制适配任意窗口，不含交互或业务状态。
extends Control

## 绿白相间棚布和金色挂边。
func _draw() -> void:
	var stripe_width: float = size.x / 24.0 # 按总宽均分，避免缩放后边缘留缝。
	for index: int in range(24): # 每段下缘用半圆模拟布帘垂坠。
		var color := Color("56794a") if index % 2 == 0 else Color("e8dabb") # 两种棚布颜色。
		draw_rect(Rect2(index * stripe_width, 0, stripe_width, size.y - 8), color)
		draw_circle(Vector2((index + 0.5) * stripe_width, size.y - 9), stripe_width * 0.5, color)
	draw_line(Vector2.ZERO, Vector2(size.x, 0), Color("d0a65f"), 3.0)
