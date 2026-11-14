## 火爆辣椒的整行与十字范围；逻辑地址选择格子，世界几何决定额外命中。
extends RefCounted
class_name AdventureJalapenoFootprint

## 本次攻击完整覆盖的行号。
var rows: Array[int] = []
## 棋盘保持同一实例；格子的位置仍随平台更新。
var _board: BoardRuntime
## 实际覆盖的格子，同时供地火、梯子和涅槃使用。
var cells: Array[PlantCell] = []
## 持续地火表现随地块运动，战局结束立即回收。
var _ground_flames: Array[JalapenoFireVisual] = []
## 引爆列只决定火浪的表现先后，命中范围仍由 [member rows] 和 [member cells] 决定。
var _origin_column: int = 0

## 从 [param origin] 的棋盘建立范围。[param spread] 扩至邻行，[param cross] 加入所在列。
func configure(origin: PlantCell, spread: bool, cross: bool) -> void:
	_board = origin.board
	_origin_column = origin.row_col.y
	for lane: int in range(maxi(0, origin.row_col.x - int(spread)), mini(_board.extent.x, origin.row_col.x + int(spread) + 1)): # 合法空行仍是完整攻击行。
		rows.append(lane)
	for cell: PlantCell in _board.cells(): # 稀疏棋盘只加入真实存在的行和格。
		if rows.has(cell.row_col.x) or (cross and cell.row_col.y == origin.row_col.y):
			cells.append(cell)

## 播放保留完整原始帧的连续火浪，并清理原版行道具；额外纵列只处理对应格和梯子。
## [param ground] 为持续地火开启额外的五秒表现，不延迟原有伤害结算。
func display(ground: bool) -> void:
	for lane: int in rows: # 每个完整行只发一组原版事件。
		EventBus.push_event("jalapeno_bomb_item_lane", [lane])
	for cell: PlantCell in cells: # 覆盖格随所在平台移动。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		JalapenoFireVisual.spawn_cell(cell, _origin_column)
		if not rows.has(cell.row_col.x):
			if is_instance_valid(cell.ladder):
				cell.ladder.ladder_death()
		if ground:
			_ground_flames.append(JalapenoFireVisual.spawn_cell(cell, _origin_column, true))

## 回收本来源仍在播放的地火，完整行及额外纵列的原生爆炸表现自行结束。
func clear_ground() -> void:
	for flame: JalapenoFireVisual in _ground_flames: # 地块可能已经先卸载。
		if is_instance_valid(flame):
			flame.queue_free()
	_ground_flames.clear()

## 读取 [param game] 的当前敌方实体；[param structures] 为 true 时同时纳入设施。
func enemies(game: MainGameManager, structures: bool = false) -> Array[Character000Base]:
	var targets: Array[Character000Base] = [] # 快照不随受击回调改写。
	targets.append_array(game.zombie_manager.all_zombies_1d)
	targets.append_array(game.zombie_manager.get_living_bosses())
	if structures:
		for node: Node in game.get_tree().get_nodes_in_group(EnemyStructureBase.GROUP): # 只读设施组实际类型。
			if node is EnemyStructureBase:
				targets.append(node)
	return targets

## [param target] 必须是 [param game] 内仍可受击的存活敌人。
func can_hit(target: Character000Base, game: MainGameManager) -> bool:
	return is_instance_valid(target) and not target.is_death and not target.is_hypno \
		and not target.is_queued_for_deletion() and game.is_ancestor_of(target) \
		and target.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and is_instance_valid(target.hurt_box_component) and target.hurt_box_component.is_enabling

## 返回 [param target] 的真实受击中心；没有有效区域时取实际位置。
static func hit_center(target: Character000Base) -> Vector2:
	var box: HurtBoxComponent = target.hurt_box_component # 使用真实框，避免把屋顶检测基线当作世界高度。
	if is_instance_valid(box) and is_instance_valid(box.hurt_box_real):
		var shape := box.hurt_box_real.get_node_or_null(^"CollisionShape2D") as Node2D # 受击形状可以有自身偏移。
		return shape.global_position if shape != null else box.hurt_box_real.global_position
	return target.global_position

## 判断 [param target] 是否实际触及被覆盖的现有格子。
## 普通角色以真实受击横坐标投影到脚下；无固定行的僵王按真实受击中心。
func touches(target: Character000Base) -> bool:
	if rows.has(target.lane):
		return true
	var center: Vector2 = hit_center(target) # 坡面与移动平台的位置均从当前世界变换读取。
	if not target is ZB000Base:
		return cells.has(_board.cell_at_ground_point(Vector2(center.x, target.global_position.y), target.lane))
	for cell: PlantCell in cells: # 无固定攻击行的僵王只接受真实世界覆盖。
		if is_instance_valid(cell) and not cell.is_queued_for_deletion() and cell.contains_world_point(center):
			return true
	return false

## 根据 [param points] 中的真实死亡位置，在 [param game] 内按约一格范围扩散。
## [param ignite] 为合格邻敌刷新灼烧。
func spread_burn(game: MainGameManager, points: Array[Vector2], ignite: Callable) -> void:
	for target: Character000Base in enemies(game): # 每批对同一存活邻敌仅施加一次。
		if not can_hit(target, game):
			continue
		var center: Vector2 = hit_center(target) # 使用受击中心比较真正的世界距离。
		var tile: PlantCell = _board.nearest_cell(center, target.lane) # 仅借邻格度量距离，不把目标吸附到格子。
		var pitch: Vector2 = _board.local_pitch(tile).max(Vector2.ONE) # 以世界行距和列距归一化一格范围。
		for point: Vector2 in points: # 同批任一死者可引燃此目标。
			if ((point - center) / pitch).length_squared() <= 1.0:
				ignite.call(target)
				break
