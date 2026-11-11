## 豌豆射手冒险转职射击运行时；复用原生攻击组件、动画与子弹注册表。
extends Node
class_name AdventurePeaPromotionRuntime

## 普通豌豆射手物种 ID；其他豌豆家族不继承该卡的转职书。
const PEA := 1
## 无限几何连发的极端安全阈值；达到阈值概率低于二的三十二次方分之一。
const MAX_CHAIN_SHOTS := 32
## 额外追射的视觉间隔，单位秒，不改变原射击周期。
const FOLLOWUP_DELAY := 0.12
## 关卡场景管理器，由所有者在入树前设置。
var game: MainGameManager
## 普通豌豆子弹场景导出的基础伤害，在本局初始化时读取。
var _base_pea_damage: int = 0
## 每株热血累计射击次数，停止攻击或死亡时清零。
var _heat: Dictionary[int, int] = {}
## 已绑定技能的植物实例 ID，防止一株重复连接信号。
var _bound: Dictionary[int, bool] = {}

## [param battle] 当前战斗场景；本运行时只在冒险关卡注册。
func setup(battle: MainGameManager) -> void:
	game = battle

func _ready() -> void:
	# 从原版子弹场景读取攻击力，避免复制魔法数值与场景资产脱节。
	var pea_scene: PackedScene = Global.bullet_registry.get_bullet_scenes(BulletRegistry.BulletType.Bullet001Pea)
	if pea_scene == null:
		push_error("豌豆转职缺少原版豌豆子弹")
		return
	var reference: Bullet000NormBase = pea_scene.instantiate() as Bullet000NormBase
	if reference == null:
		push_error("豌豆子弹场景类型不兼容")
		return
	_base_pea_damage = reference.attack_value
	reference.free()
	if not is_instance_valid(game) or not is_instance_valid(game.plant_cell_manager):
		return
	for row: Array in game.plant_cell_manager.all_plant_cells:
		for cell: PlantCell in row:
			cell.signal_plant_create.connect(_on_plant_created)
			for entry: Variant in cell.plant_in_cell.values():
				_bind_plant(entry as Plant000Base)

## [param cell] 已种植的格子；[param plant_type] 原生事件的物种编号。
func _on_plant_created(cell: PlantCell, plant_type: CharacterRegistry.PlantType) -> void:
	if int(plant_type) != PEA:
		return
	for entry: Variant in cell.plant_in_cell.values():
		_bind_plant(entry as Plant000Base)

## 使用冻结的卡片快照读取技能；静态效果无需替换原版射击入口。
func _bind_plant(plant: Plant000Base) -> void:
	if not is_instance_valid(plant) or int(plant.plant_type) != PEA \
			or plant.plant_spawn_profile == null:
		return
	var id: int = plant.get_instance_id()
	if _bound.has(id):
		return
	var card: PlantCardInstance = PlantCardInstance.from_dict(plant.plant_spawn_profile.snapshot())
	if card == null:
		return
	var rules: Dictionary = {}
	for effect: Dictionary in AdventurePromotionCatalog.effects(card).events:
		var kind: String = str(effect.get("kind", ""))
		if kind.begins_with("pea_") and kind != "pea_synergy":
			rules[kind] = effect
	if rules.is_empty():
		return
	var attack: AttackComponentBulletBase = plant.get_node_or_null("AttackComponent") as AttackComponentBulletBase
	if attack == null or attack.shoot_override.is_valid():
		push_error("豌豆转职需要空闲的原生子弹攻击入口")
		return
	_bound[id] = true
	_heat[id] = 0
	attack.shoot_override = Callable(self, "_shoot_chain").bind(attack, plant, rules)
	attack.signal_change_is_attack.connect(_on_attack_status.bind(id))
	plant.signal_character_death.connect(_on_plant_death.bind(id), CONNECT_ONE_SHOT)

## 射击目标丢失后清零热血积累；重新发现目标重新计算。
func _on_attack_status(active: bool, id: int) -> void:
	if not active:
		_heat[id] = 0

func _on_plant_death(id: int) -> void:
	_heat.erase(id)
	_bound.erase(id)

## 动画每次请求发射进入此协程，后续射击保持原有发射信号、音效和弹道参数。
func _shoot_chain(attack: AttackComponentBulletBase, plant: Plant000Base,
		rules: Dictionary) -> void:
	var id: int = plant.get_instance_id()
	var chain: int = 0
	while is_instance_valid(plant) and not plant.is_death \
			and is_instance_valid(attack) and attack.is_attack_res:
		var fire: bool = rules.has("pea_fire") \
			and randf() < float(rules["pea_fire"].get("chance", 0.0))
		var damage_factor: float = 1.0
		if rules.has("pea_hot_blood"):
			var heat_rule: Dictionary = rules["pea_hot_blood"]
			damage_factor += minf(float(heat_rule.get("cap", 0.0)),
				float(_heat.get(id, 0)) * float(heat_rule.get("step", 0.0)))
		if fire:
			damage_factor *= float(rules["pea_fire"].get("damage", 1.0))
		_fire_once(attack, fire, damage_factor, rules)
		if rules.has("pea_hot_blood"):
			_heat[id] = int(_heat.get(id, 0)) + 1
		chain += 1
		if chain >= MAX_CHAIN_SHOTS or not rules.has("pea_multishot") \
				or randf() >= float(rules["pea_multishot"].get("chance", 0.0)):
			break
		await get_tree().create_timer(FOLLOWUP_DELAY).timeout

## [param attack] 原射击组件；[param fire] 使用现成火豌豆外观。
## [param damage_factor] 本次发射倍率；[param rules] 贯穿与命中事件配置。
func _fire_once(attack: AttackComponentBulletBase, fire: bool,
		damage_factor: float, rules: Dictionary) -> void:
	var bullet_type: BulletRegistry.BulletType = (BulletRegistry.BulletType.Bullet006PeaFire
		if fire else BulletRegistry.BulletType.Bullet001Pea)
	var scene: PackedScene = Global.bullet_registry.get_bullet_scenes(bullet_type)
	if scene == null or not is_instance_valid(attack.bullets):
		return
	attack.signal_shoot_bullet.emit()
	for i: int in range(attack.markers_2d_bullet.size()):
		var bullet: Bullet000NormBase = scene.instantiate() as Bullet000NormBase
		if bullet == null:
			push_error("豌豆转职子弹场景缺少正常命中接口")
			return
		bullet.attack_value = maxi(0, roundi(float(_base_pea_damage) * damage_factor))
		if fire:
			(bullet as Bullet006PeaFire).enable_base_splash = false
		if rules.has("pea_pierce"):
			bullet.promotion_hit_factors = PackedFloat32Array(rules["pea_pierce"].get("hit_factors", []))
			bullet.max_attack_num = bullet.promotion_hit_factors.size()
		if fire or rules.has("pea_splash") or rules.has("pea_shock"):
			bullet.impact_resolved.connect(AdventurePeaProjectileEffects.impact.bind(bullet, rules))
		attack.signal_bullet_instantiated.emit(bullet)
		var paras: Dictionary = attack.get_bullet_paras(
			attack.markers_2d_bullet[i].global_position, attack.detect_component.ray_area_direction[i])
		bullet.init_bullet(paras)
		attack.bullets.add_child(bullet)
		attack.play_throw_sfx()
