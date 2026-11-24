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
## 卡牌链接负责真实UID匹配、延后生效及费用和冷却的离场回收。
var _card_discount: AdventureMushroomCardDiscount

## 绑定受益 [param plant]、所属 [param game] 与唯一输出 [param source_id]。
func configure(plant: Plant000Base, game: MainGameManager, source_id: int) -> void:
	_plant_ref = weakref(plant)
	_game = game
	_source_id = source_id
	_card_discount = AdventureMushroomCardDiscount.new()
	_card_discount.configure(plant, source_id)

## 将合成后的 [param rules] 输出一次；[param native_rules] 中的卡牌数值已应用在冻结配方中。
func apply(rules: Dictionary, native_rules: Dictionary) -> void:
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
		_refresh_scatter(attack)
	var magnet: MagnetComponent = plant.get_node_or_null(^"MagnetComponent") as MagnetComponent # 吸铁是攻击；金磁收钱不走此组件。
	if magnet != null:
		magnet.set_attack_rate_source(_source_id, attack_bonus)
	var provider: Callable = capture_attack_context # 相同目标只有本输出提供去重后的攻击规则。
	var fission: Dictionary = _rules.get("scaredy_attack_rate", {}) # 菌核裂变提供独立的带防具目标增伤。
	if _rules.has("scaredy_close_damage") or _rules.has("scaredy_armor_damage") or _rules.has("scaredy_solar") \
			or fission.has("armored_target_multiplier"):
		plant.battle_attack_context_provider = provider
	elif plant.battle_attack_context_provider == provider:
		plant.battle_attack_context_provider = Callable()
	var decay: Dictionary = _rules.get("scaredy_cost", {}) # 腐能利用的阳光减免。
	var day: Dictionary = _rules.get("scaredy_day_awake", {}) # 白昼耐性的冷却减免。
	_card_discount.set_modifiers(0 if native_rules.has("scaredy_cost") else int(decay.get("discount", 0)),
		0.0 if native_rules.has("scaredy_day_awake") else float(day.get("cooldown_reduction", 0.0)))

## 撤销本输出，保留其他睡眠来源、角色速度以及卡片冻结数值。
func clear() -> void:
	apply({}, {})
	_card_discount.clear()

## 发射时保存当前合成规则；已发弹体不依赖母株继续存活。
func capture_attack_context() -> PlantAttackContext:
	var plant: Plant000Base = _plant_ref.get_ref() as Plant000Base # 无效化或真正离场不能产生新攻击修饰。
	if not MushroomPlantQuery.is_active(plant, _game):
		return null
	var armor: Dictionary = _rules.get("scaredy_armor_damage", {}) # 防具倍率只交给原生防具分层结算。
	var fission: Dictionary = _rules.get("scaredy_attack_rate", {}) # 命中时按目标是否仍有防具判定菌核裂变。
	return PlantAttackContext.capture(plant, _rules.has("scaredy_close_damage"),
		float(armor.get("multiplier", 1.0)), _rules.has("scaredy_solar"),
		float(fission.get("armored_target_multiplier", 1.0)))

## 在受益 [param plant] 自己的位置计算群落，不使用共生来源已经算好的射速。
func _attack_bonus(plant: Plant000Base) -> float:
	var fixed: Dictionary = _rules.get("scaredy_attack_rate", {}) # 固定攻速不修改角色整体速度。
	var decay: Dictionary = _rules.get("scaredy_cost", {}) # 腐能利用与菌核裂变是不同阶的攻速来源。
	var colony: Dictionary = _rules.get("scaredy_colony", {}) # 同一种蘑菇仅计一次，中心格计入。
	var bonus: float = float(fixed.get("bonus", 0.0)) # 不同词条按攻击基础速度加算。
	if decay.has("attack_rate_bonus") and not (plant is Plant011FumeShroom and plant.plant_spawn_profile != null \
			and plant.plant_spawn_profile.snapshot().get("promotion_1") == "promotion_fume_decay_energy"):
		bonus += float(decay["attack_rate_bonus"])
	if not colony.is_empty():
		bonus += maxf(0.0, float(colony.get("per_species", 0.0))) * MushroomPlantQuery.species_count(plant, _game)
	return bonus

## 腐食渴望存在期间监听 [param attack] 的每次原生射击；重复刷新只保留一次连接。
func _refresh_scatter(attack: AttackComponentBulletBase) -> void:
	var shot: Callable = _fire_scatter.bind(attack) # 只监听当前受益株的实际发射组件。
	var equipped: bool = _rules.get("scaredy_close_damage", {}).has("count_max") # 该词条配置了散射弹数才启用。
	if equipped == attack.signal_shoot_bullet.is_connected(shot):
		return
	if equipped:
		attack.signal_shoot_bullet.connect(shot)
	else:
		attack.signal_shoot_bullet.disconnect(shot)

## 从 [param attack] 的原弹口追加一轮胆小菇子弹；随机方向可跨行碰撞，不重新发射或播放音效。
func _fire_scatter(attack: AttackComponentBulletBase) -> void:
	var rule: Dictionary = _rules.get("scaredy_close_damage", {}) # 原生发射开始后也可能同步撤销共生。
	var plant: Plant000Base = _plant_ref.get_ref() as Plant000Base # 已离场来源不能生成新散射。
	if not rule.has("count_max") or not MushroomPlantQuery.is_active(plant, _game) or plant.is_cold_frozen() \
			or not attack.is_enabling or not attack.is_attack_res \
			or not is_instance_valid(attack.bullets) or attack.bullets.is_queued_for_deletion() \
			or attack.markers_2d_bullet.is_empty() or attack.detect_component.ray_area_direction.is_empty():
		return
	var marker: Marker2D = attack.markers_2d_bullet[0] # 使用原生弹口，正中央的原发仍由组件负责。
	if not is_instance_valid(marker):
		return
	var forward: Vector2 = attack.detect_component.ray_area_direction[0].normalized() # 发射方向即扇形中心线。
	var parameters: Dictionary[Bullet000NormBase.E_InitParasAttr, Variant] = attack.get_bullet_paras(marker.global_position, forward) # 同一轮额外弹共享冻结来源。
	var context: PlantAttackContext = parameters[Bullet000NormBase.E_InitParasAttr.AttackContext] # 腐食渴望的上下文同时提供战场门禁。
	if context == null or not context.is_active():
		return
	parameters[Bullet000NormBase.E_InitParasAttr.IsActivateLane] = false
	var count: int = randi_range(int(rule["count_min"]), int(rule["count_max"])) # 额外弹数包含两端。
	var half_angle: float = deg_to_rad(float(rule["spread_degrees"])) * 0.5 # 总扇角对称分布在原弹道两侧。
	var scene: PackedScene = Global.bullet_registry.get_bullet_scenes(BulletRegistry.BulletType.Bullet005PuffLongTime) # 复用胆小菇原生弹体。
	for _index: int in range(count): # 每发额外弹独立在扇形内抽取角度及结算命中。
		var bullet: Bullet000NormBase = scene.instantiate() as Bullet000NormBase # 标准孢子弹，不继承受益植株的发射回调。
		parameters[Bullet000NormBase.E_InitParasAttr.Direction] = forward.rotated(randf_range(-half_angle, half_angle))
		bullet.init_bullet(parameters)
		attack.bullets.add_child(bullet)
