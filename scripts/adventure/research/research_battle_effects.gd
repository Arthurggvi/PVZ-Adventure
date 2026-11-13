## Apply promotion and star-growth effects to frozen battle card snapshots.
## Ordinary modes have no snapshot and keep all original combat values.
extends PlantSpawnModifier
class_name AdventureResearchBattleEffects

const Promotions = preload("res://scripts/adventure/research/research_promotion_catalog.gd")
const Growth = preload("res://scripts/adventure/adventure_plant_growth_catalog.gd")
## 卡片与已种植植物共用的星级图案和特效。
const StarBadge = preload("res://scripts/adventure/ui/star_badge_view.gd")
## 根部角标相对卡片角标的尺寸倍率。
const ROOT_BADGE_SCALE: float = 0.72

static func _record(snapshot: Dictionary) -> PlantCardInstance:
	if snapshot.is_empty():
		return null
	return PlantCardInstance.from_dict(snapshot)

static func _stats(record: PlantCardInstance) -> Dictionary:
	var result: Dictionary = Promotions.effects(record).stats
	var from_stars: Dictionary = Growth.modifiers(record.stars)
	for stat: String in from_stars:
		var addition: Dictionary = from_stars[stat]
		var entry: Dictionary = result.get(stat, {"flat": 0.0, "percent": 0.0})
		entry.flat += float(addition.get("flat", 0.0))
		entry.percent += float(addition.get("percent", 0.0))
		result[stat] = entry
	return result

func card_stats(snapshot: Dictionary, base_sun_cost: int, base_cooldown: float) -> Dictionary:
	var record := _record(snapshot)
	if record == null:
		return {}
	var modifiers: Dictionary = _stats(record)
	return {
		"sun_cost": roundi(Promotions.resolve_stat(float(base_sun_cost),
			modifiers.get("sun_cost", {}))),
		"cooldown": Promotions.resolve_stat(base_cooldown,
			modifiers.get("cooldown", {}))
	}

func apply(plant: Plant000Base, snapshot: Dictionary) -> bool:
	var record := _record(snapshot)
	if record == null:
		return false
	var modifiers: Dictionary = _stats(record)
	if modifiers.has("damage"):
		plant.set_battle_card_damage_multiplier(maxf(0.0, 1.0 + float(modifiers.damage.get("percent", 0.0))))
	# 原有角色速度信号同时驱动发射计时与动画，转职攻速共用此入口。
	if modifiers.has("attack_rate"):
		var rate: float = maxf(0.0, 1.0 + float(modifiers.attack_rate.get("percent", 0.0)))
		plant.update_speed_factor(rate, Character000Base.E_Influence_Speed_Factor.AdventurePromotionAttackRate)
	if modifiers.has("max_health"):
		var health: HpComponent = plant.get_node_or_null("HpComponent") as HpComponent
		if health == null:
			push_error("Adventure plant has no HpComponent")
			return false
		var new_max: int = maxi(1, roundi(Promotions.resolve_stat(
			float(health.max_hp), modifiers.max_health)))
		var stages: HpStageChangeComponent = plant.get_node_or_null(
			"HpStageChangeComponent") as HpStageChangeComponent
		if stages != null:
			stages.set_spawn_max_health(new_max)
		else:
			health.set_spawn_max_health(new_max)
	_attach_root_badge(plant, record.stars)
	# 静态转职和运行时事件统一来自已验证的冻结卡片快照。
	var resolved: Dictionary = Promotions.effects(record)
	var wallnut_events: Array[Dictionary] = []
	var potato_events: Array[Dictionary] = []
	var cherry_events: Array[Dictionary] = [] # 交给樱桃炸弹本身冻结，等原版引信结算。
	var puff_events: Array[Dictionary] = [] # 孢子的射击与命中能力按单株冻结。
	var sunshroom_events: Array[Dictionary] = [] # 阳光菇的成长、光环与储蓄按实际植株执行。
	for event: Dictionary in resolved.events:
		match str(event.get("kind", "")):
			"negative_effect_immunity":
				plant.battle_negative_effect_immune = true
			"puff_day_awake", "sunshroom_day_awake":
				# 出生修饰发生在入树前，耐日技能从一开始就不进入睡眠状态。
				plant.is_sleep_in_day = false
			"wallnut_hit_cap":
				var hp: HpComponentPlant = plant.get_node_or_null("HpComponent") as HpComponentPlant
				if hp == null:
					push_error("单次受伤上限需要植物专用生命组件")
					return false
				hp.max_single_hit_fraction = float(event.get("fraction", 0.0))
			_:
				var kind: String = str(event.get("kind", ""))
				if kind.begins_with("wallnut_"):
					wallnut_events.append(event)
				elif kind.begins_with("potato_"):
					potato_events.append(event)
				elif kind.begins_with("cherry_"):
					cherry_events.append(event)
				elif kind.begins_with("puff_"):
					puff_events.append(event)
				elif kind.begins_with("sunshroom_"):
					sunshroom_events.append(event)
	if not sunshroom_events.is_empty():
		if not plant is Plant010SunShroom:
			push_error("阳光菇转职事件需要对应的战斗植物")
			return false
		var sunshroom_controller := AdventureSunShroomPromotionEffects.new() # 成长事件与实际生产共用单株生命周期。
		sunshroom_controller.configure(plant as Plant010SunShroom, sunshroom_events)
		plant.add_child(sunshroom_controller)
	if not puff_events.is_empty():
		if not plant is Plant009Puff:
			push_error("小喷菇转职事件需要对应的战斗植物")
			return false
		var puff_controller := AdventurePuffPromotionEffects.new() # 随植株管理发射，弹体单独保存命中规则。
		puff_controller.configure(plant, puff_events)
		plant.add_child(puff_controller)
	if not cherry_events.is_empty():
		var cherry: Plant003CherryBomb = plant as Plant003CherryBomb # 仅真实樱桃可接管原版爆炸。
		if cherry == null:
			push_error("樱桃炸弹转职事件需要对应的战斗植物")
			return false
		cherry.configure_promotions(record.uid, cherry_events)
	if not potato_events.is_empty():
		var mine: Plant005PotatoMine = plant as Plant005PotatoMine
		if mine == null:
			push_error("土豆地雷转职事件只能挂在原版地雷植物上")
			return false
		var potato_controller := AdventurePotatoPromotionEffects.new()
		potato_controller.configure(mine, potato_events)
		mine.add_child(potato_controller)
	if not wallnut_events.is_empty():
		var controller := AdventureWallnutPromotionEffects.new()
		controller.configure(plant, wallnut_events)
		plant.add_child(controller)
	var component: CreateSunComponent = plant.get_node_or_null("CreateSunComponent")
	if component == null:
		return true
	# Only subsequent production intervals change; first sun, sun amount, cost
	# and card cooldown are untouched. Ten-star growth is capped at +15%.
	if modifiers.has("sun_production_rate"):
		var bonus: float = clampf(float(modifiers.sun_production_rate.get("percent", 0.0)), 0.0, 0.15)
		component.create_time_range_other /= 1.0 + bonus
	if plant is Plant010SunShroom:
		var sunshroom := plant as Plant010SunShroom # 两个生长阶段保留各自加成后的基础产值。
		sunshroom.time_grow = Promotions.resolve_stat(sunshroom.time_grow, modifiers.get("growth_time", {}))
		if modifiers.has("sun_value"):
			sunshroom.mini_sun_value = roundi(Promotions.resolve_stat(float(sunshroom.mini_sun_value), modifiers.sun_value))
			sunshroom.norm_sun_value = roundi(Promotions.resolve_stat(float(sunshroom.norm_sun_value), modifiers.sun_value))
	elif modifiers.has("sun_value"):
		component.change_sun_value(roundi(Promotions.resolve_stat(
			float(component.sun_value), modifiers.sun_value)))
	for event: Dictionary in resolved.events:
		match str(event.get("kind", "")):
			"sun_production":
				component.extra_small_sun_min += int(event.get("extra_small_sun_min", 0))
				component.extra_small_sun_max += int(event.get("extra_small_sun_max", 0))
			"sun_growth":
				component.production_growth_step = maxi(0, int(event.get("step", 0)))
				component.production_growth_cap = maxi(0, int(event.get("cap", 0)))
			"on_death":
				var reward: int = int(event.get("drop_sun", 0))
				if reward > 0:
					plant.signal_character_death.connect(
						func(): component.spawn_specific_sun(reward), CONNECT_ONE_SHOT)
	return true

## 主格种植成功后处理 [param cell] 的扩种能力；[param profile] 是本次冻结卡牌资料。
## 自动生成与恢复不会进入玩家提交钩子，额外植株不重复结算卡片费用或冷却。
func player_placement_committed(cell: PlantCell, profile: PlantSpawnProfile) -> void:
	AdventurePuffPropagation.expand_player_placement(cell, profile)

## 为入树前的出战植物 [param plant] 挂载 [param rank] 星角标；零星无需显示。
func _attach_root_badge(plant: Plant000Base, rank: int) -> void:
	if rank <= 0 or plant.character_init_type != Character000Base.E_CharacterInitType.IsNorm:
		return
	var shadow: Sprite2D = plant.get_node_or_null(^"Shadow") as Sprite2D # 阴影中心也适用于跨格植物。
	var root_position: Vector2 = shadow.position if shadow != null else Vector2.ZERO # 缺少阴影时用种植原点。
	var badge: Control = StarBadge.new() # 作为植物根节点的子控件，随植株移动，独立于身体动画。
	plant.add_child(badge)
	badge.configure(rank)
	badge.pivot_offset = badge.size * 0.5
	badge.position = root_position - badge.pivot_offset
	badge.scale = Vector2(ROOT_BADGE_SCALE * plant.direction_x_root, ROOT_BADGE_SCALE)
	plant.signal_direction_x_root_update.connect(func(direction: int) -> void: # 抵消根节点的水平翻转，保持数字可读。
		badge.scale.x = ROOT_BADGE_SCALE * direction
	)
	plant.signal_character_death.connect(badge.hide, CONNECT_ONE_SHOT)
