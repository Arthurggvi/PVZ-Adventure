## 推冰状态机；接近冰块后播放原推行动作，在出手时一次性提交相连冰链的位移。
extends Node
class_name TroglobitePush

## 每次出手创建一个由行节点持有的整链推行。
const IceMotion = preload("res://scripts/character/zombie/troglobite/troglobite_ice_motion.gd")
## 原推行动作中手部前推开始的归一化时刻；按实际原帧核对后固定。
const CONTACT_PROGRESS: float = 0.51
## 推行前方一格所用的动作秒；全链共用同一个时钟。
const SLIDE_SECONDS: float = 0.72
## 出手帧的手部触点距身体原点的水平距离，单位为角色缩放前的像素。
const HAND_REACH: float = 78.0
## 手与冰、冰与冰的边缘接触容差，单位为世界像素。
const CONTACT_TOLERANCE: float = 4.0
## 原蓄力声音的长度，单位动作秒；使用推行时钟，不另乘角色速率。
const WINDUP_LEAD_SECONDS: float = 0.674
## 仅在本物种脚本加载时引用四条原版呻吟，不增加全局预加载依赖。
const GRUNT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/adventure/zombies/troglobite/audio/grunt_1.ogg"),
	preload("res://assets/adventure/zombies/troglobite/audio/grunt_2.ogg"),
	preload("res://assets/adventure/zombies/troglobite/audio/grunt_3.ogg"),
	preload("res://assets/adventure/zombies/troglobite/audio/grunt_4.ogg"),
]
## 原版出手前的冰块摩擦声；通过现有音效池服从全局音量设置。
const WINDUP_SOUND: AudioStream = preload("res://assets/adventure/zombies/troglobite/audio/push_windup.ogg")
## 原版推行声音，只在本次冰链全部接受位移后播放。
const SLIDE_SOUND: AudioStream = preload("res://assets/adventure/zombies/troglobite/audio/push_slide.ogg")
## 推冰声音的播放增益（dB）；呻吟与蓄力退居背景，冰块移动保留较强反馈。
const GRUNT_GAIN_DB: float = -12.0
## 蓄力摩擦声的播放增益（dB）。
const WINDUP_GAIN_DB: float = -9.0
## 滑冰声的播放增益（dB），压低近满幅瞬态。
const SLIDE_GAIN_DB: float = -10.0
## 接近、出手前、出手后的动画收尾和永久结束互斥。
enum PushState { APPROACH, WINDUP, FOLLOW_THROUGH, DISABLED }
## 死亡、断臂或魅惑后永久停推，通知入场队列结束护送。
signal pushing_ended
## 当前动作阶段，只能由本组件改变。
var _state: PushState = PushState.APPROACH
## 本体仅使用通用僵尸公开接口，避免物种根类与组件循环依赖。
var _source: Zombie000Base
## 已绑定战场；不会使用下一局的全局棋盘。
var _game: MainGameManager
## 播放器只接受动作指令，不回调伤害和移动。
var _animator: ImportedZombieAnimator
## 原始逐帧精灵，同名推冰动作也需要明确从首帧开始。
var _sprite: AnimatedSprite2D
## 当前动作已推进的标准秒数。
var _elapsed: float = 0.0
## 当前完整推行动作时长，来自真实SpriteFrames资源。
var _duration: float = 0.0
## 同次动作最多触发一次蓄力音；取消后没有计时器残留回调。
var _windup_played: bool = false
## 此次动作对应的格宽，推进中不因视觉偏移重新计算。
var _step: float = 0.0
## 接触或蓄力时本组件取得的走路锁，只有持有时才释放。
var _owns_move_lock: bool = false
## 蓄力时本组件关闭的啃食许可，收尾恢复本次取得的锁。
var _owns_attack_lock: bool = false

## 展示实例不进行战斗查询，普通入场由configure启用。
func _ready() -> void:
	set_physics_process(false)

## [param source] 已就绪，接入原断手阶段并启用接触检查。
func configure(source: Zombie000Base) -> void:
	_source = source
	_game = Global.main_game
	_animator = source.anim_component as ImportedZombieAnimator
	_sprite = source.get_node(^"Body/SourceSprite") as AnimatedSprite2D
	_duration = _animator.clip_duration(&"push")
	source.hp_stage_change_component.signal_hp_stage_change.connect(_on_body_stage)
	source.hp_component.signal_hp_loss.connect(_on_body_hp_loss)
	source.signal_character_be_hypno.connect(finish_life)
	source.signal_lane_update.connect(_end_push)
	set_physics_process(_duration > 0.0)
	_on_body_hp_loss(source.hp_component.curr_hp, false)

## [param delta] 是战斗秒；只有原生行动资格和速率都允许时才推进动作。
func _physics_process(delta: float) -> void:
	if _state == PushState.DISABLED:
		return
	if not _can_act():
		_end_push()
		return
	if _state == PushState.APPROACH:
		_prepare_push()
		return
	_elapsed += delta * _source.speed_factor_product()
	if _state == PushState.WINDUP:
		var contact_time: float = _duration * CONTACT_PROGRESS # 同一时刻决定出手和前置音效。
		if _elapsed >= contact_time:
			if not _commit_chain():
				_end_push()
				return
			_state = PushState.FOLLOW_THROUGH
			SoundManager.play_sfx_with_pool(SLIDE_SOUND, SLIDE_GAIN_DB)
		else:
			_play_windup_if_due(contact_time)
	if _elapsed >= _duration:
		_end_push()

## 走到实际冰壳边缘才停步；等待其他推力结束时仍能被原啃食或控制接管。
func _prepare_push() -> void:
	if _source.is_attack or (not _owns_move_lock and _source.move_component.move_factors.get(
			MoveComponent.E_MoveFactor.IsCharacter, false)) \
			or not _source.attack_component.is_attack_factors.get(AttackComponentBase.E_IsAttackFactors.Character, true):
		_unlock_movement()
		return
	var chain: Array[Zombie031YetiImp] = _contact_chain() # 只在手与冰壳相接时建立预备动作。
	if chain.is_empty():
		_unlock_movement()
		return
	if not _owns_move_lock:
		_owns_move_lock = true
		_source.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsCharacter)
	if not _chain_ready(chain):
		return
	_step = _game.board.cell_width_at(_source.global_position, _source.lane)
	if _step <= 0.0:
		_unlock_movement()
		return
	_state = PushState.WINDUP
	_elapsed = 0.0
	_windup_played = false
	_owns_attack_lock = true
	_source.attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Character)
	_animator.set_override(&"push")
	_sprite.set_frame_and_progress(0, 0.0)
	_sprite.play(&"push")
	SoundManager.play_sfx_with_pool(GRUNT_SOUNDS.pick_random(), GRUNT_GAIN_DB)

## 在 [param contact_time] 前播放一次蓄力声，已经离开的冰链不发声。
func _play_windup_if_due(contact_time: float) -> void:
	if _windup_played or _elapsed < maxf(0.0, contact_time - WINDUP_LEAD_SECONDS):
		return
	_windup_played = true
	if _chain_ready(_contact_chain()):
		SoundManager.play_sfx_with_pool(WINDUP_SOUND, WINDUP_GAIN_DB)

## 出手时按实际接触重新取链；全链完成预留后才交给行节点。
func _commit_chain() -> bool:
	var motion: IceMotion = IceMotion.new() # 一次出手持有单个时间轴，与推手的动画生命周期分离。
	if not motion.prepare(_game, _source, _contact_chain(), _step, SLIDE_SECONDS):
		motion.free()
		return false
	_source.get_parent().add_child(motion)
	return true

## 收集手部已够到且冰壳边缘相接的连续区段；远处孤立冰块不受本次推力。
func _contact_chain() -> Array[Zombie031YetiImp]:
	var candidates: Array[Zombie031YetiImp] = IceMotion.lane_blocks(_game.zombie_manager, _source.lane) # 与位移使用同一份行内排序规则。
	var chain: Array[Zombie031YetiImp] = [] # 从最靠近手部的冰块向前逐块扩展。
	var contact_x: float = _source.body.to_global(Vector2(-HAND_REACH, 0.0)).x # 第一处接触从伸手位置开始。
	for index: int in range(candidates.size() - 1, -1, -1): # 逆序从右往左查找连续冰块。
		var block: Zombie031YetiImp = candidates[index] # 当前行内仍存活的冻结块。
		var x: float = block.global_position.x # 每次只判断身前的冰壳。
		if x >= _source.global_position.x:
			continue
		var half_width: float = block.ice_half_width() # 接触和扫掠使用相同冰壳轮廓。
		if contact_x - (x + half_width) > CONTACT_TOLERANCE:
			break
		chain.append(block)
		contact_x = x - half_width
	return chain

## [param chain] 至少有一块且全部未被其他推力持有时才开始蓄力。
func _chain_ready(chain: Array[Zombie031YetiImp]) -> bool:
	for block: Zombie031YetiImp in chain: # 此处没有伤害回调，成员来自同步的有效行快照。
		if block.is_ice_sliding():
			return false
	return not chain.is_empty()

## 只处理原生断手及更晚阶段；治疗不能重新长手恢复推冰。
## [param stage] 由现有生命阶段组件给出，0为断手、1为垂死。
func _on_body_stage(stage: int) -> void:
	if stage >= 0:
		finish_life()

## [param curr_hp] 始终按已缩放断手线判断；[param _drop] 只决定碎肢表现，不决定还能否推冰。
func _on_body_hp_loss(curr_hp: int, _drop: bool) -> void:
	var thresholds: Array[int] = _source.hp_stage_change_component.boundary_value_hp # 读取等阶和迷你模式处理后的真实阈值。
	if not thresholds.is_empty() and curr_hp <= thresholds[0]:
		finish_life()

## 永久取消本体后续推冰；行节点上的整链推力继续完成。
func finish_life() -> void:
	if _state == PushState.DISABLED:
		return
	_end_push()
	_state = PushState.DISABLED
	set_physics_process(false)
	pushing_ended.emit()

## 恢复接近阶段，只释放推冰自己设置的因素，其他控制和死亡保持不变。
func _end_push() -> void:
	if _state == PushState.DISABLED:
		return
	if _state != PushState.APPROACH and is_instance_valid(_animator):
		_animator.clear_override()
	_state = PushState.APPROACH
	_unlock_movement()
	if _owns_attack_lock and is_instance_valid(_source):
		_owns_attack_lock = false
		_source.attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Character)

## 只撤销本次接触或推行动作设置的走路锁。
func _unlock_movement() -> void:
	if _owns_move_lock and is_instance_valid(_source):
		_owns_move_lock = false
		_source.move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsCharacter)

## 身份、行号和战斗状态均有效才处理接触；魅惑和恐惧不继续替敌方推冰。
func _can_act() -> bool:
	return is_instance_valid(_source) and not _source.is_death and not _source.is_queued_for_deletion() \
		and is_instance_valid(_game) and _game == Global.main_game and _game.is_ancestor_of(_source) and _game.board != null \
		and _game.zombie_manager.is_game_running() and _source.lane >= 0 \
		and _source.lane < _game.zombie_manager.all_zombies_2d.size() \
		and not _source.is_changing_lane and _source.move_component.is_enabling and _source.attack_component.is_enabling \
		and not _source.is_hypno and _source.direction_x_root == 1 and not _source.is_action_suspended() \
		and not _source.move_component.is_forced_moving() and _source.speed_factor_product() > 0.0
