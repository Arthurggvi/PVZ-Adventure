## 玉米中毒每目标共用一个一秒节拍，粒弹命中叠层不重置计时。
extends AdventurePeriodicDamageEffect

## 同一目标的独立状态，原版中毒和灼烧仍可共存。
const NODE_NAME: StringName = &"CornPoison"
## 紫罗兰色滤镜，与原有受击、冰冻通道叠乘。
const TINT := Color(1.03, 0.52, 1.08, 1.0)
## 每层按最大本体生命的百分之一结算。
var stacks: int = 0

## 为 [param target] 增加一层，使用 [param source] 的实际击杀归属。
static func add_hit(target: Character000Base, source: RepeaterShotContext) -> void:
	if not is_instance_valid(target) or target.is_death:
		return
	var active: Variant = target.get_node_or_null(NodePath(NODE_NAME)) # 已在本轮激活的对象直接加一。
	if is_instance_valid(active) and active.is_effect_active() and active._battle_context_active():
		active.stacks += 1
		if not active._on_kill.is_valid() or active._source_id != source.source_id:
			active._source_id = source.source_id
			active._on_kill = func(casualty: Character000Base) -> void: source.on_kill(casualty)
		return
	var script: GDScript = load("res://scripts/adventure/research/corn_poison.gd") # 前几次命中才需要公共状态构造。
	if AdventurePeriodicDamageEffect.grant(target, 0.0,
			func(casualty: Character000Base) -> void: source.on_kill(casualty), NODE_NAME, script, true):
		active = target.get_node(NodePath(NODE_NAME))
		active._source_id = source.source_id
		active.stacks = 1

## 连续命中同一来源无需每层重新绑定奖励回调。
var _source_id: int = 0

## 活跃期间每个整游戏秒结算一次。
func _tick_seconds() -> float:
	return 1.0

## 以 [param max_hp] 和所有有效层数计算本次基础伤害。
func _base_tick_damage(max_hp: int) -> int:
	return roundi(float(max_hp) * float(stacks) * 0.01)

## 玉米中毒消耗本体生命，仍使用正式受伤及免疫入口。
func _tick_attack_mode() -> BulletRegistry.AttackMode:
	return BulletRegistry.AttackMode.Real

## 第一层进入时着色，后续只更新整数层数。
func _on_effect_started() -> void:
	_target.body.set_other_color(BodyCharacter.E_ChangeColors.CornPoison, TINT)

## 状态失效时同时退出紫色通道和叠层。
func _on_effect_cleared() -> void:
	stacks = 0
	_source_id = 0
	if is_instance_valid(_target) and is_instance_valid(_target.body):
		_target.body.set_other_color(BodyCharacter.E_ChangeColors.CornPoison, Color.WHITE)
