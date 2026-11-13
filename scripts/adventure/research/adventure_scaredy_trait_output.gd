## 单个受益者的词条输出；所有共生来源合成后只向原生组件登记一个身份。
extends RefCounted
class_name AdventureScaredyTraitOutput

## 植物使用弱引用，退出清理可继续持有本输出而不延长植物生命周期。
var _plant_ref: WeakRef
## 所属战场在换轮后仍使用同一实体；每颗攻击再冻结当时轮次。
var _game: MainGameManager
## 对睡眠、攻速、免恐惧和卡费统一使用本目标控制器的来源身份。
var _source_id: int = 0
## 当前已经去重的规则，供发射时捕获伤害上下文。
var _rules: Dictionary = {}
## 卡费独立链接负责真实UID匹配、延后生效及离场回收。
var _card_discount: AdventureMushroomCardDiscount

## 绑定受益 [param plant]、所属 [param game] 与唯一输出 [param source_id]。
func configure(plant: Plant000Base, game: MainGameManager, source_id: int) -> void:
	_plant_ref = weakref(plant)
	_game = game
	_source_id = source_id
	_card_discount = AdventureMushroomCardDiscount.new()
	_card_discount.configure(plant, source_id)

## 将合成后的 [param rules] 输出一次；[param shared_cost] 只代表临时共享减费。
func apply(rules: Dictionary, shared_cost: bool) -> void:
	_rules = rules.duplicate(true)
	var plant: Plant000Base = _plant_ref.get_ref() as Plant000Base # 已释放植物仅需撤回卡片贡献。
	if not is_instance_valid(plant):
		_card_discount.clear()
		return
	if is_instance_valid(plant.sleep_component):
		plant.sleep_component.set_awake_source(_source_id, _rules.has("scaredy_day_awake"))
	var scaredy: ScaredyComponent = plant.get_node_or_null(^"ScaredyComponent") as ScaredyComponent # 其他蘑菇没有原生恐惧。
	if scaredy != null:
		scaredy.set_fearless_source(_source_id, _rules.has("scaredy_close_damage"))
	var attack_bonus: float = _attack_bonus(plant) # 固定攻速与当前目标自身群落加算，不加速成长或产光。
	var attack: AttackComponentBulletBase = plant.get_node_or_null(^"AttackComponent") as AttackComponentBulletBase # 射击与忧郁菇共用发射时钟。
	if attack != null:
		attack.set_attack_rate_source(_source_id, attack_bonus)
	var magnet: MagnetComponent = plant.get_node_or_null(^"MagnetComponent") as MagnetComponent # 吸铁是攻击；金磁收钱不走此组件。
	if magnet != null:
		magnet.set_attack_rate_source(_source_id, attack_bonus)
	var provider: Callable = capture_attack_context # 相同目标只有本输出提供去重后的攻击规则。
	if _rules.has("scaredy_close_damage") or _rules.has("scaredy_armor_damage") or _rules.has("scaredy_solar"):
		plant.battle_attack_context_provider = provider
	elif plant.battle_attack_context_provider == provider:
		plant.battle_attack_context_provider = Callable()
	_card_discount.set_enabled(shared_cost)

## 撤销本输出，保留其他睡眠来源、角色速度以及原有永久卡费。
func clear() -> void:
	apply({}, false)
	_card_discount.clear()

## 发射时保存当前合成规则；已发弹体不依赖母株继续存活。
func capture_attack_context() -> PlantAttackContext:
	var plant: Plant000Base = _plant_ref.get_ref() as Plant000Base # 无效化或真正离场不能产生新攻击修饰。
	if not MushroomPlantQuery.is_active(plant, _game):
		return null
	var armor: Dictionary = _rules.get("scaredy_armor_damage", {}) # 防具倍率只交给原生防具分层结算。
	return PlantAttackContext.capture(plant, _rules.has("scaredy_close_damage"),
		maxf(1.0, float(armor.get("multiplier", 1.0))), _rules.has("scaredy_solar"))

## 在受益 [param plant] 自己的位置计算群落，不使用共生来源已经算好的射速。
func _attack_bonus(plant: Plant000Base) -> float:
	var fixed: Dictionary = _rules.get("scaredy_attack_rate", {}) # 固定攻速不修改角色整体速度。
	var colony: Dictionary = _rules.get("scaredy_colony", {}) # 同一种蘑菇仅计一次，中心格计入。
	var bonus: float = maxf(0.0, float(fixed.get("bonus", 0.0))) # 两个不同词条按攻击基础速度加算。
	if not colony.is_empty():
		bonus += maxf(0.0, float(colony.get("per_species", 0.0))) * MushroomPlantQuery.species_count(plant, _game)
	return bonus
