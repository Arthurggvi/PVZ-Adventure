## 普通小鬼沿地面行走，被巨人投掷时执行一次轨迹快照，再播放落地动作。
extends Zombie000Base
class_name Zombie025Imp

## 用来解除落地期间行动限制的动画名。
const LAND_ANIMATION := &"Zombie_imp_land"

## 投掷轨迹正常完成并恢复地面高度；取消飞行时不发送。
signal throw_landed

## 入树前即为真，防止释放点的地面碰撞投影提前触发进家；触地后清除。
var is_thrown := false
## 落地动画期间可以受地面伤害，但尚未开始移动或啃咬。
var _is_landing := false
## 本次出手的世界轨迹，只保存值，不追踪生成者或种植平台。
var _throw_plan: ImpThrowPlan
## 已飞行的动作秒数，始终与暂停和独立动作减速使用同一时钟。
var _flight_elapsed: float = 0.0
## 入树时应用的寒冷减速剩余秒数。
var _inherited_chill_seconds: float = 0.0


## 禁用默认物理处理，常规生成和图鉴展示不推进投掷轨迹。
func _ready() -> void:
	set_physics_process(false)
	super()


## 入树前保存有效的 [param plan] 和 [param chill_seconds] 秒寒冷减速；不读取全局变换或组件。
func initialize_throw(plan: ImpThrowPlan, chill_seconds: float) -> void:
	_throw_plan = plan
	_flight_elapsed = 0.0
	_inherited_chill_seconds = chill_seconds
	is_thrown = true


## 初始化罐子血量及投掷状态；普通出战小鬼直接行走。
func ready_norm() -> void:
	super()
	if is_thrown:
		move_component.update_move_factor(true, MoveComponent.E_MoveFactor.IsCharacter)
		attack_component.update_is_attack_factors(false, AttackComponentBase.E_IsAttackFactors.Character)
		curr_be_attack_status = E_BeAttackStatusZombie.IsJump
		body.set_forced_lift(maxf(0.0, global_position.y - _throw_plan.release_position.y))
		anim_component.signal_animation_finished.connect(_on_landing_animation_finished)
		set_physics_process(true)
		if _inherited_chill_seconds > 0.0:
			be_ice_decelerate(_inherited_chill_seconds)
		SoundManager.play_character_SFX(&"imp")
	if is_pot_zombie:
		hp_component = hp_component as HpComponentZombie
		hp_component.update_mini_zombie_hp()
		hp_stage_change_component.update_mini_zombie_hp_stage_change()


## 原生临时飞行独占位移和身体高度；不使用普通击飞的零动作速度因子。
func is_native_airborne() -> bool:
	return is_thrown


## 将 [param delta] 缩放为动作秒后解析采样；移动组件仍负责地面脚点和坡面修正。
func _physics_process(delta: float) -> void:
	if _throw_plan == null or not is_thrown:
		set_physics_process(false)
		return
	_flight_elapsed = minf(_flight_elapsed + delta * action_rate(), _throw_plan.duration)
	var air_position: Vector2 = _throw_plan.sample(_flight_elapsed) # 直接采样绝对位置，避免逐帧积分累积误差。
	if not move_component.apply_native_flight_displacement(Vector2(air_position.x - global_position.x, 0.0)):
		_end_flight(false)
		return
	body.set_forced_lift(maxf(0.0, global_position.y - air_position.y))
	if _flight_elapsed >= _throw_plan.duration:
		_end_flight(true)


## 结束空中控制；[param landed] 为真时等待落地动画，取消时只释放自身行动锁。
## [param dying] 表示正进入死亡流程，不能先切回地面受击状态或短暂恢复攻击。
func _end_flight(landed: bool, dying: bool = false) -> void:
	set_physics_process(false)
	body.set_forced_lift(0.0)
	_throw_plan = null
	is_thrown = false
	_is_landing = landed and not is_death and not is_queued_for_deletion()
	# 抓取是终态，不用投掷收尾覆盖其他系统已经接管的受击状态。
	if curr_be_attack_status == E_BeAttackStatusZombie.IsJump and not is_death and not dying:
		curr_be_attack_status = init_be_attack_status
	if _is_landing:
		throw_landed.emit()
	if not _is_landing and not dying:
		_release_throw_locks()


## [param anim_name] 为已结束的动画；完成落地后才能走路和啃咬。
func _on_landing_animation_finished(anim_name: StringName) -> void:
	if anim_name != LAND_ANIMATION or not _is_landing or is_death:
		return
	_is_landing = false
	_release_throw_locks()


## 仅释放投掷自己设置的行动因素，保留死亡、抓取、眩晕等其他来源。
func _release_throw_locks() -> void:
	attack_component.update_is_attack_factors(true, AttackComponentBase.E_IsAttackFactors.Character)
	move_component.update_move_factor(false, MoveComponent.E_MoveFactor.IsCharacter)


## 空中和落地动作期间寒冷只会减速。
func can_cold_freeze() -> bool:
	return not is_thrown and not _is_landing and super()


## 仅在常规行动中接受 [param butter_time] 秒的黄油定身。
func be_butter(butter_time: float = 4.0) -> void:
	if not is_thrown and not _is_landing:
		super(butter_time)


## 停止飞行并清理自身状态后交给通用死亡流程，不影响升阶亡语和计数。
func character_death() -> void:
	if is_thrown or _is_landing:
		_end_flight(false, true)
	super()
