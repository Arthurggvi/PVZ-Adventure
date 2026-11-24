## 花园飞艇的上部承重索。船体和甲板原画遮住埋在金属件内的索头，浮动端随实际位姿移动。
extends Node2D

## 每项依次为平台 ID、上梁锚点（战场坐标）、甲板锚点（局部坐标）和补绘耳环的 Y 坐标（零表示复用原绘五金）。
## 上梁按 BattleFrame 的拉伸 Shader 逆算，甲板端落在后栏柱或桥侧黄铜压板。两排对换时，各索仍在对应甲板上缘。
const CABLES: Array[Array] = [
	[&"upper_port", Vector2(122.0, 161.0), Vector2(25.32, -8.77), 0.0],
	[&"lower_port", Vector2(320.0, 162.0), Vector2(128.115, -8.77), 0.0],
	[&"upper_center", Vector2(523.815, 162.0), Vector2(128.115, -8.77), 194.1],
	[&"lower_center", Vector2(575.0, 163.0), Vector2(25.32, -8.77), 0.0],
	[&"upper_starboard", Vector2(708.0, 161.0), Vector2(25.32, -8.77), 0.0],
	[&"lower_starboard", Vector2(914.0, 163.0), Vector2(25.32, -8.77), 0.0],
	[&"upper_bow", Vector2(1138.215, 163.0), Vector2(128.115, -8.77), 196.6],
	[&"lower_bow", Vector2(1215.0, 164.0), Vector2(25.32, -8.77), 0.0],
	# 固定长桥由右侧弓架承托，左侧狭缝内以短索连接上梁与黄铜压板。
	[&"bridge", Vector2(1308.0, 211.0), Vector2(2.53, 80.0), 0.0],
]
## 钢索深暖灰外缘，与底图原绘索具同色系。
const CABLE_EDGE := Color(0.19, 0.155, 0.125, 0.9)
## 窄而低对比的金属索芯，用于区分近处承重索和原画栏绳。
const CABLE_CORE := Color(0.48, 0.41, 0.32, 0.85)
## 上梁两处补绘耳环的铜色，取原画梁底五金的暖暗部。
const EYE_BRASS := Color(0.56, 0.40, 0.24, 0.94)
## 浮台承重主索的宽度，单位为战场像素。
const MAIN_WIDTH: float = 1.9
## 固定桥靠船体侧弓支撑，补强用的细索宽度，单位为战场像素。
const BRIDGE_WIDTH: float = 1.35

## 按 [constant CABLES] 缓存关卡实例中的平台节点。缺失时保留空槽，保持索具编号不变。
var _surfaces: Array[BoardSurface] = []
## 缓存上次提交给绘制器的甲板端点。无平台时使用无限向量，跳过该线段。
var _deck_points := PackedVector2Array()
## 阵风只改变外露索中段，最大位移为 1.62 战场像素。
var _sway: float = 0.0

## 从 [param board] 绑定本次棋盘中的现有平台。重新绑定或传入空棋盘时清掉旧索具。
func setup(board: BoardRuntime) -> void:
	z_index = -2 # BattleFrame 在同一跟随相机的 CanvasLayer 上，位于 -1 层。
	_surfaces.resize(CABLES.size())
	_deck_points.resize(CABLES.size())
	for index: int in range(CABLES.size()): # 每条索具固定的槽位。
		var surface_id: StringName = CABLES[index][0] # 棋盘资源声明的平台身份。
		_surfaces[index] = board.surfaces.get(surface_id) if board != null else null
		_deck_points[index] = Vector2.INF
	refresh()
	queue_redraw()

## 由本关环境控制器读取最新平台位姿。保持位置不动时复用 CanvasItem 已提交的绘制命令。
func refresh() -> void:
	var changed: bool = false # 所有端点合用一次重绘请求。
	for index: int in range(_surfaces.size()): # 查询每条索具绑定的实际平台。
		var point := Vector2.INF # 平台释放或缺失时清除旧端点。
		if is_instance_valid(_surfaces[index]):
			var surface: BoardSurface = _surfaces[index] # 与地块和植物共用的移动节点。
			var fitting: Vector2 = CABLES[index][2] # 按原画缩放换算的平台局部金属锚点。
			# 两个 Canvas 都跟随同一相机，在战场坐标转接，不用屏幕坐标或额外的相机补偿。
			point = to_local(surface.to_global(fitting))
		if _deck_points[index] != point:
			_deck_points[index] = point
			changed = true
	if changed:
		queue_redraw()

## [param seconds] 来自共同风场。[param pressure] 已按画质和减少动效设置衰减。
func apply_wind(seconds: float, pressure: float) -> void:
	var bend: float = smoothstep(0.03, 0.87, pressure) * (0.60 + 1.02 * sin(seconds * 2.5)) # 向船尾轻微受力，端点继续固定。
	if is_equal_approx(bend, _sway):
		return
	_sway = bend
	queue_redraw()

## 直索只接向上梁。靠泊时，原画遮住缩短的索段及其入梁位置。
func _draw() -> void:
	for index: int in range(_deck_points.size()): # 只绘制当前有平台的索具。
		var deck_point: Vector2 = _deck_points[index] # 随原有平台移动的索尾。
		if not deck_point.is_finite():
			continue
		var hull_point: Vector2 = CABLES[index][1] # 固定在原画上梁或弓架顶端。
		if deck_point.y <= hull_point.y:
			continue # 显式位移若越过梁顶，收起该索以免画出反向受力。
		var width: float = BRIDGE_WIDTH if CABLES[index][0] == &"bridge" else MAIN_WIDTH # 桥侧补强索做细一级。
		if absf(_sway) > 0.025 and width == MAIN_WIDTH and deck_point.y - hull_point.y > 33.0:
			var center: Vector2 = hull_point.lerp(deck_point, 0.54) + Vector2(_sway, 0.0) # 两端仍紧贴金属锚点。
			_draw_cable_segment(hull_point, center, width)
			_draw_cable_segment(center, deck_point, width)
		else:
			_draw_cable_segment(hull_point, deck_point, width)
		var eye_y: float = CABLES[index][3] # 普通梁段的外缘位置，原绘箍件处为零。
		if eye_y > 0.0 and deck_point.y > eye_y:
			var eye := Vector2(hull_point.x, eye_y) # 耳环上半埋入梁底，下半接上外露索线。
			draw_circle(eye, 2.35, CABLE_EDGE, true, -1.0, true)
			draw_circle(eye + Vector2(-0.25, 0.45), 1.03, EYE_BRASS, true, -1.0, true)

## 从 [param from] 到 [param to] 绘制暖灰外缘及细索芯，[param width] 为战场像素。
func _draw_cable_segment(from: Vector2, to: Vector2, width: float) -> void:
	draw_line(from, to, CABLE_EDGE, width, true)
	draw_line(from, to, CABLE_CORE, width * 0.4, true)
