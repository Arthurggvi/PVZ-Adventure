## Savior 的原画播放入口。施法在抬掌原帧释放，沿用原动作和脚点。
extends AnimatedSprite2D

## 跟随双掌并在世界地块绘制的祈祷特效。
const PrayerEffect = preload("res://scripts/fx/savior_prayer_effect.gd")
## 含地面批次和材质的技能表现场景。
const PRAYER_SCENE: PackedScene = preload("res://scenes/fx/savior_prayer_effect.tscn")
## 从零计数的第 5 帧在最高点停留结束后出手，对应原画第六张。
const RELEASE_FRAME := 5
## 原画第五张的双手位置最高，用于有意停留的仪式特写。
const RITUAL_FRAME := 4
## 沿真实原画控制透光显隐的传送材质。
const TELEPORT_SHADER = preload("res://shaders/adventure/wonderland/savior_arrival.gdshader")
## 起手到释放的掌间位置，使用裁过透明边的原画像素。
const PALMS: Array[Vector2] = [
	Vector2(84, 144), Vector2(71, 141), Vector2(54, 138),
	Vector2(41, 122), Vector2(31, 101), Vector2(30, 103),
]

## 双掌完全展开的原画帧，技能可在此接管演出。
signal prayer_released
## 祈祷恢复原站姿时触发。
signal prayer_finished

## 当前原画在播放一次完整的施法动作。
var _casting := false
## 每轮只通知一次抬掌，纯动作也沿用同一个关键帧。
var _released := false
## 疯狂光柱还没展开时，停在已释放的抬掌帧。
var _holding_prayer := false
## 仪式祈祷与技能的抬掌停留独立，旧技能收尾时仍能维持仪式姿势。
var _ritual_prayer := false
## 仪式祈祷抵达原画最高点。
var _ritual_held := false
## 最新战斗行动倍率，仪式抬掌期间存下并在收手时恢复。
var _action_rate := 1.0
## 时停特写前的原有节点处理方式。
var _saved_process_mode: Node.ProcessMode
## 传送过程中临时使用的材质实例。
var _teleport_material: ShaderMaterial
## 传送完毕后恢复的原画材质。
var _original_material: Material
## 传送期间投影读到的 Alpha 随原画一起改变，完毕后归还原值。
var _original_tint: Color
## 正在演出的地面及掌间效果。
var _effect: PrayerEffect
## 与当前原画帧对齐的手部坐标。
@onready var _palm: Marker2D = $PrayerPalm

## 复用 AnimatedSprite2D 的帧与循环通知。
func _ready() -> void:
	_action_rate = speed_scale
	frame_changed.connect(_on_frame_changed)
	animation_looped.connect(_on_animation_looped)
	animation_changed.connect(_on_animation_changed)

## 朝 [param target_areas] 的世界地块矩形播放一次祈祷，由首个有效矩形接住主滴。
## [param profile] 决定是否附带原有黑泪和地面刻印。传空数组时只播放原画动作。
## 成功开演返回 true，已有起手时忽略重复调用。
func cast_prayer(target_areas: Array[Rect2], profile: PrayerEffect.Profile = PrayerEffect.Profile.GROUND_MARKS) -> bool:
	if not can_cast_prayer():
		return false
	var next_effect: PrayerEffect # 无垠的手势直接连接黑场，地面技能才创建墨滴。
	if not target_areas.is_empty():
		next_effect = PRAYER_SCENE.instantiate() as PrayerEffect
		if not next_effect.prepare(_palm, target_areas, profile):
			next_effect.free()
			return false
		next_effect.gather_rate = speed_scale
	_discard_effect()
	_effect = next_effect
	_casting = true
	_released = false
	play(&"pray")
	set_frame_and_progress(0, 0.0)
	_align_palm()
	if _effect != null:
		add_child(_effect)
	return true

## 整组起手前可以检查当前原画是否就绪。
func can_cast_prayer() -> bool:
	return not _casting and is_node_ready() and is_inside_tree() and not is_queued_for_deletion()

## 记录 [param rate] 并更新普通祈祷及聚滴。仪式抬掌使用导演指定的倍率。
func set_action_rate(rate: float) -> void:
	_action_rate = rate
	if _ritual_prayer:
		return
	speed_scale = rate
	if is_instance_valid(_effect):
		_effect.gather_rate = rate

## 停在当前抬掌关键帧。只有正在释放技能的原画可以进入停留，成功时返回 true。
func hold_prayer() -> bool:
	if not _casting or not _released or frame != RELEASE_FRAME:
		return false
	_holding_prayer = true
	pause()
	return true

## 从保留的帧及帧进度继续收手，已结束或被中断的祈祷不会重播。
func resume_prayer() -> void:
	if _holding_prayer:
		_holding_prayer = false
		play(&"pray")

## 启动一次仪式祈祷。[param rate] 为动作倍率，[param during_stop] 允许特写时原画独自推进。
func stage_prayer(rate: float, during_stop: bool) -> bool:
	cancel_prayer()
	if not cast_prayer([]):
		return false
	_saved_process_mode = process_mode
	if during_stop:
		process_mode = Node.PROCESS_MODE_ALWAYS
	_ritual_prayer = true
	speed_scale = 1.0
	play(&"pray", rate)
	return true

## 返回原画是否停在抬掌最高点。
func is_ritual_pose_held() -> bool:
	return _ritual_held

## 从已经停足的抬掌帧接着收手，恢复本来随战斗暂停的处理方式。
func finish_ritual_pose() -> void:
	if not _ritual_prayer:
		return
	var was_held: bool = _ritual_held # 仪式结束时沿当前动作接回原速。
	_clear_ritual_pose()
	if was_held:
		set_frame_and_progress(RITUAL_FRAME, 1.0)
	play(&"pray")

## [param presence] 为原画凝实程度，[param ivory] 为受光程度。[param retreating] 开启自石面向上退光。
## 凝实和受光为零至一，全显且无额外染色时归还原有材质。
func set_teleport_pose(presence: float, ivory: float = 0.0, retreating: bool = false) -> void:
	if presence >= 1.0 and ivory <= 0.0:
		if _teleport_material != null and material == _teleport_material:
			material = _original_material
			self_modulate = _original_tint
		return
	if material != _teleport_material or _teleport_material == null:
		_original_material = material
		_original_tint = self_modulate
		if _teleport_material == null:
			_teleport_material = ShaderMaterial.new()
			_teleport_material.shader = TELEPORT_SHADER
		material = _teleport_material
	self_modulate.a = _original_tint.a * smoothstep(0.0, 0.68, presence)
	_teleport_material.set_shader_parameter(&"presence", presence)
	_teleport_material.set_shader_parameter(&"ivory", ivory)
	_teleport_material.set_shader_parameter(&"retreating", retreating)

## 中断或结束仪式抬掌时还原处理方式和当前战斗行动倍率。
func _clear_ritual_pose() -> void:
	if _ritual_prayer:
		process_mode = _saved_process_mode
		speed_scale = _action_rate
	_ritual_prayer = false
	_ritual_held = false

## 中断施法并清除旧地面表现。[param keep_pose] 在死亡传送时保留实际原画帧。
func cancel_prayer(keep_pose: bool = false) -> void:
	var was_casting: bool = _casting # 保留直接播放美术资源时的既有姿态。
	_clear_ritual_pose()
	_casting = false
	_holding_prayer = false
	_discard_effect()
	if keep_pose:
		pause()
	elif was_casting:
		play(&"idle")

## 掌间效果在每个实际原画帧更新，出手只触发一次。
func _on_frame_changed() -> void:
	if not _casting:
		return
	_align_palm()
	if _ritual_prayer and frame == RITUAL_FRAME:
		_ritual_held = true
		pause()
		return
	if frame < RELEASE_FRAME or _released:
		return
	_released = true
	if is_instance_valid(_effect):
		_effect.release()
	prayer_released.emit()

## 原祈祷素材保留可循环预览。战斗用的单次演出在一轮结束时返回待机。
func _on_animation_looped() -> void:
	if not _casting or animation != &"pray":
		return
	_casting = false
	play(&"idle")
	prayer_finished.emit()

## 外部动画替换中断旧起手时，及时收走未完成的地面预警。
func _on_animation_changed() -> void:
	if _casting and animation != &"pray":
		_clear_ritual_pose()
		_casting = false
		_holding_prayer = false
		_discard_effect()

## 用同一份精灵 offset 换算到原站位坐标。
func _align_palm() -> void:
	_palm.position = PALMS[mini(frame, RELEASE_FRAME)] + offset

## 回收上一轮尚在淡去的特效。
func _discard_effect() -> void:
	if is_instance_valid(_effect):
		_effect.queue_free()
	_effect = null
