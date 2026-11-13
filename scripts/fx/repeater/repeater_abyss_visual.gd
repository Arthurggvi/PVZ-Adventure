## 地狱弹的单层空间吸力视觉；黑色核心、体积环流和崩塌均由解析战斗时间驱动。
extends Node2D
class_name RepeaterAbyssVisual

## GPU解析黑洞替代两套循环翻页的低帧传送贴图。
const ABYSS_SHADER: Shader = preload("res://shaders/repeater/repeater_abyss_vortex.gdshader")
## 一张小画布即可完整承载漩涡；像素面积与真实棋盘格距相关。
var _disk: Sprite2D
## 本场独立材质只接收秒数和视觉预算。
var _ink: ShaderMaterial
## 当前可见战斗时间，冻结画面不会自行转动。
var _age: float = 0.0
## 结束时向内坍缩，不让动画无限循环。
var _lifetime: float = 5.0

## [param pitch] 决定本场画布尺寸，[param lifetime] 和战斗场寿命严格一致。
func configure(pitch: Vector2, lifetime: float) -> void:
	_lifetime = maxf(0.01, lifetime)
	_disk = Sprite2D.new()
	_disk.texture = RepeaterVisualPalette.halo_texture() # 共用UV载体，不重复生成纹理。
	_disk.scale = Vector2(maxf(96.0, pitch.x * 1.65), maxf(112.0, pitch.y * 1.36)) / _disk.texture.get_size()
	_ink = ShaderMaterial.new()
	_ink.shader = ABYSS_SHADER
	_disk.material = _ink
	add_child(_disk)
	_ink.set_shader_parameter(&"lifetime", _lifetime)
	set_age(0.0)

## 只更新两个着色器标量，视觉质量变化不重新创建材质或节点。
func set_age(seconds: float) -> void:
	_age = clampf(seconds, 0.0, _lifetime)
	visible = _age < _lifetime
	_ink.set_shader_parameter(&"age", _age)
	_ink.set_shader_parameter(&"quality", RepeaterVisualBudget.quality())
	queue_redraw()

## 短促黑紫裂隙与吸入碎屑：近场8条解析曲线，低预算自动关闭。
func _draw() -> void:
	var t: float = _age # 使用场的唯一生命周期。
	if t < 0.21:
		var slash: float = 1.0 - RepeaterVisualPalette.smooth(t / 0.21) # 先撕裂后扩张。
		var half: float = 8.0 + RepeaterVisualPalette.out_cubic(t / 0.21) * 46.0
		draw_line(Vector2(0, -half), Vector2(0, half), Color(0.65, 0.16, 0.95, slash), 2.5, true)
		draw_line(Vector2(-3, -half * 0.7), Vector2(3, half * 0.7), Color(1.0, 0.61, 0.82, slash * 0.85), 1.2, true)
		return
	var quality: int = RepeaterVisualBudget.quality() # 高负载不画无碰撞的灰烬。
	if quality == RepeaterVisualBudget.CHEAP:
		return
	var count: int = 8 if quality == RepeaterVisualBudget.FULL else 4 # 单节点多线段而非独立粒子。
	var ending: float = RepeaterVisualPalette.smooth((_lifetime - t) / 0.48)
	for i: int in range(count):
		var phase: float = float(i) * TAU / float(count) + t * 0.40 # 缓慢的吸入轨道。
		var fraction: float = fposmod(t * (0.18 + float(i % 3) * 0.02) + float(i) * 0.13, 1.0)
		var radius: float = 42.0 * (1.0 - RepeaterVisualPalette.smooth(fraction)) # 灰烬逐渐向内加速。
		var point: Vector2 = Vector2(cos(phase + fraction * 1.45) * radius, sin(phase + fraction * 1.45) * radius * 0.72)
		var inward: Vector2 = (Vector2.ZERO - point).normalized()
		draw_line(point - inward * 6.0, point + inward * 3.0,
			Color(0.53, 0.22, 0.68, ending * (1.0 - fraction) * 0.62), 1.0, true)
