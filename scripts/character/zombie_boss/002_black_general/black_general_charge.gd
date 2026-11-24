## 冲锋的移动及扫掠命中；本体结算伤害，影子只施加劣化。
extends RefCounted
class_name BlackGeneralCharge

## 二阶段转场影子施加的劣化强度，沿用生命组件的最高值规则。
const SHADOW_DEGRADATION: float = 0.10

## 本次冲锋已命中的植物 ID，防止一株高血植物每帧重复受伤。
var _hit: Dictionary[int, bool] = {}
## 本次累计撞死植物数。
var _kills: int = 0
## 零表示不限制撞死数，只在第二列停止。
var _kill_limit: int = 0
## 执行中的冲锋开关。
var active: bool = false

## [param kill_limit] 一阶段为 2；二阶段/转阶段为 0。
func begin(kill_limit: int) -> void:
	_hit.clear()
	_kills = 0
	_kill_limit = kill_limit
	active = true

## 取消后不会保留命中历史或继续移动。
func cancel() -> void:
	active = false
	_hit.clear()

## 返回 [param cells] 的第二列右边界；没有足够格子时返回 INF，表示无有效冲锋路径。
func stop_line(cells: Array) -> float:
	var row: Array = _ordered_row(cells) # 与扫掠使用相同的排序与停止线。
	return _second_column_edge(row) if row.size() >= 2 else INF

## [param cells] 当前行格子。返回按画面坐标排序的副本，不改变关卡布局。
func _ordered_row(cells: Array) -> Array:
	var row: Array = cells.duplicate() # 只排序副本，不改变场地原始布局。
	row.sort_custom(func(a: PlantCell, b: PlantCell) -> bool: return a.global_position.x < b.global_position.x)
	return row

## [param row] 至少两格且已按 X 排序的行。返回受保护第二列的右边界。
func _second_column_edge(row: Array) -> float:
	var second: PlantCell = row[1] # 画面第二列。
	return second.get_global_rect().end.x

## [param boss] 冲锋速度及本体伤害来源；[param cells] 所在行格子；[param delta] 已乘角色速度的秒数。
## [param shadow] 提供时移动该影子，命中时只施加劣化。
## 返回是否完成；扫描整个移动区间，低帧率也不会跳过植物或碰到第二列植物。
func advance(boss: ZB002BlackGeneral, cells: Array, delta: float, shadow: Node2D = null) -> bool:
	if not active or cells.size() < 2:
		active = false
		return true
	var row: Array = _ordered_row(cells) # 从右向左遍历这一份有序副本。
	var stop_x: float = _second_column_edge(row) # 第二列右边界，禁止进入受保护格。
	var actor: Node2D = shadow if shadow != null else boss # 本次扫掠移动的节点。
	var from_x: float = actor.global_position.x # 本帧移动起点。
	var to_x: float = maxf(stop_x, from_x - boss.config.charge_speed * delta) # 裁剪后的移动终点。
	for column: int in range(row.size() - 1, 1, -1): # 第三列至最右列，从右向左结算。
		var cell: PlantCell = row[column] # 本次扫过的格子。
		var bounds: Rect2 = cell.get_global_rect() # 格子世界范围；从格内开始冲锋也能命中。
		if bounds.position.x >= from_x or bounds.end.x <= to_x:
			continue
		for candidate: Variant in cell.living_plants(): # 可在伤害回调中被删除的植物快照。
			if not is_instance_valid(candidate) or not candidate is Plant000Base:
				continue
			var plant: Plant000Base = candidate # 已检查类型的活体引用。
			if plant.is_death or plant.is_queued_for_deletion() or not plant.hurt_box_component.is_enabling \
				or _hit.has(plant.get_instance_id()):
				continue
			_hit[plant.get_instance_id()] = true
			if shadow != null:
				AdventurePlantNegativeEffects.apply(plant, AdventurePlantNegativeEffects.Kind.DEGRADATION, 0, SHADOW_DEGRADATION)
				continue
			# 按实际致死播放压扁，守护或护甲抵消的伤害不会预演死亡。
			var health: HpComponent = plant.hp_component # 只为当前这笔同步伤害监听。
			var flatten := func(_cause: CombatHitScope.DeathCause) -> void: plant.body.be_flattened_body()
			health.before_death.connect(flatten, CONNECT_ONE_SHOT)
			var receipt: Dictionary = {} # 冲锋击杀预算计入实际承伤者。
			plant.be_attacked_bullet(boss.config.charge_damage, BulletRegistry.AttackMode.Penetration, false, false, 0, -1, receipt,
				CombatHitScope.for_plant_attack(boss, CombatHitScope.PlantImpact.CRUSH))
			if is_instance_valid(health) and health.before_death.is_connected(flatten):
				health.before_death.disconnect(flatten)
			if is_instance_valid(receipt.get("casualty")):
				_kills += 1
			if boss.is_death or not active:
				return true
			if _kill_limit > 0 and _kills >= _kill_limit:
				boss.move_charge_to(boss, minf(from_x, bounds.end.x))
				active = false
				return true
	boss.move_charge_to(actor, to_x)
	active = to_x > stop_x
	return not active
