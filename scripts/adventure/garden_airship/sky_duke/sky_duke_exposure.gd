## 短时曝光只覆盖飞艇背景画布。实体导弹、操作和预警全部画在其上方。
extends Node2D

## 相邻强曝光的最短间隔，单位为战斗秒。局部气浪在此期间依然可以正常出现。
const MIN_PULSE_GAP := 1.0
## 同帧或相邻帧的两次冲击共用一次亮度包络。
const MERGE_WINDOW := 0.08
## 加亮从峰值恢复常态所用的战斗秒数。
const FADE_SECONDS := 0.24

## 最近一次获准亮度冲击的战斗秒。
var _pulse_start: float = -INF
## 当前可见亮度脉冲的最高 alpha。
var _pulse_power: float = 0.0
## 同一次脉冲稳定的阶段亮色，阶段重叠可让更强的一次接管。
var _pulse_tint := Color.WHITE
## 当前背景叠色，透明时跳过所有绘制。
var _fill := Color.TRANSPARENT


## 放在现有飞艇背景层的最后，活动时也维持在战斗世界层下方。
func _ready() -> void:
	z_index = 60


## 在 [param seconds] 发起 [param power] 归一强度的局部指令曝光。
## [param phase] 决定峰值颜色。相邻动作不重启频闪包络。
func pulse(seconds: float, phase: int, power: float) -> void:
	var age: float = seconds - _pulse_start # 同一次曝光距当前的战斗时间。
	var alpha: float = 0.135 * clampf(power, 0.0, 1.0) # 背景光仍保留明暗纹理。
	if age >= MIN_PULSE_GAP or (age <= MERGE_WINDOW and alpha > _pulse_power):
		if age >= MIN_PULSE_GAP:
			_pulse_start = seconds
		_pulse_power = alpha
		_pulse_tint = Color("ffe8de") if phase >= 2 else Color("e4f6ff")


## 按 [param seconds] 取当前照度。仅在有效蓄势时由 [param charge] 缓缓压低背景。
func update_frame(seconds: float, charge: float) -> void:
	var age: float = seconds - _pulse_start # 过期闪光不会在低帧率时补播。
	var bright: float = _pulse_power * (1.0 - smoothstep(0.035, FADE_SECONDS, age)) # 背景加亮而不覆盖世界。
	var next_fill: Color = _pulse_tint if bright > 0.001 else Color("111929") # 单层复用明与暗的曝光。
	next_fill.a = bright if bright > 0.001 else 0.13 * clampf(charge, 0.0, 1.0)
	if next_fill.a <= 0.001 and _fill.a <= 0.001:
		return
	_fill = next_fill
	queue_redraw()


## 清掉曝光并归还背景原始亮度。
func clear() -> void:
	_pulse_start = -INF
	_pulse_power = 0.0
	_fill = Color.TRANSPARENT
	queue_redraw()


## 只画当前渲染窗口。随正常相机逆变换定位，零 alpha 时不提交绘制。
func _draw() -> void:
	if _fill.a <= 0.001:
		return
	var size: Vector2 = get_viewport_rect().size # 当前游戏内部画布的宽高。
	var inverse: Transform2D = get_global_transform_with_canvas().affine_inverse() # 画布相机独立于输入和近景。
	var quad := PackedVector2Array([inverse * Vector2.ZERO, inverse * Vector2(size.x, 0.0),
		inverse * size, inverse * Vector2(0.0, size.y)]) # 四角覆盖有效视口，保持透视不变。
	draw_colored_polygon(quad, _fill)
