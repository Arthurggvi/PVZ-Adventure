## 地狱弹的熔火裂隙；单张GPU画布表现黑核与前后吸积盘，少量余烬沿曲线吞入。
extends Node2D
class_name RepeaterAbyssVisual

## 不读取屏幕纹理的解析裂隙，兼容项目的GL渲染器。
const ABYSS_SHADER: Shader = preload("res://shaders/repeater/repeater_abyss_vortex.gdshader")
## 熔火与黑核共用的局部画布，尺寸由格距决定。
var _disk: Sprite2D
## 私有材质避免多个裂隙相互覆盖时间。
var _ink: ShaderMaterial
## 当前可暂停战斗年龄，单位秒。
var _age: float = 0.0
## 场的真实寿命，视觉结束不能延长伤害。
var _lifetime: float = 5.0
## 余烬运动的横纵半径，与GPU画布保持同一尺度。
var _extent: Vector2 = Vector2(76.0, 80.0)
## 每个裂隙独立错相，不使用全局战斗随机流。
var _phase: float = 0.0

## [param pitch] 是真实棋盘格距；[param lifetime] 是战斗场寿命，单位秒。
func configure(pitch: Vector2, lifetime: float) -> void:
	_lifetime = maxf(0.01, lifetime)
	_extent = Vector2(maxf(112.0, pitch.x * 1.90), maxf(128.0, pitch.y * 1.60)) * 0.5
	_phase = float(get_instance_id() % 101) * 0.06221
	_disk = Sprite2D.new()
	_disk.texture = RepeaterVisualPalette.halo_texture()
	_disk.scale = _extent * 2.0 / _disk.texture.get_size()
	_ink = ShaderMaterial.new()
	_ink.shader = ABYSS_SHADER
	_disk.material = _ink
	add_child(_disk)
	_ink.set_shader_parameter(&"lifetime", _lifetime)
	_ink.set_shader_parameter(&"phase", _phase)
	set_age(0.0)

## [param seconds] 由战斗场传入；暂停时光流和余烬一同冻结，结束时隐藏整场。
func set_age(seconds: float) -> void:
	_age = clampf(seconds, 0.0, _lifetime)
	visible = _age < _lifetime
	_ink.set_shader_parameter(&"age", _age)
	_ink.set_shader_parameter(&"quality", RepeaterVisualBudget.quality())
	queue_redraw()

## 在一次绘制内表现开裂尖光与向心余烬；最多六条短曲线，不创建粒子节点。
func _draw() -> void:
	var onset: float = RepeaterVisualPalette.smooth(_age / 0.32) # 先开裂后吸入。
	var ending: float = RepeaterVisualPalette.smooth((_lifetime - _age) / 0.55) # 与GPU共用坍缩节奏。
	if _age < 0.25:
		var flash: float = sin(clampf(_age / 0.25, 0.0, 1.0) * PI) # 闪光只在开裂阶段短促出现。
		var half_length: float = lerpf(8.0, _extent.y * 0.84, RepeaterVisualPalette.out_cubic(_age / 0.25)) # 裂口纵向拉长。
		draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(-15.0, -half_length, 30.0, half_length * 2.0), false, Color(1.0, 0.23, 0.06, flash * 0.42))
		var outer_cut := PackedVector2Array([Vector2(-3.0, -half_length), Vector2(1.0, -half_length * 0.32), Vector2(5.0, -half_length * 0.08), Vector2(1.2, half_length * 0.37), Vector2(3.0, half_length), Vector2(-2.5, half_length * 0.29), Vector2(-5.0, half_length * 0.05), Vector2(-1.4, -half_length * 0.35)]) # 变宽与偏折的裂口两边均收尖。
		draw_colored_polygon(outer_cut, Color(1.0, 0.37, 0.08, flash * 0.90))
		var inner_cut := PackedVector2Array([Vector2(-2.0, -half_length * 0.89), Vector2(1.6, -half_length * 0.07), Vector2(2.0, half_length * 0.84), Vector2(-1.6, half_length * 0.05)]) # 白热尖心没有矩形端盖。
		draw_colored_polygon(inner_cut, Color(1.0, 0.94, 0.72, flash))
	var quality: int = RepeaterVisualBudget.quality() # 高负载只保留GPU主轮廓。
	if quality == RepeaterVisualBudget.CHEAP:
		return
	var count: int = 6 if quality == RepeaterVisualBudget.FULL else 3 # 曲线条数随预算收敛。
	for index: int in range(count): # 每条流线错开出生与吸入时机。
		var progress: float = fposmod(_age * (0.48 + float(index % 3) * 0.055) + float(index) * 0.173, 1.0) # 一次吸入周期。
		var opacity: float = sin(progress * PI) * onset * ending # 两端透明避免轨道跳变。
		var angle: float = float(index) * 2.39996 + _phase # 黄金角让余烬分布自然。
		var points := PackedVector2Array() # 固定四段短尾，最多五个点。
		for step: int in range(5): # 尾端沿历史轨道回溯，始终指向吸入方向。
			var fraction: float = maxf(0.0, progress - float(4 - step) * 0.015) # 短尾的解析历史时刻。
			var radius: float = lerpf(0.91, 0.28, pow(fraction, 1.65)) * ending # 越接近黑核越快。
			var turn: float = angle + fraction * 2.5 + _age * 0.22 # 向内旋转而非直线收缩。
			points.append(Vector2(cos(turn), sin(turn) * 0.69) * _extent * radius)
		draw_polyline(points, Color(0.40, 0.035, 0.10, opacity * 0.48), 2.0, true)
		draw_polyline(points, Color(1.0, 0.31 + progress * 0.32, 0.08, opacity * 0.78), 0.8, true)
		var tip: Vector2 = points[points.size() - 1] # 最靠近黑核的白热尖端。
		var heading: Vector2 = (tip - points[points.size() - 2]).normalized() # 尖端顺着曲线而非朝固定方向。
		draw_line(tip - heading * 1.8, tip + heading * 0.5, Color(1.0, 0.91, 0.62, opacity), 1.5, true)
