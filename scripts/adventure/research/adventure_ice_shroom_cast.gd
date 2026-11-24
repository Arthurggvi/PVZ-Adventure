## 原生引信触发的一次寒冰菇转职结算；母株死亡不影响已经施放的技能。
extends RefCounted
class_name AdventureIceShroomCast

## 全场寒冷涵盖原生普通僵尸的六种受击位，物种免疫仍逐目标检查。
const ALL_ZOMBIE_STATUSES: int = 63
## 本次施法的战场、棋盘、轮次及阶段身份。
var _battle: RepeaterShotContext
## 转职规则按事件键索引，参数沿用研究目录。
var _rules: Dictionary[String, Dictionary] = {}
## 计入转职加成后的本次冻结时长，单位为游戏秒。
var _freeze_seconds: float
## 原生冻结时长，供普通冻结被折为减速时使用，单位为游戏秒。
var _base_freeze_seconds: float
## 解冻后的减速时长，单位为游戏秒。
var _slow_seconds: float
## 本次已处理的普通僵尸实例 ID，行名单变动不会重复结算。
var _visited: Dictionary[int, bool] = {}
## 实际受到本次完全冻结的唯一普通僵尸数量。
var _frozen_count: int = 0

## 为 [param plant] 的 [param uid] 按 [param events] 结算；[param freeze_seconds] 和
## [param slow_seconds] 为原生冻结和后续减速秒数。无正式战场时返回 false，让引信沿用原生事件。
static func try_cast(plant: Plant015IceShroom, uid: String, events: Array[Dictionary],
		freeze_seconds: float, slow_seconds: float) -> bool:
	var game: MainGameManager = Global.main_game # 当前施放只能影响实际所属战场。
	if not is_instance_valid(plant) or not is_instance_valid(game) or not game.is_ancestor_of(plant):
		return false
	var cast := AdventureIceShroomCast.new() # 每次引爆独立记录来源及受击身份。
	# 亡语可能在植株标记死亡后引爆，从战场直接冻结身份。
	cast._battle = RepeaterShotContext.new()
	cast._battle.game = game
	cast._battle.board = game.board
	cast._battle.round_index = game.curr_game_round
	cast._battle.phase = AdventureSession.get_active_phase(game.game_para)
	if not cast._battle.is_active():
		return false
	for event: Dictionary in events: # 出生时已经校验的单株事件。
		cast._rules[String(event.kind)] = event
	var extension: float = float(cast._rules.get("ice_shroom_deep_cold", {}).get("extra_seconds", 0.0)) # 深寒将两个阶段各延长。
	cast._base_freeze_seconds = freeze_seconds
	cast._freeze_seconds = freeze_seconds + extension
	cast._slow_seconds = slow_seconds + extension
	if not cast._rules.has("ice_shroom_deep_cold"):
		cast._freeze_seconds += float(cast._rules.get("ice_shroom_quick_freeze", {}).get("extra_freeze_seconds", 0.0))
	cast._detonate(uid, plant.get_instance_id())
	return true

## 用 [param uid] 结算卡牌，并以本株 [param source_id] 标记独立的限时效果。
func _detonate(uid: String, source_id: int) -> void:
	var manager: ZombieManager = _battle.game.zombie_manager # 复用设施、珊瑚及僵王所在的原生入口。
	if _rules.has("ice_shroom_world"):
		AdventureIceShroomWorld.start(_battle, manager.zombie_wave_manager, source_id, _freeze_seconds)
	if _rules.has("ice_shroom_dynasty"):
		var dynasty: Dictionary = _rules["ice_shroom_dynasty"] # 以施放时的友军阵容结算，末击也能完成治疗。
		AdventureIceShroomDynasty.apply_to_board(_battle, source_id, _freeze_seconds,
			float(dynasty.heal_fraction), float(dynasty.attack_rate_multiplier))
	manager.resolve_ice_blast(_freeze_seconds, _slow_seconds, _freeze_zombie)
	EventBus.push_event("ice_shroom_dispel_fireballs", [])
	if _battle.is_same_battle():
		_reward_cards(uid)

## 对 [param zombie] 结算一次原生冻伤和合法控制，只有实际完全冻结才计入奖励。
func _freeze_zombie(zombie: Zombie000Base) -> void:
	if not _battle.is_active() or not _is_battle_target(zombie):
		return
	var identity: int = zombie.get_instance_id() # 一次施放内同一目标只能结算一次。
	if _visited.has(identity):
		return
	_visited[identity] = true
	if _is_legal_target(zombie):
		var can_freeze: bool = zombie.can_cold_freeze() # 气球与持杆跳跳仅接受减速。
		var freeze_factor := Character000Base.E_Influence_Speed_Factor.IceFreezeSpeed # 区分本次原生与深寒冻结。
		if _rules.has("ice_shroom_deep_cold"):
			freeze_factor = Character000Base.E_Influence_Speed_Factor.DeepColdFreeze
			if can_freeze:
				zombie.hp_component.Hp_loss(20, BulletRegistry.AttackMode.Real, true, false)
			if _is_legal_target(zombie):
				# 仅复用抗火寒冷状态；解冻后的特殊减速仍占满原生减速阶段。
				AdventureDeepCold.apply_to(zombie, _battle, _freeze_seconds + _slow_seconds,
					_freeze_seconds, ALL_ZOMBIE_STATUSES)
		else:
			# 只接受减速的僵尸会合并两个阶段，按原生时长结算。
			var target_freeze_seconds: float = _freeze_seconds if can_freeze else _base_freeze_seconds
			zombie.be_ice_freeze(target_freeze_seconds, _slow_seconds)
		if _is_legal_target(zombie) and can_freeze and zombie.can_cold_freeze() \
				and zombie.influence_speed_factors.get(freeze_factor, 1.0) == 0.0:
			_frozen_count += 1
	# 冻原的生命损失不依赖寒冷免疫；非Boss仍须满足原战斗的受击资格。
	if _battle.is_active() and _is_battle_target(zombie) and _rules.has("ice_shroom_tundra"):
		_apply_tundra(zombie)

## 判断 [param zombie] 是否仍为本战局可受击的普通敌方僵尸，独立于寒冷免疫。
func _is_battle_target(zombie: Zombie000Base) -> bool:
	return is_instance_valid(zombie) and not zombie.is_death and not zombie.is_queued_for_deletion() \
		and zombie.is_inside_tree() and _battle.game.is_ancestor_of(zombie) and not zombie.is_hypno \
		and zombie.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and is_instance_valid(zombie.hurt_box_component) and zombie.hurt_box_component.is_enabling

## 只有允许寒冷状态的 [param zombie] 才能进入冻结和对应奖励结算。
func _is_legal_target(zombie: Zombie000Base) -> bool:
	return _is_battle_target(zombie) and zombie.can_receive_negative_effects() and zombie.can_receive_cold()

## 对仍合法的 [param zombie] 以本体最大生命计算附伤，沿用真实伤害、无敌和死亡阈值。
func _apply_tundra(zombie: Zombie000Base) -> void:
	var rule: Dictionary = _rules["ice_shroom_tundra"] # 附伤和脆弱来自同一本书。
	var hp: HpComponentZombie = zombie.hp_component as HpComponentZombie # 使用本体上限，不含护甲。
	var damage: int = roundi(float(hp.max_hp) * float(rule.max_health_fraction)) # 生命组件按整数扣血。
	hp.apply_hit(damage, BulletRegistry.AttackMode.Real, true, false)
	AdventurePlantNegativeEffects.apply(zombie, AdventurePlantNegativeEffects.Kind.BRITTLENESS,
		0, float(rule.brittleness))

## 汇总一次冻结计数，按 [param uid] 找到原始卡；回声只影响其他实卡的剩余冷却。
func _reward_cards(uid: String) -> void:
	if not is_instance_valid(_battle.game.card_manager):
		return
	var slots: CardSlotBattle = _battle.game.card_manager.card_slot_battle # 当前战场的真实出战卡槽。
	if not is_instance_valid(slots):
		return
	var source: Card = slots.find_plant_card_by_uid(uid) # 同物种其他卡不能代领原卡的奖励。
	if _frozen_count > 0:
		if is_instance_valid(source) and _rules.has("ice_shroom_regeneration"):
			source.adventure_multiply_remaining_cooldown(pow(1.0 - float(_rules["ice_shroom_regeneration"].fraction), _frozen_count))
		if _rules.has("ice_shroom_quick_freeze"):
			slots.sun_value += _frozen_count * int(_rules["ice_shroom_quick_freeze"].sun_per_target)
	if _rules.has("ice_shroom_echo"):
		var multiplier: float = float(_rules["ice_shroom_echo"].remaining_multiplier) # 保留基础冷却和可用卡状态。
		for card: Card in slots.curr_cards: # 仅当前出战的其他独立卡。
			if is_instance_valid(card) and not card.is_queued_for_deletion() and card != source \
					and card.card_context == Card.CardContext.Battle:
				card.adventure_multiply_remaining_cooldown(multiplier)
