## 感染保存一次实际击杀时的状态，使用原生僵尸生成入口还原为独立友军。
extends RefCounted
class_name AdventureHypnoClone

## 捕获 [param source] 的血池、伤势、战斗增益与仍在生效的控制时钟。
static func capture(source: Zombie000Base) -> Dictionary:
	var hp := source.hp_component as HpComponentZombie # 实际伤害通过本体及独立防具保留。
	var stages: HpStageChangeComponent = source.hp_stage_change_component # 已发生的掉肢或破甲阶段。
	var attack := source.attack_component as AttackComponentZombieNorm # 特殊攻击者可能没有普通啃咬基数。
	var light := source.get_node_or_null(NodePath(AdventureSunBeanEffect.NODE_NAME)) as AdventureSunBeanEffect # 光能还保留未兑现伤害积分。
	var timers: Dictionary[int, float] = {} # 只保存仍运行的原生游戏秒数，不复制 Timer 引用。
	for kind: int in source.all_timer: # 原生类别决定恢复时的具体行为。
		var timer: Timer = source.all_timer[kind] # 未收到该控制的个体可以没有对应节点。
		if is_instance_valid(timer) and timer.time_left > 0.0:
			timers[kind] = timer.time_left
	var state: Dictionary = { # 保存给延迟生成的克隆，避免依赖原件仍在场。
		"species": source.zombie_type, "scene": source.scene_file_path, "modifier": source.inherited_child_modifier(),
		"position": source.global_position, "lane": source.lane, "terrain": source.curr_zombie_row_type,
		"mini": source.is_mini_zombie, "tint": source.modulate,
		"walk_speed": source.influence_speed_factors.get(Character000Base.E_Influence_Speed_Factor.InitRandomSpeed, 1.0),
		"body": Vector2i(hp.curr_hp, hp.max_hp), "death_hp": hp.death_hp, "minimum_hp": hp.combat_minimum_hp,
		"armor1": Vector2i(hp.curr_hp_armor1, hp.max_hp_armor1),
		"armor2": Vector2i(hp.curr_hp_armor2, hp.max_hp_armor2), "bonus_armor": hp.bonus_armor,
		"fixed_armor_hit": hp.armor1_fixed_damage_per_hit,
		"stages": Vector3i(stages.curr_hp_stage, stages.curr_hp_armor1_stage, stages.curr_hp_armor2_stage),
		"base_attack": attack.init_attack_value_per_min if attack != null else -1,
		"persistent_hp": hp.copy_persistent_health_effects(), "block": hp.damage_block.value,
		"reduction": PackedFloat64Array([hp.damage_reduction.raw_reduction(), hp.armor1_reduction.raw_reduction(), hp.armor2_reduction.raw_reduction()]),
		"timed_buffs": AdventureZombieTimedCombatBuff.capture(source), "deep_cold": AdventureDeepCold.capture(source),
		"timers": timers, "after_freeze": source.time_ice_end_decelerate,
		"light": light.copy_charge() if light != null else Vector2i.ZERO,
	}
	if source is Zombie041RocketImp:
		state[Zombie041RocketImp.SPAWN_ARMOR_OVERRIDE] = source.spawn_armor
	return state

## 从 [param state] 恢复 [param battle] 中的友军及 [param rules]，原件此时可以已死亡。
## [param captured_at] 是实际击杀时的战场调度时间，效果回放扣除等待时间。
static func spawn(state: Dictionary, battle: RepeaterShotContext, rules: Dictionary[String, Dictionary],
		captured_at: float) -> void:
	if not battle.is_active():
		return
	var manager: ZombieManager = battle.game.zombie_manager # 队列到达时再次确认原关卡及原路线。
	var elapsed: float = maxf(0.0, manager.periodic_updates.active_seconds() - captured_at) # 保持已存在效果的到期时间。
	var lane: int = state["lane"] # 使用击杀时的攻防行，已坍塌的行不能创建。
	if not manager.is_lane_open(lane):
		return
	var row: ZombieRow = manager.all_zombie_rows[lane] # 复用同一地形和绘制父节点。
	var position: Vector2 = state["position"] # 冻结的是击杀时的世界脚点。
	var slope: MainGameSlope = battle.game.main_game_slope # ready 自己应用斜坡，预先撤掉它将施加的一次表现偏移。
	if is_instance_valid(slope):
		position -= row.get_global_transform().basis_xform(Vector2(0.0, slope.get_all_slope_y(position.x)))
	var scene: PackedScene = null # 保留原生形态和脚本，各运行时节点均为全新实例。
	var scene_path: String = state["scene"] # 特殊形态可能使用非默认的原生场景。
	if not scene_path.is_empty():
		var prefab: PackedScene = Global.character_registry.get_zombie_info(state["species"],
			CharacterRegistry.ZombieInfoAttribute.ZombieScenes) # 普通形态仍走默认装扮，特殊形态复用自己的场景。
		if scene_path != prefab.resource_path:
			scene = load(scene_path) as PackedScene
	var init_parameters: Dictionary = { # 在等阶结算前恢复复制实例的初始头盔。
		Zombie000Base.E_ZInitAttr.Lane: lane,
		Zombie000Base.E_ZInitAttr.CurrZombieRowType: state["terrain"],
		Zombie000Base.E_ZInitAttr.IsMiniZombie: state["mini"],
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
		Zombie000Base.E_ZInitAttr.StartsHypnotized: true,
	}
	if state.has(Zombie041RocketImp.SPAWN_ARMOR_OVERRIDE):
		init_parameters[Zombie041RocketImp.SPAWN_ARMOR_OVERRIDE] = state[Zombie041RocketImp.SPAWN_ARMOR_OVERRIDE]
	manager.create_norm_zombie(state["species"], row, init_parameters, position,
		_prepare.bind(state, battle, rules, elapsed), state["modifier"], scene)

## 入树后为 [param clone] 设置 [param state] 和 [param rules]，完成初始化才向 [param battle] 发布。
## [param elapsed] 为排队消耗的游戏秒数。
static func _prepare(clone: Zombie000Base, state: Dictionary, battle: RepeaterShotContext,
		rules: Dictionary[String, Dictionary], elapsed: float) -> void:
	clone.signal_character_be_hypno.connect(_restore.bind(clone, state, battle, rules, elapsed), CONNECT_ONE_SHOT)

## 在 [param battle] 中恢复友军 [param clone] 的 [param rules] 及 [param state]。
## 各计时状态扣除 [param elapsed]，相同来源的原件和克隆各自继续结算。
static func _restore(clone: Zombie000Base, state: Dictionary, battle: RepeaterShotContext,
		rules: Dictionary[String, Dictionary], elapsed: float) -> void:
	var hp := clone.hp_component as HpComponentZombie # 角色已完成就绪，可同步更新真实血量组件和表现。
	var body: Vector2i = state["body"] # x 是原本体当前血量，y 是上限。
	var armor1: Vector2i = state["armor1"] # 一类防具的当前值和上限。
	var armor2: Vector2i = state["armor2"] # 二类防具的当前值和上限。
	hp.max_hp = body.y
	hp.death_hp = state["death_hp"]
	hp.combat_minimum_hp = state["minimum_hp"]
	hp.curr_hp = body.x
	hp.max_hp_armor1 = armor1.y
	hp.max_hp_armor2 = armor2.y
	if hp.curr_hp_armor1 != armor1.x:
		hp.curr_hp_armor1 = armor1.x
	if hp.curr_hp_armor2 != armor2.x:
		hp.curr_hp_armor2 = armor2.x
	hp.armor1_fixed_damage_per_hit = state["fixed_armor_hit"]
	hp.grant_bonus_armor(int(state["bonus_armor"]))
	clone.hp_stage_change_component.restore_body_stages(state["stages"])
	clone.modulate = state["tint"]
	clone.update_speed_factor(float(state["walk_speed"]), Character000Base.E_Influence_Speed_Factor.InitRandomSpeed)
	var attack := clone.attack_component as AttackComponentZombieNorm # 普通啃咬使用已结算过等阶的攻击基数。
	if attack != null and int(state["base_attack"]) >= 0:
		attack.restore_base_attack(int(state["base_attack"]))
	hp.restore_persistent_health_effects(state["persistent_hp"])
	var reductions: PackedFloat64Array = state["reduction"] # 顺序为本体、一类防具、二类防具。
	hp.damage_block.set_source(clone.get_instance_id(), int(state["block"]))
	hp.damage_reduction.set_source(clone.get_instance_id(), reductions[0])
	hp.armor1_reduction.set_source(clone.get_instance_id(), reductions[1])
	hp.armor2_reduction.set_source(clone.get_instance_id(), reductions[2])
	var light: Vector2i = state["light"] # x 为层数，y 为尚未兑现的加权伤害积分。
	if light.x > 0:
		AdventureSunBeanEffect.apply_to(clone, true, light.x, light.y)
	AdventureZombieTimedCombatBuff.restore(clone, state["timed_buffs"], elapsed)
	AdventureDeepCold.restore(clone, state["deep_cold"], elapsed)
	_restore_controls(clone, state["timers"], float(state["after_freeze"]), float(state["deep_cold"].get("freeze", 0.0)), elapsed)
	AdventureHypnoAlly.install(clone, battle, rules, true)

## 为 [param clone] 恢复 [param timers] 的原生控制，扣除排队已经经过的 [param elapsed] 秒。
## [param after_freeze] 与 [param deep_freeze] 确定排队期间解冻后仍生效的减速及冻结值保护。
static func _restore_controls(clone: Zombie000Base, timers: Dictionary, after_freeze: float,
		deep_freeze: float, elapsed: float) -> void:
	var types := Character000Base.E_TimerType # 依原生计时器种类重建到期回调。
	var freeze: float = timers.get(types.IceFreeze, 0.0) # 冻结可能在等待入场时自然到期。
	var slow: float = float(timers.get(types.IceDecelerate, 0.0)) - elapsed # 已生效减速由旧时钟继续扣除。
	var recovery: float = float(timers.get(types.IceChargeRecovery, 0.0)) - elapsed # 解冻保护时钟也随战场推进。
	if freeze > 0.0 and freeze <= elapsed:
		slow = maxf(slow, freeze + after_freeze - elapsed)
	var last_thaw: float = maxf(freeze, deep_freeze) # 原生冻结和深寒都结束之后才开始保护期。
	if last_thaw > 0.0 and last_thaw <= elapsed:
		recovery = maxf(recovery, last_thaw + Character000Base.ICE_CHARGE_RECOVERY_SECONDS - elapsed)
	clone.be_ice_decelerate(slow)
	clone.apply_ice_freeze_control(freeze - elapsed, after_freeze)
	var butter: float = float(timers.get(types.Butter, 0.0)) - elapsed # 过期黄油不重新挂到头部。
	if butter > 0.0:
		clone.be_butter(butter)
	clone.be_stunned(float(timers.get(types.Stun, 0.0)) - elapsed)
	clone.restore_ice_charge_recovery(recovery)
