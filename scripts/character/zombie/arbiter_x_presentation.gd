## 仲裁者的巡航、故障告警和保护光束表现，独立于战场脚点及受击框。
extends Node
class_name ArbiterXPresentation

## 巡航轴心与光束共用的节点。
@onready var machine: Node2D = %PlaneVisual
## 巡航与坠毁共用的机体和喷口坐标。
@onready var _airframe: ArbiterXAirframe = %Airframe
## 预设局部位置，以此为基准每帧计算悬浮偏移。
@onready var _rest_position: Vector2 = machine.position
## 向机体后方照射的原版青蓝色渐变光束，不改变其后方僵尸的可见性。
@onready var beam: Sprite2D = %ProtectionBeam
## 开启时的原作能量弧线与短促充能闪光。
@onready var beam_arc: Sprite2D = %BeamArc
## 动态渐变的三行扇形能量覆盖，补足原版 PNG 在草地上的低对比度。
@onready var cone: Polygon2D = %ProtectionCone
## 上沿、下沿随实际保护状态启停，不参与目标索引与伤害处理。
@onready var edge_top: Line2D = %BeamTopEdge
@onready var edge_bottom: Line2D = %BeamBottomEdge
## 扫描线沿光束中心上下摆动，是动态表现而非硬编码在原画上。
@onready var scan: Line2D = %BeamScan

## 播放与本体死亡登记解耦的触地演出。
const CRASH_SCENE: PackedScene = preload("res://scenes/character/zombie/arbiter_x/arbiter_x_crash.tscn")
## 原版背景引擎声音的音量均衡版本。
const ENGINE_SFX: AudioStream = preload("res://assets/adventure/zombies/arbiter_x/audio/engine_start.ogg")
## 原版电力射手素材改频谱和响度后的光束启动声。
const BEAM_SFX: AudioStream = preload("res://assets/adventure/zombies/arbiter_x/audio/beam_charge.ogg")
## 冰冻技能中提取的轻低频能量脉冲声。
const PULSE_SFX: AudioStream = preload("res://assets/adventure/zombies/arbiter_x/audio/beam_pulse.ogg")

## 当前的唯一战斗实体，保证展示和正式战斗共用动作。
var _plane: Zombie000Base
## 悬浮与双尾焰共用的循环相位，单位为动画秒。
var _flight_seconds: float = 0.0
## 上一拍的悬浮轴心局部速度，包含巡航俯仰对轴心的偏移，单位为像素/秒。
var _hover_velocity: Vector2 = Vector2.ZERO
## 光束震荡时钟，与保护逻辑的行动秒一致。
var _clock: float = 0.0
## 当前护盾光场真实活动目标，开关来自战斗逻辑。
var _field_on: bool = false
## 光束从当前数值渐变到目标亮度，不被动作状态抢占。
var _brightness: float = 0.0
## 音效首次入场只播放一次。
var _entered: bool = false

## [param plane] 提供角色状态与速度。图鉴中的实例只循环播放巡航。
func configure(plane: Zombie000Base) -> void:
	_plane = plane
	set_process(true)
	_apply_flight_pose()
	if not _entered and plane.character_init_type == Character000Base.E_CharacterInitType.IsNorm:
		_entered = true
		SoundManager.play_world_sfx(ENGINE_SFX, self, _airframe.near_exhaust.global_position, -14.0, 1.0, &"arbiter_start")

## [param delta] 只控制视觉，不改变碰撞世界位置或移速。
func _process(delta: float) -> void:
	if not is_instance_valid(_plane) or _plane.is_death:
		return
	_flight_seconds = fposmod(_flight_seconds + delta * _plane.speed_factor_product(),
		ArbiterXAirframe.CYCLE_SECONDS)
	var pressure: float = _damage_pressure() # 半血以下先预警，逼近坠毁阈值时逐步加重。
	var previous_center: Vector2 = machine.transform * _airframe.position # 相对机身父节点，不计战斗实体的横移。
	_apply_flight_pose(pressure)
	if delta > 0.0:
		_hover_velocity = (machine.transform * _airframe.position - previous_center) / delta
	_airframe.advance_fault(delta, pressure)
	_clock += delta * _plane.action_rate()
	_brightness = move_toward(_brightness, 1.0 if _field_on else 0.0, delta * 1.55)
	beam.modulate = Color(0.58, 0.98, 1.0, _brightness * (0.37 + 0.055 * sin(_clock * 5.0)))
	beam_arc.modulate.a = _brightness * (0.55 + 0.24 * sin(_clock * 6.2))
	beam.visible = _brightness > 0.01
	beam_arc.visible = _brightness > 0.01
	cone.visible = _brightness > 0.01
	edge_top.visible = cone.visible
	edge_bottom.visible = cone.visible
	scan.visible = cone.visible
	cone.modulate.a = _brightness * (0.85 + 0.08 * sin(_clock * 3.2))
	edge_top.modulate.a = _brightness * (0.62 + 0.14 * sin(_clock * 3.8))
	edge_bottom.modulate.a = edge_top.modulate.a
	scan.modulate.a = _brightness * (0.38 + 0.28 * absf(sin(_clock * 4.6)))
	scan.set_point_position(1, Vector2(450, sin(_clock * 4.5) * 105.0))

## 返回低于最大本体生命一半时的故障强度。展示实例只使用正常巡航。
func _damage_pressure() -> float:
	var health: HpComponent = _plane.hp_component # 只看本体生命，临时护甲不抵消机体告警。
	if _plane.character_init_type != Character000Base.E_CharacterInitType.IsNorm or health.curr_hp * 2 >= health.max_hp:
		return 0.0
	var remaining: float = 2.0 * health.curr_hp / health.max_hp # 从半血到零对应 1–0。
	return lerpf(0.54, 0.29, remaining)


## 计算悬浮、俯仰和尾焰。[param pressure] 大于零时，双喷口以不同节奏失稳。
func _apply_flight_pose(pressure: float = 0.0) -> void:
	var phase: float = TAU * _flight_seconds / ArbiterXAirframe.CYCLE_SECONDS # 当前巡航相位。
	machine.rotation = deg_to_rad(sin(phase + 0.4) * 0.85 + sin(phase * 4.0) * pressure * 2.3)
	machine.position = _rest_position + Vector2(1.1, 5.0) * sin(phase) * _airframe.scale
	var flicker: Vector2 = Vector2(absf(sin(phase * 3.0 + 0.7)), absf(sin(phase * 2.0))) # 两侧发动机独立失稳。
	_airframe.pose_exhaust(_flight_seconds, Vector2.ONE - flicker * pressure)


## 从当前巡航姿态创建坠毁演出，与即将释放的战斗实体分离。
func play_crash() -> void:
	var row: CanvasItem = _plane.get_parent() as CanvasItem # 演出与本战场行同寿命。
	if row == null or row.is_queued_for_deletion():
		return
	var move: MoveComponent = _plane.move_component # 读取阵亡前已经合成的实际推进速度。
	var speed_x: float = 0.0 # 停止推进时从静止接入，下方统一换算到世界坐标。
	if move.is_move and move.is_enabling and not _plane.is_stunned():
		speed_x = -move.get_speed_mode_speed() * _plane.direction_x_root
	var world_speed: float = row.get_global_transform().basis_xform(Vector2(speed_x, 0.0)).x # 世界像素/秒。
	var world_hover: Vector2 = _plane.body.global_transform.basis_xform(_hover_velocity) # 把机身尚未走完的悬浮惯性带入演出。
	var crash: ArbiterXCrash = CRASH_SCENE.instantiate() as ArbiterXCrash # 仅在正常击毁时创建。
	crash.z_index = _plane.z_index
	row.add_child(crash)
	crash.start(_airframe, _plane.global_position, world_speed, world_hover,
		_flight_seconds, _plane.body.modulate * _plane.modulate, _plane.airship_death_presentation())


## [param value] 来自减伤组件的真实开关，用于同步光束动画。
func set_beam_active(value: bool) -> void:
	if _field_on == value:
		return
	_field_on = value
	if value and is_instance_valid(_plane) and not _plane.is_death:
		SoundManager.play_world_sfx(BEAM_SFX, self, _airframe.global_position, -12.0, 1.0, &"arbiter_beam", true, 1)
		SoundManager.play_world_sfx(PULSE_SFX, self, _airframe.global_position, -16.0, 1.0, &"arbiter_pulse")

## 最终死亡与三叶草退场优先于所有光束动作。
func finish_life() -> void:
	_field_on = false
	_brightness = 0.0
	beam.hide()
	beam_arc.hide()
	cone.hide()
	edge_top.hide()
	edge_bottom.hide()
	scan.hide()
	if machine.is_ancestor_of(_airframe):
		_airframe.release_fault()
	set_process(false)
