## 在子管理器登记实体前装配战场；背景和行标记入树后可以对齐旧水路。
extends RefCounted
class_name BoardSceneAdapter

## 从 [param game] 的关卡定义装配；旧场景只适配一次，之后与新布局共用运行时。
static func install(game: MainGameManager) -> BoardRuntime:
	var board := BoardRuntime.new() # 当前战斗独占索引。
	var plant_root := game.get_node_or_null("PlantCellsRoot") as Node2D # 原种植根节点。
	var zombie_root := game.get_node_or_null("ZombiesRoot") as Node2D # 原攻击行根节点。
	if plant_root == null or zombie_root == null:
		push_error("战场缺少种植/攻击行挂载根。")
		return board
	var level: ResourceLevelData = game.game_para # 入树前已经绑定的关卡参数。
	if level.board_definition == null:
		_adopt_legacy(game, board, plant_root, zombie_root)
	else:
		var definition := level.board_definition.duplicate(true) as BoardDefinition # 禁止污染共享布局。
		if level.game_round != 1 and level.save_game_data_main_game != null:
			var saved: ResourceSaveGamePlantCellManager = level.save_game_data_main_game.plant_cell_manager_data # 先恢复形状，再按常规校验占用。
			if saved != null:
				definition.apply_saved_topology(saved.board_state)
		var errors: PackedStringArray = definition.validate() # 全量预检。
		if not level.terrain_rows.is_empty():
			errors.append("board_definition 与旧 terrain_rows 不得同时定义地形。")
		if not errors.is_empty():
			push_error("战场布局无效：" + "; ".join(errors))
			return board
		_build_definition(game, board, definition, plant_root, zombie_root)
	return board

## 在 [param game] 的背景和攻击行入树后，用背景水域对齐旧棋盘的水路出生和清洁车位置。
## 显式棋盘已经声明完整行坐标，直接使用其定义。
static func align_legacy_water_lanes(game: MainGameManager) -> void:
	var profile: WaterSurfaceProfile = game.game_para.water_surface_profile # 水域及近岸行基准。
	if game.board.definition != null or profile == null or profile.lane_baseline_inset <= 0.0:
		return
	var background: Sprite2D = game.get_node(^"%Background") # 底图像素坐标的实际参照节点。
	var zombie_root: Node2D = game.get_node(^"ZombiesRoot") # 旧场景的攻击行容器。
	# 经过视口坐标转换，保留背景 CanvasLayer 与主战场之间的偏移。
	var board_to_background: Transform2D = background.get_global_transform_with_canvas().affine_inverse() \
		* game.get_global_transform_with_canvas()
	var background_to_board: Transform2D = board_to_background.affine_inverse() # 水域像素坐标到棋盘。
	for index: int in range(game.board.lanes.size()): # 和攻击行节点的登记顺序一致。
		var lane: BoardLaneDefinition = game.board.lanes[index] # 本局独占的旧行定义。
		if lane.spawn_type != CharacterRegistry.ZombieRowType.Pool:
			continue
		var marker: Marker2D = zombie_root.get_child(index).get_node(^"ZombieCreatePosition") # 正式出生标记。
		var source_position: Vector2 = board_to_background * game.to_local(marker.global_position) # 原行高在底图中的位置。
		source_position.y = profile.lane_baseline_y(source_position.y)
		lane.spawn_position = background_to_board * source_position
		lane.mower_position.y = lane.spawn_position.y
		marker.global_position = game.to_global(lane.spawn_position)

## 适配旧 [param plant_root] / [param zombie_root]，保留原关节点和最终逻辑顺序。
static func _adopt_legacy(game: MainGameManager, board: BoardRuntime,
		plant_root: Node2D, zombie_root: Node2D) -> void:
	if not Global.main_scene_registry.matches_legacy_spawn_rows(game.game_para.game_sences, zombie_root):
		push_error("基础战场行布局与 MainSceneRegistry 静态行协议不一致。")
		return
	var rows: Array[Node] = plant_root.get_children() # 读取原行节点，保持已有场景路径与 owner。
	var types: Array[CharacterRegistry.ZombieRowType] = game.game_para.terrain_rows # 旧行覆盖协议。
	if rows.size() != zombie_root.get_child_count() or (not types.is_empty() and types.size() != rows.size()):
		push_error("旧战场种植行、攻击行或地形覆盖数量不一致。")
		return
	var lanes: Array[BoardLaneDefinition] = [] # 从现有标记读取，不另造坐标常量。
	for index: int in range(zombie_root.get_child_count()): # 保留原攻击行身份。
		var row := zombie_root.get_child(index) as ZombieRow # 原攻击行节点。
		if row == null or not row.has_node("ZombieCreatePosition"):
			return
		if not types.is_empty():
			row.zombie_row_type = types[index]
		var lane := BoardLaneDefinition.new() # 当前行静态快照。
		var marker := row.get_node("ZombieCreatePosition") as Marker2D # 现有出生标记。
		lane.lane_id = StringName("lane_%d" % index)
		lane.spawn_type = row.zombie_row_type
		lane.spawn_position = zombie_root.transform * (row.get_transform() * marker.position)
		lane.mower_position = Vector2(20.0, lane.spawn_position.y)
		lane.mower_kind = 2 if game.game_para.game_sences == MainSceneRegistry.MainScenes.MainGameRoof else 0
		if lane.spawn_type == CharacterRegistry.ZombieRowType.Pool:
			lane.mower_kind = 1
		lanes.append(lane)
	board.board_id = StringName("legacy_%d" % game.game_para.game_sences)
	board.configure_lanes(lanes)
	for kind: int in [0, 1, 2]: # 旧种植能力目录。
		var terrain := BoardTerrainDefinition.legacy(kind) # 战斗私有资源。
		board.terrains[terrain.terrain_id] = terrain
	var surface_data := BoardSurfaceDefinition.new() # 静态默认平台，允许显式整体移动。
	surface_data.origin = plant_root.position
	plant_root.set_script(load("res://scripts/battle/board/board_surface.gd"))
	var surface := plant_root as BoardSurface # 直接复用原根节点，不重挂任何旧行。
	surface.configure(surface_data, game)
	surface.process_mode = Node.PROCESS_MODE_PAUSABLE
	board.surfaces[surface_data.surface_id] = surface
	for index: int in range(rows.size()): # 原行的矩形锚点保持不变。
		var row := rows[index] as CanvasItem # 行节点及渲染顺序。
		row.z_index = index * 50 + 10
		for column: int in range(row.get_child_count()): # 保留旧管理器反向枚举后的最终列号。
			var cell := row.get_child(row.get_child_count() - 1 - column) as PlantCell # 现有格子。
			if cell == null:
				push_error("旧种植行包含非 PlantCell 节点。")
				return
			if not types.is_empty():
				cell.plant_cell_type = PlantCell.PlantCellType.Pool if types[index] == CharacterRegistry.ZombieRowType.Pool else PlantCell.PlantCellType.Grass
			var data := BoardCellDefinition.new() # 适配后的稳定身份，不保留第二份占用。
			data.cell_id = StringName("cell_%d_%d" % [index, column])
			data.address = Vector2i(index, column)
			data.terrain_id = [&"grass", &"pool", &"roof"][cell.plant_cell_type]
			cell.legacy_ground_height = true
			board.register_cell(cell, data)
	board.finish_configuration()

## 装配 [param definition]；全部预检完成后才替换实例中的旧行，不改场景资源文件。
static func _build_definition(game: MainGameManager, board: BoardRuntime, definition: BoardDefinition,
		plant_root: Node2D, zombie_root: Node2D) -> void:
	plant_root.transform = Transform2D.IDENTITY
	zombie_root.transform = Transform2D.IDENTITY
	board.definition = definition
	board.board_id = definition.board_id
	board.revision = definition.revision
	for child: Node in plant_root.get_children(): # 删除的是本次场景实例的旧布局节点。
		plant_root.remove_child(child)
		child.free()
	for child: Node in zombie_root.get_children(): # 替换实例中的旧攻击行。
		zombie_root.remove_child(child)
		child.free()
	board.configure_lanes(definition.lane_definitions())
	for terrain: BoardTerrainDefinition in definition.terrains: # 注册独占地形目录。
		board.terrains[terrain.terrain_id] = terrain
	for data: BoardSurfaceDefinition in definition.surfaces: # 每个平台拥有自己的移动生命周期。
		_create_surface(game, board, plant_root, data)
	var scene := load("res://scenes/ui/plant_cell.tscn") as PackedScene # 复用正式种植点场景。
	for data: BoardCellDefinition in definition.cell_definitions(): # 稀疏布局无需空节点填格。
		var cell := scene.instantiate() as PlantCell # 正式格子实例，沿用所有种植事务。
		cell.name = "Cell_%d" % board.cells().size()
		cell.set_anchors_preset(Control.PRESET_TOP_LEFT)
		cell.position = data.position
		cell.size = data.size
		cell.z_index = data.address.x * 50 + 10
		board.register_cell(cell, data)
		board.surfaces[data.surface_id].add_child(cell)
	for index: int in range(board.lanes.size()): # 与种植点数量独立的固定攻击行。
		var row: Node = Node2D.new() # 同一脚本也承载于旧水路 Panel，因此从共同 Node 类型绑定。
		row.set_script(load("res://scripts/main_game_item/zombies_row.gd"))
		row.name = "ZombieRow_%d" % index
		(row as ZombieRow).zombie_row_type = board.lanes[index].spawn_type
		var marker := Marker2D.new() # 出生标记使用现有 ZombieManager 协议。
		marker.name = "ZombieCreatePosition"
		marker.position = board.lanes[index].spawn_position
		row.add_child(marker)
		zombie_root.add_child(row)
	board.finish_configuration()

## 创建 [param data] 对应平台，挂到 [param parent]；只由装配器调用。
static func _create_surface(game: MainGameManager, board: BoardRuntime,
		parent: Node2D, data: BoardSurfaceDefinition) -> BoardSurface:
	var surface := BoardSurface.new() # 平台实例。
	surface.name = "Surface_%d" % board.surfaces.size()
	surface.process_mode = Node.PROCESS_MODE_PAUSABLE
	surface.configure(data, game)
	parent.add_child(surface)
	board.surfaces[data.surface_id] = surface
	return surface
