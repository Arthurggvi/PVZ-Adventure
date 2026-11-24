## 造冰车向左铺冰并登记覆盖格。雪坡上的冰面按实际地形折弯。
extends Node2D
class_name IceRoad

## 原版冰面从冰缘左端右移 13 像素处开始平铺。
const TILE_START_OFFSET := 13.0

## 普通地面的平铺冰面，固定右端并向左伸长。
@onready var texture_rect: TextureRect = $TextureRect
## 车停止铺冰后用于融化的倒计时。
@onready var ice_road_disappear_timer: Timer = $IceRoadDisappearTimer
## 冰道向前延伸的一端，使用原版冰缘贴图。
@onready var ice_cap: Sprite2D = $IceCap
## 本冰道所属关卡的管理器，切场时仍引用原来的冰道登记。
var _zombie_manager: ZombieManager
## 雪山的地形高度来源；普通地面和屋顶的平段铺冰时为空。
var _terrain_slope: MainGameSlope
## 雪坡冰面沿世界 Y 轴的厚度，单位为世界像素。
var _terrain_depth: float

## 冰冻生成结束后30秒消失
@export var exist_time:float = 30

## 当前冰道行
var lane :int
## 当前行植物格子(植物格子顺序为从左到右)
var curr_lane_plant_cells : Array
## 植物格子到达的位置即算覆盖该格子(覆盖格子1/3的位置)
var x_plant_cell_target:Array[float]
## 当前覆盖的格子索引(从size()到0,倒序)
var curr_i_plant_cell := 0
## 冰道最左边x值
var left_x:float

## 冰道消失信号
signal signal_ice_road_disappear

## [param curr_lane] 是冰道铺设的行号。先登记并同步初始覆盖的地块。
func ice_road_init(curr_lane: int) -> void:
	self.lane = curr_lane
	_zombie_manager = Global.main_game.zombie_manager
	self.curr_lane_plant_cells = Global.main_game.plant_cell_manager.all_plant_cells[lane]
	# plant_cell 是同行从左到右的种植格，冰面覆盖三分之二处即锁定种植。
	for plant_cell:PlantCell in self.curr_lane_plant_cells:
		x_plant_cell_target.append(plant_cell.global_position.x + plant_cell.size.x*2/3)
	curr_i_plant_cell = x_plant_cell_target.size()
	_zombie_manager.all_ice_roads[lane].append(self)
	var terrain: MainGameSlope = Global.main_game.main_game_slope # 雪坡和僵尸共用多段高度采样。
	if is_instance_valid(terrain) and terrain.sample_walking_height and not curr_lane_plant_cells.is_empty():
		_bind_terrain(terrain)
	left_x = texture_rect.global_position.x
	extend_to(left_x - texture_rect.size.x * texture_rect.get_global_transform().x.length())

## [param world_x] 是当前车尾的世界 X 坐标。冰道固定右端并只向左铺设。
func extend_to(world_x: float) -> void:
	if world_x >= left_x:
		return
	left_x = world_x
	if is_instance_valid(_terrain_slope):
		queue_redraw()
	else:
		texture_rect.size.x = maxf(0.0,
				(texture_rect.global_position.x - left_x) / texture_rect.get_global_transform().x.length() - TILE_START_OFFSET)
		ice_cap.global_position = Vector2(left_x, texture_rect.global_position.y)
	# 一帧跨过多格时逐格登记，直到左端尚未覆盖下一格。
	while curr_i_plant_cell > 0 and left_x < x_plant_cell_target[curr_i_plant_cell - 1]:
		curr_i_plant_cell -= 1
		# plant_cell 是刚被冰道覆盖的地块。
		var plant_cell:PlantCell = curr_lane_plant_cells[curr_i_plant_cell]
		plant_cell.add_new_ice_road(self)

## 用本行右端的地格定位冰道。[param terrain] 提供冰道各处的实际高差。
func _bind_terrain(terrain: MainGameSlope) -> void:
	_terrain_slope = terrain
	var right_cell: PlantCell = curr_lane_plant_cells.back() # 雪山最右格在平坦高台，可作整行基准。
	var bounds: Rect2 = right_cell.get_global_rect() # 已随本局地板下沉的世界坐标及实际行高。
	var center: Vector2 = bounds.get_center() # 冰道居中铺在同一行。
	_terrain_depth = minf(bounds.size.y, texture_rect.size.y * get_global_transform().y.length())
	global_position.y = center.y - _terrain_depth * 0.5 \
			+ terrain.get_all_slope_y(global_position.x) - terrain.get_all_slope_y(center.x)
	texture_rect.hide()
	ice_cap.hide()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

## 先画平铺冰面，再画覆盖冰面左端的冰缘，两者都在地形折点处续接。
func _draw() -> void:
	if not is_instance_valid(_terrain_slope):
		return
	var right_x: float = texture_rect.global_position.x # 冰面固定的世界右端。
	var x_scale: float = get_global_transform().x.length() # 原贴图像素对应的世界宽度。
	var tile_start: float = left_x + TILE_START_OFFSET * x_scale # 留出冰缘与平铺冰面的原有重叠。
	var cap_end: float = left_x + ice_cap.texture.get_width() * x_scale # 冰缘保持原贴图的横向比例。
	_draw_terrain_strip(texture_rect.texture, tile_start, right_x, right_x, x_scale)
	_draw_terrain_strip(ice_cap.texture, left_x, cap_end, left_x, x_scale)

## 把 [param texture] 铺在世界坐标 [param start_x] 到 [param end_x] 之间。
## [param texture_origin_x] 锚定横向采样位置，[param x_scale] 为每个原图像素的世界宽度。
func _draw_terrain_strip(texture: Texture2D, start_x: float, end_x: float,
		texture_origin_x: float, x_scale: float) -> void:
	if end_x <= start_x or is_equal_approx(start_x, end_x):
		return
	var cuts: Array[float] = [] # 从左到右记录区间内的坡脚、坡顶及右端。
	for part: Slope in _terrain_slope.all_slopes: # 坡段的世界范围已按横坐标排好。
		for x: float in [part.slope_global_pos_x_range.x, part.slope_global_pos_x_range.y]: # 平地与斜坡的接点。
			if start_x < x and x < end_x and not (is_equal_approx(x, start_x) or is_equal_approx(x, end_x)):
				cuts.append(x)
	cuts.append(end_x)
	var to_road: Transform2D = get_global_transform().affine_inverse() # 将地形世界点转换为冰道本地画布位置。
	var base_y: float = global_position.y - _terrain_slope.get_all_slope_y(global_position.x) # 去掉右端坡高后的上沿基准。
	var down: Vector2 = to_road.basis_xform(Vector2(0.0, _terrain_depth)) # 两侧都沿世界 Y 轴延伸同一个行内宽度。
	var world_width: float = texture.get_width() * x_scale # 一个完整贴图重复周期的世界跨度。
	var previous_top: Vector2 = to_road * Vector2(start_x, base_y + _terrain_slope.get_all_slope_y(start_x)) # 上一段右上角。
	var previous_u: float = (start_x - texture_origin_x) / world_width # 共用同一个横向采样位置，纹理在折点处衔接。
	for x: float in cuts: # 每段内高度只线性变化，可用一个四边形精确覆盖。
		var top: Vector2 = to_road * Vector2(x, base_y + _terrain_slope.get_all_slope_y(x)) # 该段右上角。
		var u: float = (x - texture_origin_x) / world_width # 冰道延长时，已有平铺部分的取样位置固定。
		draw_polygon(PackedVector2Array([previous_top, top, top + down, previous_top + down]),
				PackedColorArray([Color.WHITE]),
				PackedVector2Array([Vector2(previous_u, 0.0), Vector2(u, 0.0), Vector2(u, 1.0), Vector2(previous_u, 1.0)]),
				texture)
		previous_top = top
		previous_u = u

## 冰道已经进入可种植区域时允许雪橇登场。
func has_board_ice() -> bool:
	return not is_queued_for_deletion() and curr_i_plant_cell < x_plant_cell_target.size()

## 开始计算消失计时器
func start_disappear_timer():
	if is_inside_tree() and ice_road_disappear_timer.is_stopped():
		ice_road_disappear_timer.start(exist_time)

## [param seconds] 是雪橇经过时保留冰道的最短剩余秒数。
## 仅延长已经开始融化的冰道，仍在铺设的冰道无需启动倒计时。
func extend_remaining_time(seconds: float) -> void:
	if not ice_road_disappear_timer.is_stopped() and ice_road_disappear_timer.time_left < seconds:
		ice_road_disappear_timer.start(seconds)

## 冰道消失
func _on_ice_road_disappear_timer_timeout() -> void:
	ice_road_disappear()

func ice_road_disappear():
	if is_instance_valid(_zombie_manager) and lane < _zombie_manager.all_ice_roads.size():
		_zombie_manager.all_ice_roads[lane].erase(self)
	signal_ice_road_disappear.emit()
	queue_free()
