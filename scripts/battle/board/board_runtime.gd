## 战场空间唯一索引；植物占用仍由 PlantCell 持有，不复制为第二份状态。
extends RefCounted
class_name BoardRuntime

## 布局稳定身份及兼容修订号。
var board_id: StringName = &"legacy"
## 不兼容拓扑修订号。
var revision: int = 1
## 全部装配完成后才为 true。
var configured: bool = false
## 逻辑地址范围，不表示每一个地址都存在格子。
var extent := Vector2i.ZERO
## 运行时独占的布局快照，旧场景适配时为空。
var definition: BoardDefinition
## 唯一地块身份索引。
var _by_id: Dictionary[StringName, PlantCell] = {}
## 稀疏逻辑地址索引。
var _by_address: Dictionary[Vector2i, PlantCell] = {}
## 分行枚举视图，只保存有效地块，不使用 null 填补缺格。
var _rows: Array[Array] = []
## 稳定顺序的地块列表。
var _cells: Array[PlantCell] = []
## 可移动平台的节点实例。
var surfaces: Dictionary[StringName, BoardSurface] = {}
## 独占地形目录，供运行时切换及存档身份校验。
var terrains: Dictionary[StringName, BoardTerrainDefinition] = {}
## 固定攻击行定义；旧关由场景适配得到。
var lanes: Array[BoardLaneDefinition] = []
## 同步恢复事务的唯一所有者；阻止回调重入触发第二次空间变更。
var _restore_owner: RefCounted
## 种植地形变更通知；不承担卡槽费用结算。
signal terrain_changed(cell: PlantCell)
## 已有植株换位完成；邻接效果刷新，不触发新种植或死亡的收益。
signal plant_relocated
## [param plant] 的实体与占格尚未释放，供环境在死亡前捕获姿态。
signal plant_dying(plant: Plant000Base)

## 初始化行容器，[param lane_definitions] 的数组顺序就是战斗行号。
func configure_lanes(lane_definitions: Array[BoardLaneDefinition]) -> void:
	lanes = lane_definitions
	extent.x = lanes.size()
	for lane: int in range(lanes.size()): # 空行也保留其攻击行身份。
		_rows.append([])

## 装配期注册 [param cell]；[param data] 的身份和地址不随平台移动变化。
func register_cell(cell: PlantCell, data: BoardCellDefinition) -> void:
	assert(not configured and not _by_id.has(data.cell_id) and not _by_address.has(data.address))
	cell.board = self
	cell.board_definition = data
	cell.row_col = data.address
	cell.board_terrain = terrains[data.terrain_id]
	cell.plant_cell_type = cell.board_terrain.presentation_kind as PlantCell.PlantCellType
	_by_id[data.cell_id] = cell
	_by_address[data.address] = cell
	_rows[data.address.x].append(cell)
	_cells.append(cell)
	extent.y = maxi(extent.y, data.address.y + 1)

## 返回有效地块的枚举副本；消费者不能增删权威索引。
func cells() -> Array[PlantCell]:
	return _cells.duplicate()

## 返回按攻击行分组的副本；每行可有不同数量的种植点。
func rows() -> Array[Array]:
	var result: Array[Array] = [] # 独立枚举容器，不复制节点。
	for row: Array in _rows: # 行内部同样禁止外部排序污染索引。
		result.append(row.duplicate())
	return result

## 按实际攻防行 [param lane] 枚举种植点；无效行返回空数组。
func row_cells(lane: int) -> Array[PlantCell]:
	var result: Array[PlantCell] = [] # 类型明确的空行/结果。
	if lane < 0 or lane >= _rows.size():
		return result
	if definition != null and definition.project_surface_combat_lanes:
		for cell: PlantCell in _cells: # 当前攻防行可能不同于存档中的初始种植行。
			if cell.combat_lane == lane:
				result.append(cell)
		result.sort_custom(func(left: PlantCell, right: PlantCell): return left.row_col.y < right.row_col.y)
	else:
		result.assign(_rows[lane])
	return result

## 将战场局部脚点 [param foot_y] 投影到固定进攻线；无行返回 -1，等距时取上行。
func lane_at_foot_y(foot_y: float) -> int:
	var nearest: int = -1 # 当前最近的进攻线。
	var distance: float = INF # 当前最短的纵向像素差。
	for index: int in lanes.size(): # 与正式出怪标记共享同一条基线。
		var offset: float = absf(lanes[index].spawn_position.y - foot_y) # 只按高度匹配进攻方向。
		if offset < distance:
			nearest = index
			distance = offset
	return nearest

## 稳定 ID 查询；不存在的 [param id] 返回 null，不回退数组下标。
func cell_by_id(id: StringName) -> PlantCell:
	var cell: Variant = _by_id.get(id) # 节点生命周期独立于 RefCounted 索引。
	return cell if is_instance_valid(cell) and not cell.is_queued_for_deletion() else null

## 稀疏地址查询；缺格返回 null。
func cell_at(address: Vector2i) -> PlantCell:
	var cell: Variant = _by_address.get(address) # 缺格或已离场节点均不可被重新种植。
	return cell if is_instance_valid(cell) and not cell.is_queued_for_deletion() else null

## 返回 [param origin] 周围 [param radius] 步的拓扑邻格，默认包含自身。
func neighbors(origin: PlantCell, radius: int = 1) -> Array[PlantCell]:
	return BoardQueries.neighbors(self, origin, radius)

## 多格占用的向右邻格；不能跨平台。
func right_of(origin: PlantCell) -> PlantCell:
	if origin == null or origin.board != self:
		return null
	var data: BoardCellDefinition = origin.board_definition # 显式拓扑优先。
	var result: PlantCell = cell_by_id(data.right_neighbor_id) if data.right_neighbor_id != &"" \
		else cell_at(origin.row_col + Vector2i(0, 1))
	return result if result != null and result.board_definition.surface_id == data.surface_id else null

## 返回当前世界坐标 [param point] 下实际交互地块；重叠时与 GUI 的场景树顺序一致。
func pick_cell(point: Vector2) -> PlantCell:
	return BoardQueries.pick_cell_from(point, _cells)


## 在可选 [param lane] 内寻找离 [param point] 最近的种植点，-1 表示所有行。
func nearest_cell(point: Vector2, lane: int = -1) -> PlantCell:
	return BoardQueries.nearest(self, point, lane)

## 按 [param lane] 和当前世界脚点 [param point] 精确找格；空洞或盘外返回 null。
## 允许格子底边脚点，保留自定义命中多边形；不把击杀位置吸附到最近远格。
func cell_at_ground_point(point: Vector2, lane: int) -> PlantCell:
	return BoardQueries.cell_at_ground_point(self, point, lane)

## 从地形目录切换 [param cell_id]；[param keep_occupants] 必须显式允许保留不兼容植物。
## 默认有植物/障碍则拒绝，失败不改动现有状态，不自动铲除或退款。
func set_cell_terrain(cell_id: StringName, terrain_id: StringName, keep_occupants: bool = false) -> bool:
	var cell: PlantCell = cell_by_id(cell_id) # 目标地块。
	if not allows_mutation() or cell == null or not terrains.has(terrain_id):
		return false
	if not keep_occupants and (cell.get_curr_plant_num() > 0 or cell.curr_special_state_plant.values().any(func(active): return active)):
		return false
	if not cell.apply_board_terrain(terrains[terrain_id]):
		return false
	terrain_changed.emit(cell)
	return true

## 将 [param surface_id] 移至主战场局部 [param target]；秒数为零时立即定位。
func move_surface_to(surface_id: StringName, target: Vector2, seconds: float = 0.0) -> bool:
	if not allows_mutation() or not surfaces.has(surface_id) or not target.is_finite() or not is_finite(seconds) or seconds < 0.0:
		return false
	surfaces[surface_id].move_to(target, seconds)
	return true

## 保存身份、地形与平台运动阶段；植物仍由现有事务保存。
func capture_state() -> Dictionary:
	return BoardStateSnapshot.capture(self)

## 先验证全部 [param state] 再恢复；失败不得部分改写战场。
func restore_state(state: Dictionary) -> bool:
	return BoardStateSnapshot.restore(self, state)


## 同攻击行内的拓扑邻格，排除自身；[param reach] 为逻辑格数，不是像素距离。
func horizontal_neighbors(origin: PlantCell, reach: int = 1) -> Array[PlantCell]:
	var result: Array[PlantCell] = [] # 规则和显式拓扑复用同一个邻接定义。
	for cell: PlantCell in neighbors(origin, reach): # 跨攻击行候选不属于前后邻格。
		if cell != origin and cell.row_col.x == origin.row_col.x:
			result.append(cell)
	return result

## [param point] 附近真实地块的宽度；空行返回 0，消费者自行决定无目标行为。
func cell_width_at(point: Vector2, lane: int) -> float:
	var cell: PlantCell = nearest_cell(point, lane) # 不以本行首格代表所有位置。
	return cell.size.x if cell != null else 0.0

## 当前 [param origin] 附近列间距/行间距，供像素范围技能使用，不改变逻辑邻接。
func local_pitch(origin: PlantCell) -> Vector2:
	return BoardQueries.local_pitch(self, origin)


## 完成索引构建；枚举行按逻辑列排序，不依赖资源声明顺序。
func finish_configuration() -> void:
	assert(not configured)
	for row: Array in _rows: # 排序的是私有索引，外部只取得副本。
		row.sort_custom(func(left: PlantCell, right: PlantCell): return left.row_col.y < right.row_col.y)
	configured = true


## 仅恢复事务自身可在提交期变更占用；普通操作不携带 [param transaction]。
func allows_mutation(transaction: RefCounted = null) -> bool:
	return _restore_owner == null or _restore_owner == transaction

## 同步提交开始前取得唯一令牌；已有事务时拒绝重入。
func begin_restore(transaction: RefCounted) -> bool:
	if transaction == null or _restore_owner != null:
		return false
	_restore_owner = transaction
	return true

## 由相同 [param transaction] 释放令牌，不能结束其他事务。
func end_restore(transaction: RefCounted) -> void:
	assert(_restore_owner == transaction)
	_restore_owner = null

## 移去最后一行的全部格子和占用，保留其余地址及原实例。
func retire_last_lane() -> bool:
	if lanes.size() <= 1:
		return false
	var transaction := RefCounted.new() # 清理植物期间禁止死亡回调重入种植。
	if not begin_restore(transaction):
		return false
	for cell: PlantCell in _rows.back().duplicate(): # 收缩永久拓扑，按逻辑末行清理占用。
		if is_instance_valid(cell.tombstone):
			cell.tombstone.tombstone_death()
		if is_instance_valid(cell.ladder):
			cell.ladder.ladder_death()
		_remove_for_layout(cell)
	_rows.pop_back()
	lanes.pop_back()
	extent.x = lanes.size()
	end_restore(transaction)
	return true

## 将 [param cell] 及其实体从当前布局移去，沿用原植物清场的死亡语义。
func _remove_for_layout(cell: PlantCell) -> void:
	for plant: Plant000Base in cell.living_plants(): # 占用多格的同一实例仍只死亡一次。
		plant.is_can_death_language = false
	cell.clear_data_plant_cell()
	_by_id.erase(cell.cell_id)
	_by_address.erase(cell.row_col)
	_rows[cell.row_col.x].erase(cell)
	_cells.erase(cell)
	cell.hide()
	cell.queue_free()

## 安装已预检的 [param layout] 和 [param layers]；[param transaction] 独占本次索引变更。
## 移除的格子按原死亡协议清理，保留格子及所有植株继续使用原实例。
func commit_phase_layout(layout: BoardDefinition, layers: Dictionary, transaction: RefCounted) -> void:
	var accepted: bool = begin_restore(transaction) # 发行构建也必须执行互斥获取，不能藏在 assert 中。
	assert(accepted)
	if not accepted:
		return
	var game: MainGameManager = surfaces.values()[0].game # 本棋盘所属战斗。
	for cell: PlantCell in cells(): # 先清理退出布局的完整占用，再更新索引。
		if layers.has(cell.cell_id):
			continue
		_remove_for_layout(cell)
	definition = layout
	board_id = layout.board_id
	revision = layout.revision
	lanes = layout.lane_definitions()
	extent = Vector2i(lanes.size(), 0)
	terrains.clear()
	for terrain: BoardTerrainDefinition in layout.terrains: # 丢弃旧水路能力目录。
		terrains[terrain.terrain_id] = terrain
	for data: BoardCellDefinition in layout.cell_definitions(): # 原 Control 的锚点更新其所有植物容器。
		var cell: PlantCell = cell_by_id(data.cell_id) # 预检保证存在且身份不变。
		cell.board_definition = data
		cell.position = data.position
		cell.size = data.size
		cell.update_ground_anchors()
		cell.install_prepared_terrain(layers[data.cell_id])
		extent.y = maxi(extent.y, data.address.y + 1)
	for data: BoardSurfaceDefinition in layout.surfaces: # 水体区域不留在已成为陆地的战场。
		var surface: BoardSurface = surfaces[data.surface_id] # 保留所有种植节点的父平台。
		for child: Node in surface.get_children(): # 移除原平台的连续水域接触节点。
			if child is WaterBodyArea:
				surface.remove_child(child)
				child.queue_free()
		surface.configure(data, game)
		for region: Rect2 in data.water_regions: # 当前噩梦配置为空，协议仍按资源执行。
			surface.add_child(WaterBodyArea.from_region(region))
	for index: int in range(lanes.size()): # 同步正式出怪标记和水陆资格。
		var row: ZombieRow = game.zombie_manager.all_zombie_rows[index] # 保留原攻击行节点。
		row.zombie_row_type = lanes[index].spawn_type
		row.zombie_create_position.global_position = game.to_global(lanes[index].spawn_position)
	# 选行器缓存地形资格；布局交接后必须刷新，避免陆地阶段仍沿用水路权重。
	game.zombie_manager.zombie_wave_manager.zombie_wave_create_manager.zombie_choose_row_system.init_zombie_choose_row_system(game.zombie_manager.all_zombie_rows)
	game.game_para.board_definition = definition
	game.plant_cell_manager.rebuild_plant_counts()
	end_restore(transaction)
	plant_relocated.emit()
	EventBus.push_event("update_card_purple_sun_cost")
