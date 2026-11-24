## 雪山地面表现。将战斗脚点映射到实际地板画布，保留原棋盘和地形的所有权。
extends Node2D
class_name SnowSurface

## 固定天气步长的隔离调度器，在本场景初始化时由项目资源直接加载。
const StepClock = preload("res://scripts/weather/snow/snow_surface_step_clock.gd")

## 行界光影复用雪山棋盘的实测格位。
const MountainBoard = preload("res://scripts/adventure/snow_mountain_board.gd")
## 只用于分离原图大色块和细雪纹的色调图尺寸，不参与积雪容量或压痕。
const BASE_TONE_SIZE := Vector2i(96, 48)
## 接触候选的世界像素分桶边长；实际命中仍按地块局部几何。
const CONTACT_BUCKET_SIZE: float = 128.0
## 单个格子最多按每轴八桶登记，超出时整批回退即时棋盘查询。
const CONTACT_BUCKET_SPAN: float = 8.0
## 世界桶轴坐标的绝对值上限，留出 Vector2i 转换的余量。
const CONTACT_BUCKET_LIMIT: float = 1000000000.0
## 候选边界保守外扩的世界像素数，吸收正逆变换的舍入差。
const CONTACT_BOUNDS_MARGIN: float = 0.01

## 正式战场提供实时攻击行、坡面和棋盘索引。
var _game: MainGameManager
## 当前关卡地板，底图和雪面使用同一 CanvasItem。
var _ground: Sprite2D
## 原场景材质，用于天气节点独立退场时恢复。
var _original: ShaderMaterial
## 只写本关卡实例的雪面参数，Shader 本体仍可共享。
var _material: ShaderMaterial
## 天空与雪地共享的雪线和坡面投影数据，只在场景装配时建立。
var _ridge: ImageTexture
## 地板实际绘制区在世界坐标中的范围。
var _ridge_bounds: Rect2
## 地面未下沉时的局部纵坐标，后续只按相对位移更新。
var _ground_y: float
## 浮点厚度、压实和潮湿网格。
var _state := SnowSurfaceState.new()
## 纹理批次合成的压痕及轨迹。
var _imprints := SnowSurfaceImprints.new()
## 固定步长与帧间工作预算由单一雪面时钟管理，不向其他场景注册进程。
var _step_clock = StepClock.new()
## 只在本次同步角色接触推进期间允许共享几何。
var _contact_step_active: bool = false
## 本批首次查雪时才准备候选与地板映射；空批不拷贝格子。
var _contact_index_prepared: bool = false
## 按世界位置缩小候选，格子、地形和占用仍由棋盘持有。
var _contact_buckets: Dictionary[Vector2i, Array] = {}
## 本次同步推进期间的世界到雪面 UV 变换。
var _contact_world_to_uv: Transform2D
## 同次同步推进中的行脚点基线。空行用 INF 标记，保留绘制用的原世界坐标精度。
var _contact_lane_baselines := PackedFloat64Array()
## 同次同步推进共用的坡面；每个横坐标仍按真实区间求高差。
var _contact_slope: MainGameSlope

## 使用 [param game] 的权威地形和 [param ground] 的现有着色器，按 [param high_quality] 分配一次可变状态。
func configure(game: MainGameManager, ground: Sprite2D, high_quality: bool) -> void:
	if _material != null:
		return
	_game = game
	_ground = ground
	if not is_instance_valid(ground) or not ground.get_rect().has_area() or not ground.material is ShaderMaterial:
		push_warning("雪面未找到带着色器的地板节点。")
		return
	_ground_y = ground.position.y
	var frame: Image = SnowSurfaceMask.read_frame(ground) # 雪线与积雪状态复用一次纹理读取。
	if frame == null:
		push_warning("雪面未取得可读的地板帧。")
		return
	_original = ground.material as ShaderMaterial
	_material = _original.duplicate() as ShaderMaterial
	_ground.material = _material
	var bounds: Rect2 = ground.get_rect() # 实际绘制的局部矩形，包含居中和偏移。
	_ridge_bounds = ground.get_global_transform() * bounds
	_ridge = SnowSurfaceMask.read_ridge(frame, _ridge_bounds, game.main_game_slope)
	bind_ground_ridge(_material)
	frame.resize(SnowSurfaceState.MASK_SIZE.x, SnowSurfaceState.MASK_SIZE.y, Image.INTERPOLATE_BILINEAR)
	_state.read_ground(frame)
	if _ridge != null:
		# 状态已读取原色容量。复用帧生成极小的低频色调图，减淡原图的格状色块。
		frame.resize(BASE_TONE_SIZE.x, BASE_TONE_SIZE.y, Image.INTERPOLATE_LANCZOS)
		_material.set_shader_parameter("snow_base_tones", ImageTexture.create_from_image(frame))
	_material.set_shader_parameter("snow_ground_rect", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	if _game.board != null and _game.board.configured:
		var right: float = BoardQueries.bounds(_game.board.cells()).end.x # 现有格位的最右界，右侧只有备战背景。
		var uv_to_world: Transform2D = _world_to_uv().affine_inverse() # 用同一转换把界线投影到着色器。
		_material.set_shader_parameter("snow_contact_clip", Vector3(uv_to_world.x.x, uv_to_world.y.x, right - uv_to_world.origin.x))
		if _game.board.definition is MountainBoard:
			var left: float = MountainBoard.art_to_world(Vector2(MountainBoard.COLUMN_EDGES[0], 0.0)).x # 第一列左界，雪脊从这里淡入。
			var last_edge: int = MountainBoard.ROW_EDGES.size() - 2 # 完整棋盘的最后一条内侧行界。
			_material.set_shader_parameter("snow_lane_span", Vector2(left, right))
			_material.set_shader_parameter("snow_lane_edges", Vector3(MountainBoard.rim_height(1),
				MountainBoard.rim_height(last_edge), MountainBoard.row_stride()))
	_step_clock.configure(_state, _imprints)
	set_quality(high_quality)
	_material.set_shader_parameter("snow_surface_enabled", true)

## 将本关同一份世界雪线绑定到包含雪线函数的 [param target] 材质，供天空和地板对齐。
func bind_ground_ridge(target: ShaderMaterial) -> void:
	if _ridge == null:
		return
	target.set_shader_parameter("snow_ridge", _ridge)
	target.set_shader_parameter("snow_ridge_bounds", Vector4(_ridge_bounds.position.x,
		_ridge_bounds.position.y, _ridge_bounds.size.x, _ridge_bounds.size.y))

## [param descent] 为整块场地的纵移，[param rim] 为源图坡面上的近端裂口纵深。
func set_board_descent(descent: float, rim: float) -> void:
	if _material == null:
		return
	_ground.position.y = _ground_y + descent
	_material.set_shader_parameter(&"snow_ridge_descent", descent)
	_material.set_shader_parameter(&"snow_slab_rim", rim)

## 按 [param high_quality] 更新分辨率和推进场频，保留已有积雪、潮湿与压痕。
func set_quality(high_quality: bool) -> void:
	if _material == null:
		return
	_step_clock.set_interval(0.1 if high_quality else 0.2) # 先提交旧步，再重采样新精度。
	_state.set_quality(high_quality)
	_imprints.resize(_state.size)
	_material.set_shader_parameter("snow_state", _state.texture)
	_material.set_shader_parameter("snow_details", _imprints.texture)

## 由场景游戏时钟提供 [param delta] 秒；[param channels] 为雪、目标风和云，[param wind] 为当前实际风强。
## [param ridge_weather] 为能见度损失和世界雪墙相位，只影响雪线附近的绘制。
func advance(delta: float, channels: Vector3, wind: float, ridge_weather: Vector2) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("snow_ridge_weather", ridge_weather)
	_step_clock.advance(delta, channels.x, wind) # 固定物理步长不变，CPU 雪面按帧分批结算。

## [param tint] 为天空传来的低频环境色与权重，留在原场景材质的色值范围内。
func set_environment_tint(tint: Color) -> void:
	if _material != null:
		_material.set_shader_parameter("snow_ambient", tint)

## 开始一次同步接触推进，使本批查询能复用当前棋盘和地板几何。
func begin_contact_step() -> void:
	_contact_step_active = true
	if not is_instance_valid(_game) or not is_instance_valid(_game.zombie_manager):
		_contact_lane_baselines.clear()
		return
	_contact_slope = _game.main_game_slope
	var rows: Array[ZombieRow] = _game.zombie_manager.all_zombie_rows # 与普通脚点查询使用同一批出怪行。
	_contact_lane_baselines.resize(rows.size())
	for lane: int in range(rows.size()): # 每次表现更新只读取一次各行的实时世界基线。
		var row: ZombieRow = rows[lane] # 沉降后的行容器位置以本次快照为准。
		_contact_lane_baselines[lane] = row.zombie_create_position.global_position.y \
			if is_instance_valid(row) and is_instance_valid(row.zombie_create_position) else INF

## 结束接触推进并释放候选。推进之外的落地和死亡回调即时读取棋盘。
func end_contact_step() -> void:
	_contact_step_active = false
	_contact_index_prepared = false
	_contact_buckets.clear()
	_contact_slope = null

## 从 [param board] 的当前实际变换登记保守候选，同步推进结束即失效。
func _prepare_contact_index(board: BoardRuntime) -> void:
	_contact_world_to_uv = _world_to_uv()
	_contact_index_prepared = true
	for cell: PlantCell in board.cells(): # 候选快照来自权威棋盘而非场景树遍历。
		if not is_instance_valid(cell) or cell.is_queued_for_deletion():
			continue
		var bounds: Rect2 = (cell.get_global_transform() * Rect2(Vector2.ZERO, cell.size)).grow(CONTACT_BOUNDS_MARGIN) # 含坡面、旋转和父级位移。
		var minimum: Vector2 = (bounds.position / CONTACT_BUCKET_SIZE).floor() # 世界包围盒左上角所在的桶。
		var maximum: Vector2 = (bounds.end / CONTACT_BUCKET_SIZE).floor() # 右下角所在的桶也参与精确的闭边判定。
		var span: Vector2 = maximum - minimum + Vector2.ONE # 每轴桶数量。
		var furthest: Vector2 = minimum.abs().max(maximum.abs()) # 坐标转换前确认两个端点均在整数桶范围内。
		if not minimum.is_finite() or not maximum.is_finite() \
				or maxf(furthest.x, furthest.y) > CONTACT_BUCKET_LIMIT \
				or span.x > CONTACT_BUCKET_SPAN or span.y > CONTACT_BUCKET_SPAN:
			_contact_buckets.clear()
			return
		for y: int in range(int(minimum.y), int(maximum.y) + 1): # 逐行登记跨越桶边界的格子。
			for x: int in range(int(minimum.x), int(maximum.x) + 1): # 同一世界点只匹配一个桶。
				var key := Vector2i(x, y) # 本格包围盒触及的候选桶。
				if not _contact_buckets.has(key):
					var cells: Array[PlantCell] = [] # 精确查询复用有类型的候选列表。
					_contact_buckets[key] = cells
				_contact_buckets[key].append(cell)

## 取得 [param lane] 在 [param world_x] 的行走脚点。缺行或横坐标无效时返回 [constant Vector2.INF]。
## 允许查询棋盘边缘外的真实坡面；是否允许提交接触由 [method allows_contact] 判断。
func ground_point(world_x: float, lane: int) -> Vector2:
	if lane < 0 or not is_finite(world_x):
		return Vector2.INF
	var baseline: float # 本行出怪点的世界纵坐标。
	var slope: MainGameSlope # 僵尸行走与当前接触共用的坡面。
	if _contact_step_active:
		if lane >= _contact_lane_baselines.size():
			return Vector2.INF
		baseline = _contact_lane_baselines[lane]
		if not is_finite(baseline):
			return Vector2.INF
		slope = _contact_slope
	else:
		if not is_instance_valid(_game) or not is_instance_valid(_game.zombie_manager):
			return Vector2.INF
		var rows: Array[ZombieRow] = _game.zombie_manager.all_zombie_rows # 与正式生成角色相同的可用攻击行。
		if lane >= rows.size():
			return Vector2.INF
		var row: ZombieRow = rows[lane] # 批外落地事件使用当前行标记。
		if not is_instance_valid(row) or not is_instance_valid(row.zombie_create_position):
			return Vector2.INF
		baseline = row.zombie_create_position.global_position.y
		slope = _game.main_game_slope
	var elevation: float = slope.get_all_slope_y(world_x) if is_instance_valid(slope) else 0.0 # 僵尸行走使用的相对高度。
	return Vector2(world_x, baseline + elevation)

## [param lane] 的 [param world_x] 两侧各取一个世界像素，返回沿坡向右的单位切线。
func ground_tangent(world_x: float, lane: int) -> Vector2:
	return (ground_point(world_x + 1.0, lane) - ground_point(world_x - 1.0, lane)).normalized()

## 仅接受 [param point] 下确有雪面地块且底图有允许积雪像素的世界点。
func allows_contact(point: Vector2) -> bool:
	return snow_at_contact(point).x >= 0.0

## 返回 [param point] 所在格的松雪和压实，盘外、预览和裸岩返回负值。
## 已知 [param lane] 时只查该行；默认 -1 为与原脚印相同的格位命中。
func snow_at_contact(point: Vector2, lane: int = -1) -> Vector2:
	if _material == null or not is_instance_valid(_ground) or not point.is_finite():
		return -Vector2.ONE
	var board: BoardRuntime = _game.board # 权威格位查询，不复制占用或匹配最近格。
	if board == null or not board.configured:
		return -Vector2.ONE
	if _contact_step_active and not _contact_index_prepared:
		_prepare_contact_index(board)
	var cell: PlantCell # 命中格由原精确判定选出，选出后才检查地形标签。
	if not _contact_buckets.is_empty():
		var coordinate: Vector2 = (point / CONTACT_BUCKET_SIZE).floor() # 当前世界脚点所在的候选桶坐标。
		if maxf(absf(coordinate.x), absf(coordinate.y)) > CONTACT_BUCKET_LIMIT:
			return -Vector2.ONE
		var bucket := Vector2i(coordinate) # 坐标已确认可以安全转成字典键。
		if not _contact_buckets.has(bucket):
			return -Vector2.ONE
		var candidates: Array[PlantCell] = _contact_buckets[bucket] # 仅检查可能覆盖当前点的格子。
		cell = BoardQueries.ground_cell_from(board, point, lane, candidates) if lane >= 0 \
			else BoardQueries.pick_cell_from(point, candidates)
	else:
		cell = board.cell_at_ground_point(point, lane) if lane >= 0 else board.pick_cell(point)
	if cell == null or cell.board_terrain == null or not cell.board_terrain.tags.has(&"snow"):
		return -Vector2.ONE
	var uv: Vector2 = _world_to_uv() * point # 压痕可同步改写雪面，因此雪量本身每次即时取样。
	if not Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv):
		return -Vector2.ONE
	var sample: Vector3 = _state.sample(uv) # 共用地板着色输入的 CPU 样本。
	return Vector2(sample.y, sample.z) if sample.x > 0.035 else -Vector2.ONE

## 沿 [param from] 与 [param to] 的实际斜面短段扫掠，[param width] 为世界像素全宽、[param strength] 在 0..1。
func sweep(from: Vector2, to: Vector2, width: float, strength: float) -> void:
	var center: Vector2 = (from + to) * 0.5 # 短段接触的世界中心。
	if not is_finite(width) or not allows_contact(center):
		return
	var radius: float = clampf(width, 1.0, 180.0) * 0.5 # 局部胶囊端点的世界半径。
	var travel: Vector2 = to - from # 当前坡段切线。
	if travel.length_squared() > 4096.0:
		return
	var shape := Transform2D(travel.angle(), Vector2(radius, radius), 0.0, center) # 胶囊的局部单位和切线方向。
	_press(_world_to_uv() * shape, strength, travel.length() * 0.5 / radius)

## 在 [param world_position] 附近按 [param size] 世界全宽高和 [param intensity]（0..1）暂时融去少量表雪。
func apply_visual_heat(world_position: Vector2, size: Vector2, intensity: float) -> void:
	if not size.is_finite() or not is_finite(intensity) or not allows_contact(world_position):
		return
	var scale_px: Vector2 = size.clamp(Vector2.ONE, Vector2(300.0, 180.0)) * 0.5 # 有界热源范围，不扫描整张地板。
	var shape: Transform2D = _world_to_uv() * Transform2D(0.0, scale_px, 0.0, world_position) # 热源投影到低频状态 UV。
	_state.apply_local(shape.origin, shape.x.abs() + shape.y.abs(), clampf(intensity, 0.0, 1.0), true)

## 将 [param shape] 的连续雪槽按基底松雪缩放 [param strength] 后提交；[param span] 扩展胶囊中段。
func _press(shape: Transform2D, strength: float, span: float) -> void:
	if not is_finite(strength) or strength <= 0.0:
		return
	var material_sample: Vector3 = _state.sample(shape.origin) # 静态可积覆盖、松雪厚度与压实。
	var force: float = clampf(strength, 0.0, 1.0) # 防止盖章穿透普通底图颜色。
	var depth: float = force * material_sample.x * (0.21 + 0.70 * material_sample.y) # 薄雪和裸冰上的压痕较浅。
	_imprints.draw_mark(shape, depth, span)
	_state.apply_local(shape.origin, shape.x.abs() * (1.0 + span) + shape.y.abs(), force)

## 返回战斗世界坐标到地板绘制矩形 UV 的变换；经公共视口桥接跟随镜头的背景 CanvasLayer。
func _world_to_uv() -> Transform2D:
	if _contact_index_prepared:
		return _contact_world_to_uv
	var bounds: Rect2 = _ground.get_rect() # 真实 Sprite2D 局部绘制区，状态 UV 不依赖源图像素尺寸。
	var local_to_uv := Transform2D(Vector2(1.0 / bounds.size.x, 0.0), Vector2(0.0, 1.0 / bounds.size.y), -bounds.position / bounds.size) # 归一化偏移及分轴比例。
	return local_to_uv * _ground.get_global_transform_with_canvas().affine_inverse() * _game.get_canvas_transform()

## 天气组件可独立卸载，地板仍存活时恢复原材质并释放本场的可变状态。
func _exit_tree() -> void:
	if is_instance_valid(_ground) and _ground.material == _material:
		_ground.material = _original
