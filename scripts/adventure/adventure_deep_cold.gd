## 目标持有的抗火寒冷；两种期限独立于原生冰和火焰解除。
extends Node
class_name AdventureDeepCold

## 同一角色只有一份深寒；多个来源只续时。
const STATUS_NAME: StringName = &"AdventureDeepCold"
## 本状态所属战局；母株离场后控制仍继续。
var _battle: RepeaterShotContext
## 深寒作用的普通僵尸。
var _target: Zombie000Base
## 最近施加者原生允许的僵尸受击状态位。
var _statuses: int
## 剩余抗火减速秒数。
var _slow: float = 0.0
## 剩余抗火冻结秒数。
var _freeze: float = 0.0

## 为 [param target] 在 [param battle] 施加 [param slow_seconds] 秒减速与 [param freeze_seconds] 秒冻结。
## [param statuses] 为允许的僵尸受击状态位；冻结抵抗的普通僵尸仍可减速。
static func apply_to(target: Zombie000Base, battle: RepeaterShotContext,
		slow_seconds: float, freeze_seconds: float, statuses: int) -> bool:
	if not is_instance_valid(target) or battle == null or not battle.is_active() \
			or not battle.game.is_ancestor_of(target) or not target.can_receive_cold() \
			or slow_seconds <= 0.0 or not is_finite(freeze_seconds) \
			or (target.curr_be_attack_status & statuses) == 0 or not target.hurt_box_component.is_enabling:
		return false
	var status := target.get_node_or_null(NodePath(STATUS_NAME)) as AdventureDeepCold # 每目标复用一个计时状态。
	if status == null:
		status = _attach(target)
	elif not status._battle.is_same_battle():
		status._reset()
	status._battle = battle
	status._statuses = statuses
	status._slow = maxf(slow_seconds, status._slow)
	if target.can_cold_freeze():
		status._freeze = maxf(freeze_seconds, status._freeze)
	target.on_cold_control()
	status._sync()
	status.set_physics_process(true)
	return true

## 为 [param target] 附加本角色的状态节点；冷却和来源随节点形成独立生命周期。
static func _attach(target: Zombie000Base) -> AdventureDeepCold:
	var status := AdventureDeepCold.new() # 新角色使用自己的控制节点和时钟。
	status.name = STATUS_NAME
	status._target = target
	target.add_child(status)
	return status

## 保存 [param source] 尚在作用的深寒秒数，保留结算状态位及来源战场。
static func capture(source: Zombie000Base) -> Dictionary:
	var status := source.get_node_or_null(NodePath(STATUS_NAME)) as AdventureDeepCold
	if status == null or (status._slow <= 0.0 and status._freeze <= 0.0):
		return {}
	return {"battle": status._battle, "statuses": status._statuses, "slow": status._slow, "freeze": status._freeze}

## 在 [param target] 独立还原 [param state]，扣除排队所用的 [param elapsed] 秒。
static func restore(target: Zombie000Base, state: Dictionary, elapsed: float) -> void:
	if state.is_empty() or not target.can_receive_cold():
		return
	var slow: float = maxf(0.0, float(state["slow"]) - elapsed) # 已到期的普通减速不延长。
	var freeze: float = maxf(0.0, float(state["freeze"]) - elapsed) if target.can_cold_freeze() else 0.0 # 两种时钟各自结算。
	if slow == 0.0 and freeze == 0.0:
		return
	var status: AdventureDeepCold = _attach(target) # 克隆的计时与原单位相互独立。
	status._battle = state["battle"]
	status._statuses = state["statuses"]
	status._slow = slow
	status._freeze = freeze
	target.on_cold_control()
	status._sync()
	status.set_physics_process(true)

## 死亡和魅惑同步撤销控制；菜单暂停由场景树负责。
func _ready() -> void:
	set_physics_process(false)
	_target.signal_character_death.connect(_reset)
	_target.signal_character_be_hypno.connect(_reset)

## [param delta] 为有效战斗秒；只有控制状态发生改变时更新角色输出。
func _physics_process(delta: float) -> void:
	if not _battle.is_active() or not _target.can_receive_cold() \
			or not _target.can_receive_negative_effects() or _target.is_queued_for_deletion() \
			or _target.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not _target.hurt_box_component.is_enabling or (_target.curr_be_attack_status & _statuses) == 0:
		_reset()
		return
	var was_frozen: bool = _freeze > 0.0 # 本来源退出时核对是否真正解冻。
	var was_slowed: bool = _slow > 0.0 # 时钟越过零才更新乘色和速度。
	_freeze = maxf(0.0, _freeze - delta) if _target.can_cold_freeze() else 0.0
	_slow = maxf(0.0, _slow - delta)
	if was_frozen != (_freeze > 0.0) or was_slowed != (_slow > 0.0):
		_sync()
		if was_frozen and _freeze == 0.0:
			_target.notify_cold_thaw()
		if _slow == 0.0 and _freeze == 0.0:
			set_physics_process(false)

## 普通换行短暂离树时保留状态，真正离场才释放。
func _exit_tree() -> void:
	if is_instance_valid(_target) and not _target.is_changing_lane:
		_reset()

## 阶段结束或角色失效时撤销本状态的全部输出。
func _reset() -> void:
	_slow = 0.0
	_freeze = 0.0
	set_physics_process(false)
	if is_instance_valid(_target):
		_sync()

## 把当前独立寒冷控制写入原生速度合成器和身体滤镜。
func _sync() -> void:
	_set_factor(Character000Base.E_Influence_Speed_Factor.DeepColdSlow, 0.5 if _slow > 0.0 else 1.0)
	_set_factor(Character000Base.E_Influence_Speed_Factor.DeepColdFreeze, 0.0 if _freeze > 0.0 else 1.0)
	if is_instance_valid(_target.body):
		_target.body.set_other_color(BodyCharacter.E_ChangeColors.DeepCold,
			Color(0.37, 0.66, 1.0) if _slow > 0.0 or _freeze > 0.0 else Color.WHITE)

## 为 [param factor] 写入有变化的 [param value]，避免重复刷新动画和移动。
func _set_factor(factor: Character000Base.E_Influence_Speed_Factor, value: float) -> void:
	if _target.influence_speed_factors.get(factor, 1.0) != value:
		_target.update_speed_factor(value, factor)
