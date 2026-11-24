## 灯条引爆后的白热爆心、扩散压力波、上升发光雾与水中气泡。
extends Node2D
class_name MingLanternUnderwaterBlast

## 局部爆炸材质，使用与 [member FIELD_BOUNDS] 一致的归一化坐标。
const BLAST_SHADER: Shader = preload("res://shaders/adventure/wonderland/ming_lantern_blast.gdshader")
## 以 3×3 半宽高为单位，预留两侧压力波和上方雾带的空间。
const FIELD_BOUNDS := Rect2(-1.54, -1.74, 3.08, 3.02)
## 末尾微泡消失后释放整个效果，单位为战斗秒。
const LIFETIME := 2.08
## 单次爆炸允许绘制的气泡数，连爆时每次保持同样的开销上限。
const BUBBLE_COUNT := 44
## 疏散喷发角度的黄金角，单位为弧度。
const GOLDEN_ANGLE := 2.39996323

## 由演出在入树前传入的 3×3 世界半宽、半高，单位为像素。
var extent := Vector2(132.0, 105.0)
## 入树后的战斗秒数，暂停时冻结。
var _age := 0.0
## 爆炸的局部体积材质，仅由当前实例写入。
var _field: ShaderMaterial
## 参与本次喷发的气泡，入树后只读初始条件。
var _bubbles: Array[Bubble] = []
## 当前帧白热爆心的强度，供体积与环境照明共用。
var _flash := 1.0
## 以 [member extent] 为单位的压力波传播半径。
var _pressure_radius := 0.08
## 压力波可见度，波越远越弱。
var _pressure := 0.0
## 爆后雾带可见度，随残余发光退去。
var _haze := 0.0
## 雾带相对爆心的归一化位置，随水中浮升与侧流移动。
var _haze_center := Vector2.ZERO
## 单次爆炸的横向流向，决定雾带向哪侧上扬。
var _drift := 0.0

## 一个气泡的初始条件。各帧用解析轨迹绘制，避免步进误差累积。
class Bubble:
	## 爆心附近的出生点，单位为局部像素。
	var origin: Vector2
	## 受压力波推动的初始速度，单位为像素每秒。
	var launch: Vector2
	## 浮力和液体阻力平衡后的速度，单位为像素每秒。
	var terminal: Vector2
	## 线性水阻系数，单位为每秒。
	var drag: float
	## 从爆炸到气泡生成的延时，单位为秒。
	var delay: float
	## 从生成到溶散的时间，单位为秒。
	var lifetime: float
	## 未变形时的气泡直径，单位为像素。
	var diameter: float
	## 气泡偏离浮升轴的横向涡流振幅，单位为像素。
	var eddy: float
	## 回弹和侧涡的弧度相位，各泡错开。
	var phase: float

## 建立一个局部透明体积与确定性的气泡喷发序列。
func _ready() -> void:
	var rng := RandomNumberGenerator.new() # 只取格中心作为随机种子，不改动战斗随机序列。
	rng.seed = hash(Vector2i(global_position.round()))
	_drift = rng.randf_range(-0.18, 0.18)
	_field = ShaderMaterial.new()
	_field.shader = BLAST_SHADER
	_field.set_shader_parameter(&"pattern_seed", rng.randf_range(1.0, 87.0))
	var volume := ColorRect.new() # 一个透明矩形合成全部体积，气泡沿父节点绘制在前方。
	volume.mouse_filter = Control.MOUSE_FILTER_IGNORE
	volume.show_behind_parent = true
	volume.position = FIELD_BOUNDS.position * extent
	volume.size = FIELD_BOUNDS.size * extent
	volume.material = _field
	add_child(volume)
	_seed_bubbles(rng)
	_update_field()

## 使用 [param rng] 给各泡分配不同的压力喷射、浮力和涡流。
func _seed_bubbles(rng: RandomNumberGenerator) -> void:
	var start_angle: float = rng.randf_range(0.0, TAU) # 相邻格的喷发朝向有所区别。
	for index: int in range(BUBBLE_COUNT): # 黄金角排布后略微偏摆，避免成条向外射出。
		var bubble := Bubble.new() # 仅存储解析轨迹的初始条件。
		var direction := Vector2.from_angle(start_angle + index * GOLDEN_ANGLE + rng.randf_range(-0.25, 0.25)) # 以爆心为原点的喷射方向。
		var size_bias: float = pow(rng.randf(), 2.1) # 小泡占多数，中间混入足以辨认形变的大泡。
		bubble.origin = direction * extent * rng.randf_range(0.03, 0.115)
		bubble.launch = direction * extent * Vector2(1.0, 0.78) * rng.randf_range(2.25, 5.9)
		bubble.terminal = Vector2(0.0, -extent.y * (0.18 + size_bias * 0.24 + rng.randf_range(0.0, 0.18)))
		bubble.drag = rng.randf_range(4.5, 7.3)
		bubble.delay = rng.randf_range(0.0, 0.17)
		bubble.lifetime = rng.randf_range(0.55, 1.65) + size_bias * 0.18
		bubble.diameter = lerpf(4.4, 24.0, size_bias)
		bubble.eddy = extent.x * rng.randf_range(0.013, 0.082)
		bubble.phase = rng.randf_range(0.0, TAU)
		_bubbles.append(bubble)

## 推进 [param delta] 个战斗秒，爆后雾与末尾气泡散去后释放节点。
func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	_update_field()
	queue_redraw()

## 从同一时间轴推导爆心、压力前沿、余雾的位置与亮度。
func _update_field() -> void:
	_flash = 1.0 - smoothstep(0.035, 0.245, _age)
	_pressure_radius = 0.08 + 1.26 * (1.0 - exp(-3.65 * _age))
	_pressure = smoothstep(0.009, 0.075, _age) * (1.0 - smoothstep(0.19, 0.71, _age))
	_haze = smoothstep(0.065, 0.36, _age) * (1.0 - smoothstep(0.75, 1.94, _age))
	_haze_center = Vector2(_drift, -0.69) * (1.0 - exp(-_age * 1.03))
	_field.set_shader_parameter(&"age", _age)
	_field.set_shader_parameter(&"flash", _flash)
	_field.set_shader_parameter(&"pressure_radius", _pressure_radius)
	_field.set_shader_parameter(&"pressure", _pressure)
	_field.set_shader_parameter(&"haze", _haze)
	_field.set_shader_parameter(&"haze_center", _haze_center)

## 向 [param lighting] 投射白青爆光、随波前扩散的亮圈和逐渐上升的余雾照明。
func draw_scene_light(lighting: MingLanternLighting) -> void:
	var spill: float = 1.0 - smoothstep(0.075, 0.46, _age) # 附近地面退亮比白热爆心稍晚。
	lighting.cast(self, Vector2.ZERO, extent * Vector2(1.78, 1.46), Color("76d9ff"), spill * 0.94)
	lighting.cast(self, Vector2.ZERO, extent * Vector2(0.73, 0.64), Color("e2ffff"), _flash * 0.88)
	lighting.cast(self, Vector2.ZERO, extent * Vector2(1.0, 0.85) * (_pressure_radius / 0.72),
		Color("91ecff"), _pressure * 0.78, true)
	lighting.cast(self, _haze_center * extent, extent * Vector2(1.29, 0.94), Color("39c6ff"), _haze * 0.34)

## 以解析的阻力与浮升轨迹绘制气泡，同时沿运动方向压扁泡膜并逐渐回弹。
func _draw() -> void:
	for bubble: Bubble in _bubbles: # 仅绘制已生成且未消散的气泡。
		var elapsed: float = _age - bubble.delay # 当前气泡经过的秒数。
		if elapsed < 0.0 or elapsed >= bubble.lifetime:
			continue
		var age_ratio: float = elapsed / bubble.lifetime # 用于浮升膨胀和寿命末尾淡出。
		var retained: float = exp(-bubble.drag * elapsed) # 喷出速度尚未被水阻消耗的比例。
		var drift_time: float = (1.0 - retained) / bubble.drag # 对剩余冲量积分，累计径向位移有上限。
		var drift_axis: Vector2 = bubble.launch - bubble.terminal # 相对于浮力终速的初始速度。
		var point: Vector2 = bubble.origin + drift_axis * drift_time + bubble.terminal * elapsed # 先随压力向外，再逐渐转为上浮。
		var phase: float = bubble.phase + elapsed * 8.2 # 微小侧涡随时间摆动且各泡错开。
		var eddy: float = bubble.eddy * (1.0 - retained) * (1.0 - retained) # 侧涡在高速喷发后才逐渐显现。
		point.x += eddy * sin(phase)
		var velocity: Vector2 = bubble.terminal + drift_axis * retained # 主运动轴决定泡膜压缩的朝向。
		velocity.x += eddy * 8.2 * cos(phase)
		var compression: float = retained * (0.49 - 0.16 * sin(elapsed * 27.0)) # 压力冲量激发衰减回弹。
		var flutter: float = sin(phase * 1.38) * 0.095 * (1.0 - retained) # 上升时仍受水流轻微扰动。
		var shape := Vector2(1.0 - compression + flutter, 1.0 + compression * 0.42 - flutter * 0.5) # 沿运动轴压缩，垂直于运动轴鼓起。
		var diameter: float = bubble.diameter * (0.81 + age_ratio * 0.34) # 浮升过程小幅膨胀。
		var alpha: float = smoothstep(0.0, 0.047, elapsed) * (1.0 - smoothstep(0.55, 1.0, age_ratio)) # 泡膜先显形再消散。
		var rim: float = 0.68 + 0.29 * maxf(_flash, _haze * 0.68) # 泡膜折射邻近爆光和余雾。
		var heading: float = velocity.angle() # 泡膜的压扁方向随喷射和上浮改变。
		var highlight: float = -2.05 - heading # 反射的亮侧留在画面左上方，不随泡膜自转。
		draw_set_transform(point, heading, shape)
		draw_texture_rect(MingLanternArt.BUBBLE, Rect2(Vector2.ONE * -diameter * 0.5, Vector2.ONE * diameter),
			false, Color(0.57 + _flash * 0.34, 0.85 + _flash * 0.14, 1.0, alpha * rim))
		draw_arc(Vector2.ZERO, diameter * 0.43, highlight - 0.58, highlight + 0.58, 9,
			Color("b9f7ff", alpha * rim * 0.88), clampf(diameter * 0.075, 0.7, 1.6), true)
