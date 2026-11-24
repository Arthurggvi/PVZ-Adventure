## 仲裁者的机体、喷口和损伤表现，共用同一节点从巡航过渡到坠毁。
extends Node2D
class_name ArbiterXAirframe

## 尾焰图集每秒采样 30 帧。
const EXHAUST_FPS: float = 30.0
## 尾焰图集按行排列，共 6 行 × 6 列。
const EXHAUST_FRAMES: int = 36
## 两个喷口尾焰共同使用的循环时长，单位为秒。
const CYCLE_SECONDS: float = EXHAUST_FRAMES / EXHAUST_FPS
## 远翼旋转与次爆采用同一个局部轴心，坐标为纹理像素。
const FAR_WING_PIVOT: Vector2 = Vector2(42, -130)
## 近翼旋转与次爆采用同一个局部轴心，坐标为纹理像素。
const NEAR_WING_PIVOT: Vector2 = Vector2(119, 96)
## 机舱内部的爆点，坐标为纹理像素。
const CABIN_BURST_POINT: Vector2 = Vector2(-62, 33)

## 远侧喷口先播放一帧，避免两个尾焰完全同步。
@onready var far_exhaust: Sprite2D = $FarExhaust
## 近侧喷口与巡航时钟同相位。
@onready var near_exhaust: Sprite2D = $NearExhaust
## 黑白闪烁只作用在机壳，避免把已有烟迹和尾焰染成同一个颜色。
@onready var _hull: Sprite2D = $Hull
## 世界坐标的双喷口烟迹，飞机换父节点时保留已生成的烟团。
@onready var _smoke: ArbiterXSmokeTrail = $SmokeTrail
## 半血后的机舱警报，声源跟着机体移动。
@onready var _alarm: AudioStreamPlayer2D = $Alarm
## 高速滑行时的破空声，随加速提高响度。
@onready var _rush: AudioStreamPlayer2D = $Rush

## 上一帧的故障程度，范围 0–1；坠落从此数值继续加重。
var damage_pressure: float = 0.0
## 黑白周期在 0–1 内的相位，更换演出拥有者时延续此值。
var _warning_phase: float = 0.0
## 擦滑从撞地当刻的黑白进度平顺熄灭。
var _contact_warning: Vector2 = Vector2.ZERO
## 主机舱解体之后抛出的远翼与近翼。
var _detached_wings: Array[Sprite2D] = []


## [param seconds] 为继承的尾焰相位时间，[param power] 依次为远侧与近侧的功率，范围 0–1。
func pose_exhaust(seconds: float, power: Vector2 = Vector2.ONE) -> void:
	var frame_index: int = posmod(floori(seconds * EXHAUST_FPS), EXHAUST_FRAMES) # 按行取当前帧。
	far_exhaust.frame = (frame_index + 1) % EXHAUST_FRAMES
	near_exhaust.frame = frame_index
	far_exhaust.self_modulate.a = power.x
	near_exhaust.self_modulate.a = power.y


## 在当前姿态发射烟迹和更新警报。[param delta] 为场景秒数，[param pressure] 为 0–1 的故障强度。
func advance_fault(delta: float, pressure: float) -> void:
	if pressure > 0.0:
		_warning_phase = fposmod(_warning_phase + lerpf(1.05, 2.72, pressure) * delta, 1.0)
		var glow: float = 0.5 - 0.5 * cos(TAU * _warning_phase) # 先黑后白，过渡相位连续。
		var contrast: float = lerpf(0.88, 0.99, pressure) # 俯冲后加强明暗对比。
		_hull.set_instance_shader_parameter(&"warning", Vector2(contrast, smoothstep(0.19, 0.81, glow)))
		if not _alarm.playing:
			_alarm.play()
	elif damage_pressure > 0.0:
		_warning_phase = 0.0
		_hull.set_instance_shader_parameter(&"warning", Vector2.ZERO)
		_alarm.stop()
	damage_pressure = pressure
	var power: Vector2 = Vector2(far_exhaust.self_modulate.a, near_exhaust.self_modulate.a) # 推力下降后烟量加重。
	var smoke_load: Vector2 = (Vector2.ONE - power * 0.31) * pressure # 双喷口的烟量独立变化。
	_smoke.advance(delta, far_exhaust.global_transform, near_exhaust.global_transform, smoke_load)


## 将当前机体交给 [param host] 继续播放，恢复重新入树前的警报进度。
## [param tint] 为旧父节点累积的机体颜色，保留受击、冰冻和等阶染色。
func handoff_to_glide(host: Node2D, tint: Color) -> void:
	var alarm_position: float = _alarm.get_playback_position() if _alarm.playing else -1.0 # 取下旧机体前先保存声音进度。
	reparent(host)
	modulate = tint
	if alarm_position >= 0.0 and not _alarm.playing:
		_alarm.play(alarm_position)
	_rush.bus = SoundManager.spatial_sfx_bus()
	_rush.volume_db = -12.0
	_rush.play()


## [param amount] 为已经加速的比例，0–1 对应破空声从远到近。
func shape_rush(amount: float) -> void:
	_rush.volume_db = lerpf(-12.0, -3.0, amount)


## 停止发射新烟并结束飞行声音，已经形成的尾迹自行动画至散尽。
func release_fault() -> void:
	_alarm.stop()
	_rush.stop()
	_smoke.release()


## 停机后保留此刻机壳的闪烁颜色，供擦地时平顺融入烟尘和火光。
func begin_ground_contact() -> void:
	_contact_warning = _hull.get_instance_shader_parameter(&"warning")
	release_fault()
	far_exhaust.hide()
	near_exhaust.hide()


## 将已经停止的声音和留在世界坐标中的尾迹留在 [param crash]，机身随后可安全独立回收。
func retain_contact_effects(crash: Node2D) -> void:
	_smoke.reparent(crash)
	_alarm.reparent(crash)
	_rush.reparent(crash)


## [param progress] 为擦滑进度，范围 0–1。褪去告警亮度，接上擦地火光。
func pose_scrape(progress: float) -> void:
	_hull.set_instance_shader_parameter(&"warning", _contact_warning * (1.0 - smoothstep(0.0, 0.74, progress)))
	_hull.set_instance_shader_parameter(&"wreck_heat", Vector2(
		0.50 * smoothstep(0.0, 1.0, progress), 0.20 * sin(PI * progress)))


## 用原机壳的互补区域拆出两翼，首帧三块仍贴在原位。
func break_apart() -> void:
	_hull.set_instance_shader_parameter(&"warning", Vector2.ZERO)
	_hull.set_instance_shader_parameter(&"hull_section", 1)
	_detached_wings.assign([_create_wing(2), _create_wing(3)])


## [param seconds] 从爆炸首帧计时，[param heat] 为这一拍实际爆光强度。
## [param opacity] 控制残骸与双翼同步淡退，原尾迹仍按自己的寿命消散。
func pose_wreck(seconds: float, heat: float, opacity: float) -> void:
	var scorch: float = lerpf(0.50, 0.98, smoothstep(0.04, 0.59, seconds)) # 火光变暗后才显出焦色。
	var cool_glow: float = 0.08 * smoothstep(0.2, 0.40, seconds) * (1.0 - smoothstep(0.5, 1.5, seconds)) # 炭化边缘余温。
	var surface := Vector2(scorch, heat + cool_glow) # 三块继承同一束触地反光。
	_hull.set_instance_shader_parameter(&"wreck_heat", surface)
	_hull.self_modulate.a = opacity

	var lift: float = clampf(seconds / 0.54, 0.0, 1.0) # 远翼弹起后再落回。
	var slide: float = clampf(seconds / 0.66, 0.0, 1.0) # 近翼短暂划过地面。
	_pose_wing(_detached_wings[0], FAR_WING_PIVOT, _far_wing_drift(seconds, lift),
		0.36 * ease(lift, 0.52), surface, opacity)
	_pose_wing(_detached_wings[1], NEAR_WING_PIVOT, _near_wing_drift(slide),
		-0.30 * ease(slide, 0.50), surface, opacity)


## [param index] 选定原机械部位，[param seconds] 为爆炸后时间。返回相对于机身的原次爆位置。
static func wreck_burst_offset(index: int, seconds: float) -> Vector2:
	match index:
		0:
			return FAR_WING_PIVOT + _far_wing_drift(seconds, clampf(seconds / 0.54, 0.0, 1.0))
		1:
			return NEAR_WING_PIVOT + _near_wing_drift(clampf(seconds / 0.66, 0.0, 1.0))
	return CABIN_BURST_POINT


## [param seconds] 和 [param lift] 为远翼抛飞时间及归一进度，返回原翼片的局部位移。
static func _far_wing_drift(seconds: float, lift: float) -> Vector2:
	var bounce: float = sin(PI * clampf((seconds - 0.54) / 0.12, 0.0, 1.0)) # 远翼拍地后的短回弹。
	var y: float = 108.0 * lift * lift - 55.0 * sin(PI * lift) - 9.0 * bounce # 上抛后落向机身后方。
	return Vector2(110.0 * ease(lift, 0.53), y)


## [param slide] 是近翼归一进度，返回近翼擦过地面并停住的局部位移。
static func _near_wing_drift(slide: float) -> Vector2:
	return Vector2(-90.0 * ease(slide, 0.50), 14.0 * slide * slide - 15.0 * sin(PI * slide))


## 完成 [method break_apart] 后，返回远翼、近翼和机舱的实际绘制节点。
func wreck_burst_pieces() -> Array[Node2D]:
	var pieces: Array[Node2D] = [_detached_wings[0], _detached_wings[1], self] # 顺序与各自局部爆点一致。
	return pieces


## [param index] 依次选远翼、近翼和机舱，返回此刻的世界爆点。
func wreck_burst_origin(index: int) -> Vector2:
	match index:
		0:
			return _detached_wings[0].to_global(FAR_WING_PIVOT)
		1:
			return _detached_wings[1].to_global(NEAR_WING_PIVOT)
	return to_global(CABIN_BURST_POINT)


## [param section] 对应机壳着色器中的翼片区域，初始坐标与原机壳相同。
func _create_wing(section: int) -> Sprite2D:
	var wing := Sprite2D.new() # 同一纹理中的一片翼壳，无需额外贴图。
	wing.centered = _hull.centered
	wing.offset = _hull.offset
	wing.texture = _hull.texture
	wing.material = _hull.material
	add_child(wing)
	if section == 2:
		move_child(wing, _hull.get_index())
	wing.set_instance_shader_parameter(&"hull_section", section)
	return wing


## [param wing] 绕 [param pivot] 转动 [param roll]，并沿 [param drift] 分离。
## [param surface] 与 [param opacity] 保持翼片的焦化、反光及淡退。
func _pose_wing(wing: Sprite2D, pivot: Vector2, drift: Vector2, roll: float,
		surface: Vector2, opacity: float) -> void:
	var pose := Transform2D(roll, drift) # 从局部轴心抛出，而不是让翼片绕整架飞机旋转。
	pose.origin += pivot - pose.basis_xform(pivot)
	wing.transform = pose
	wing.set_instance_shader_parameter(&"wreck_heat", surface)
	wing.self_modulate.a = opacity
