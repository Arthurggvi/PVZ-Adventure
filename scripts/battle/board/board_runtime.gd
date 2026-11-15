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

## 按 [param lane] 枚举种植点；无效行返回空数组。
func row_cells(lane: int) -> Array[PlantCell]:
	var result: Array[PlantCell] = [] # 类型明确的空行/结果。
	if lane >= 0 and lane < _rows.size():
		result.assign(_rows[lane])
	return result

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
	var result: PlantCell = null # 命中重叠地块时按场景树输入顺序选择。
	for cell: PlantCell in _cells: # 地块几何与 Button._has_point 使用同一接口。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion() or not cell.is_visible_in_tree():
			continue
		if cell.contains_world_point(point) and (result == null or cell.is_greater_than(result)):
			result = cell
	return result


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
