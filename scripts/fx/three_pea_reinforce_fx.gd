## 洪流补种沿原株升起两道净化光环；一株固定一个画布节点。
extends Node2D

## 效果寿命，以游戏秒计。
const DURATION: float = 0.66
## 脉冲累计时间，达到寿命后停止刷新画布。
var _elapsed: float = DURATION

## 初装时由叠种提交启动，无空转。
func _ready() -> void:
	z_index = 5
	set_process(false)

## 新叠种重置同一效果，连点不累积节点。
func pulse() -> void:
	_elapsed = 0.0
	show()
	set_process(true)
	queue_redraw()

## [param delta] 为可暂停的战斗时间。
func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		hide()
		set_process(false)
	queue_redraw()

## 使用固定数目的弧与叶形高光绘制净化、回复及上限增长。
func _draw() -> void:
	var t: float = clampf(_elapsed / DURATION, 0.0, 1.0) # 统一寿命曲线。
	var alpha: float = (1.0 - t) * (1.0 - t) # 起始清晰，柔和收尾。
	draw_set_transform(Vector2(0.0, -17.0 * t), 0.0, Vector2(1.0, 0.37))
	draw_arc(Vector2.ZERO, lerpf(16.0, 57.0, t), 0.0, TAU, 32, Color(0.28, 1.0, 0.65, alpha), 3.0, true)
	draw_arc(Vector2.ZERO, lerpf(10.0, 42.0, t), 0.0, TAU, 28, Color(0.96, 1.0, 0.63, alpha), 2.0, true)
	draw_set_transform(Vector2.ZERO)
	for index: int in range(7): # 七枚光屑直接画在同一画布上。
		var angle: float = TAU * index / 7.0 + t * 1.1 # 扩散时短暂绕根上升。
		var point: Vector2 = Vector2(cos(angle) * (22.0 + 23.0 * t), sin(angle) * 7.0 - t * (31.0 + 3.0 * index)) # 原株局部像素。
		draw_line(point + Vector2(0.0, -4.0), point + Vector2(0.0, 3.0),
			Color(0.82, 1.0, 0.65, alpha), 2.0, true)
		draw_line(point - Vector2(3.0, 0.0), point + Vector2(3.0, 0.0),
			Color(0.95, 1.0, 0.83, alpha), 1.4, true)
