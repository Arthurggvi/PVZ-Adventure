## 同一世界风场驱动远中雪、远景散射和贴坡雪尘，近景独立受底行保护。
extends Node
class_name SnowStormRenderer

## 角色前方的世界近雪和薄雾，镜头雪仍由独立视口层负责。
var _near: ColorRect
## 战斗前景以下的远中雪画面。
var _air: ColorRect
## 远雪、中雪、近雪、冰粒的格距（世界像素），对应着色器同名常量，切档不改网格。
const WORLD_SPACING := Vector4(27.0, 46.0, 184.0, 112.0)
## 由远到近的风速视差。冰粒由水平风主导。
const WIND_SCALE := Vector4(0.42, 0.77, 1.26, 1.85)
## 各深度的竖向落速比例，避免同时变成相同角度的线条。
const FALL_SCALE := Vector4(0.65, 1.00, 0.92, 0.40)
## 四个独立雪层的有界世界像素位移，低档仍推进隐藏层。
var _travel: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
## 记录本帧四种实际速度的方向，不在每帧分配容器。
var _direction: Array[Vector2] = [Vector2.DOWN, Vector2.DOWN, Vector2.DOWN, Vector2.DOWN]
## 贴地风的归一化循环距离。
var _drift: float = 0.0
## 每层雪花每个方向的哈希周期格数，须与着色器一致。
const GRID_PERIOD: float = 128.0

## 以 [param game] 的实际棋盘及 [param backdrop] 的世界范围装配；[param profile] 只提供颜色。
func configure(game: MainGameManager, backdrop: Sprite2D, profile: SnowVisualProfile) -> void:
	var bounds: Rect2 = (backdrop.get_global_transform() * backdrop.get_rect()).grow(18.0) # 扩到地板上缘和右侧预览画幅。
	var last_lane: Array[PlantCell] = game.board.row_cells(game.board.extent.x - 1) # 最下行现有交互几何。
	var first_lane: Array[PlantCell] = game.board.row_cells(0) # 顶边用于将远景雾限制在雪线附近。
	if last_lane.is_empty() or first_lane.is_empty():
		return
	var final_cell: PlantCell = last_lane.back() # 高台上最右端的真实格子。
	var top_cell: PlantCell = first_lane.back() # 同一高台上最远一行的格顶。
	var cell: Rect2 = final_cell.get_global_rect() # 该处高台的实际底行边界。
	var board: Rect2 = BoardQueries.bounds(last_lane) # 保护区只在棋盘横向范围内。
	var band := Vector4(board.position.x, board.end.x, cell.position.y, cell.end.y)
	var slope: MainGameSlope = game.main_game_slope # 斜坡段从关卡配置取值。
	var breaks := Vector4.ZERO # 平地时保留零高差。
	var heights := Vector4.ZERO # 两段坡首尾的世界纵向偏移。
	if is_instance_valid(slope) and slope.all_slopes.size() == 2:
		var a: Slope = slope.all_slopes[0] # 第一段坡。
		var b: Slope = slope.all_slopes[1] # 第二段坡。
		breaks = Vector4(a.slope_global_pos_x_range.x, a.slope_global_pos_x_range.y,
			b.slope_global_pos_x_range.x, b.slope_global_pos_x_range.y)
		heights = Vector4(a.start_pos_slope.y, a.end_pos_slope.y, b.start_pos_slope.y, b.end_pos_slope.y)
	var shader := load("res://shaders/weather/snow_atmosphere.gdshader") as Shader # 只在雪山打开时载入。
	_air = _plane(-9, shader, bounds, false)
	_near = _plane(4, shader, bounds, true)
	for plane: ColorRect in [_air, _near]: # 两个实例的材质各自持有参数。
		var material := plane.material as ShaderMaterial # 供本场气候更新的可变材质。
		material.set_shader_parameter("bottom_band", band)
		material.set_shader_parameter("slope_edges", breaks)
		material.set_shader_parameter("slope_heights", heights)
		material.set_shader_parameter("ridge_y", top_cell.get_global_rect().position.y)
		material.set_shader_parameter("haze_color", profile.haze_color)

## 创建世界跟随的半透明面；[param order] 为现有背景与卡槽之间的层号。
## [param shader] 为共享程序，[param bounds] 为世界范围，[param near_layer] 选择稀疏近雪。
func _plane(order: int, shader: Shader, bounds: Rect2, near_layer: bool) -> ColorRect:
	var layer := CanvasLayer.new() # 所有画面挂在雪组件下，退出随场释放。
	layer.layer = order
	layer.follow_viewport_enabled = true
	add_child(layer)
	var plane := ColorRect.new() # 视图之外的像素由裁剪处理，不生成场景粒子节点。
	plane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plane.focus_mode = Control.FOCUS_NONE
	plane.position = bounds.position
	plane.size = bounds.size
	var material := ShaderMaterial.new() # 不共享可变 uniform。
	material.shader = shader
	material.set_shader_parameter("near_layer", near_layer)
	plane.material = material
	layer.add_child(plane)
	return plane

## 将远雾与地吹雪的参考线设到当前 [param height] 世界坐标。
func set_ridge_height(height: float) -> void:
	for plane: ColorRect in [_air, _near]: # 两个原有风雪层共享同一地形高度。
		if is_instance_valid(plane):
			(plane.material as ShaderMaterial).set_shader_parameter(&"ridge_y", height)

## 使用 [param delta] 游戏秒推进，[param channels] 为雪风云，[param wind] 为实际世界风速。
## [param fall] 为竖向落速，[param weather] 为能见度损失、阵风、地吹雪、雪墙相位，均为 0..1。
## [param high_quality] 选择世界雪片的绘制预算，[param burst] 是额外拉长雪轨的 0..1 狂风包络。
func advance(delta: float, channels: Vector3, wind: Vector2, fall: float, weather: Vector4, high_quality: bool,
		burst: float = 0.0) -> void:
	if not is_instance_valid(_air):
		return
	for index: int in range(_travel.size()): # 每层的位置和冰粒方向都来自同一世界风。
		var velocity: Vector2 = wind * WIND_SCALE[index] + Vector2(0.0, fall * FALL_SCALE[index]) # 世界像素每秒。
		var length: float = WORLD_SPACING[index] * GRID_PERIOD # 有接缝匹配的本层世界周期。
		var offset: Vector2 = _travel[index] + velocity * delta # 切档时不重置相位。
		_travel[index] = Vector2(fposmod(offset.x, length), fposmod(offset.y, length))
		_direction[index] = velocity.normalized() if not velocity.is_zero_approx() else Vector2.DOWN
	_drift = fposmod(_drift - wind.x * delta / 256.0, 1.0)
	_air.visible = channels.x > 0.001 or weather.x > 0.001 or weather.z > 0.001
	_near.visible = channels.x > 0.001 or weather.x > 0.01 or burst > 0.001
	if _air.visible:
		_upload(_air, channels, weather, 0, high_quality, burst)
	if _near.visible:
		_upload(_near, channels, weather, 2, high_quality, burst)

## 更新 [param plane] 的独立材质。以 [param first] 和它的下一层取位移，[param channels] 和
## [param weather] 沿用 [method advance] 输入，[param high_quality] 选择附加粒子预算，[param burst] 为狂风强度。
func _upload(plane: ColorRect, channels: Vector3, weather: Vector4, first: int, high_quality: bool, burst: float) -> void:
	var material := plane.material as ShaderMaterial # 合成平面只接收它实际需要的两层数据。
	var a: Vector2 = _travel[first] # 当前平面的第一层世界位移。
	var b: Vector2 = _travel[first + 1] # 当前平面的第二层世界位移。
	var dir_a: Vector2 = _direction[first] # 第一层的实际运动轴。
	var dir_b: Vector2 = _direction[first + 1] # 第二层的实际运动轴。
	material.set_shader_parameter("flake_travel", Vector4(a.x, a.y, b.x, b.y))
	material.set_shader_parameter("flake_direction", Vector4(dir_a.x, dir_a.y, dir_b.x, dir_b.y))
	material.set_shader_parameter("snow_sample", channels)
	material.set_shader_parameter("storm_weather", weather)
	material.set_shader_parameter("fine_world_snow", high_quality)
	material.set_shader_parameter("drift_phase", _drift)
	material.set_shader_parameter("wind_burst", burst)
