## 等阶能力的可撤销输出与暂停协议；沉默保留节点、成长和计时进度。
extends Node
class_name AdventureZombieTierAbility

## 能力所属僵尸；死亡技能仍可读取死亡瞬间的沉默快照。
var tier_owner: Zombie000Base
## 本能力期望的速度、啃咬和防御输出，沉默只遮蔽而不丢失数值。
var _tier_outputs: Dictionary[StringName, Variant] = {}
## 显式登记的原生配置覆盖，记录默认值而不快照运行时生命或动作状态。
var _tier_properties: Array[Dictionary] = []

## 绑定 [param zombie] 的能力启停信号，不重放初始化或出生奖励。
func bind_tier(zombie: Zombie000Base) -> void:
	tier_owner = zombie
	zombie.signal_tier_skills_changed.connect(_on_tier_skills_changed)
	process_mode = Node.PROCESS_MODE_INHERIT if tier_enabled() else Node.PROCESS_MODE_DISABLED

## 返回当前等阶资格；死亡时使用角色冻结的资格，避免清理沉默后复活亡语。
func tier_enabled() -> bool:
	return is_instance_valid(tier_owner) and tier_owner.are_tier_skills_active()

## [param allow_dead] 仅供亡语使用；普通事件需要来源存活且未排队销毁。
func tier_can_trigger(allow_dead: bool = false) -> bool:
	var game: MainGameManager = Global.main_game # 迟到信号不得把旧场景来源作用到后来的战场。
	return tier_enabled() and tier_owner.is_inside_tree() and is_instance_valid(game) \
		and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game.is_ancestor_of(tier_owner) and (allow_dead or (
			not tier_owner.is_death and not tier_owner.is_queued_for_deletion()))

## 永久能力允许跨续战阶段继续绑定，但旧出生事件的一次性奖励不能在新阶段补发。
func tier_can_grant_entry() -> bool:
	if not tier_can_trigger():
		return false
	var binding: Node = tier_owner.get_node_or_null("AdventureTierBehavior") # 同一出生绑定保存原事件阶段。
	return is_instance_valid(binding) and bool(binding.call("allows_entry_reward"))

## 按 [param multiplier] 保存等阶专用动作倍率；其他减速、原生暴走和基础成长不受影响。
func set_tier_speed(multiplier: float) -> void:
	_tier_outputs[&"speed"] = multiplier
	_apply_output(&"speed")

## 保存 [param multiplier] 到独立啃咬通道 [param factor]，沉默时仅撤销本能力的通道。
func set_tier_bite(multiplier: float, factor: AttackComponentZombieNorm.E_AttackValueFactor) -> void:
	var key := StringName("bite:%d" % factor) # 通道编号只标识本能力管理的等阶啃咬加成。
	_tier_outputs[key] = multiplier
	_apply_output(key)

## 保存防御 [param channel] 的 [param amount]；按本节点来源撤销，不覆盖其他保护者。
func set_tier_defense(channel: StringName, amount: float) -> void:
	_tier_outputs[channel] = amount
	_apply_output(channel)

## 明确覆盖 [param target] 的配置 [param property] 为 [param value]；首次记录原生值供沉默回退。
## 仅用于能力拥有的配置字段，不可登记生命池、动作状态或计时器剩余时间。
func set_tier_property(target: Object, property: StringName, value: Variant) -> void:
	if not is_instance_valid(target):
		return
	for entry: Dictionary in _tier_properties: # 同一配置反复更新时保留最初的原生默认值。
		if entry["id"] == target.get_instance_id() and entry["property"] == property:
			entry["value"] = value
			target.set(property, value if tier_enabled() else entry["native"])
			return
	var entry: Dictionary = { # 弱引用避免能力配置延长管理器或动画节点的生命周期。
		"id": target.get_instance_id(), "target": weakref(target), "property": property,
		"native": target.get(property), "value": value,
	}
	_tier_properties.append(entry)
	target.set(property, value if tier_enabled() else entry["native"])

## [param active] 改变可撤销输出并暂停自身处理；计时器和累积值保持原进度。
func _on_tier_skills_changed(active: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	for key: StringName in _tier_outputs: # 所有持续输出使用同一门禁，不靠各调用端另行覆盖。
		_apply_output(key)
	for entry: Dictionary in _tier_properties: # 只恢复本能力声明拥有的配置。
		var target: Object = (entry["target"] as WeakRef).get_ref() # 对象可能已随原生阶段结束销毁。
		if is_instance_valid(target):
			target.set(entry["property"], entry["value"] if active else entry["native"])
	_tier_state_changed(active)

## 子类按 [param active] 撤销光环或切换原生策略，不得调用 setup 重建能力。
func _tier_state_changed(_active: bool) -> void:
	pass

## 将 [param key] 对应输出合成到角色，失效时只恢复该通道的中性值。
func _apply_output(key: StringName) -> void:
	if not is_instance_valid(tier_owner):
		return
	var enabled: bool = tier_enabled() # 生效判定与死亡快照共用同一个角色入口。
	var value: float = float(_tier_outputs[key]) # 输出值保持原单位，仅生效时写入。
	if key == &"speed":
		tier_owner.update_speed_factor(value if enabled else 1.0,
			Character000Base.E_Influence_Speed_Factor.AdventureTierStance)
	elif String(key).begins_with("bite:"):
		var attack: AttackComponentZombieNorm = tier_owner.get_node_or_null("AttackComponent") as AttackComponentZombieNorm # 部分物种没有啃咬组件。
		if attack != null:
			attack.update_attack_value(value if enabled else 1.0,
				int(String(key).get_slice(":", 1)) as AttackComponentZombieNorm.E_AttackValueFactor)
	else:
		var hp: HpComponentZombie = tier_owner.get_node_or_null("HpComponent") as HpComponentZombie # 绑定可发生在角色 ready 前。
		if hp == null:
			return
		var effect: RefCounted = hp.get(key) as RefCounted # 防御组件自身管理来源叠加。
		if effect != null:
			if key == &"damage_block":
				effect.call("set_source", get_instance_id(), roundi(value) if enabled else 0)
			else:
				effect.call("set_source", get_instance_id(), value if enabled else 0.0)

## 按 [param origin]、[param lane]、[param damage] 和 [param profile] 排队等阶爆炸。
## 真正执行时复核来源资格与关卡身份，沉默或换阶段不会触发迟到的额外伤害。
func queue_tier_explosion(origin: Vector2, lane: int, damage: int, profile: CombatExplosionProfile) -> void:
	var game: MainGameManager = Global.main_game # 捕获攻击发出时所属战场。
	if not tier_can_trigger() or not is_instance_valid(game):
		return
	_detonate_tier_explosion.call_deferred(game, game.curr_game_round,
		AdventureSession.get_active_phase(game.game_para), origin, lane, damage, profile)

## 执行 [param game] 的 [param round_id]、[param phase] 中已排队的等阶爆炸。
## [param origin]、[param lane]、[param damage]、[param profile] 保留原攻击数据。
func _detonate_tier_explosion(game: MainGameManager, round_id: int, phase: StagePhaseDefinition,
		origin: Vector2, lane: int, damage: int, profile: CombatExplosionProfile) -> void:
	if not tier_can_trigger() or not battle_context_active(game, round_id, phase) \
			or not tier_owner.is_inside_tree() or not game.is_ancestor_of(tier_owner):
		return
	CombatExplosion.detonate(game, origin, lane, tier_owner.get_instance_id(),
		tier_owner.is_hypno, damage, profile)

## 检查 [param game]、[param round_id]、[param phase] 的完整战斗身份，允许已确认的亡语脱离死者存活检查。
static func battle_context_active(game: MainGameManager, round_id: int, phase: StagePhaseDefinition) -> bool:
	return is_instance_valid(game) and game.is_inside_tree() and not game.is_queued_for_deletion() \
		and game == Global.main_game and game.get_tree().current_scene == game \
		and game.curr_game_round == round_id and AdventureSession.get_active_phase(game.game_para) == phase \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.GameOver, false) \
		and not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false)

## 让已经确认的亡语在 [param game]、[param round_id]、[param phase] 中安全生成子体。
## [param kind]、[param attrs]、[param origin] 和 [param modifier] 保留原子体策略，不引用即将释放的母体节点。
static func spawn_child_if_current(game: MainGameManager, round_id: int, phase: StagePhaseDefinition,
		kind: CharacterRegistry.ZombieType, attrs: Dictionary, origin: Vector2, modifier: ZombieSpawnModifier) -> void:
	if not battle_context_active(game, round_id, phase) or not is_instance_valid(game.zombie_manager):
		return
	var lane: int = int(attrs.get(Zombie000Base.E_ZInitAttr.Lane, -1)) # 出生行在实际执行时重新校验。
	if lane < 0 or lane >= game.zombie_manager.all_zombie_rows.size():
		return
	game.zombie_manager.create_norm_zombie(kind, game.zombie_manager.all_zombie_rows[lane],
		attrs, origin, Callable(), modifier)
