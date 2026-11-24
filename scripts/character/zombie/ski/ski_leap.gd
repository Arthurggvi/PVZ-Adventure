## 滑雪僵尸的地面接触与动作门面；识别当前冰障，将唯一空中轨迹交给SkiFlight。
extends Node
class_name SkiLeap

## 普通行走通过一格所需的基础动作秒数。
const WALK_SECONDS_PER_CELL: float = 2.0
## 前方一格存在冰障时的滑雪速度，单位为动作秒/格。
const SKI_SECONDS_PER_CELL: float = 1.5
## 空中水平移速相对于基础步速的倍率。
const JUMP_SPEED_MULTIPLIER: float = 2.2
## 完整飞跃的动作秒数；起跳处的格宽在距离和速度换算中相消。
const JUMP_DURATION: float = SkiFlightPlan.JUMP_CELLS * WALK_SECONDS_PER_CELL / JUMP_SPEED_MULTIPLIER
## 地面动作互斥；真正空中状态由飞行组件独占。
enum GroundState { WALK, RUSH_START, RUSH, LAND, DISABLED }
## 当前地面表现，不另建计时器或延迟起跳回调。
var _state: GroundState = GroundState.WALK
## 行为拥有者只使用通用僵尸接口，避免物种根的循环依赖。
var _source: Zombie000Base
## 原生飞行拥有者，负责独占位移和行动锁。
var _flight: SkiFlight
## 当前所属战场，用于真实格宽和同行目标查询。
var _game: MainGameManager
## 原帧动画门面，不直接修改全局动画倍率。
var _animator: ImportedZombieAnimator
## 当前滑行准备或落地恢复已播放的动作秒。
var _elapsed: float = 0.0
## 上一次借力的实体只持有弱引用；离开接触带后允许再次借力。
var _last_obstacle: WeakRef
## 上一次地面行号；大蒜换行后不沿用旧行接触门禁。
var _lane: int = -1
## 落地恢复动作秒数；资源中已缩短为快速重新滑行。
var _land_seconds: float = 0.0
## 滑行准备原动作时长；准备过程中仍按滑雪速度前进。
var _rush_seconds: float = 0.0

## 展示实例不自动查询战场。
func _ready() -> void:
	set_physics_process(false)

## [param source] 为正式战斗实例，[param flight] 已绑定同一战局；只设置本物种步速。
func configure(source: Zombie000Base, flight: SkiFlight) -> void:
	_source = source
	_flight = flight
	_game = Global.main_game
	_animator = source.anim_component as ImportedZombieAnimator
	_land_seconds = _animator.clip_duration(&"land")
	_rush_seconds = _animator.clip_duration(&"rush_start")
	_lane = source.lane
	_flight.landed.connect(_on_landed)
	_flight.interrupted.connect(_on_interrupted)
	_update_speed(false)
	set_physics_process(true)

## [param delta] 为物理秒；所有地面动作时钟只乘一次角色合成速率。
func _physics_process(delta: float) -> void:
	if not _flight.belongs_to_battle():
		finish_life()
		return
	if _flight.is_airborne():
		return
	if _state == GroundState.LAND:
		_elapsed += delta * maxf(0.0, _source.speed_factor_product())
		if _elapsed >= _land_seconds:
			_flight.release_landing()
			_walk()
		return
	if _source.lane != _lane:
		_lane = _source.lane
		_last_obstacle = null
		_walk()
	if not _can_ground_act():
		_walk()
		return
	var previous: Character000Base = _last_obstacle.get_ref() as Character000Base if _last_obstacle != null else null # 弱引用不阻止铲除或冰块退场。
	if previous == null or not SkiObstacleQuery.is_touching(_source, previous):
		_last_obstacle = null
		previous = null
	var width: float = SkiObstacleQuery.cell_width(_source, _game) # 本物理步的实际格宽，只计算一次。
	var obstacle: Character000Base = SkiObstacleQuery.nearest(_source, _game, 1.0, previous, width) # 已借力冰障仍保留排除资格。
	if obstacle != null and SkiObstacleQuery.is_touching(_source, obstacle):
		# 在起跳时锁定格宽和落点。
		var plan: SkiFlightPlan = SkiFlightPlan.for_jump(_source, _game,
			width, JUMP_DURATION, SkiObstacleQuery.bounds(obstacle))
		if _flight.begin(plan):
			_last_obstacle = weakref(obstacle)
			_animator.set_override(&"air", plan.duration)
			SoundManager.play_character_SFX(&"SkiTakeoff")
			return
	if obstacle == null or _source.is_attack:
		_walk(width)
		return
	_update_speed(true, width)
	if _state == GroundState.WALK:
		_state = GroundState.RUSH_START
		_elapsed = 0.0
		_animator.set_override(&"rush_start")
	if _state == GroundState.RUSH_START:
		_elapsed += delta * maxf(0.0, _source.speed_factor_product())
		if _elapsed >= _rush_seconds:
			_state = GroundState.RUSH
			_animator.set_override(&"rush")

## 保留原普通啃咬；已在咬冻结植物也可起跳，但外部动作锁、眩晕和爬梯不能被抢占。
func _can_ground_act() -> bool:
	return _game.zombie_manager.is_game_running() and not _source.is_changing_lane \
		and _source.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsNorm \
		and not _source.is_action_suspended() and _source.speed_factor_product() > 0.0 \
		and _source.move_component.is_enabling and _source.attack_component.is_enabling \
		and not _source.move_component.is_forced_moving() \
		and _source.move_component.ladder_state == MoveComponent.E_LadderState.None \
		and not _source.move_component.move_factors.get(MoveComponent.E_MoveFactor.IsCharacter, false)

## 恢复普通原帧选择；不主动启用任何外部行动因素。
## [param known_width] 为同一物理步已经量过的格宽；负数表示状态回调需重新量取。
func _walk(known_width: float = -1.0) -> void:
	if _state != GroundState.WALK:
		_state = GroundState.WALK
		_elapsed = 0.0
		_animator.clear_override()
	_update_speed(false, known_width)

## [param skiing] 选择滑行或步行速度；速度组件写父空间坐标，需换算真实世界格宽。
## [param known_width] 只在本帧已有真实宽度时复用，不跨帧缓存会移动的平台坐标。
func _update_speed(skiing: bool, known_width: float = -1.0) -> void:
	var width: float = known_width if known_width >= 0.0 and is_finite(known_width) \
		else SkiObstacleQuery.cell_width(_source, _game) # 其他入口按当前脚点计算。
	var parent: Node2D = _source.get_parent() as Node2D # 原移动组件使用角色position，不能除以角色本身的迷你倍率。
	if width <= 0.0 or parent == null:
		return
	var scale_x: float = absf(parent.global_transform.x.x) # 把世界水平速度转换为该行容器的局部水平速度。
	if is_zero_approx(scale_x):
		return
	var seconds: float = SKI_SECONDS_PER_CELL if skiing else WALK_SECONDS_PER_CELL # 每格基础动作秒数。
	var speed: float = width / scale_x / seconds # 只更新基础值，寒冷和其他倍率仍由移动组件组合。
	if not is_equal_approx(_source.move_component.ori_speed, speed):
		_source.move_component.ori_speed = speed
		_source.move_component.owner_update_speed(_source.speed_factor_product())

## 正常触地才播放短恢复动作，落地期间仍可被地面攻击命中。
func _on_landed() -> void:
	if _state == GroundState.DISABLED:
		return
	_state = GroundState.LAND
	_elapsed = 0.0
	_animator.set_override(&"land")

## 同战局换行后清除旧行踏板门禁；即使从WALK直接起跳，也必须撤销残留的air覆盖。
func _on_interrupted() -> void:
	if _state == GroundState.DISABLED:
		return
	_last_obstacle = null
	_lane = _source.lane
	_elapsed = 0.0
	_animator.clear_override()
	_walk()

## 真正离场后不再查目标；飞行组件由根类独立清理，避免两个组件互相驱动生命周期。
func finish_life() -> void:
	_state = GroundState.DISABLED
	_last_obstacle = null
	set_physics_process(false)
	if is_instance_valid(_animator):
		_animator.clear_override()
