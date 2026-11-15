## 战场掉落服务：把通用掉落池的一次抽取实例化成具体的掉落物。
## 抽池规则（[BattleDropPool]）与掉落表现（[BattlePickup]）彼此独立，这里只负责把两者接起来。
extends RefCounted
class_name BattleDropService

## 战场材料与结算保底共用的掉落物场景。
const MaterialPickupScene := preload("res://scenes/item/game_scenes_item/drop/material_pickup.tscn")

## 实例化掉落物场景、挂到 [param parent]、定位到 [param origin]；调用方配置完外观后再 [method BattlePickup.launch]。
## [param target] 是收集动画的终点锚点（金币栏），可与掉落物处于不同画布。
## [param persistent] 为 true 时不启动落地后的超时淡出，实体会留到收取或离场。
static func spawn(scene: PackedScene, parent: Node, target: Node2D, origin: Vector2,
		persistent: bool = false) -> BattlePickup:
	if not is_instance_valid(parent) or scene == null:
		return null
	var pickup: BattlePickup = scene.instantiate() # 入树前配置寿命，[method BattlePickup._ready] 会依此启动计时。
	if persistent:
		pickup.exist_time = 0.0
	parent.add_child(pickup)
	pickup.setup(target)
	pickup.global_position = origin
	return pickup

## 在 [param parent] 的世界坐标 [param origin] 生成已入账的 [param item_id]，叠放 [param quantity] 份。
## [param target] 是点击物品或奖杯后收取飞行的锚点；调用方负责抛掷到本次胜利的落点。
static func spawn_settled_item(parent: Node, target: Node2D, origin: Vector2,
		item_id: StringName, quantity: int) -> MaterialPickup:
	var pickup: MaterialPickup = spawn(MaterialPickupScene, parent, target, origin, true) as MaterialPickup # 胜利保底常驻到收取。
	if pickup != null:
		pickup.settled_reward = true
		pickup.auto_collect_on_landing = false
		pickup.setup_item(item_id, quantity)
	return pickup

## 掷出掉落物；[param target_offset] 是相对落点（x 随机左右，y 固定往前）。
static func throw_pickup(pickup: BattlePickup, target_offset := Vector2.ZERO) -> void:
	if not is_instance_valid(pickup):
		return
	if target_offset == Vector2.ZERO:
		target_offset = Vector2(randf_range(-50.0, 50.0), randf_range(80.0, 90.0))
	pickup.launch(target_offset)

## 从 [param phase] 抽取材料，按 [param effects] 修正概率与数量，挂到 [param parent] 并定位到 [param origin]。
## [param target] 为收集锚点；未命中或数值越界返回 null，不改变共享阶段资源。
static func drop_material(phase: StagePhaseDefinition, parent: Node, target: Node2D, origin: Vector2,
		effects: PlayerEffects = null) -> MaterialPickup:
	var pool: BattleDropPool = BattleDropPool.from_phase(phase) # 临时池不修改阶段共享资源。
	if effects != null:
		pool.chance = minf(1.0, pool.chance * effects.drop_chance_multiplier)
	var pick: Dictionary = pool.roll() # 数量加成发生在抽中后，不改变材料权重。
	if pick.is_empty():
		return null
	var quantity: int = PlayerEffects.scale_amount(int(pick["quantity"]), float(effects.loot_multiplier)) \
		if effects != null else int(pick["quantity"]) # 单份掉落金额固定，拾取时不重新解析装备。
	if quantity < 1:
		return null
	var pickup := spawn(MaterialPickupScene, parent, target, origin) as MaterialPickup
	if pickup == null:
		return null
	pickup.setup_item(StringName(pick["id"]), quantity)
	throw_pickup(pickup)
	return pickup
