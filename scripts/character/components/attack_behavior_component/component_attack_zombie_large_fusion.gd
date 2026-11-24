## 接触碾压的有限状态机；自身后抛绕过外部控制入口，耗尽后永久停驻且不啃咬。
extends AttackComponentBase
class_name AttackComponentZombieLargeFusion

## 碾压的基础伤害固定，不套用普通啃咬的等阶倍率。
const CRUSH_DAMAGE: int = 1000
## 一生最多消耗的接触次数，第三次未击杀仍完成后抛。
const MAX_CRUSHES: int = 3
## 后抛持续时间，单位动作秒，与疲劳后的地面速度无关。
const REBOUND_SECONDS: float = 0.65
## 后抛最高抬升距离，单位世界像素。
const REBOUND_HEIGHT: float = 80.0
## 地面、后抛、耗尽与死亡互斥，不依赖动画帧发出伤害事件。
enum RollState { ROLLING, AIRBORNE, EXHAUSTED, DEAD }
## 单次碾压的世界脚点，在伤害回调可能释放目标之前发出。
signal crush_contact(world_position: Vector2)
## 自身原生后抛已经开始，不由动画帧决定是否起跳。
signal rebound_started
## 真正完成落地；第三次的永久耗尽已在此信号前确定。
signal rebound_landed
## 碾压次数耗尽的单次通知，表现不能借此恢复移动。
signal rolling_exhausted

## 本体接口仅依赖通用僵尸，避免与物种根类循环依赖。
@onready var _zombie: Zombie000Base = owner as Zombie000Base
## 当前翻滚姿态的前缘锚点，继承精灵的变换。
@onready var _crush_front: Marker2D = _zombie.get_node(^"Body/FusionSprite/CrushFront") as Marker2D
## 接触框所在的区域，保留通用检测器的屋顶行基准；区域原点对应接触框前缘。
@onready var _crush_area: Area2D = $DetectComponent/Area2d
## 从前缘向球体内部延伸的窄接触框，仅作为当步物理查询的形状数据。
@onready var _crush_shape: CollisionShape2D = $DetectComponent/Area2d/CollisionShape2D
## 当前翻滚阶段。
var _state: RollState = RollState.ROLLING
## 已预留的碾压次数，结算目标伤害前递增以防回调重入。
var _crush_count: int = 0
## 当前连续接触对象，未离开接触区时不能逐帧重复碾压。
var _contact_id: int = 0
## 本次后抛起点的世界横坐标。
var _rebound_start_x: float = 0.0
## 本次后抛的两格世界距离，包含本体实际前进方向。
var _rebound_distance: float = 0.0
## 本次后抛已推进的动作秒数。
var _rebound_elapsed: float = 0.0

## 展示和未初始化战斗的实例不推进接触判定。
func _ready() -> void:
	super()
	detect_component.detects_hidden_plant_contacts = true
	set_physics_process(false)

## 由物种根节点在生命与召唤组件完成配置后启用。
func activate() -> void:
	set_physics_process(true)

## 返回当前是否处于地面滚动态；地面特效仍需检查是否真的产生位移。
func is_rolling_on_ground() -> bool:
	return _state == RollState.ROLLING

## 返回是否正在执行自身后抛，供脚点位移与进家检测识别。
func is_rebounding() -> bool:
	return _state == RollState.AIRBORNE

## 返回是否永久耗尽；用于呼吸姿态与滚动声收尾，不公开可写状态。
func is_exhausted() -> bool:
	return _state == RollState.EXHAUSTED

## [param delta] 是战斗秒；只有地面滚动可以消耗碾压次数。
func _physics_process(delta: float) -> void:
	if _zombie.is_death or _zombie.is_queued_for_deletion():
		finish_life()
		return
	if not is_enabling:
		return
	if _state == RollState.AIRBORNE:
		_advance_rebound(delta * _zombie.action_rate())
		return
	if _state != RollState.ROLLING or _zombie.is_action_suspended() or not detect_component.is_enabling:
		return
	# 直接查询当前画面上的接触框，换帧后立即使用新的前缘位置。
	_crush_area.position = _zombie.to_local(_crush_front.global_position)
	# 每个候选快照独立选取角色和道具。
	detect_component.enemy_can_be_attacked = null
	detect_component.brain = null
	detect_component.judge_enemy_in_areas(CombatExplosion.query_collider(_crush_shape, _crush_area.collision_mask))
	var target: Character000Base = detect_component.enemy_can_be_attacked # 沿用外壳、行号及屏障筛选。
	if not is_instance_valid(target) or target.is_death or target.is_queued_for_deletion():
		_contact_id = 0
		# 我是僵尸模式的脑子沿用冰车接触规则，耗尽后不会进入此分支。
		if is_instance_valid(detect_component.brain) and not detect_component.brain.is_death:
			detect_component.brain.be_flattened()
		return
	if not (target is Plant000Base or target is FriendlyBattleBarrier):
		return
	if target.get_instance_id() != _contact_id:
		_crush(target)

## [param target] 是首次接触的有效防线实体；伤害结算后的真实存活状态决定是否后抛。
func _crush(target: Character000Base) -> void:
	_contact_id = target.get_instance_id()
	_crush_count += 1
	_zombie.update_speed_factor(0.0 if _crush_count >= MAX_CRUSHES else pow(0.5, _crush_count),
		Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
	var point: Vector2 = Vector2(_crush_front.global_position.x, _zombie.global_position.y) # 将前缘投影到实际地面。
	var slope: MainGameSlope = Global.main_game.main_game_slope # 屋顶前缘和本体脚下可能处于不同高度。
	if is_instance_valid(slope):
		point.y += slope.get_all_slope_y(point.x) - slope.get_all_slope_y(_zombie.global_position.x)
	crush_contact.emit(point)
	if target is FriendlyBattleBarrier:
		(target as FriendlyBattleBarrier).be_zombie_eat(CRUSH_DAMAGE, _zombie)
	else:
		_damage_plant(target as Plant000Base)
	if _zombie.is_death or _zombie.is_queued_for_deletion() or _state == RollState.DEAD:
		return
	if is_instance_valid(target) and not target.is_death and not target.is_queued_for_deletion():
		_begin_rebound()
	elif _crush_count >= MAX_CRUSHES:
		_exhaust()

## [param plant] 仍由原生命入口结算 1000 点伤害；只为本次真实致死挂接原生压扁表现。
func _damage_plant(plant: Plant000Base) -> void:
	var health: HpComponent = plant.hp_component # 临时观察真实死亡，不能用原始伤害预判护甲和减伤结果。
	var flatten: Callable = _show_crushed_plant.bind(plant) # 本次同步扣血结束即移除，幸存植物的以后死亡不受影响。
	health.before_death.connect(flatten, CONNECT_ONE_SHOT)
	health.Hp_loss(CRUSH_DAMAGE, BulletRegistry.AttackMode.Norm, true, false, true, 0, -1, null,
		CombatHitScope.for_plant_attack(_zombie, CombatHitScope.PlantImpact.CRUSH))
	if is_instance_valid(health) and health.before_death.is_connected(flatten):
		health.before_death.disconnect(flatten)

## [param _cause] 保留原死亡来源；[param plant] 已由生命组件确认死亡，尚未执行植物普通退场。
func _show_crushed_plant(_cause: CombatHitScope.DeathCause, plant: Plant000Base) -> void:
	if is_instance_valid(plant) and plant.is_inside_tree() and is_instance_valid(plant.body):
		plant.body.be_flattened_body()

## 两格按当前棋盘实测宽度计算，不硬编码格宽；原生飞行保持坡面与行走基准同步。
func _begin_rebound() -> void:
	_state = RollState.AIRBORNE
	_rebound_elapsed = 0.0
	_rebound_start_x = _zombie.global_position.x
	_rebound_distance = 2.0 * Global.main_game.board.cell_width_at(_zombie.global_position, _zombie.lane) \
		* _zombie.direction_x_root
	_zombie.move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsJump)
	_zombie.curr_be_attack_status = Zombie000Base.E_BeAttackStatusZombie.IsJump
	rebound_started.emit()

## [param seconds] 为动作时间增量；按绝对进度采样，第三次零地面速度不会卡在空中。
func _advance_rebound(seconds: float) -> void:
	_rebound_elapsed = minf(_rebound_elapsed + seconds, REBOUND_SECONDS)
	var progress: float = _rebound_elapsed / REBOUND_SECONDS # 同时控制水平位置和抛物线高度。
	var next_x: float = _rebound_start_x + _rebound_distance * progress # 轨迹终点恰好为起点后两格。
	if not _zombie.move_component.apply_native_flight_displacement(Vector2(next_x - _zombie.global_position.x, 0.0)):
		_land()
		return
	_zombie.body.set_forced_lift(4.0 * REBOUND_HEIGHT * progress * (1.0 - progress))
	if _rebound_elapsed >= REBOUND_SECONDS:
		_land()

## 释放自身后抛锁，耗尽时先建立永久停车锁，避免落地瞬间恢复移动。
func _land() -> void:
	if _state == RollState.DEAD:
		return
	_zombie.body.set_forced_lift(0.0)
	if _zombie.curr_be_attack_status == Zombie000Base.E_BeAttackStatusZombie.IsJump:
		_zombie.curr_be_attack_status = _zombie.init_be_attack_status
	_state = RollState.ROLLING
	_contact_id = 0
	if _crush_count >= MAX_CRUSHES:
		_exhaust()
	_zombie.move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsJump)
	rebound_landed.emit()

## 永久消耗全部碾压能力，保留生命、受击和后代生成。
func _exhaust() -> void:
	_state = RollState.EXHAUSTED
	_zombie.is_walk = false
	_zombie.move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	disable_component(ComponentNormBase.E_IsEnableFactor.Character)
	set_physics_process(false)
	rolling_exhausted.emit()

## 死亡抢占自身飞行和接触逻辑，不恢复地面攻击状态。
func finish_life() -> void:
	_state = RollState.DEAD
	set_physics_process(false)
	_zombie.body.set_forced_lift(0.0)
	_zombie.move_component.disable_component(ComponentNormBase.E_IsEnableFactor.Death)
	disable_component(ComponentNormBase.E_IsEnableFactor.Death)

## 接触检测不切换普通僵尸的停步啃咬状态。
func attack_start() -> void:
	pass

## 离开接触区也不产生普通攻击信号。
func attack_end() -> void:
	pass

## [param _speed_product] 不再驱动固定帧钟；表现组件读取真实位移，避免低速空转。
func owner_update_speed(_speed_product: float) -> void:
	pass
