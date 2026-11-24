## 主动技能的敌方目标读取门面；重用 ZombieManager 的登记，不重新维护名单。
extends RefCounted
class_name CharacterSkillTargetQuery

## [param context] 必须仍属于有效战局；[param bosses] 和 [param structures] 控制敌人类别。
## 仅在施放时生成快照。[param require_hurt_box] 为 true 时要求受击框开放。
static func all_hostiles(context: CharacterSkillContext,
		bosses: bool = true, structures: bool = false, require_hurt_box: bool = true) -> Array[Character000Base]:
	var results: Array[Character000Base] = [] # 单次施放的去重目标。
	if context == null or not context.is_active():
		return results
	var manager: ZombieManager = context.game.zombie_manager # 当前战场权威敌人注册。
	var seen: Dictionary[int, bool] = {} # 同个实体跨行登记时也不能重复结算。
	for row: Array in manager.all_zombies_2d: # 只读取当前行的快照，不修改管理器数组。
		for zombie: Zombie000Base in row.duplicate():
			_append(context, zombie, seen, results, require_hurt_box)
	if bosses:
		for boss: ZB000Base in manager.get_living_bosses(): # Boss 不属于普通僵尸行。
			_append(context, boss, seen, results, require_hurt_box)
	if structures:
		for structure: Node in context.game.get_tree().get_nodes_in_group(EnemyStructureBase.GROUP):
			_append(context, structure as Character000Base, seen, results, require_hurt_box)
	return results

## [param context] 是本局身份，[param candidate] 是待检实体；[param seen] 避免同击重复命中。
## [param results] 只追加敌方实体。[param require_hurt_box] 控制是否检查受击框。
static func _append(context: CharacterSkillContext, candidate: Character000Base,
		seen: Dictionary[int, bool], results: Array[Character000Base], require_hurt_box: bool) -> void:
	if not is_valid_hostile(context, candidate, require_hurt_box):
		return
	var identity: int = candidate.get_instance_id() # 复生是新实例，不与旧实体混淆。
	if not seen.has(identity):
		seen[identity] = true
		results.append(candidate)

## [param context] 必须有效。[param target] 仍属本局敌方且存活；[param require_hurt_box] 控制是否要求可受击。
static func is_valid_hostile(context: CharacterSkillContext, target: Character000Base,
		require_hurt_box: bool = true) -> bool:
	if context == null or not context.is_active() or not is_instance_valid(target) \
			or target.is_queued_for_deletion() or target.is_death or not target.is_inside_tree() \
			or not context.game.is_ancestor_of(target) \
			or target.character_init_type != Character000Base.E_CharacterInitType.IsNorm:
		return false
	if target is Zombie000Base and (target as Zombie000Base).is_hypno:
		return false
	return not require_hurt_box or (is_instance_valid(target.hurt_box_component) and target.hurt_box_component.is_enabling)

## [param context] 和 [param target] 必须有效且目标允许接收负面状态。
static func can_receive_negative(context: CharacterSkillContext, target: Character000Base) -> bool:
	return is_valid_hostile(context, target) and target.can_receive_negative_effects()

## [param complete_freeze] 需要真正完全冻结时校验物种额外免疫。
## Boss 和设施默认拒绝寒冷，不允许新技能绕过它们的受击窗口和行为树。
static func can_receive_cold(context: CharacterSkillContext,
		target: Character000Base, complete_freeze: bool = true) -> bool:
	return can_receive_negative(context, target) and target.can_receive_cold() \
		and (not complete_freeze or target.can_cold_freeze())
