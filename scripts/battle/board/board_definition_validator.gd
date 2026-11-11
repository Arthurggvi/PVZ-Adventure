## 布局静态校验；建立所有索引之前拒绝重复身份、悬空引用及非法几何。
extends RefCounted
class_name BoardDefinitionValidator

## 校验 [param definition]；不装配场景、不修改资源。
static func validate(definition: BoardDefinition) -> PackedStringArray:
	var errors := PackedStringArray() # 全部配置错误。
	if str(definition.board_id).strip_edges().is_empty() or definition.revision < 1:
		errors.append("战场必须声明稳定 board_id 和正 revision。")
	if definition is BoardGridDefinition:
		var grid := definition as BoardGridDefinition # 网格生成器的几何前置条件。
		if grid.dimensions.x < 1 or grid.dimensions.y < 1 or not grid.pitch.is_finite() \
				or grid.pitch.x <= 0.0 or grid.pitch.y <= 0.0 \
				or not grid.grid_origin.is_finite() or not is_finite(grid.spawn_x) or not is_finite(grid.mower_x):
			errors.append("规则网格行列、坐标及间距无效。")
			return errors
		var overrides: Dictionary = {} # 显式覆盖地址不能重复，也不能落在生成范围外。
		for override: BoardCellDefinition in grid.cells: # 原始覆盖表必须先于展开校验。
			if override == null:
				errors.append("网格覆盖包含空资源。")
				continue
			if override.address.x < 0 or override.address.x >= grid.dimensions.x \
					or override.address.y < 0 or override.address.y >= grid.dimensions.y \
					or overrides.has(override.address):
				errors.append("网格覆盖地址越界或重复。")
			overrides[override.address] = true
		if not errors.is_empty():
			return errors
	var terrain_ids: Dictionary = {} # 已验证的地形引用。
	for terrain: BoardTerrainDefinition in definition.terrains: # 注册能力目录。
		if terrain == null:
			errors.append("地形目录包含空资源。")
			continue
		errors.append_array(terrain.validate())
		if terrain_ids.has(terrain.terrain_id):
			errors.append("重复地形 ID：%s" % terrain.terrain_id)
		terrain_ids[terrain.terrain_id] = true
	var surface_ids: Dictionary = {} # 平台身份集合。
	for surface: BoardSurfaceDefinition in definition.surfaces: # 检查移动几何。
		if surface == null:
			errors.append("平台目录包含空资源。")
			continue
		if surface.surface_id == &"" or surface_ids.has(surface.surface_id):
			errors.append("平台 ID 为空或重复。")
		if not surface.origin.is_finite() or not surface.travel_offset.is_finite() \
				or not is_finite(surface.travel_seconds) or surface.travel_seconds <= 0.0:
			errors.append("平台位置/运动时间无效。")
		surface_ids[surface.surface_id] = true
	var lanes := definition.lane_definitions() # 展开后的攻击行。
	var lane_ids: Dictionary = {} # 行身份集合。
	if lanes.is_empty():
		errors.append("战场至少需要一条攻击行。")
	for lane: BoardLaneDefinition in lanes: # 行必须有完整生成协议。
		if lane == null:
			errors.append("攻击行包含空资源。")
			continue
		if lane.lane_id == &"" or lane_ids.has(lane.lane_id):
			errors.append("攻击行 ID 为空或重复。")
		if not lane.spawn_position.is_finite() or not lane.mower_position.is_finite() \
				or lane.mower_kind not in [0, 1, 2] \
				or not CharacterRegistry.ZombieRowType.values().has(lane.spawn_type):
			errors.append("攻击行生成参数无效。")
		lane_ids[lane.lane_id] = true
	var by_id: Dictionary = {} # 全部地块，随后验证邻接引用。
	var addresses: Dictionary = {} # 稀疏逻辑地址不能重复。
	var cells := definition.cell_definitions() # 本次校验使用同一展开结果。
	if cells.is_empty():
		errors.append("战场缺少种植点。")
	for cell: BoardCellDefinition in cells: # 地块身份及几何。
		if cell == null:
			errors.append("种植点包含空资源。")
			continue
		if cell.cell_id == &"" or by_id.has(cell.cell_id) or addresses.has(cell.address):
			errors.append("种植点 ID 为空、重复或逻辑地址重复。")
		if cell.address.x < 0 or cell.address.x >= lanes.size() or cell.address.y < 0:
			errors.append("种植点逻辑地址越界：%s" % cell.cell_id)
		if not surface_ids.has(cell.surface_id) or not terrain_ids.has(cell.terrain_id):
			errors.append("种植点引用未知平台/地形：%s" % cell.cell_id)
		if not cell.position.is_finite() or not cell.size.is_finite() \
				or cell.size.x <= 0.0 or cell.size.y <= 0.0 or not is_finite(cell.ground_height):
			errors.append("种植点几何无效：%s" % cell.cell_id)
		if not cell.hit_polygon.is_empty():
			if cell.hit_polygon.size() < 3 or Geometry2D.triangulate_polygon(cell.hit_polygon).is_empty():
				errors.append("种植点交互多边形无效：%s" % cell.cell_id)
			for point: Vector2 in cell.hit_polygon: # 顶点必须属于声明的局部矩形。
				if not point.is_finite() or point.x < 0.0 or point.y < 0.0 \
						or point.x > cell.size.x or point.y > cell.size.y:
					errors.append("交互多边形越出格子边界：%s" % cell.cell_id)
		by_id[cell.cell_id] = cell
		addresses[cell.address] = true
	for cell: BoardCellDefinition in cells: # 验证跨点关系，不允许跨运动平台拉伸多格植物。
		if cell == null:
			continue
		var references: Array[StringName] = cell.neighbor_ids.duplicate() # 本格显式邻接引用。
		if cell.right_neighbor_id != &"":
			references.append(cell.right_neighbor_id)
		for target_id: StringName in references: # 同平台且不指向自身。
			var target: BoardCellDefinition = by_id.get(target_id) # 目标声明。
			if target == null or target == cell or target.surface_id != cell.surface_id:
				errors.append("种植点邻接引用无效：%s -> %s" % [cell.cell_id, target_id])
		if cell.right_neighbor_id != &"" and by_id.has(cell.right_neighbor_id):
			var right: BoardCellDefinition = by_id[cell.right_neighbor_id] # 多格植物仍必须属于同一攻击行。
			if right.address.x != cell.address.x:
				errors.append("多格植物的向右邻格不能跨攻击行：%s" % cell.cell_id)
	return errors
