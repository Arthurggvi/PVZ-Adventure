## 陷阵只限制移速；各发命中刷新同一个状态，避免成倍叠减或每次创建计时器。
extends Node

## 在目标上复用的唯一陷阵状态。
const EFFECT_NAME := &"ThreePeaAssaultSlow"
## 按需构造同脚本的状态节点，仅在首次命中时使用资源缓存。
const SCRIPT_PATH := "res://scripts/bullet/three_pea_assault_slow.gd"
## 当前受影响的真实僵尸。
var _target: Zombie000Base
## 跟随战场时钟的剩余秒数。
var _remaining: float = 0.0

## 为有效 [param enemy] 刷新 [param seconds] 秒移速系数 [param rate]；保留其他来源的移速和攻速。
static func apply(enemy: Character000Base, seconds: float, rate: float) -> void:
	var zombie := enemy as Zombie000Base # 设施、僵王和不可控制的目标沿用其免疫。
	if not is_instance_valid(zombie) or zombie.is_death or zombie.is_hypno or zombie.is_queued_for_deletion() \
			or not is_instance_valid(zombie.move_component) or not zombie.can_receive_control_effects() \
			or not zombie.can_receive_negative_effects():
		return
	var effect: Node = zombie.get_node_or_null(NodePath(EFFECT_NAME)) # 非叠加效果共用一个状态节点。
	if effect == null:
		effect = (load(SCRIPT_PATH) as GDScript).new()
		effect.name = EFFECT_NAME
		effect._target = zombie
		zombie.add_child(effect)
	if effect._remaining <= 0.0:
		zombie.move_component.set_move_rate_source(effect.get_instance_id(), rate)
		effect.set_physics_process(true)
	effect._remaining = maxf(effect._remaining, seconds)

## 状态与僵尸共存，死亡或变阵营时同步解除。
func _ready() -> void:
	_target.signal_character_death.connect(_release)
	_target.signal_character_be_hypno.connect(_release)

## [param delta] 为游戏秒。移速独立来源在结束帧就移除。
func _physics_process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0 or not is_instance_valid(_target) or _target.is_death or _target.is_hypno \
			or not _target.can_receive_control_effects() or not _target.can_receive_negative_effects():
		_release()

## 换行的同步重挂保留减速；永久离开战场时清除。
func _exit_tree() -> void:
	if is_instance_valid(_target) and not _target.is_changing_lane:
		_release()

## 只撤销本效果的移速。
func _release() -> void:
	_remaining = 0.0
	set_physics_process(false)
	if is_instance_valid(_target) and is_instance_valid(_target.move_component):
		_target.move_component.set_move_rate_source(get_instance_id(), 1.0)
