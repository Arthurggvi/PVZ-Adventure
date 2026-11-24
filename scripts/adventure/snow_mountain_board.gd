## 边境雪山棋盘：用地板原图的格线和两段坡面生成同一套种植、点选及攻击行坐标。
extends BoardDefinition

## 2172×724 天幕及格线参考画布的世界原点。
const ART_ORIGIN := Vector2(-150.0, 0.0)
## 按战斗镜头 0.8 倍缩放、1066×600 画面和原图 X=1414 的战区右界换算。
const ART_SCALE := Vector2(1332.5 / 1414.0, 750.0 / 724.0)
## 原图 11 列的实测竖线，最后一条为选卡雪台的左界。
const COLUMN_EDGES: Array[float] = [92.0, 211.0, 330.0, 451.0, 571.0, 690.0, 812.0, 931.0,
	1051.0, 1171.0, 1292.0, 1414.0]
## 将六行格线投影到右侧高台后的原图 Y 坐标，可叠加坡面高度还原实际边界。
const ROW_EDGES: Array[float] = [139.6, 193.9, 248.2, 302.5, 356.8, 411.1, 465.4]
## 两段坡的端点，X 为原图列界，Y 为相对高台的向下位移。端点间的空隙为平段。
const RAMP_POINTS: Array[Vector2] = [Vector2(92.0, 188.8), Vector2(451.0, 94.3),
	Vector2(812.0, 94.3), Vector2(1051.0, 0.0)]
## 脚点距格底的原图像素，保证植物和行走僵尸站在行内。
const FOOT_INSET: float = 18.0
## 正式敌人出生点的原图 X，紧贴战区右边缘之外。
const ENTRY_X: float = 1455.0
## 清洁车标记的原图 X，位于第一列左侧，并为车与失败边界留出触发距离。
const MOWER_X: float = 72.0
## 凯莱赫的完整转阶段最多从下边缘移去三行。
const COLLAPSE_ROWS: int = 3

## 本局独占布局已沉入的行数，包括从轮间存档恢复的行。
var sunk_rows: int = 0

## 一行在真实棋盘中的纵向间距，单位为世界像素。
static func row_stride() -> float:
	return (ROW_EDGES[1] - ROW_EDGES[0]) * ART_SCALE.y

## [param rows] 行沉降后的累计世界位移。
static func descent(rows: int) -> float:
	return row_stride() * rows

## [param remaining_rows] 行的原始近端轮廓，再叠加各坡高度和当前沉降。
static func rim_height(remaining_rows: int) -> float:
	return ROW_EDGES[remaining_rows] * ART_SCALE.y

## 将本局布局提交为已失去 [param count] 行，保留格子的原地址和局部位置。
func set_sunk_rows(count: int) -> void:
	var next_count: int = clampi(count, 0, COLLAPSE_ROWS) # 保留地图声明的最少行数。
	var change: float = descent(next_count - sunk_rows) # 只应用本次变化量。
	sunk_rows = next_count
	for surface: BoardSurfaceDefinition in surfaces: # 雪坡整体随平台降低。
		surface.origin.y += change

## 从 [param snapshot] 保存的行表还原雪坡，再由通用存档协议核对每格身份。
func apply_saved_topology(snapshot: Dictionary) -> void:
	var saved: Variant = snapshot.get("lanes") # 旧档的完整六行对应零沉降。
	if (snapshot.get("version") != 1 or snapshot.get("board_id") != str(board_id)
			or snapshot.get("revision") != revision or not saved is Array):
		return
	var collapse: int = ROW_EDGES.size() - 1 - saved.size() # 保留行的地址没有重排。
	if collapse >= 0 and collapse <= COLLAPSE_ROWS:
		set_sunk_rows(collapse)

## 将素材中的 [param point] 像素换算为主战场局部坐标。
static func art_to_world(point: Vector2) -> Vector2:
	return ART_ORIGIN + point * ART_SCALE

## 返回素材 [param x] 处的向下偏移，左右两端延续外侧平地，单位为原图像素。
static func terrain_offset(x: float) -> float:
	var first_ramp: float = inverse_lerp(RAMP_POINTS[0].x, RAMP_POINTS[1].x, x) # 下坡段的横向进度。
	var second_ramp: float = inverse_lerp(RAMP_POINTS[2].x, RAMP_POINTS[3].x, x) # 上坡段的横向进度。
	return RAMP_POINTS[0].y + (RAMP_POINTS[1].y - RAMP_POINTS[0].y) * clampf(first_ramp, 0.0, 1.0) \
		+ (RAMP_POINTS[3].y - RAMP_POINTS[2].y) * clampf(second_ramp, 0.0, 1.0)

## 返回 [param row] 的高台脚点 Y，单位为原图像素，斜面上再叠加坡度。
static func lane_foot_y(row: int) -> float:
	return ROW_EDGES[row + 1] - FOOT_INSET

## 攻击行沿用高台的水平基线，战斗运行时按横坐标给僵尸叠加地形高度。
func lane_definitions() -> Array[BoardLaneDefinition]:
	var result: Array[BoardLaneDefinition] = [] # 按原图从远到近保存攻击行。
	for row: int in range(ROW_EDGES.size() - 1 - sunk_rows): # 只装配露出地面的攻击行。
		var lane := BoardLaneDefinition.new() # 本行的未投影出生和清洁车标记。
		lane.lane_id = StringName("lane_%d" % row)
		lane.spawn_position = art_to_world(Vector2(ENTRY_X, lane_foot_y(row)))
		lane.mower_position = art_to_world(Vector2(MOWER_X, lane_foot_y(row)))
		lane.spawn_position.y += descent(sunk_rows)
		lane.mower_position.y += descent(sunk_rows)
		lane.mower_kind = 2
		result.append(lane)
	return result

## 两侧分别投影到坡面，生成覆盖绘制格线的四边形与格内脚点。
func cell_definitions() -> Array[BoardCellDefinition]:
	var result: Array[BoardCellDefinition] = [] # 逐行展开的私有棋盘定义。
	for row: int in range(ROW_EDGES.size() - 1 - sunk_rows): # 格内位置不变，随平台统一下沉。
		for column: int in range(COLUMN_EDGES.size() - 1): # 图上从左到右的格列。
			result.append(_make_cell(row, column))
	return result

## 将 [param row] 和 [param column] 的四条格线换算为引擎的局部矩形及命中轮廓。
func _make_cell(row: int, column: int) -> BoardCellDefinition:
	var left_x: float = COLUMN_EDGES[column] # 原图格左界。
	var right_x: float = COLUMN_EDGES[column + 1] # 原图格右界。
	var top_y: float = ROW_EDGES[row] # 高台处的原图上界。
	var bottom_y: float = ROW_EDGES[row + 1] # 高台处的原图下界。
	var left_offset: float = terrain_offset(left_x) # 格左侧的原图高度偏移。
	var right_offset: float = terrain_offset(right_x) # 格右侧的原图高度偏移。
	var foot_offset: float = terrain_offset((left_x + right_x) * 0.5) # 格中心横坐标的原图高度偏移。
	var bounds_top: float = top_y + right_offset # 右侧是画面里更高的一端。
	var row_height: float = (bottom_y - top_y) * ART_SCALE.y # 世界坐标中的行厚度。
	var slant: float = (left_offset - right_offset) * ART_SCALE.y # 同格左右边的世界高差。
	var cell := BoardCellDefinition.new() # 同时提供视觉脚点和水平检测面。
	cell.cell_id = StringName("cell_%d_%d" % [row, column])
	cell.address = Vector2i(row, column)
	cell.terrain_id = &"snow"
	cell.position = art_to_world(Vector2(left_x, bounds_top))
	cell.size = Vector2((right_x - left_x) * ART_SCALE.x, row_height + slant)
	cell.hit_polygon = PackedVector2Array([
		Vector2(0.0, slant),
		Vector2(cell.size.x, 0.0),
		Vector2(cell.size.x, row_height),
		Vector2(0.0, cell.size.y),
	])
	cell.ground_height = foot_offset * ART_SCALE.y
	cell.ground_anchor_y = (lane_foot_y(row) + foot_offset - bounds_top) * ART_SCALE.y
	return cell
