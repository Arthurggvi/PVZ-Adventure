## 战斗机僵尸沿单行推进，可从运输舰平滑出舱，正常击毁时自爆。
extends Zombie000Base
class_name Zombie034Fighter

## 完成出舱后预留的尾部距离，单位为世界像素，对应正常体型的机尾及遮挡余量。
const TAIL_CLEARANCE: float = 74.0
## 从舱口滑出、抬头加速到接上巡航的动作秒数。
const CARGO_LAUNCH_SECONDS: float = 0.96
## 机身刚从舱口显现时起播的动作秒数，声势随出舱进度抬升。
const CARGO_AUDIO_SECONDS: float = 0.17
## 仍在货舱深处时的机身表现倍率。
const CARGO_START_SCALE: float = 0.36

## 机枪计时与击毁时的范围伤害。
@onready var fighter_attack: AttackComponentZombieFighter = $AttackComponent
## 悬浮、开火和击毁爆炸的表现控制器。
@onready var fighter_visual: FighterPresentation = $FighterPresentation
## 附在实际机身上的短促出舱旋翼声，普通刷出的战斗机不播放。
@onready var _cargo_launch_audio: AudioStreamPlayer2D = $Body/DeathBlastOrigin/CargoLaunchAudio

## 生命结束入口的幂等锁，避免击毁伤害和爆炸演出重复。
var _death_processed: bool = false
## 舱口内部的位置快照，普通战斗机保持无效坐标。
var _cargo_mouth: Vector2 = Vector2.INF
## 运输舰放飞时的舱门下沿世界坐标。
var _cargo_ramp_lip: Vector2
## 出舱期间的绘制层，允许机身从母舰下沿滑出。
var _cargo_depth: int
## 出舱动作的两端与控制点，以可见机身中心为基准。
var _launch_curve: PackedVector2Array
## 上一帧预计的脚点，只应用采样间的差值，保留外部位移。
var _last_launch_root: Vector2
## 出舱动作已经完成的秒数。
var _launch_elapsed: float = 0.0
## 普通巡航的机身缩放。
var _cruise_scale: Vector2
## 普通巡航的局部旋转弧度。
var _cruise_rotation: float
## 普通巡航的绘制层，脱离运输舰遮挡后恢复。
var _cruise_depth: int
## 出舱前的机身、阴影、血条透明度，分别按 x、y、z 保存。
var _cruise_opacity: Vector3


## 在入树前保存世界坐标 [param mouth] 与 [param ramp_lip]，以及低于运输舰的 [param depth]。
func configure_cargo_launch(mouth: Vector2, ramp_lip: Vector2, depth: int) -> void:
	_cargo_mouth = mouth
	_cargo_ramp_lip = ramp_lip
	_cargo_depth = depth


## 保留原僵尸受击/战场登记。空中放飞的机体完全离舱后才接入巡航和机枪。
func _ready() -> void:
	head1_path_candidate.assign([NodePath("Body/HeadAnchor")])
	super()
	fighter_visual.configure(self)
	set_process(false)
	if character_init_type != E_CharacterInitType.IsNorm:
		return
	if _cargo_mouth.is_finite():
		_start_cargo_launch()
	else:
		fighter_attack.activate(self, fighter_visual)


## 先从真实货舱起步，最后一段切线贴合当前巡航速度，避免切换到匀速移动时顿一下。
func _start_cargo_launch() -> void:
	_last_launch_root = global_position
	_cruise_scale = body.scale
	_cruise_rotation = body.rotation
	_cruise_depth = z_index
	_cruise_opacity = Vector3(fighter_visual.sprite.modulate.a, shadow.modulate.a, hp_component.modulate.a)
	var row := get_parent() as CanvasItem # 移动组件在该行坐标中沿左侧巡航。
	var travel: float = move_component.get_speed_mode_speed() * CARGO_LAUNCH_SECONDS / 3.0 # 三次曲线末端切线的三分之一。
	var tangent: Vector2 = row.get_global_transform().basis_xform(Vector2(travel, 0.0)) # 以世界坐标接续向左的巡航步幅。
	var cruise_center: Vector2 = fighter_visual.blast_origin.global_position # 普通姿态的机身中心作为最终接续点。
	var ramp_direction: Vector2 = _cargo_ramp_lip - _cargo_mouth # 舱内到舱门下沿的初始方向。
	_launch_curve = PackedVector2Array([_cargo_mouth, _cargo_ramp_lip + ramp_direction * 1.6,
		cruise_center + tangent, cruise_center])
	z_index = _cargo_depth
	move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsCharacter)
	hurt_box_component.disable_component(ComponentNormBase.E_IsEnableFactor.Prepare)
	_sample_cargo_launch(0.0)
	set_process(true)


## [param delta] 为当前战斗秒数。玩家吹风时让统一位移组件推进，随后从被吹动的位置接续。
func _process(delta: float) -> void:
	if is_death or is_queued_for_deletion():
		return
	if _launch_elapsed >= CARGO_LAUNCH_SECONDS:
		_restore_cruise_depth()
		return
	if move_component.is_forced_moving() or is_action_suspended():
		return
	var was_inside_cargo: bool = _launch_elapsed < CARGO_AUDIO_SECONDS # 出舱动作中只触发一次。
	_launch_elapsed = minf(CARGO_LAUNCH_SECONDS, _launch_elapsed + delta * action_rate())
	_sample_cargo_launch(_launch_elapsed / CARGO_LAUNCH_SECONDS)
	if was_inside_cargo and _launch_elapsed >= CARGO_AUDIO_SECONDS:
		SoundManager.play_attached_sfx(_cargo_launch_audio, &"cargo_launch", 1)
	if _launch_elapsed >= CARGO_LAUNCH_SECONDS:
		move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsCharacter)
		hurt_box_component.enable_component(ComponentNormBase.E_IsEnableFactor.Prepare)
		fighter_attack.activate(self, fighter_visual)
		_restore_cruise_depth()


## [param progress] 是归一化动作时间。机体先探出舱下沿，再抬头驶入对应的攻击行。
func _sample_cargo_launch(progress: float) -> void:
	var emerge: float = smoothstep(0.08, 0.87, progress) # 随出舱深度恢复正常机体尺寸。
	var dive: float = -14.0 * (1.0 - smoothstep(0.12, 0.61, progress)) # 从舱内沿下沿俯冲。
	var pull_up: float = 8.0 * sin(PI * smoothstep(0.26, 1.0, progress)) # 滑出后抬头，巡航前回正。
	body.scale = _cruise_scale * lerpf(CARGO_START_SCALE, 1.0, emerge)
	body.rotation = _cruise_rotation + deg_to_rad(dive + pull_up)
	fighter_visual.sprite.modulate.a = _cruise_opacity.x * smoothstep(0.0, 0.37, progress)
	var show_ground_ui: float = smoothstep(0.78, 1.0, progress) # 血条和投影到巡航末段才显现。
	shadow.modulate.a = _cruise_opacity.y * show_ground_ui
	hp_component.modulate.a = _cruise_opacity.z * show_ground_ui
	var anchor: Vector2 = _launch_curve[0].bezier_interpolate(_launch_curve[1],
		_launch_curve[2], _launch_curve[3], progress) # 这帧可见机身中心应在的位置。
	var relative_center: Vector2 = fighter_visual.blast_origin.global_position - global_position # 计入当前缩放和俯仰。
	var next_root: Vector2 = anchor - relative_center # 将机身中心轨迹还原为角色脚点。
	global_position += next_root - _last_launch_root
	_last_launch_root = next_root


## 被推回舰下的飞机先保持遮挡，巡航离开母舰前缘后再换回普通绘制层。
func _restore_cruise_depth() -> void:
	if global_position.x > _last_launch_root.x + 1.0 and not is_hypno:
		return
	z_index = _cruise_depth
	set_process(false)


## 由三叶草共用风力按飞行目标处理，受击和进家仍沿用普通行判定。
func is_blover_flying_target() -> bool:
	return not is_death


## 对载具而言冰封转换成减速，保持飞行机体运动连续性。
func can_cold_freeze() -> bool:
	return false


## 被灰烬攻击击毁时也保留机体专属爆炸。
func _preserves_blast_death_animation() -> bool:
	return true


## 击毁时立即结算一次伤害并开始爆炸，风力越界沿共享退场流程清理登记。
func character_death() -> void:
	if _death_processed:
		return
	_death_processed = true
	set_process(false)
	var should_blast: bool = not retiring_from_battle # 只在正常击毁时爆炸。
	var burst_id: int = 0 # 首次爆心保留原位置，结算后将次爆接到真实残骸。
	if is_instance_valid(fighter_attack):
		fighter_attack.finish_life()
	if is_instance_valid(fighter_visual):
		fighter_visual.finish_life()
		if should_blast:
			burst_id = fighter_visual.play_death_blast()
	if should_blast and is_instance_valid(fighter_attack):
		fighter_attack.apply_crash_damage()
	if should_blast:
		var death_visuals: Node = airship_death_presentation() # 把击毁前的真实机身帧和后续爆点一并交接。
		if death_visuals != null:
			death_visuals.capture_body(self, 0.44, death_visuals.source_velocity(self), &"fighter", burst_id)
	super()
	queue_free()
