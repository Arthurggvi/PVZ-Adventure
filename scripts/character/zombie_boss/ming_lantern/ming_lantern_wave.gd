## 明灯与潜水员共用的分路浪。扫掠、翻卷、碎浪与尾迹沿同一条战斗轨迹推进。
extends Node2D
class_name MingLanternWave

## 将 [param previous_x] 到 [param current_x] 的世界横坐标交给战斗结算。
signal wave_advanced(previous_x: float, current_x: float)

## 起浪时每战斗秒推进的世界像素数。
const START_SPEED := 150.0
## 浪头到达场地边缘前的最高速度，单位为世界像素每战斗秒。
const END_SPEED := 360.0
## 浪尖从棋盘外起步，留出卷起浪身的世界像素。
const START_MARGIN := 158.0
## 浪尖越过最后一格后，继续走到场外再化成泡沫。
const END_MARGIN := 85.0
## 浅水尾迹自经过后留存的最长战斗秒数。
const WAKE_LIFETIME := 1.85
## 撞到目标后迅速塌落，单位为战斗秒；水花和地面尾迹继续消散。
const IMPACT_SETTLE_TIME := 0.28
## 离场时浪头下伏并摊开的战斗秒数。
const SETTLE_TIME := 0.48
## 浪面绘图区的基础宽高，使用单行格高作为单位。
const CREST_SIZE := Vector2(2.55, 1.42)
## 飞沫沿浪头运动路径生成的间距，单位为战斗秒。
const SPRAY_STEP := 0.083
## 可见的常态飞沫批次数。
const SPRAY_BATCHES := 6
## 一次局部触水所产生泡沫的寿命，单位为战斗秒。
const SPLASH_TIME_ON_HIT := 0.44
## 每路同时存在的局部飞沫簇上限，密集目标优先共享近处水花。
const MAX_SPLASHES := 5

## 借用原画的水体体积和泡沫结构，由材质压低自身亮度。
const CREST: Texture2D = preload("res://assets/adventure/zombies/ming_lantern/wave_crest.png")
## 控制浪头色阶、翻卷和破碎后的侵蚀。
const CREST_SHADER: Shader = preload("res://shaders/adventure/wonderland/ming_lantern_wave.gdshader")
## 分别按实际经过时间计算每个像素的水光余迹。
const WAKE_SHADER: Shader = preload("res://shaders/adventure/wonderland/ming_lantern_wave_wake.gdshader")
## 整批浪头共用的低频水声。
const SURF: AudioStream = preload("res://resources/audio/sfx/ming_lantern_surf.ogg")

## 同高度相邻格合并成水膜；大的棋盘缺口仍分开绘制。
var _wake_geometry: Array[Rect2] = []

## 本路真实格子的世界矩形，入树前由棋盘或图鉴提供。
var lane_cells: Array[Rect2] = []
## 场地外的终止线，单位为世界横坐标。
var end_x := 0.0
## 本路高度，单位为世界像素，控制浪身及水花的透视。
var lane_height := 70.0
## 水浪扫过期间读取本体速度；截停后的水纹独立消散。
var sweep_rate: Callable
## 浪沿同一时间轴前进、落光和碎裂，单位为战斗秒。
var _age := 0.0
## 浪尖开始推进的世界横坐标，同时作为余迹几何的横向原点。
var _start_x := 0.0
## 横向推进的符号，-1 向左，1 向右；入树时由终止线确定。
var _direction := -1.0
## 本路起浪到离场的加速度，单位为世界像素每战斗秒平方。
var _acceleration := 0.0
## 浪尖当前的世界横坐标。击中角色后精确停在碰撞位置。
var _front_x := 0.0
## 浪尖停止推进的时刻。负值表示仍在移动。
var _broken_at := -1.0
## 浪头是否被角色截停，决定是否喷发额外的近地水花。
var _blocked := false
## 从浪所在的行高生成的固定相位，打散相邻行的水纹和泡沫。
var _phase := 0.0
## 从中间向两侧逐步抬起浪峰所用的额外路程，单位为世界像素。
var _formation_distance: float
## 相邻行的抬升周期在 0 至 1 内错开。
var _roll_phase: float
## 命中积下的浅水飞沫；XY 为浪宿主本地位置，Z 为生成战斗秒。
var _splashes: Array[Vector3] = []

## 可压缩的浪身。根节点保持不动，地面余光留在原地。
var _crest: Sprite2D
## 每道浪独立持有的浪头材质。
var _crest_material: ShaderMaterial
## 只覆盖有效格子的余光材质，保留一份静态几何。
var _wake_material: ShaderMaterial

## 返回无阻挡时推进 [param distance] 个世界像素所需的战斗秒数。
static func travel_duration(distance: float) -> float:
	return 2.0 * distance / (START_SPEED + END_SPEED)

## 用 [param field] 给出世界行范围，[param cells] 描述实格，[param canvas] 提供父节点坐标系。
## [param rightward] 镜像行进方向，[param lane] 和 [param lane_count] 控制可见浪冠的分路相位。
## 返回准备好连结命中回调、尚未入树的浪。
static func for_lane(canvas: Node2D, field: Rect2, cells: Array[Rect2], rightward: bool = false,
		lane: int = 0, lane_count: int = 1) -> MingLanternWave:
	var wave := MingLanternWave.new() # 施放方只选择方向、行布局及碰撞行为。
	var start: float = field.position.x - START_MARGIN if rightward else field.end.x + START_MARGIN # 起浪侧世界横坐标。
	wave.position = canvas.to_local(Vector2(start, field.get_center().y + 1.0))
	wave.end_x = field.end.x + END_MARGIN if rightward else field.position.x - END_MARGIN
	wave.lane_height = cells.front().size.y if not cells.is_empty() else field.size.y
	wave.lane_cells = cells
	wave._formation_distance = absf(float(lane) - float(lane_count - 1) * 0.5) * 22.0
	wave._roll_phase = fposmod(float(lane) * 0.237 + 0.12, 1.0)
	return wave

## 组装前进的浪身和固定在地面的余光层。
func _ready() -> void:
	_start_x = global_position.x
	_front_x = _start_x
	_direction = 1.0 if end_x > _start_x else -1.0
	var crossing: float = travel_duration(absf(end_x - _start_x)) # 按行跨度分配加速过程，使渐快持续到离场。
	_acceleration = (END_SPEED - START_SPEED) / crossing
	_phase = global_position.y * 0.073
	if not lane_cells.is_empty():
		_merge_flat_wake_cells()
	_wake_material = ShaderMaterial.new()
	_wake_material.shader = WAKE_SHADER
	_wake_material.set_shader_parameter(&"start_speed", START_SPEED)
	_wake_material.set_shader_parameter(&"acceleration", _acceleration)
	_wake_material.set_shader_parameter(&"lifetime", WAKE_LIFETIME)
	_wake_material.set_shader_parameter(&"phase", _phase)
	var wake := Node2D.new() # 静态格子网格，只有材质时间和浪前缘逐帧更新。
	wake.material = _wake_material
	wake.z_as_relative = false
	wake.z_index = -1
	wake.draw.connect(_draw_wake.bind(wake))
	add_child(wake)
	_crest_material = ShaderMaterial.new()
	_crest_material.shader = CREST_SHADER
	_crest = Sprite2D.new()
	_crest.texture = CREST
	_crest.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_crest.flip_h = _direction > 0.0
	_crest.material = _crest_material
	add_child(_crest)
	_update_crest(0.0)

## 在 [param world_x] 处截停浪身。相同浪只响应第一次碰撞。
func break_wave(world_x: float) -> void:
	if _broken_at < 0.0:
		_blocked = true
		_stop_at(world_x)
		splash_at(world_x)

## 在命中位置 [param world_x] 溅起泡沫；穿透浪可只调用此方法而继续推进。
func splash_at(world_x: float) -> void:
	var origin: Vector2 = to_local(Vector2(world_x, _waterline_at(world_x))) # 水花立在接触点的水面。
	var starts_at: float = _broken_at if _blocked else _age # 截停时的水花与塌落共用准确时点。
	for splash: Vector3 in _splashes: # 紧邻的接触共用已有泡沫簇。
		if absf(splash.x - origin.x) < 24.0 and _age - splash.z < 0.11:
			return
	if _splashes.size() >= MAX_SPLASHES:
		return
	_splashes.append(Vector3(origin.x, origin.y, starts_at))

## [param delta] 为战斗秒数。先结算前缘的整段扫掠，再根据实际终点写入余光。
func _process(delta: float) -> void:
	_age += delta * float(sweep_rate.call()) if _broken_at < 0.0 and sweep_rate.is_valid() else delta
	if _broken_at < 0.0:
		var previous: float = _front_x # 上帧经过的最后一个真实位置。
		var next_x: float = clampf(_start_x + _direction * _distance_at(_age), minf(_start_x, end_x),
			maxf(_start_x, end_x)) # 解析求位置，与余光的经过时刻保持一致。
		_front_x = next_x
		wave_advanced.emit(previous, next_x)
		if _broken_at < 0.0 and next_x == end_x:
			_stop_at(end_x)
	var stopped_for: float = _age - _broken_at if _broken_at >= 0.0 else 0.0 # 碎浪和光路软边共用同一个截停时钟。
	if stopped_for >= WAKE_LIFETIME:
		queue_free()
		return
	_wake_material.set_shader_parameter(&"clock_seconds", _age)
	_wake_material.set_shader_parameter(&"front_offset", _wake_offset(_front_x))
	_wake_material.set_shader_parameter(&"stopped_for", stopped_for)
	_update_crest(stopped_for)
	while not _splashes.is_empty() and _age - _splashes.front().z >= SPLASH_TIME_ON_HIT:
		_splashes.pop_front()
	queue_redraw()

## 返回起浪后 [param seconds] 内沿加速曲线推进的世界像素数。
func _distance_at(seconds: float) -> float:
	return seconds * (START_SPEED + 0.5 * _acceleration * seconds)

## 返回浪尖经过 [param world_x] 的战斗时刻，与浪尾着色器共用同一曲线参数。
func _passage_time(world_x: float) -> float:
	var distance: float = -_wake_offset(world_x) # 从出发点到命中点或余光采样点的实际路程。
	return 2.0 * distance / (START_SPEED + sqrt(START_SPEED * START_SPEED + 2.0 * _acceleration * distance))

## 将 [param world_x] 转成水光纹理坐标，沿前进方向始终为负。
func _wake_offset(world_x: float) -> float:
	return (_start_x - world_x) * _direction

## 记录 [param world_x] 的实际经过时刻，长帧跨过命中点时也不延后碎浪。
func _stop_at(world_x: float) -> void:
	_front_x = world_x
	_broken_at = _passage_time(world_x)

## 抬升后翻卷，受阻时加快塌落；[param elapsed] 是浪尖停止后的战斗秒。
func _update_crest(elapsed: float) -> void:
	var duration: float = IMPACT_SETTLE_TIME if _blocked else SETTLE_TIME # 撞击比自然退浪更急。
	_crest.visible = elapsed < duration
	if not _crest.visible:
		return
	var distance: float = -_wake_offset(_front_x) # 按实际行程从入场侧的浅水抬成浪冠。
	var formation: float = _formation_at(distance) # 先铺水，中路浪冠较早抬起。
	var crest_time: float = _broken_at if _blocked else _age # 按触点的浪形塌落。
	var profile: Vector3 = _crest_profile(crest_time, formation) # 浪身和离开浪冠的飞沫共用变形。
	var settle: float = smoothstep(0.0, duration, elapsed) # 把水冠平滑压回水面。
	var size: Vector2 = (CREST_SIZE + Vector2(0.25 * profile.z + 0.27 * settle, 0.0)) * lane_height # 低长的后坡比水冠更宽。
	_crest.scale = size / CREST.get_size()
	_crest.global_position = Vector2(_front_x - _direction * size.x * 0.46, _waterline_at(_front_x) - size.y * 0.39)
	_crest.modulate.a = smoothstep(0.0, 0.72, formation) * (1.0 - smoothstep(duration * 0.25, duration, elapsed))
	_crest_material.set_shader_parameter(&"travel_time", _age)
	_crest_material.set_shader_parameter(&"phase", _roll_phase * TAU)
	_crest_material.set_shader_parameter(&"formation", formation)
	_crest_material.set_shader_parameter(&"peak", profile.x)
	_crest_material.set_shader_parameter(&"crest_height", profile.y * lerpf(1.0, 0.15, settle))
	_crest_material.set_shader_parameter(&"curl", lerpf(profile.z, 1.0, settle) if _blocked else profile.z)
	_crest_material.set_shader_parameter(&"collapse", settle)

## 返回浪尖走过 [param distance] 像素后的成形比例，错峰只作用于演出。
func _formation_at(distance: float) -> float:
	return smoothstep(12.0, 150.0, distance - _formation_distance)

## 由 [param seconds] 的周期和 [param formation] 求水冠的归一横位、相对高度和卷口程度。
func _crest_profile(seconds: float, formation: float) -> Vector3:
	var beat: float = fposmod(seconds * 1.04 + _roll_phase, 1.0) # 0 为回落后、约 0.55 时达到浪尖。
	var lift: float = smoothstep(0.01, 0.57, beat) * (1.0 - smoothstep(0.56, 0.93, beat)) # 上升长于倾覆。
	var curl: float = smoothstep(0.44, 0.79, beat) * (1.0 - smoothstep(0.79, 0.99, beat)) # 卷口在峰值之后向前。
	return Vector3(lerpf(0.38, 0.21, curl), (0.28 + 0.44 * lift) * lerpf(0.14, 1.0, formation), curl)

## 在 [param world_x] 按实际格子脚点插值，仅用作浪面与泡沫的水位。
func _waterline_at(world_x: float) -> float:
	var left := Vector2(-INF, 0.0) # 当前接点左边最近的格心与水位。
	var right := Vector2(INF, 0.0) # 当前接点右边最近的格心与水位。
	for cell: Rect2 in lane_cells: # 屋顶、坡面与宽度不等的格子均由实际几何给出。
		var x: float = cell.get_center().x # 横向以格心为锚。
		var y: float = cell.position.y + cell.size.y * 0.82 # 水脚贴近地面实体的脚点。
		if x <= world_x and x > left.x:
			left = Vector2(x, y)
		if x > world_x and x < right.x:
			right = Vector2(x, y)
	if not left.is_finite():
		return right.y if right.is_finite() else global_position.y + lane_height * 0.32
	if not right.is_finite():
		return left.y
	return lerpf(left.y, right.y, inverse_lerp(left.x, right.x, world_x))

## 合并同高度格间的像素接缝；缺格和有高度差的地块继续独立铺水。
func _merge_flat_wake_cells() -> void:
	var ordered: Array[Rect2] = lane_cells.duplicate() # 不改用于投光和查询水位的实际地块。
	ordered.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var strip: Rect2 = ordered.front() # 正在合并的连续水面范围。
	for tile: Rect2 in ordered.slice(1): # 仅把横向接近且上下边齐平的实格连在一起。
		if tile.position.x - strip.end.x <= 2.0 and is_equal_approx(tile.position.y, strip.position.y) \
				and is_equal_approx(tile.end.y, strip.end.y):
			strip = strip.merge(tile)
		else:
			_wake_geometry.append(strip)
			strip = tile
	_wake_geometry.append(strip)

## 在 [param canvas] 上提交本路的固定格网。跨格的横向坐标连续，纵向按各格水面尺寸归一化。
func _draw_wake(canvas: Node2D) -> void:
	var points := PackedVector2Array() # 只包含实际存在的格子，悬空与行间空隙不会写入光路。
	var uvs := PackedVector2Array() # X 是相对于出生点的世界像素，Y 是本格的纵向比例。
	var indices := PackedInt32Array() # 每格两个三角形，共享一次材质绘制。
	var board_edges := Vector2(INF, -INF) # 水光纹理坐标中的格网外沿，用于让反光在边缘收淡。
	for cell: Rect2 in _wake_geometry: # 相邻片使用同一世界横坐标，水纹相位连续。
		var first: int = points.size() # 本格左上角的顶点索引。
		var left: float = _wake_offset(cell.position.x) # 本格左缘在水光纹理坐标中的位置。
		var right: float = _wake_offset(cell.end.x) # 镜像时世界右缘的纹理坐标较小。
		board_edges.x = minf(board_edges.x, minf(left, right))
		board_edges.y = maxf(board_edges.y, maxf(left, right))
		points.append_array(PackedVector2Array([to_local(cell.position), to_local(Vector2(cell.end.x, cell.position.y)),
			to_local(Vector2(cell.position.x, cell.end.y)), to_local(cell.end)]))
		uvs.append_array(PackedVector2Array([Vector2(left, 0.0), Vector2(right, 0.0),
			Vector2(left, 1.0), Vector2(right, 1.0)]))
		indices.append_array(PackedInt32Array([first, first + 1, first + 2, first + 1, first + 3, first + 2]))
	if points.is_empty():
		return
	_wake_material.set_shader_parameter(&"board_edges", board_edges)
	var colors := PackedColorArray() # 材质负责着色，所有格的原始颜色一致。
	colors.resize(points.size())
	colors.fill(Color.WHITE)
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors, uvs)

## 将经过的地面和碰撞水花的余光交给 [param lighting]，亮度由各位置的经过时间决定。
func draw_scene_light(lighting: MingLanternLighting) -> void:
	var oldest_x: float = _start_x + _direction * _distance_at(maxf(0.0, _age - WAKE_LIFETIME)) # 最早还保有余光的地方。
	var wake_left: float = minf(_front_x, oldest_x) # 当前余光的左界，同时适用于两种推进方向。
	var wake_right: float = maxf(_front_x, oldest_x) # 当前余光的右界。
	for cell: Rect2 in lane_cells: # 只在确实被扫过且仍有余光的部分投射照明。
		var left: float = maxf(cell.position.x, wake_left) # 停在碰撞格时，只照到实际扫过的一侧。
		var right: float = minf(cell.end.x, wake_right) # 尾迹超时的部分不再参与照明。
		var width: float = right - left # 本格仍在发光的横向长度。
		if width < 1.0:
			continue
		var x: float = (left + right) * 0.5 # 在余光片段中心采样时刻与光色。
		var elapsed: float = _age - _passage_time(x) # 自浪扫过采样点以来的时间。
		var intensity: float = smoothstep(0.0, 0.045, elapsed) * (1.0 - smoothstep(0.16, WAKE_LIFETIME, elapsed)) # 与地面材质同步积光和消光。
		var surface := Vector2(x, cell.position.y + cell.size.y * 0.66) # 受光集中在水面和植物根部附近。
		lighting.cast(self, to_local(surface), Vector2(width * 0.77 + 10.0, cell.size.y * 0.54),
			Color("46dcd0"), intensity * 0.27 * (width / cell.size.x))
	if _blocked:
		var elapsed: float = _age - _broken_at # 水花只在触点产生一小片短暂反光。
		lighting.cast(self, to_local(Vector2(_front_x, _waterline_at(_front_x))), Vector2(84.0, lane_height * 0.52),
			Color("a3e5dc"), 0.24 * (1.0 - smoothstep(0.04, 0.33, elapsed)))

## 补绘浪冠带出的细沫和命中时留在原水面的泡沫。
func _draw() -> void:
	_draw_spindrift()
	for splash: Vector3 in _splashes: # 命中点的局部水纹不跟着浪身离开。
		_draw_contact_splash(Vector2(splash.x, splash.y), _age - splash.z)

## 用每批初次离开水冠的位置解析飞行，泡沫离开浪后继续扬起并回落。
func _draw_spindrift() -> void:
	var end: float = _age if _broken_at < 0.0 else _broken_at # 浪收束后不再吹出新沫。
	var newest: int = floori(end / SPRAY_STEP) # 最近一次喷发的时间索引。
	for offset: int in range(SPRAY_BATCHES): # 每路只绘制尚未消散的少量泡沫。
		var batch: int = newest - offset # 向前找仍在水面上方的批次。
		var release: float = float(batch) * SPRAY_STEP # 生长、抛撒和停浪均使用同一战斗钟。
		var elapsed: float = _age - release # 泡沫自离开波冠开始计时。
		if batch < 1 or elapsed <= 0.0 or elapsed >= SPRAY_BATCHES * SPRAY_STEP:
			continue
		var distance: float = _distance_at(release) # 此批泡沫出生时的浪行程。
		var formation: float = _formation_at(distance) # 尚未成形时不在水面上显露飞沫。
		if formation < 0.08:
			continue
		var front: float = _start_x + distance * _direction # 出生时的推进前缘。
		var profile: Vector3 = _crest_profile(release, formation) # 出生帧浪冠轮廓，之后固定起点。
		var width: float = lane_height * (CREST_SIZE.x + 0.25 * profile.z) # 与浪身绘图区一致。
		var x: float = front - _direction * (profile.x - 0.04) * width # 飞沫从实际浪峰处甩出。
		var surface: float = _waterline_at(front) # 高低不齐的地面共用脚点采样。
		var height: float = CREST_SIZE.y * lane_height * profile.y # 飞沫起点离水高度。
		var progress: float = elapsed / (SPRAY_BATCHES * SPRAY_STEP) # 飞出水冠后独立运动到消散。
		var seed: float = float(batch) * 2.39996 + _phase # 解析的散布方向，不消耗战斗随机数。
		var alpha: float = smoothstep(0.0, 0.07, elapsed) * (1.0 - smoothstep(0.14, 0.49, elapsed)) \
			* formation # 细沫随对应浪冠长出。
		for strand: int in range(2): # 一滴压低贴地，另一滴被卷向上方。
			var t: float = seed + float(strand) * 2.1 # 两滴在形状和散布方向上不同。
			var drift: float = (18.0 + 23.0 * sin(t)) * progress # 两侧细沫的纵向飞行宽度。
			var apex: float = 5.0 + 11.0 * (0.5 + 0.5 * cos(t)) # 小泡沫从水冠再扬起的距离。
			var elevation: float = height * (1.0 - progress * progress) + apex * sin(PI * progress) # 扬起后回落到水面。
			var diameter: float = 3.4 + 3.3 * fposmod(t, 1.0) # 以原素材渲染半透明水滴。
			_drop(to_local(Vector2(x + drift * _direction, surface - elevation)), diameter, alpha * 0.67)

## 从 [param origin] 绘制冲开的白沫和水滴；[param elapsed] 是从接触开始的战斗秒。
func _draw_contact_splash(origin: Vector2, elapsed: float) -> void:
	var time: float = clampf(elapsed / SPLASH_TIME_ON_HIT, 0.0, 1.0) # 一次飞溅从起白到沉入水中的比例。
	var travel: float = 1.0 - exp(-time * 3.7) # 水滴急速弹出，随后受水阻减速。
	var alpha: float = smoothstep(0.0, 0.10, time) * (1.0 - smoothstep(0.32, 1.0, time)) # 冲击水花随余纹一起渐隐。
	draw_set_transform(origin, 0.0, Vector2(_direction, 0.34))
	draw_arc(Vector2.ZERO, lerpf(9.0, 56.0, travel), -1.05, 1.19, 18, Color(0.72, 0.98, 0.99, alpha * 0.69), 2.1, true)
	draw_arc(Vector2(-7.0, 0.0), lerpf(7.0, 35.0, travel), 1.80, 4.55, 14, Color(0.51, 0.90, 0.94, alpha * 0.42), 2.0, true)
	draw_set_transform(Vector2.ZERO)
	for index: int in range(9): # 让细沫扩散到接触点的两侧。
		var angle: float = float(index) * 2.39996 + _phase # 黄金角使水滴不排成扇骨。
		var flight := Vector2(cos(angle) * _direction, sin(angle) * 0.36) # 水平方向的散布较宽。
		var point: Vector2 = origin + flight * (23.0 + fposmod(angle * 13.0, 43.0)) * travel # 完整落点在半格到一格之内。
		point.y -= sin(time * PI) * (11.0 + fposmod(angle * 21.0, 24.0))
		_drop(point, 4.4 + fposmod(angle * 10.1, 6.5), alpha * 0.92)

## 在本地 [param point] 用明灯的泡沫贴图画一滴，[param size] 为像素，[param alpha] 为透明度。
func _drop(point: Vector2, size: float, alpha: float) -> void:
	var diameter := Vector2(size, size * 0.90) # 稍扁的形状贴合快速运动的水滴。
	draw_texture_rect(MingLanternArt.BUBBLE, Rect2(point - diameter * 0.5, diameter),
		false, Color(0.78, 0.97, 1.0, alpha))
