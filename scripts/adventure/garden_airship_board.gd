## 花园飞艇的稀疏棋盘。每块甲板拥有自己的种植点，五条进攻线固定在船体上。
extends BoardDefinition

## 本关平台在通用运动数据上补充种植拓扑和可点击的草皮范围。
const AirshipDeck := preload("res://scripts/adventure/garden_airship_deck.gd")
## 自上而下的固定敌军进攻线数。
const LANE_COUNT: int = 5
## 棋盘从左舷到长桥的逻辑列数，包含悬空缺格。
const COLUMN_COUNT: int = 17
## 第一行甲板上沿的战场 Y 坐标，单位为像素。
const TOP_EDGE: float = 184.0
## 相邻进攻线的垂直间距，独立于装饰边缘。
const ROW_PITCH: float = 81.0
## 敌方大型飞艇内部的僵尸入场横坐标。
const ENEMY_ENTRY_X: float = 1679.0
## 玩家飞艇左舷的失败线横坐标。
const HOME_EDGE_X: float = 40.0
## 地面脚点距格子下沿的距离。
const FOOT_INSET: float = 15.0
## 固定长桥的平台身份，扩展前后的存档共用。
const BRIDGE_ID: StringName = &"bridge"
## 修订 1、2 存档中的长桥逻辑列，从零开始，并保留在其地块 ID 中。
const LEGACY_BRIDGE_COLUMN: int = 10
## 修订 2 长桥的起点，用于迁移已保存的手动运动轨迹。
const LEGACY_BRIDGE_ORIGIN := Vector2(856.5, TOP_EDGE)
## 修订 1、2 均有 5 块四格浮台和 5 格长桥。
const LEGACY_CELL_COUNT: int = 25

## 在通用身份及几何校验前，确认每个甲板都能展开成 5×17 范围内的种植点。
func validate() -> PackedStringArray:
	var bounds := Rect2i(0, 0, COLUMN_COUNT, LANE_COUNT) # 棋盘范围按列、行表达。
	for surface: BoardSurfaceDefinition in surfaces: # 编辑器可能误配为普通平台或空资源。
		var deck := surface as AirshipDeck # 只有本关甲板才声明草皮与逻辑区域。
		if deck == null or not deck.grid_rect.has_area() or not bounds.encloses(deck.grid_rect):
			return PackedStringArray(["飞艇甲板必须声明棋盘范围内的有效种植区域。"])
	return super()

## 将各甲板局部草皮划分为种植点；稳定 ID 和攻击行取自初始逻辑区域。
func cell_definitions() -> Array[BoardCellDefinition]:
	var result: Array[BoardCellDefinition] = [] # 只登记甲板上的有效种植点。
	for deck: AirshipDeck in surfaces: # 同一个资源也用于装配实际移动节点及其美术。
		var extent: Vector2 = deck.turf_rect.size / Vector2(deck.grid_rect.size) # 草皮上每格的宽高。
		for y: int in range(deck.grid_rect.size.y): # 甲板内的局部行号。
			for x: int in range(deck.grid_rect.size.x): # 甲板内的局部列号。
				var cell := BoardCellDefinition.new() # 局部命中范围和稳定的逻辑身份。
				cell.address = Vector2i(deck.grid_rect.position.y + y, deck.grid_rect.position.x + x)
				var id_column: int = LEGACY_BRIDGE_COLUMN if deck.surface_id == BRIDGE_ID else cell.address.y # 旧长桥格保留原 ID。
				# 旧长桥所在列新增的浮台格使用独立 ID。
				var id_format: String = "deck_%d_%d" if cell.address.y == LEGACY_BRIDGE_COLUMN else "cell_%d_%d"
				cell.cell_id = StringName(id_format % [cell.address.x, id_column])
				cell.surface_id = deck.surface_id
				cell.position = deck.turf_rect.position + Vector2(x, y) * extent
				cell.size = extent
				cell.ground_anchor_y = (y + 1) * ROW_PITCH - FOOT_INSET - cell.position.y
				result.append(cell)
	return result

## 在 [param snapshot] 的副本中保留旧格子和平台进度，迁移长桥列并补齐新甲板。
## 修订 1 的共用平台从起点开始，修订 2 的新增浮台沿用旧浮台相位。未识别的数据留给公共预检拒绝。
func upgrade_saved_state(snapshot: Dictionary) -> Dictionary:
	var old_revision: Variant = snapshot.get("revision") # 只接纳本关发布过的两个旧布局。
	if revision != 3 or snapshot.get("version") != 1 or old_revision not in [1, 2] \
			or snapshot.get("board_id") != str(board_id):
		return snapshot
	var shared_surface: bool = old_revision == 1 # 首版共用 ground，第二版单独保存五块浮台和长桥。
	var old_surfaces: Variant = snapshot.get("surfaces") # 旧版的完整平台位姿表。
	var old_cells: Variant = snapshot.get("cells") # 旧版的完整地块表。
	if not old_surfaces is Dictionary or old_surfaces.size() != (1 if shared_surface else 6) \
			or not old_cells is Dictionary or old_cells.size() != LEGACY_CELL_COUNT:
		return snapshot
	var phase_source: Variant = old_surfaces.get("ground" if shared_surface else "upper_port") # 新浮台的自动行程参考左侧旧浮台。
	if not phase_source is Dictionary or not BoardSurface.accepts_state(phase_source):
		return snapshot
	var upgraded_cells: Dictionary = {} # 全部地块迁移成功后再组装快照。
	for cell: BoardCellDefinition in cell_definitions(): # 公共协议仍检查地形及行为状态。
		var key: String = str(cell.cell_id) # 以存档保存的稳定 ID 查找。
		var surface_id: String = str(cell.surface_id) # 修订 3 中该格所属的平台。
		var bridge_cell: bool = cell.surface_id == BRIDGE_ID # 旧长桥只移动逻辑列，身份不变。
		var entry: Dictionary = {"terrain": str(cell.terrain_id), "behavior": {}} # 新增地块从空草皮开始。
		if bridge_cell or cell.address.y < LEGACY_BRIDGE_COLUMN:
			var old_address := Vector2i(cell.address.x, LEGACY_BRIDGE_COLUMN) if bridge_cell else cell.address # 校对旧逻辑位置。
			var old_entry: Variant = old_cells.get(key) # 旧格必须完整保留其地形及行为数据。
			if not old_entry is Dictionary or old_entry.get("address") != old_address \
					or old_entry.get("surface") != ("ground" if shared_surface else surface_id):
				return snapshot
			entry = old_entry.duplicate(true)
		entry["address"] = cell.address
		entry["surface"] = surface_id
		upgraded_cells[key] = entry
	var poses: Dictionary = {} # 原平台保留各自状态，新增浮台使用自动往返。
	for deck: AirshipDeck in surfaces: # 长桥的手动轨迹随长桥起点平移。
		var key: String = str(deck.surface_id) # 每个平台保存一份独立位姿。
		if deck.surface_id != BRIDGE_ID and deck.grid_rect.position.x >= LEGACY_BRIDGE_COLUMN:
			poses[key] = {"elapsed": 0.0 if shared_surface else phase_source["elapsed"],
				"manual": false, "from": Vector2.ZERO, "target": Vector2.ZERO,
				"duration": 0.0, "move_elapsed": 0.0}
			continue
		var old_pose: Variant = phase_source if shared_surface else old_surfaces.get(key) # 首版轨迹使用共用平台的坐标。
		if not old_pose is Dictionary or not BoardSurface.accepts_state(old_pose):
			return snapshot
		var pose: Dictionary = old_pose.duplicate() # 转换位姿时保留原存档。
		if shared_surface:
			pose["elapsed"] = 0.0
		if pose["manual"]:
			var shift := Vector2.ZERO # 修订 2 的旧浮台轨迹仍使用原来的世界坐标。
			if shared_surface:
				shift = deck.origin
			elif deck.surface_id == BRIDGE_ID:
				shift = deck.origin - LEGACY_BRIDGE_ORIGIN
			pose["from"] = Vector2(pose["from"]) + shift
			pose["target"] = Vector2(pose["target"]) + shift
		poses[key] = pose
	var upgraded: Dictionary = snapshot.duplicate(true) # 原存档仍供实体事务核对当时的行列。
	upgraded["cells"] = upgraded_cells
	upgraded["surfaces"] = poses
	upgraded["revision"] = revision
	return upgraded

## 五条连续进攻线始终存在；悬空缺口不改变出生行与攻击行的高度。
func lane_definitions() -> Array[BoardLaneDefinition]:
	var result: Array[BoardLaneDefinition] = [] # 与五行逻辑地址一一对应的进攻线。
	for row: int in range(LANE_COUNT): # 行进基线不跟随浮台。
		var lane := BoardLaneDefinition.new() # 本行敌军进入点及失败边界位置。
		var baseline: float = TOP_EDGE + (row + 1) * ROW_PITCH - FOOT_INSET # 行脚点。
		lane.lane_id = StringName("lane_%d" % row)
		lane.spawn_type = CharacterRegistry.ZombieRowType.Land
		lane.spawn_position = Vector2(ENEMY_ENTRY_X, baseline)
		lane.mower_position = Vector2(HOME_EDGE_X, baseline)
		lane.mower_kind = 2
		result.append(lane)
	return result
