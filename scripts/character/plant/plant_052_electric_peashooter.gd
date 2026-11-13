## 电能豌豆：复用原版分层动作与音效，在唯一动作时钟上触发声音和电球离手。
extends Plant000Base
class_name Plant052ElectricPeashooter

## 独立电球负责离手后的飞行、穿透和附近放电。
const Projectile = preload("res://scripts/bullet/electric_pea_projectile.gd")
## 原版电系调色由本物种入口应用，阶级读取冻结出战卡。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 原版相邻两次起手的随机秒数，不额外等待上一次完整攻击动画。
const ATTACK_INTERVAL: Vector2 = Vector2(2.25, 2.4)
## PAM Attack_Start、Attack_Fire 与 use_action 在攻击片段内的原版秒数。
const START_SOUND_TIME: float = 1.0 / 30.0
## 原版蓄电完成音效先于电球离手四帧。
const FIRE_SOUND_TIME: float = 34.0 / 30.0
## 原版 use_action 位于攻击片段第38帧。
const RELEASE_TIME: float = 38.0 / 30.0
## 原版攻击共71帧；仅用于恢复待机，不阻塞下一次合法起手。
const ACTION_DURATION: float = 71.0 / 30.0
## 无目标时的有限重查间隔，不影响有目标时的原版周期。
const RECHECK_DELAY: float = 0.05
## 原版 Attack_Start 事件三选一且不连续重复。
const START_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/attack_start.tres")
## 原版 Attack_Fire 主体声音层三选一且不连续重复，混音中压低于电光层。
const FIRE_BODY_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/attack_fire_body.tres")
## 原版 Attack_Fire 电光声音层三选一且不连续重复，与主体层同时播放。
const FIRE_ZAP_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/attack_fire_zap.tres")
## 原版 Idle_01 的八选一不连续重复声音层。
const IDLE_RANDOM_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/idle.tres")
## 原版 Idle_01 与随机层叠播的固定声音。
const IDLE_FIXED_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/idle_9.wav")
## 原版 idle 片段在第二帧播放声音；idle2、idle3的音频事件在原版音库中为空。
const IDLE_SOUND_TIME: float = 2.0 / 30.0

## 本株所在的实际关卡，旧植物不能借用新关卡继续发射。
var _game: MainGameManager
## 植株入场时的棋盘身份，换板后旧地格不能继续工作。
var _board: BoardRuntime
## 当前动作所属轮次，换轮时取消尚未离手的电球。
var _round_index: int = -1
## 当前动作所属冒险阶段，防止普通与噩梦复用轮次时补发旧动作。
var _phase: StagePhaseDefinition
## 距下一次起手的正常动作秒数；原版 InitialMinCooldownTime 为零。
var _cooldown: float = 0.0
## 当前动作累计秒数；负一表示没有进行中的机械动作。
var _attack_elapsed: float = -1.0
## 当前动作三个事件各自只消费一次。
var _start_sound_pending: bool = false
## 本轮原版双层发射声音是否尚未播放。
var _fire_sound_pending: bool = false
## 本轮电球是否尚未离手。
var _release_pending: bool = false
## 通用角色动作倍率，冻结与眩晕为零，已经离手电球不使用此值。
var _owner_speed: float = 1.0
## 当前待机变体剩余的正常动作秒数。
var _idle_remaining: float = 0.0
## 距本次待机声音的正常动作秒数；负一表示该片段没有待播声音。
var _idle_sound_remaining: float = -1.0
## 原版分层美术场景内的播放器，由通用组件统一处理角色速度。
@onready var _animation: AnimationPlayer = ($AnimComponent as AnimComponentPlayer).animation_player
## 实际口部发射点，随身体和移动平台一起移动。
@onready var _launch: Marker2D = $Body/BodyCorrect/Launch
## 本株同行前方索敌组件，场景限制可攻击状态。
@onready var _detect: DetectComponent = $DetectComponent


## 入树即订阅战斗阶段边界，禁用物理处理期间也能取消旧动作。
func _enter_tree() -> void:
	if character_init_type == E_CharacterInitType.IsNorm:
		EventBus.subscribe("main_game_progress_update", _on_progress_changed)


## 正常出战建立战场快照；展示和花园仅按原版权重播放待机。
func _ready() -> void:
	super()
	_play_idle()
	if character_init_type != E_CharacterInitType.IsNorm:
		return
	var rank: int = plant_spawn_profile.promotion_tier() if plant_spawn_profile != null else 0 # 战斗只取冻结等阶，展示保留调用方预先应用的配色。
	PromotionArt.apply_to_body($Body/BodyCorrect, rank)
	_game = Global.main_game
	if not is_instance_valid(_game):
		set_physics_process(false)
		return
	_board = _game.board
	_round_index = _game.curr_game_round
	_phase = AdventureSession.get_active_phase(_game.game_para)
	_owner_speed = GlobalUtils.get_dic_product(influence_speed_factors)
	signal_update_speed.connect(_on_owner_speed_changed)
	signal_character_death.connect(_cancel_attack)
	sleep_component.signal_is_sleep.connect(_cancel_attack)


## [param delta] 已含引擎时间倍率；冷却、原版声音及离手帧只乘一次通用角色速度。
func _physics_process(delta: float) -> void:
	if character_init_type != E_CharacterInitType.IsNorm:
		_advance_idle(delta * maxf(0.0, _animation.speed_scale))
		return
	if get_tree().paused:
		return
	if is_instance_valid(_game) and (_game.curr_game_round != _round_index \
			or AdventureSession.get_active_phase(_game.game_para) != _phase):
		_cancel_attack()
		_round_index = _game.curr_game_round
		_phase = AdventureSession.get_active_phase(_game.game_para)
	if not _can_emit():
		_cancel_attack()
		return
	var elapsed: float = maxf(0.0, delta) * _owner_speed # 本株唯一正常动作时钟。
	_cooldown = maxf(0.0, _cooldown - elapsed)
	_advance_attack(elapsed)
	_advance_idle(elapsed)
	if _cooldown <= 0.0:
		if _has_target():
			_begin_attack()
		else:
			_cooldown = RECHECK_DELAY


## 起手立即确定下一次冷却；上一动作的末尾恢复帧不会推迟本次起手。
func _begin_attack() -> void:
	if not _can_emit():
		return
	_cooldown = randf_range(ATTACK_INTERVAL.x, ATTACK_INTERVAL.y)
	_attack_elapsed = 0.0
	_start_sound_pending = true
	_fire_sound_pending = true
	_release_pending = true
	_animation.stop()
	_animation.play(&"attack")


## 推进 [param elapsed] 个正常动作秒；各事件先消费标记再回调，防止重入重复发射。
func _advance_attack(elapsed: float) -> void:
	if _attack_elapsed < 0.0:
		return
	_attack_elapsed += elapsed
	if _start_sound_pending and _attack_elapsed >= START_SOUND_TIME:
		_start_sound_pending = false
		SoundManager.play_sfx_with_pool(START_SOUND, -12.0)
	if _fire_sound_pending and _attack_elapsed >= FIRE_SOUND_TIME:
		_fire_sound_pending = false
		# 两个发射声层仍同时播放，相近时刻的同类音效交给音效池合并。
		SoundManager.play_sfx_with_pool(FIRE_BODY_SOUND, -20.0)
		SoundManager.play_sfx_with_pool(FIRE_ZAP_SOUND, -14.0)
	if _release_pending and _attack_elapsed >= RELEASE_TIME:
		_release_pending = false
		_release()
	if _attack_elapsed >= ACTION_DURATION:
		_attack_elapsed = -1.0
		_play_idle()


## 在原版 use_action 帧捕获伤害与等阶，并在原战场容器内生成独立电球。
func _release() -> void:
	if not _can_emit():
		return
	var snapshot: ElectricPeaShotContext = ElectricPeaShotContext.capture(self) # 发射时读取一次动态光环和输出修正。
	if snapshot == null:
		return
	var projectile: ElectricPeaProjectile = Projectile.new() # 不经过普通豌豆升级或火炬转换。
	projectile.shot = snapshot
	projectile.position = _game.bullets.to_local(_launch.global_position)
	_game.bullets.add_child(projectile)


## 返回本株能否开始或完成自然攻击，涵盖死亡、冻结、睡眠、无效化、暂停及换战场。
func _can_emit() -> bool:
	if not is_instance_valid(_game) or not _game.is_inside_tree() or _game.is_queued_for_deletion() \
			or _game != Global.main_game or get_tree().current_scene != _game or not _game.is_ancestor_of(self) \
			or _game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or _game.curr_game_round != _round_index or _game.board != _board or _board == null \
			or AdventureSession.get_active_phase(_game.game_para) != _phase \
			or get_tree().paused or is_death or is_queued_for_deletion() or not is_inside_tree() \
			or not can_process() or is_sleeping or not is_finite(_owner_speed) or _owner_speed <= 0.0 \
			or has_node(NodePath(AdventurePlantNullification.NODE_NAME)) \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
			or TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false):
		return false
	return is_instance_valid(plant_cell) and not plant_cell.is_queued_for_deletion() \
		and plant_cell.board == _board and plant_cell.living_plants().has(self) \
		and is_instance_valid(_detect) and _detect.is_enabling \
		and is_instance_valid(_game.bullets) and not _game.bullets.is_queued_for_deletion()


## 同行前方进入当前画面的有效目标才能起手；僵王由索敌组件的真实重叠范围决定。
func _has_target() -> bool:
	var screen: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect() # 镜头移动时仍按实际可见战场索敌。
	for target: Character000Base in _detect.get_all_enemy_can_be_attacked(): # 组件已完成同行与状态筛选。
		if not ElectricPeaFlightQuery.can_hit(target):
			continue
		var target_x: float = target.hurt_box_component.global_position.x # 机甲根节点不代表可命中位置。
		if target_x >= global_position.x and target_x <= screen.end.x:
			return true
	return false


## 根据原版49:49:2权重选择待机变体，完整保留罕见电光动作。
func _play_idle() -> void:
	if not is_instance_valid(_animation) or is_death:
		return
	var draw: int = randi_range(0, 99) # 原版 IdleAnimationWeights 的整数权重。
	var clip: StringName = &"idle" if draw < 49 else (&"idle2" if draw < 98 else &"idle3") # 三个原版片段。
	_animation.stop()
	_animation.play(clip)
	_idle_remaining = _animation.get_animation(clip).length
	_idle_sound_remaining = IDLE_SOUND_TIME if clip == &"idle" else -1.0


## [param elapsed] 为正常动作秒；循环片段每播完一次重新按原版权重抽取。
func _advance_idle(elapsed: float) -> void:
	if _attack_elapsed >= 0.0 or elapsed <= 0.0:
		return
	if _idle_sound_remaining >= 0.0:
		_idle_sound_remaining -= elapsed
		if _idle_sound_remaining <= 0.0:
			_idle_sound_remaining = -1.0
			if character_init_type == E_CharacterInitType.IsNorm and _can_emit():
				# 待机电流声留在背景，避免多株待机盖过出手提示。
				SoundManager.play_sfx_with_pool(IDLE_RANDOM_SOUND, -30.0)
				SoundManager.play_sfx_with_pool(IDLE_FIXED_SOUND, -20.0)
	_idle_remaining -= elapsed
	if _idle_remaining <= 0.0:
		_play_idle()


## 取消尚未离手的旧动作并保留自然冷却，已经飞出的电球仍由原战场快照管理。
func _cancel_attack() -> void:
	var had_action: bool = _attack_elapsed >= 0.0 # 持续禁用时不反复重启待机。
	_attack_elapsed = -1.0
	_start_sound_pending = false
	_fire_sound_pending = false
	_release_pending = false
	if had_action and is_inside_tree():
		_play_idle()


## [param progress] 的非战斗阶段立即取消旧动作，即使母株物理处理已禁用。
func _on_progress_changed(progress: int) -> void:
	if progress != MainGameManager.E_MainGameProgress.MAIN_GAME or _game != Global.main_game:
		_cancel_attack()


## [param speed_product] 为通用动作倍率；零速取消未离手事件，解冻后不会补发旧电球。
func _on_owner_speed_changed(speed_product: float) -> void:
	_owner_speed = maxf(0.0, speed_product) if is_finite(speed_product) else 0.0
	if _owner_speed <= 0.0:
		_cancel_attack()


## [param what] 的禁用通知先于停止物理帧，保证无效化不会留下待发攻击。
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED:
		_cancel_attack()


## 离树清除尚未离手的动作并解除全局事件订阅。
func _exit_tree() -> void:
	_cancel_attack()
	EventBus.unsubscribe("main_game_progress_update", _on_progress_changed)
