## 咖啡豆的冻结规则与目标资格；预览、放置复核和实际施效共用同一入口。
extends RefCounted
class_name AdventureCoffeePromotionRules

## 仅接受目录已经验证的咖啡机制，其他物种事件不进入工具作用计划。
const KINDS: Array[String] = ["coffee_area", "coffee_solar", "coffee_haste",
	"coffee_damage", "coffee_armor", "coffee_revive"]

## 从 [param snapshot] 读取合法已选转职；无快照或其他物种返回原生空规则。
static func from_snapshot(snapshot: Dictionary) -> Dictionary:
	var rules: Dictionary = {} # 使用效果族去重，数据不与卡牌或目录共享可写引用。
	if int(snapshot.get("plant_type", 0)) != CharacterRegistry.PlantType.P036CoffeeBean:
		return rules
	var record: PlantCardInstance = PlantCardInstance.from_dict(snapshot) # 原有目录负责连续阶数与物种校验。
	if record == null:
		return rules
	for event: Dictionary in AdventurePromotionCatalog.effects(record).events: # 保留每项机制的完整冻结参数。
		var kind: String = str(event.get("kind", "")) # 只允许明确列出的咖啡作用族。
		if KINDS.has(kind):
			rules[kind] = event.duplicate(true)
	return rules

## 读取 [param profile] 的独立快照；普通模式没有配方时仍使用原生咖啡资格。
static func from_profile(profile: PlantSpawnProfile) -> Dictionary:
	return {} if profile == null else from_snapshot(profile.snapshot())

## 为 [param snapshot] 复制 [param base_condition] 的咖啡条件，不修改全局共享资源。
static func condition_for(snapshot: Dictionary, base_condition: ResourcePlantCondition) -> ResourcePlantCondition:
	if int(snapshot.get("plant_type", 0)) != CharacterRegistry.PlantType.P036CoffeeBean:
		return base_condition
	if not base_condition is ResourcePlantConditionCoffeeBean:
		return base_condition
	var condition: ResourcePlantConditionCoffeeBean = base_condition.duplicate() as ResourcePlantConditionCoffeeBean # 每张出战卡独立持有规则。
	condition.coffee_rules = from_snapshot(snapshot)
	return condition

## 返回 [param target] 实际拥有的生产组件；不按物种白名单猜测生产能力。
static func producer(target: Plant000Base) -> CreateSunComponent:
	return target.get_node_or_null(^"CreateSunComponent") as CreateSunComponent

## [param target] 的合法对象范围为蘑菇；[param rules] 中光能亲和额外开放生产植物。
static func accepts_target(target: Plant000Base, rules: Dictionary) -> bool:
	return is_instance_valid(target) and (MushroomPlantQuery.is_mushroom(target)
		or (rules.has("coffee_solar") and producer(target) != null))

## 判断当前清醒的 [param target] 是否至少有一项来自 [param rules] 的有效作用。
## 已有永久产值加成不会单独消耗咖啡；强效阵痛不会额外开放普通植物资格。
static func has_target_effect(target: Plant000Base, rules: Dictionary) -> bool:
	if not accepts_target(target, rules) or target.hp_component == null or target.hp_component.curr_hp <= 0:
		return false
	if target.is_sleeping:
		return true
	if rules.has("coffee_haste") or rules.has("coffee_damage") or rules.has("coffee_armor"):
		return true
	var sun: CreateSunComponent = producer(target) # 生产者已有加成时，仍可由其他技能提供合法作用理由。
	var solar: Dictionary = rules.get("coffee_solar", {}) # 不存在该分支时不扩大生产目标资格。
	return sun != null and not solar.is_empty() \
		and sun.coffee_solar_bonus < maxf(0.0, float(solar.get("bonus", 0.0)))
