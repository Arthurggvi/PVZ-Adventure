## 生成规则矩阵，可用测量过的格线修正各格边界。
extends BoardDefinition
class_name BoardGridDefinition

## 逻辑行列数；x 行、y 列，不改变任何已有生产关卡。
@export var dimensions := Vector2i(5, 9)
## 首格在平台内的左上角，单位像素。
@export var grid_origin := Vector2(40.0, 80.0)
## 行列之间的像素间距；x 列间距、y 行间距。
@export var pitch := Vector2(80.0, 100.0)
## 每格交互尺寸，不等同于植物美术尺寸。
@export var cell_size := Vector2(76.0, 95.0)
## 可选列边界，平台局部 X 像素，从左至右含外边界。空数组按 [member pitch] 生成。
@export var column_edges := PackedFloat32Array()
## 可选行边界，平台局部 Y 像素，从上至下含外边界。空数组按 [member pitch] 生成。
@export var row_edges := PackedFloat32Array()
## 生成格子所属平台 ID，须在 surfaces 中声明。
@export var grid_surface_id: StringName = &"ground"
## 默认地形，cells 可按 address 覆盖个别格子。
@export var default_terrain_id: StringName = &"grass"
## 未显式提供 lanes 时的出怪/清洁车横坐标。
@export var spawn_x: float = 850.0
## 默认清洁车横坐标。
@export var mower_x: float = 20.0
## 未显式提供 lanes 时的行地形。水路使用泳池清洁车。
@export var default_lane_spawn_type: CharacterRegistry.ZombieRowType = CharacterRegistry.ZombieRowType.Land
## 生成行的脚点距该行底边的像素数，水路可据此对齐入水位置。
@export var lane_baseline_inset: float = 0.0

## 按行列生成稳定 ID；单格覆盖使用相同 address，但身份由覆盖资源显式声明。
func cell_definitions() -> Array[BoardCellDefinition]:
	var result: Array[BoardCellDefinition] = [] # 一次展开的私有结果。
	var has_columns: bool = not column_edges.is_empty() # 该轴来自测量格线。
	var has_rows: bool = not row_edges.is_empty() # 另一轴仍可沿用规则间距。
	if dimensions.x < 1 or dimensions.y < 1 \
			or (has_columns and column_edges.size() != dimensions.y + 1) \
			or (has_rows and row_edges.size() != dimensions.x + 1):
		return result
	for row: int in range(dimensions.x): # 零起点逻辑行。
		var top: float = row_edges[row] if has_rows else grid_origin.y + row * pitch.y # 行上边。
		var height: float = row_edges[row + 1] - top if has_rows else cell_size.y # 交互高度。
		for column: int in range(dimensions.y): # 零起点逻辑列。
			var left: float = column_edges[column] if has_columns else grid_origin.x + column * pitch.x # 列左边。
			var width: float = column_edges[column + 1] - left if has_columns else cell_size.x # 交互宽度。
			var cell := BoardCellDefinition.new() # 格子生成数据。
			cell.cell_id = StringName("cell_%d_%d" % [row, column])
			cell.address = Vector2i(row, column)
			cell.surface_id = grid_surface_id
			cell.position = Vector2(left, top)
			cell.size = Vector2(width, height)
			cell.terrain_id = default_terrain_id
			for override: BoardCellDefinition in cells: # 显式局部地形/坐标覆盖。
				if override != null and override.address == cell.address:
					cell = override
			result.append(cell)
	return result

## 显式 lanes 优先；否则生成水平攻击行，与平台运动相互独立。
func lane_definitions() -> Array[BoardLaneDefinition]:
	if not lanes.is_empty():
		return lanes
	var result: Array[BoardLaneDefinition] = [] # 规则布局的默认攻击行。
	if not row_edges.is_empty() and row_edges.size() != dimensions.x + 1:
		return result
	var origin_y: float = 0.0 # 自动生成行只匹配平台初始高度，不跟随其后续运动。
	for surface: BoardSurfaceDefinition in surfaces: # 指定平台的初始世界偏移。
		if surface != null and surface.surface_id == grid_surface_id:
			origin_y = surface.origin.y
			break
	for row: int in range(maxi(0, dimensions.x)): # 零起点行号。
		var lane := BoardLaneDefinition.new() # 本行的固定出生/清洁车位置。
		var bottom: float = grid_origin.y + row * pitch.y + cell_size.y if row_edges.is_empty() else row_edges[row + 1] # 平台内行底边。
		lane.lane_id = StringName("lane_%d" % row)
		lane.spawn_type = default_lane_spawn_type
		lane.spawn_position = Vector2(spawn_x, origin_y + bottom - lane_baseline_inset)
		lane.mower_position = Vector2(mower_x, lane.spawn_position.y)
		lane.mower_kind = 1 if lane.spawn_type == CharacterRegistry.ZombieRowType.Pool else 0
		result.append(lane)
	return result
