## 仙人掌发射和撞击的共享绘制层；短命效果不占用单独节点或发射器。
extends Node2D

## 玩家需要辨认的不同瞬时事件。
enum Style { HIT, SHOT, FAN, BLOOM, CHARGE, THUNDER_MARK }
## 屏幕内允许同时存在的瞬时效果数，只限制绘制。
const MAX_FLASHES: int = 64

## 单个短命事件，全部坐标保存在当前特效层。
class Flash:
	## 绘制样式。
	var style: Style
	## 世界命中或枪口换算出的本地坐标。
	var position: Vector2
	## 枪口朝向或阶段点数，由样式决定。
	var facing: Vector2
	## 各路线的主要提示色。
	var tint: Color
	## 从事件触发算起的总持续秒数。
	var duration: float
	## 从触发开始已经经过的战斗秒数。
	var elapsed: float = 0.0
	## 用来错开碎片排布的稳定取值。
	var phase: float

## 仍在屏幕上播放的列表，上限由密集战场保护。
var _flashes: Array[Flash] = []
## 只影响视觉噪点，不改变出战随机数。
var _serial: int = 0

## 空场不需要刷新。
func _ready() -> void:
	z_index = 368
	set_process(false)

## 在 [param at] 加入 [param style] 表现，[param heading] 是方向或格子尺寸，[param tint] 提供颜色。
func trigger(style: Style, at: Vector2, heading: Vector2, tint: Color) -> void:
	if _flashes.size() >= MAX_FLASHES:
		if style == Style.HIT or style == Style.SHOT or style == Style.CHARGE or style == Style.THUNDER_MARK:
			return
		_flashes.pop_front()
	var flash := Flash.new() # 一次事件只分配普通数据，不创建场景。
	flash.style = style
	flash.position = to_local(at)
	flash.facing = heading
	flash.tint = tint
	flash.duration = 0.15
	match style:
		Style.FAN: flash.duration = 0.32
		Style.BLOOM: flash.duration = 0.42
		Style.CHARGE: flash.duration = 0.28
		Style.THUNDER_MARK: flash.duration = 0.25
	_serial += 1
	flash.phase = float(_serial % 13) * TAU / 13.0
	_flashes.append(flash)
	set_process(true)
	queue_redraw()

## 按 [param delta] 更新全层寿命，清空后停止处理。
func _process(delta: float) -> void:
	for i: int in range(_flashes.size() - 1, -1, -1): # 小数组反向回收。
		var flash: Flash = _flashes[i] # 当前正在播放的短效果。
		flash.elapsed += delta
		if flash.elapsed >= flash.duration:
			_flashes.remove_at(i)
	queue_redraw()
	if _flashes.is_empty():
		set_process(false)

## 汇总本帧所有可见短效，全部使用原生画布基元。
func _draw() -> void:
	for flash: Flash in _flashes: # 一次绘制调用推进所有枪口和命中反馈。
		var t: float = clampf(flash.elapsed / flash.duration, 0.0, 1.0) # 统一归一化时间。
		var fade: float = 1.0 - t # 末帧自然淡出。
		var at: Vector2 = flash.position # 随世界层变换。
		var heading: float = flash.facing.angle() # 散射覆盖左右方向。
		match flash.style:
			Style.SHOT:
				draw_circle(at + flash.facing * 5.0, 3.0 + t * 7.0, Color(flash.tint, 0.74 * fade), true, -1.0, true)
				draw_line(at - flash.facing * 3.0, at + flash.facing * (12.0 + 10.0 * t), Color(Color.WHITE, 0.87 * fade), 1.25, true)
			Style.FAN:
				var radius: float = 12.0 + 86.0 * t # 金属锐光从真实枪口展开。
				draw_arc(at, radius, heading - PI / 6.0, heading + PI / 6.0, 22, Color(flash.tint, fade * 0.62), 2.1, true)
				draw_arc(at, radius * 0.75, heading - PI / 6.0, heading + PI / 6.0, 17, Color("effbff", fade * 0.62), 1.2, true)
				for i: int in range(5): # 边缘细亮线强调十发齐射的张开过程。
					var ray: Vector2 = Vector2.from_angle(heading + lerpf(-PI / 6.0, PI / 6.0, i / 4.0))
					draw_line(at + ray * radius * 0.61, at + ray * radius, Color(flash.tint, 0.35 * fade), 1.5, true)
			Style.BLOOM:
				var radius: float = 9.0 + 54.0 * t # 亡语从尸体向外开花。
				draw_arc(at, radius, 0.0, TAU, 30, Color(flash.tint, fade * 0.72), 2.3, true)
				draw_arc(at, radius * 0.65, 0.0, TAU, 24, Color("efceff", fade * 0.52), 1.2, true)
				_sparks(at, flash.tint, flash.phase, 10, radius, fade)
			Style.CHARGE:
				draw_arc(at, 9.0 + 13.0 * t, flash.phase, flash.phase + TAU * 0.7, 15, Color(flash.tint, fade * 0.65), 1.4, true)
				_sparks(at, flash.tint, flash.phase, 3, 9.0 + 11.0 * t, fade)
			Style.THUNDER_MARK:
				for mark: int in range(int(flash.facing.x)): # 每格灯只对应当前真实的一层惊雷。
					var angle: float = PI + mark * 0.46 # 小弧围住受击点上缘，不覆盖僵尸表情。
					draw_arc(at, 21.0 + 2.5 * t, angle, angle + 0.28, 5, Color(flash.tint, fade * 0.88), 2.25, true)
			_:
				_sparks(at, flash.tint, flash.phase, 4, 2.0 + 19.0 * t, fade)

## 从 [param at] 按 [param phase] 发出 [param count] 条短尖线，沿 [param radius] 散开并按 [param fade] 淡出。
func _sparks(at: Vector2, tint: Color, phase: float, count: int, radius: float, fade: float) -> void:
	for i: int in range(count): # 样式间共用同一碎光形态。
		var ray: Vector2 = Vector2.from_angle(phase + i * TAU / count) # 画面相位确定，无逐帧抖动。
		draw_line(at + ray * radius * 0.56, at + ray * (radius + 4.0), Color(tint, 0.75 * fade), 1.45, true)
