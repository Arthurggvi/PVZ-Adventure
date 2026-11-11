## 战场空间存档协议；先预检所有 ID/拓扑/行为状态，再一次性恢复。
extends RefCounted
class_name BoardStateSnapshot

## 捕获 [param board] 的地形和运动状态，不复制植物占用。
static func capture(board: BoardRuntime) -> Dictionary:
	var cells: Dictionary = {} # 按稳定地块 ID 保存，不依赖数组顺序。
	for cell: PlantCell in board.cells(): # 地形及扩展行为的独立状态。
		cells[str(cell.cell_id)] = {"address": cell.row_col,
			"surface": str(cell.board_definition.surface_id),
			"terrain": str(cell.board_terrain.terrain_id), "behavior": cell.capture_terrain_state()}
	var surfaces: Dictionary = {} # 平台的完整运动阶段。
	for id: StringName in board.surfaces: # 每个平台只保存一次。
		surfaces[str(id)] = board.surfaces[id].capture_state()
	var lanes: Array[String] = [] # 行顺序是原战斗内核的兼容契约。
	for lane: BoardLaneDefinition in board.lanes: # 存档记录稳定行身份。
		lanes.append(str(lane.lane_id))
	return {"version": 1, "board_id": str(board.board_id), "revision": board.revision,
		"cells": cells, "surfaces": surfaces, "lanes": lanes}

## 校验 [param state] 是否与当前 [param board] 完全兼容，失败不修改任何实体。
static func accepts(board: BoardRuntime, state: Dictionary) -> bool:
	if state.is_empty():
		return board.definition == null # 仅旧布局允许没有空间快照的旧存档。
	if state.get("version") != 1 or state.get("board_id") != str(board.board_id) \
			or state.get("revision") != board.revision:
		return false
	if not state.get("cells") is Dictionary or not state.get("surfaces") is Dictionary \
			or not state.get("lanes") is Array:
		return false
	var cells: Dictionary = state["cells"] # 已确认的地块状态表。
	var surfaces: Dictionary = state["surfaces"] # 已确认的平台状态表。
	if cells.size() != board.cells().size() or surfaces.size() != board.surfaces.size() \
			or state["lanes"].size() != board.lanes.size():
		return false
	for index: int in range(board.lanes.size()): # 防止相同 ID 但行顺序变化导致植物错行。
		if state["lanes"][index] != str(board.lanes[index].lane_id):
			return false
	for cell: PlantCell in board.cells(): # 所有地块都必须匹配身份和逻辑拓扑。
		var entry: Variant = cells.get(str(cell.cell_id)) # 未可信存档数据。
		if not entry is Dictionary or entry.get("address") != cell.row_col \
				or entry.get("surface") != str(cell.board_definition.surface_id) \
				or not entry.get("terrain") is String or not entry.get("behavior") is Dictionary:
			return false
		var terrain: BoardTerrainDefinition = board.terrains.get(StringName(entry["terrain"])) # 目录内的有效地形。
		if terrain == null or not BoardTerrainLayer.accepts_state(terrain, entry["behavior"]):
			return false
	for id: StringName in board.surfaces: # 位姿必须全部有限且运动阶段合法。
		if not surfaces.get(str(id)) is Dictionary \
				or not BoardSurface.accepts_state(surfaces[str(id)]):
			return false
	return true

## 恢复预检通过的 [param state]；应在植物与墓碑读档之前调用。
static func restore(board: BoardRuntime, state: Dictionary) -> bool:
	if not accepts(board, state):
		push_error("战场空间存档与当前布局不兼容，已拒绝恢复。")
		return false
	if state.is_empty():
		return true
	for id: StringName in board.surfaces: # 先恢复平台，使后续实例使用最终锚点。
		board.surfaces[id].restore_state(state["surfaces"][str(id)])
	for cell: PlantCell in board.cells(): # 地形已在全量预检中验证。
		var entry: Dictionary = state["cells"][str(cell.cell_id)] # 当前地块状态。
		cell.apply_board_terrain(board.terrains[StringName(entry["terrain"])])
		cell.restore_terrain_state(entry["behavior"])
	return true
