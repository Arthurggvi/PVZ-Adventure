## 明灯的震颤。扩散前沿驱动战斗结算与水面折射，扫过的格子依次受光。
extends Node2D
class_name MingLanternShockRing

## 当前帧达到的归一化半径。最大值 1 只发出一次，细纹阶段不再结算。
signal ring_advanced(radius: float)

## 环形折射、白色波冠和散开的细水纹在同一局部画布上合成。
const SURFACE: Shader = preload("res://shaders/adventure/wonderland/ming_lantern_shock_ring.gdshader")
## 每道可见震颤的鲸鸣，低通与反射尾音已写入素材。
const WHALE: AudioStream = preload("res://resources/audio/sfx/ming_lantern_whale.ogg")
## 震颤影响的格子半径，中心格与两侧共五格。
const GRID_RADIUS := 2
## 水纹在最远对角格中心之外开始退散。
const EXTENT_SCALE := 3.15
## 主环与余波达到完整半径的战斗秒数。
const MAIN_DURATION := 0.88
## 余波的传播稍慢，单位为战斗秒。
const AFTERSHOCK_DURATION := 1.05
## 最后一圈细水纹继续散开的时间，单位为战斗秒。
const DISSIPATION_TIME := 0.58
## 每处被波前扫过的地面保留余光的战斗秒数。
const CELL_LIGHT_TIME := 0.37
## 水圈的半径随此幂增长，场景余光使用对应的逆函数。
const WAVE_EXPONENT := 0.59
## 给最大半径之外的透镜边缘及渐散细纹预留的比例。
const SURFACE_MARGIN := 1.28

## 主环达到最大半径时的横纵世界半径，由演出在入树前设置。
var extent := Vector2(300.0, 220.0)
## 同一震颤的第二道水圈，显示为较轻的余波。
var aftershock := false
## 多个浪交汇时可软化水纹，只影响可见强度。
var brightness := 1.0
## 五格影响区中实际存在的地块，使用世界坐标。
var cell_rects: Array[Rect2] = []
## 入树后经过的战斗秒数。折射、水纹与投光同帧推进。
var _age := 0.0
## 完整扩散所需的战斗秒数，入树时按主环或余波选定。
var _duration := MAIN_DURATION
## 主环和连放余波共用材质，后者的强度较低。
var _strength := 1.0
## 结算与折射共用的当前半径，以 [member extent] 为单位。
var _radius := 0.0
## 投光使用的本地格子矩形，索引与 [member _arrivals] 对应。
var _light_cells: Array[Rect2] = []
## 波前经过各格几何中心的时刻，单位为战斗秒。
var _arrivals := PackedFloat32Array()
## 局部折射材质。每个震颤独立写入时间和半径。
var _surface_material: ShaderMaterial

## 在 [param canvas] 的坐标系准备震颤；[param center] 为世界波心，[param cell_size] 决定水圈长宽。
## [param rectangles] 只包含受光的实际地块；[param faint] 给第二道余波减弱亮度。
static func at_contact(canvas: Node2D, center: Vector2, cell_size: Vector2,
		rectangles: Array[Rect2], faint: bool = false) -> MingLanternShockRing:
	var ring := MingLanternShockRing.new() # 由调用方接入本次结算后再入树。
	ring.position = canvas.to_local(center)
	ring.extent = cell_size * EXTENT_SCALE
	ring.cell_rects = rectangles
	ring.aftershock = faint
	return ring

## 在 [param host] 播放 [param center] 对应的一次鲸鸣；[param faint] 为余波使用较轻的声音。
## 并发声音按同组仍在播放的数量衰减，音尾自然结束或随宿主回收。
static func play_voice(host: Node, center: Vector2, faint: bool = false) -> void:
	var voices := 1 # 本次也计入同组叠音数。
	for effect: Node in host.get_children(): # 其余技能声音使用各自的增益。
		if effect is AudioStreamPlayer and effect.stream == WHALE and effect.playing:
			voices += 1
	var player := AudioStreamPlayer.new() # 余波和主环在不同空间位置略微错开音高。
	player.bus = &"SFX"
	player.stream = WHALE
	player.volume_db = (-6.5 if faint else -2.0) - linear_to_db(sqrt(float(voices)))
	player.pitch_scale = (1.04 if faint else 0.98) + 0.045 * sin(center.dot(Vector2(0.023, 0.017)))
	player.finished.connect(player.queue_free)
	host.add_child(player)
	player.play()

## 生成折射画布，并确定沿途各格被照亮的时间。
func _ready() -> void:
	_duration = AFTERSHOCK_DURATION if aftershock else MAIN_DURATION
	_strength = (0.64 if aftershock else 1.0) * brightness
	var inverse: Transform2D = global_transform.affine_inverse() # 将格子和折射统一到光圈局部坐标。
	for cell: Rect2 in cell_rects: # 用格中心判定通过时刻，与现有震颤的受击范围一致。
		var local: Rect2 = inverse * cell # 给后续投光保留真正的格子尺寸。
		var radius: float = (local.get_center() / extent).length() # 到格中心的归一化椭圆距离。
		if local.has_area() and radius <= 1.0:
			_light_cells.append(local)
			_arrivals.append(_duration * pow(radius, 1.0 / WAVE_EXPONENT))
	_surface_material = ShaderMaterial.new()
	_surface_material.shader = SURFACE
	_surface_material.set_shader_parameter(&"half_extent", extent)
	_surface_material.set_shader_parameter(&"surface_margin", SURFACE_MARGIN)
	_surface_material.set_shader_parameter(&"phase", global_position.dot(Vector2(0.023, 0.041)) + (2.3 if aftershock else 0.0))
	var surface := ColorRect.new() # 局部透明面片保持在技能层，圆环以外的像素不参与合成。
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.position = -extent * SURFACE_MARGIN
	surface.size = extent * (SURFACE_MARGIN * 2.0)
	surface.material = _surface_material
	add_child(surface)

## [param delta] 推进原有震颤半径。结算结束后让最后一圈细水纹自然散去。
func _process(delta: float) -> void:
	var before: float = _age # 跨过终点时仍发送最后一次满半径结算。
	_age += delta
	_radius = pow(clampf(_age / _duration, 0.0, 1.0), WAVE_EXPONENT)
	if before < _duration:
		ring_advanced.emit(_radius)
	if _age >= _duration + DISSIPATION_TIME:
		queue_free()
		return
	var fade: float = clampf((_age - _duration) / DISSIPATION_TIME, 0.0, 1.0) # 游离的水纹在扩散结束后继续推进。
	_surface_material.set_shader_parameter(&"clock_seconds", _age)
	_surface_material.set_shader_parameter(&"front_radius", _radius)
	_surface_material.set_shader_parameter(&"fade_progress", fade)
	_surface_material.set_shader_parameter(&"intensity", _strength * smoothstep(0.0, 0.18, _radius))

## 把活跃波前及刚被扫过的格子交给 [param lighting]，植物和地面接收同一束反光。
func draw_scene_light(lighting: MingLanternLighting) -> void:
	var front: float = smoothstep(0.03, 0.20, _radius) * (1.0 - smoothstep(0.62, 1.0, _radius)) # 集中的白光在水圈变成细纹前退去。
	lighting.cast(self, Vector2.ZERO, extent * (_radius / 0.72), Color("b8f0ff"), front * _strength * 0.34, true)
	for index: int in range(_light_cells.size()): # 每格的余光只在经过后才开始衰减。
		var elapsed: float = _age - _arrivals[index] # 自波前经过本格中心以来的战斗秒数。
		if elapsed < 0.0 or elapsed >= CELL_LIGHT_TIME:
			continue
		var cell: Rect2 = _light_cells[index] # 由实际棋盘尺寸决定光池大小。
		var glow: float = smoothstep(0.0, 0.05, elapsed) * (1.0 - smoothstep(0.11, CELL_LIGHT_TIME, elapsed)) # 亮斑先托出植物根部，再散回水面。
		lighting.cast(self, cell.get_center() + Vector2(0.0, cell.size.y * 0.12), cell.size * Vector2(0.66, 0.55),
			Color("a4e8ec"), glow * _strength * 0.60)
