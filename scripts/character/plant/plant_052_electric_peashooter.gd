## 电能豌豆：复用原版分层动作与音效，在唯一动作时钟上触发声音和电球离手。
extends Plant000Base
class_name Plant052ElectricPeashooter
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
## 待机变体与音效只消费原株提供的动作时间。
var _presentation := ElectricPeaPresentation.new()
## 待播蓄电声音位。
const START_EVENT: int = 1
## 待播发射声音位。
const FIRE_EVENT: int = 2
## 待执行离手位。
const RELEASE_EVENT: int = 4
## 由出战事件冻结的一至四转选择；普通植株使用原版参数。
var _promotions := ElectricPeaPromotions.new([])
## 仅选择电磁共生时建立本株光环和轻量连线。
var _symbiosis: ElectricPeaSymbiosis
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
## 尚未消费的原版声音和离手事件位；取消攻击时一并清零。
var _pending_events: int = 0
## 通用角色动作倍率，冻结与眩晕为零，已经离手电球不使用此值。
var _owner_speed: float = 1.0
## 原版分层美术场景内的播放器，由通用组件统一处理角色速度。
@onready var _animation: AnimationPlayer = ($AnimComponent as AnimComponentPlayer).animation_player
## 实际口部发射点，随身体和移动平台一起移动。
@onready var _launch: Marker2D = $Body/BodyCorrect/Launch
## 本株同行前方索敌组件，场景限制可攻击状态。
@onready var _detect: DetectComponent = $DetectComponent

## 将出战卡的 [param events] 冻结到原株；展示模式仍沿用通用配色入口。
func configure_promotions(events: Array[Dictionary]) -> void:
	_promotions = ElectricPeaPromotions.new(events)

## 入树即订阅战斗阶段边界，禁用物理处理期间也能取消旧动作。
func _enter_tree() -> void:
	if character_init_type == E_CharacterInitType.IsNorm:
		EventBus.subscribe("main_game_progress_update", _on_progress_changed)

## 正常出战建立战场快照；展示和花园仅按原版权重播放待机。
func _ready() -> void:
	super()
	_presentation.play_idle(_animation, is_death)
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
	_symbiosis = ElectricPeaSymbiosis.install(self, _launch, _promotions.neighbor_bonus)

## [param delta] 已含引擎时间倍率；冷却、原版声音及离手帧只乘一次通用角色速度。
func _physics_process(delta: float) -> void:
	if character_init_type != E_CharacterInitType.IsNorm:
		_presentation.advance_idle(_animation, delta * maxf(0.0, _animation.speed_scale), false)
		return
	if get_tree().paused:
		return
	if is_instance_valid(_game) and (_game.curr_game_round != _round_index \
			or AdventureSession.get_active_phase(_game.game_para) != _phase):
		_cancel_attack()
		_round_index = _game.curr_game_round
		_phase = AdventureSession.get_active_phase(_game.game_para)
	if _symbiosis != null:
		_symbiosis.refresh(_board if _in_battle() else null)
	if not _can_emit():
		_cancel_attack()
		return
	var elapsed: float = maxf(0.0, delta) * _owner_speed # 本株唯一正常动作时钟。
	_cooldown = maxf(0.0, _cooldown - elapsed)
	_advance_attack(elapsed)
	if _attack_elapsed < 0.0:
		_presentation.advance_idle(_animation, elapsed, _can_emit(), is_death)
	if _cooldown <= 0.0:
		if ElectricPeaFlightQuery.has_forward_target(self, _detect):
			_begin_attack()
		else:
			_cooldown = RECHECK_DELAY

## 起手立即确定下一次冷却；上一动作的末尾恢复帧不会推迟本次起手。
func _begin_attack() -> void:
	if not _can_emit():
		return
	_cooldown = randf_range(ATTACK_INTERVAL.x, ATTACK_INTERVAL.y)
	_attack_elapsed = 0.0
	_pending_events = START_EVENT | FIRE_EVENT | RELEASE_EVENT
	_animation.stop()
	_animation.play(&"attack")

## 推进 [param elapsed] 个正常动作秒；各事件先消费标记再回调，防止重入重复发射。
func _advance_attack(elapsed: float) -> void:
	if _attack_elapsed < 0.0:
		return
	_attack_elapsed += elapsed
	if (_pending_events & START_EVENT) != 0 and _attack_elapsed >= START_SOUND_TIME:
		_pending_events &= ~START_EVENT
		ElectricPeaPresentation.play_start()
	if (_pending_events & FIRE_EVENT) != 0 and _attack_elapsed >= FIRE_SOUND_TIME:
		_pending_events &= ~FIRE_EVENT
		ElectricPeaPresentation.play_fire()
	if (_pending_events & RELEASE_EVENT) != 0 and _attack_elapsed >= RELEASE_TIME:
		_pending_events &= ~RELEASE_EVENT
		_release()
	if _attack_elapsed >= ACTION_DURATION:
		_attack_elapsed = -1.0
		_presentation.play_idle(_animation, is_death)

## 在原版 use_action 帧捕获伤害与等阶，并在原战场容器内生成独立电球。
func _release() -> void:
	if not _can_emit():
		return
	var snapshot: ElectricPeaShotContext = ElectricPeaShotContext.capture(self, _promotions) # 发射时读取一次动态光环和输出修正。
	if snapshot == null:
		return
	ElectricPeaVolley.emit(snapshot, plant_cell, _launch.global_position)

## 返回本株是否仍位于原战场有效阶段；已离手电球独立处理自己的生命周期。
func _in_battle() -> bool:
	return is_instance_valid(_game) and _game.is_inside_tree() and not _game.is_queued_for_deletion() \
		and _game == Global.main_game and get_tree().current_scene == _game and _game.is_ancestor_of(self) \
		and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and _game.curr_game_round == _round_index and _game.board == _board and _board != null \
		and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and not is_death and not is_queued_for_deletion() and is_inside_tree() and can_process() \
		and not has_node(NodePath(AdventurePlantNullification.NODE_NAME)) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 返回本株能否自然攻击；暂停、冻结、睡眠和失去真实占位都会停止出手。
func _can_emit() -> bool:
	return _in_battle() and not get_tree().paused and not is_sleeping and is_finite(_owner_speed) and _owner_speed > 0.0 \
		and is_instance_valid(plant_cell) and not plant_cell.is_queued_for_deletion() \
		and plant_cell.board == _board and plant_cell.living_plants().has(self) \
		and is_instance_valid(_detect) and _detect.is_enabling \
		and is_instance_valid(_game.bullets) and not _game.bullets.is_queued_for_deletion()

## 取消尚未离手的旧动作并保留自然冷却，已经飞出的电球仍由原战场快照管理。
func _cancel_attack() -> void:
	var had_action: bool = _attack_elapsed >= 0.0 # 持续禁用时不反复重启待机。
	_attack_elapsed = -1.0
	_pending_events = 0
	if had_action and is_inside_tree():
		_presentation.play_idle(_animation, is_death)

## [param progress] 的非战斗阶段立即取消旧动作，即使母株物理处理已禁用。
func _on_progress_changed(progress: int) -> void:
	if progress != MainGameManager.E_MainGameProgress.MAIN_GAME or _game != Global.main_game:
		_cancel_attack()
		if _symbiosis != null:
			_symbiosis.clear()

## [param speed_product] 为通用动作倍率；零速取消未离手事件，解冻后不会补发旧电球。
func _on_owner_speed_changed(speed_product: float) -> void:
	_owner_speed = maxf(0.0, speed_product) if is_finite(speed_product) else 0.0
	if _owner_speed <= 0.0:
		_cancel_attack()

## [param what] 的禁用通知先于停止物理帧，保证无效化不会留下待发攻击。
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED:
		_cancel_attack()
		if _symbiosis != null:
			_symbiosis.clear()

## 离场清除尚未离手的动作；手套换格保留同一战场中的攻击与冷却进度。
func _exit_tree() -> void:
	if not is_being_relocated:
		_cancel_attack()
	EventBus.unsubscribe("main_game_progress_update", _on_progress_changed)
