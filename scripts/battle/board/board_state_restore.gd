## 空间恢复的离树准备计划；构造全部地形成功后才改变平台及活格子。
extends RefCounted
class_name BoardStateRestore

## 目标空间与冻结快照。
var board: BoardRuntime
## 准备时复制，不接受调用者随后修改输入字典。
var state: Dictionary = {}
## 尚未安装的地形层，计划销毁时必须释放。
var layers: Array[BoardTerrainLayer] = []
## 只允许提交一次。
var _committed: bool = false

## [param snapshot] 全量验证后离树构造；任何失败释放此前准备的层。
static func prepare(target: BoardRuntime, snapshot: Dictionary) -> BoardStateRestore:
	if target == null or not target.configured or not target.allows_mutation() \
			or not BoardStateSnapshot.accepts(target, snapshot):
		return null
	var plan := BoardStateRestore.new() # 只有成功后返回给提交入口。
	plan.board = target
	plan.state = snapshot.duplicate(true)
	if snapshot.is_empty():
		return plan
	for cell: PlantCell in target.cells(): # 先准备所有格子，拒绝后半场景错误的部分提交。
		var entry: Dictionary = plan.state["cells"][str(cell.cell_id)] # 已校验记录。
		var layer: BoardTerrainLayer = BoardTerrainLayer.prepare(cell,
			target.terrains[StringName(entry["terrain"])], entry["behavior"], true) # 预留真实实例。
		if layer == null:
			return null
		plan.layers.append(layer)
	return plan

## 提交前重新检查目标生命周期；准备过程不跨帧，也不重造行为实例。
func can_commit() -> bool:
	if _committed or board == null or not board.configured:
		return false
	for layer: BoardTerrainLayer in layers: # 稳定 ID 必须仍指向准备时的地块。
		if not is_instance_valid(layer.cell) or layer.cell.is_queued_for_deletion() \
				or board.cell_by_id(layer.cell.cell_id) != layer.cell or layer.get_parent() != null:
			return false
	for surface: BoardSurface in board.surfaces.values(): # 平台也必须仍有效。
		if not is_instance_valid(surface) or surface.is_queued_for_deletion():
			return false
	return true

## 已取得 [param transaction] 的事务提交此空间计划；不再实例化或解码输入。
func apply_prepared(transaction: RefCounted) -> void:
	assert(can_commit() and board.allows_mutation(transaction))
	_committed = true
	if state.is_empty():
		return
	for id: StringName in board.surfaces: # 平台先恢复，植物随后使用最终锚点。
		board.surfaces[id].restore_state(state["surfaces"][str(id)])
	for layer: BoardTerrainLayer in layers: # 所有地形已经准备成功。
		layer.cell.install_prepared_terrain(layer)
	layers.clear()

## 独立空间恢复也使用相同的锁与准备阶段。
func commit() -> bool:
	if not can_commit() or not board.begin_restore(self):
		return false
	apply_prepared(self)
	board.end_restore(self)
	return true

## 放弃计划只释放离树预留，不触碰活场景。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for layer: BoardTerrainLayer in layers: # 已安装的层从列表移除。
			if is_instance_valid(layer) and layer.get_parent() == null:
				layer.free()
