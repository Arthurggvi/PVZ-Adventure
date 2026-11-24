## 连续阶段的布局预检；只允许保留平台、攻击行和现有地块身份的收缩布局。
## 保留的植株不离树、不重新种植，状态和计时器随原格子一起继承。
extends RefCounted
class_name BoardPhaseLayout

## 预检对应的唯一棋盘。
var board: BoardRuntime
## 下一阶段的独占布局资源。
var target: BoardDefinition
## 以稳定格子 ID 保存已离树构造的地形层；提交后移交给原格子。
var layers: Dictionary[StringName, BoardTerrainLayer] = {}

## 为 [param source] 准备 [param layout]；任何失败均保留原战场。
static func prepare(source: BoardRuntime, layout: BoardDefinition) -> BoardPhaseLayout:
	if source == null or layout == null or not source.allows_mutation() or not layout.validate().is_empty():
		return null
	var plan := BoardPhaseLayout.new() # 仅本次交接持有，无全局缓存。
	plan.board = source
	plan.target = layout.duplicate(true) as BoardDefinition
	var lanes: Array[BoardLaneDefinition] = plan.target.lane_definitions() # 固定攻击行身份必须对应。
	if lanes.size() != source.lanes.size() or plan.target.surfaces.size() != source.surfaces.size():
		return null
	for index: int in range(lanes.size()): # 不支持把植物改派到其他攻击行。
		if lanes[index].lane_id != source.lanes[index].lane_id:
			return null
	for surface: BoardSurfaceDefinition in plan.target.surfaces: # 本次只调整静态平面格位。
		if not source.surfaces.has(surface.surface_id) or surface.visual_scene != null \
				or not surface.travel_offset.is_zero_approx():
			return null
	for data: BoardCellDefinition in plan.target.cell_definitions(): # 新增地块需独立实现，不能静默重建实体。
		var cell: PlantCell = source.cell_by_id(data.cell_id) # 保留原节点及其信号连接。
		if cell == null or cell.row_col != data.address or cell.board_definition.surface_id != data.surface_id:
			return null
		var terrain: BoardTerrainDefinition = null # 使用目标资源中的地形权威。
		for candidate: BoardTerrainDefinition in plan.target.terrains: # 匹配目标格子的显式地形。
			if candidate.terrain_id == data.terrain_id:
				terrain = candidate
		# 动态水体几何暂不支持；本次转换为无水体的陆地。
		if terrain == null or terrain.water_contact:
			return null
		var layer: BoardTerrainLayer = BoardTerrainLayer.prepare(cell, terrain) # 先构造再释放旧层。
		if layer == null:
			return null
		plan.layers[data.cell_id] = layer
	return plan

## 成功预检后同步提交；调用期间必须暂停战斗。
func commit() -> void:
	board.commit_phase_layout(target, layers, self)
	layers.clear() # 已入树的节点由 PlantCell 接管。

## [param what] 为销毁通知时，只释放本计划创建而尚未交接的离树节点。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for layer: BoardTerrainLayer in layers.values(): # 已交接的层不在此字典中。
			if is_instance_valid(layer) and not layer.is_inside_tree():
				layer.free()
