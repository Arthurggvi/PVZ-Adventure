extends Node2D
class_name IceRoad
## 冰道使用TextureRect节点,
## 为了方便使用,左右反过来的(scale=[-1,1]),位置固定,修改大小,从而延申冰道
## 使用事件总线推送当前冰道,让plant_cell连接信号

## 原版冰面从冰缘左端右移 13 像素处开始平铺。
const TILE_START_OFFSET := 13.0

@onready var texture_rect: TextureRect = $TextureRect
@onready var ice_road_disappear_timer: Timer = $IceRoadDisappearTimer
## 冰道向前延伸的一端，使用原版冰缘贴图。
@onready var ice_cap: Sprite2D = $IceCap
## 本冰道所属关卡的管理器，切场时仍引用原来的冰道登记。
var _zombie_manager: ZombieManager

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
	left_x = texture_rect.global_position.x
	extend_to(left_x - texture_rect.size.x * texture_rect.get_global_transform().x.length())

## [param world_x] 是当前车尾的世界 X 坐标。冰道固定右端并只向左铺设。
func extend_to(world_x: float) -> void:
	if world_x >= left_x:
		return
	left_x = world_x
	texture_rect.size.x = maxf(0.0,
			(texture_rect.global_position.x - left_x) / texture_rect.get_global_transform().x.length() - TILE_START_OFFSET)
	ice_cap.global_position = Vector2(left_x, texture_rect.global_position.y)
	# 一帧跨过多格时逐格登记，直到左端尚未覆盖下一格。
	while curr_i_plant_cell > 0 and left_x < x_plant_cell_target[curr_i_plant_cell - 1]:
		curr_i_plant_cell -= 1
		# plant_cell 是刚被冰道覆盖的地块。
		var plant_cell:PlantCell = curr_lane_plant_cells[curr_i_plant_cell]
		plant_cell.add_new_ice_road(self)

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
