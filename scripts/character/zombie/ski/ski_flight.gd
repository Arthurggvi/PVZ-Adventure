## 滑雪僵尸原生短跳的唯一位置写入者；风力接管同一轨迹，不叠加外部强制位移。
extends Node
class_name SkiFlight

## 起点、终点为世界脚点；[param wind] 区分自然借冰与风力改道，供表现和观察使用。
signal started(start: Vector2, end: Vector2, wind: bool)
## 只有活体完整到达落点才发送；取消、死亡和吹出屏幕不发送。
signal landed
## 同一战局换行只中断当前动作；通知门面恢复新行步行，不结束此角色的后续借冰。
signal interrupted
## 当前角色；展示实例不配置，所有清理入口允许为空。
var _source: Zombie000Base
## 初始化所属战局，防止旧实体借用新场景的全局入口。
var _game: MainGameManager
## 初始化棋盘身份，布局被替换后不能继续旧轨迹。
var _board: BoardRuntime
## 初始化阶段；非冒险关允许为空。
var _phase: StagePhaseDefinition
## 初始化轮数，换轮取消尚未完成的动作。
var _round: int = 0
## 当前数值轨迹；空值表示没有飞行，不持有冰障对象。
var _plan: SkiFlightPlan
## 已推进的动作秒数；风力改道后使用物理秒。
var _elapsed: float = 0.0
## 最近采样的世界空中脚点，改道从这里连续开始。
var _air_position: Vector2 = Vector2.ZERO
## 本次飞行开始的行号；换行不延续原行的落点。
var _lane: int = -1
## 是否为三叶草接管的风推，决定时钟和出屏清场。
var _wind: bool = false
## 本次风推的视野右界，其他场景切换后不再沿用。
var _visible_right: float = INF
## 触地后继续持有行动锁，直到落地原帧播放完。
var _landing: bool = false
## 真正离场或战局失效后不再接收新飞行。
var _ended: bool = false
## 只释放本组件实际取得的跳跃移动锁。
var _owns_move_lock: bool = false
## 只释放本组件实际取得的角色攻击锁。
var _owns_attack_lock: bool = false
## This flight owns a damage-reduction source only while genuinely airborne.
const AIR_DAMAGE_REDUCTION: float = 0.60

## 展示实例及空闲轨迹不运行物理处理。
func _ready() -> void:
	set_physics_process(false)

## [param source] 已完成原生初始化；绑定战局但不主动起跳。
func configure(source: Zombie000Base) -> void:
	_source = source
	_game = Global.main_game
	_board = _game.board
	_phase = AdventureSession.get_active_phase(_game.game_para)
	_round = _game.curr_game_round

## 返回是否正在占用原生空中位移；落地恢复不属于天空状态。
func is_airborne() -> bool:
	return _plan != null and not _ended

## 当前实体、棋盘、轮数与阶段必须仍属于初始化的战局；不改变任何状态。
func belongs_to_battle() -> bool:
	return not _ended and is_instance_valid(_source) and _source.is_inside_tree() \
		and not _source.is_death and not _source.is_queued_for_deletion() \
		and is_instance_valid(_game) and _game == Global.main_game and _game.is_ancestor_of(_source) \
		and _game.board == _board and _game.curr_game_round == _round \
		and AdventureSession.get_active_phase(_game.game_para) == _phase

## 接受已校验的 [param plan]；只有地面活体可起跳，成功后独占移动、啃咬和天空状态。
func begin(plan: SkiFlightPlan) -> bool:
	if plan == null or not belongs_to_battle() or is_airborne() or _landing \
			or not _game.zombie_manager.is_game_running() or _source.is_action_suspended() \
			or _source.move_component.is_forced_moving():
		return false
	_owns_move_lock = not _source.move_component.move_factors.get(MoveComponent.E_MoveFactor.IsJump, false)
	_owns_attack_lock = _source.attack_component.is_attack_factors.get(AttackComponentBase.E_IsAttackFactors.Character, true)
	if not _owns_move_lock or not _owns_attack_lock:
		_owns_move_lock = false
		_owns_attack_lock = false
		return false
	_source.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsJump)
	_source.attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Character)
	_plan = plan
	_elapsed = 0.0
	_air_position = plan.sample(0.0)
	_lane = _source.lane
	_wind = false
	_source.curr_be_attack_status = Zombie000Base.E_BeAttackStatusZombie.IsSky
	_source.hp_component.damage_reduction.set_source(get_instance_id(), AIR_DAMAGE_REDUCTION)
	_source.anim_component.owner_update_speed(1.0) # Ignore any ground slow for the entire air animation.
	set_physics_process(true)
	started.emit(_air_position, plan.landing_position, false)
	return true

## [param delta] 为战斗物理秒；普通短跳只消费一次合成动作倍率，零倍率保持当前高度。
func _physics_process(delta: float) -> void:
	if not belongs_to_battle() or not _game.zombie_manager.is_game_running():
		finish_life()
		return
	if _source.lane != _lane:
		_interrupt_for_lane_change()
		return
	if _plan == null:
		return # 落地恢复仍监视战局身份，换场不能留下行动锁。
	if _source.curr_be_attack_status != Zombie000Base.E_BeAttackStatusZombie.IsSky:
		finish_life()
		return
	var rate: float = 1.0 # Airborne immunity prevents existing or incoming slow effects changing the flight clock. # 风与共用吹退保持同一物理时钟。
	_elapsed = minf(_plan.duration, _elapsed + delta * rate)
	_air_position = _plan.sample(_elapsed)
	if not _source.move_component.apply_native_flight_displacement(Vector2(_air_position.x - _source.global_position.x, 0.0)):
		finish_life()
		return
	_source.body.set_forced_lift(maxf(0.0, _source.global_position.y - _air_position.y))
	if _elapsed >= _plan.duration:
		_arrive()

## 三叶草将余程替换成向右 [param cells] 格；保持当前空中脚点，成功返回 true。
func redirect_wind(cells: int) -> bool:
	if not belongs_to_battle() or not is_airborne():
		return false
	var replacement: SkiFlightPlan = SkiFlightPlan.for_wind(_source, _game, _air_position,
		SkiObstacleQuery.cell_width(_source, _game), cells) # 新风轨迹不会与原短跳同时推进。
	if replacement == null:
		return false
	_plan = replacement
	_elapsed = 0.0
	_wind = true
	var viewport: Viewport = _source.get_viewport() # 记录真实可见右界，非棋盘最右格。
	_visible_right = (viewport.get_canvas_transform().affine_inverse()
		* Vector2(viewport.get_visible_rect().size.x, 0.0)).x
	started.emit(_air_position, _plan.landing_position, true)
	return true

## 达到精确终点后恢复地面受击；吹出视野按现有三叶草规则退场。
func _arrive() -> void:
	if _wind and AdventureZombieWindGust.is_wind_elimination(true, _source.global_position.x, _visible_right):
		_source.character_death_disappear()
		return
	_source.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)
	_source.anim_component.owner_update_speed(_source.speed_factor_product())
	_plan = null
	_landing = true
	_source.body.set_forced_lift(0.0)
	_source.curr_be_attack_status = _source.init_be_attack_status
	landed.emit()

## 落地原帧播完后仅释放自身行动锁；外部死亡、眩晕和推移因素仍保持原值。
func release_landing() -> void:
	_landing = false
	set_physics_process(false)
	_release_locks()

## 同战局换行取消余程或落地恢复；不设置_ended，下一次接触仍能创建新轨迹。
func _interrupt_for_lane_change() -> void:
	set_physics_process(false)
	_clear_motion()
	_lane = _source.lane
	interrupted.emit()

## 终止余程和本组件的抬高，不执行落地回调；展示、死亡、换场重复清理均安全。
func finish_life() -> void:
	if _ended:
		return
	_ended = true
	set_physics_process(false)
	_clear_motion()

## 只撤销仍由本轨迹占有的高度和天空状态；落地后外部抛起的高度不属于本组件。
func _clear_motion() -> void:
	if is_instance_valid(_source) and _plan != null:
		_source.body.set_forced_lift(0.0)
		if not _source.is_death and _source.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsSky:
			_source.curr_be_attack_status = _source.init_be_attack_status
	if is_instance_valid(_source) and is_instance_valid(_source.hp_component):
		_source.hp_component.damage_reduction.set_source(get_instance_id(), 0.0)
		if is_instance_valid(_source.anim_component):
			_source.anim_component.owner_update_speed(_source.speed_factor_product())
	_plan = null
	_landing = false
	_elapsed = 0.0
	_wind = false
	_release_locks()

## 不使用全量启用开关；只归还起跳时确实取得的两个因素。
func _release_locks() -> void:
	if _owns_move_lock and is_instance_valid(_source.move_component):
		_owns_move_lock = false
		_source.move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsJump)
	if _owns_attack_lock and is_instance_valid(_source.attack_component):
		_owns_attack_lock = false
		_source.attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Character)
