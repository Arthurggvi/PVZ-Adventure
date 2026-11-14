## 斯卡蒂命中后留在目标身上的来源；不附带减速，也不接管原僵尸死亡事务。
extends Node
class_name SnowPeaStatueMark

## 每个僵尸唯一的登记节点，多株攻击只更新来源，不重复连接死亡信号。
const NODE_NAME: StringName = &"SnowPeaStatueMark"
## 接受命中的普通实战僵尸，魅惑和真正离场会撤销登记。
var _target: Zombie000Base
## 最近一次合格根攻击的冻结来源；母株被铲除或死亡不影响已经登记的目标。
var _shot: SnowPeaShot
## 最近一次根弹接触序号，只用于拒绝同次冷萃立即击碎新冰雕。
var _contact: int = 0
## 每个目标第一次死亡最多采集一次，后续尸体扣血不能再次生成。
var _consumed: bool = false

## 为真正被 [param shot] 攻击的 [param target] 登记来源，[param contact] 标识根弹接触。
## 寒冷免疫只阻止活体控制，不取消死亡冰雕；未命中目标、魅惑和旧战局均不登记。
static func register(target: Zombie000Base, shot: SnowPeaShot, contact: int) -> void:
	if not is_instance_valid(target) or shot == null or not shot.loadout.has(&"skadi") \
			or not shot.battle.is_active() or contact <= 0 or target.is_death or target.is_hypno \
			or target.is_queued_for_deletion() or not target.is_inside_tree() \
			or not shot.battle.game.is_ancestor_of(target) \
			or target.character_init_type != Character000Base.E_CharacterInitType.IsNorm:
		return
	var mark := target.get_node_or_null(NodePath(NODE_NAME)) as SnowPeaStatueMark # 重复命中复用同一观察节点。
	if mark == null:
		mark = SnowPeaStatueMark.new()
		mark.name = NODE_NAME
		mark._target = target
		target.add_child(mark)
	if mark._consumed:
		return
	mark._shot = shot
	mark._contact = contact
	mark.set_physics_process(true)

## 一次连接首次死亡观察和魅惑清理；死亡前无需依赖正在变化的碰撞或动画状态。
func _ready() -> void:
	set_physics_process(false)
	_target.hp_component.before_death.connect(_on_before_death)
	_target.signal_character_be_hypno.connect(clear)

## [param cause] 只描述这一笔真正致死的伤害，先前火焰或冥弹擦伤不阻止未来普通死亡。
func _on_before_death(cause: CombatHitScope.DeathCause) -> void:
	if _consumed:
		return
	_consumed = true
	if _shot != null and _shot.battle.is_active() and not _target.is_hypno \
			and cause not in [CombatHitScope.DeathCause.FIRE, CombatHitScope.DeathCause.HADES]:
		SnowPeaStatue.capture(_target, _shot, _contact)
	clear()

## [param _delta] 不消耗时限；登记持续至目标死亡或原战局、轮次及阶段失效。
func _physics_process(_delta: float) -> void:
	if _shot == null or not _shot.battle.is_active():
		clear()

## 只撤销本冰雕来源，不清理目标的其他状态和其他伤害来源。
func clear() -> void:
	_shot = null
	_contact = 0
	set_physics_process(false)

## 大蒜换行的短暂离树不算离场；真正移除或切换战场才撤销登记。
func _exit_tree() -> void:
	if is_instance_valid(_target) and _target.is_changing_lane:
		return
	clear()
