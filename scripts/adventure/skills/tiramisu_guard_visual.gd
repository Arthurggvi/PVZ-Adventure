## 花冠守护的世界层演出。植物脚下呈现光印，琉璃墙正面呈现受击和退场光效。
extends Node2D

## 屏障片元使用战斗时钟，并与地面光印分开排序。
const WALL_SHADER: Shader = preload("res://shaders/adventure/tiramisu_guard_wall.gdshader")
## 着色平面连同侧框与辉光的总宽度，单位为世界像素。
const PANE_WIDTH: float = 186.0
## 镶边与高光的象牙金。
const IVORY := Color(1.0, 0.95, 0.76)
## 花粉、碎晶与仪式基座使用温金。
const GOLD := Color(1.0, 0.72, 0.32)
## 保护来源对应的青叶高光。
const MINT := Color(0.61, 0.89, 0.69)
## 限制每帧绘制的余辉数量，保留最近的多行撞击。
const MAX_IMPACTS: int = 8
## 升盾已成立后，花冠在 Cut-in 退开时点亮。
const SEAL_BEAT: float = 1.13

## 当前保护植物的棋盘格，只读取实际占位和世界位置。
var _cells: Array[PlantCell]
## 与受击框一致的竖向高度。
var _height: float
## 玻璃正面的宽度与实际碰撞截面一致。
var _width: float
## 屏障前景的光线和花瓣绘制节点。
var _accents: Node2D
## 屏障主体的每实例参数。
var _material: ShaderMaterial
## 演出开始至今的游戏秒数。
var _elapsed: float = 0.0
## 退出演出起点；负数表示仍在保护植物。
var _exit_start: float = -1.0
## 退出演出归一化进度。
var _exit_progress: float = 0.0
## 血量归零时使用更快的脆裂和向外飞散。
var _broken: bool = false
## [member _impacts] 每项为 (命中纵坐标, 开始秒数, 强度)。
var _impacts: Array[Vector3] = []
## 地面光印低频刷新，棋盘和玻璃的动态分开更新。
var _ground_update: float = 0.0

## 退场的最后一缕光消失后通知宿主释放。
signal dismissed

## [param size] 是实际受击框尺寸。[param cells] 用于跟踪当前受保护植物。
func _init(size: Vector2, cells: Array[PlantCell]) -> void:
	_width = size.x
	_height = size.y
	_cells = cells.duplicate()

## 将地面纹路留在角色下方，透明玻璃与近场高光放在世界临时演出层。
func _ready() -> void:
	z_as_relative = false
	z_index = 2
	var glass := Node2D.new() # 主体着色平面和前景笔触共享高层顺序。
	glass.z_as_relative = false
	glass.z_index = 4010
	add_child(glass)
	var pane := ColorRect.new() # 无贴图的着色平面，中心沿格间障碍布置。
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.position.x = -PANE_WIDTH * 0.5
	pane.size = Vector2(PANE_WIDTH, _height)
	_material = ShaderMaterial.new()
	_material.shader = WALL_SHADER
	_material.set_shader_parameter(&"view_width", PANE_WIDTH)
	_material.set_shader_parameter(&"width_px", _width)
	_material.set_shader_parameter(&"height_px", _height)
	var lanes: Dictionary[int, bool] = {} # 每行形成一扇花窗。
	for cell: PlantCell in _cells: # 稀疏棋盘中同一逻辑行只计算一次。
		lanes[cell.row_col.x] = true
	_material.set_shader_parameter(&"rows", float(lanes.size()))
	pane.material = _material
	glass.add_child(pane)
	# 在琉璃前景同批绘制花瓣和接触光效。
	_accents = Node2D.new()
	glass.add_child(_accents)
	_accents.draw.connect(_draw_glass.bind(_accents))

## 在屏障的 [param local_y] 处添加与 [param amount] 成比例的亮圈。
func impact(local_y: float, amount: int) -> void:
	if amount < 350:
		for hit: Vector3 in _impacts: # 邻近位置的持续啃食沿用还在扩散的光圈。
			if absf(hit.x - local_y) < 27.0 and _elapsed - hit.y < 0.24:
				return
	if _impacts.size() >= MAX_IMPACTS:
		_impacts.pop_front()
	_impacts.append(Vector3(clampf(local_y, 13.0, _height - 13.0), _elapsed,
			clampf(float(amount) / 900.0, 0.22, 1.0)))

## 开始退出演出；[param broken] 为真时从玻璃裂纹向外散开。
func dismiss(broken: bool) -> void:
	_exit_start = _elapsed
	_broken = broken
	_material.set_shader_parameter(&"broken", 1.0 if broken else 0.0)

## [param delta] 全部以游戏秒计，保证暂停和倍速下的演出与判定一致。
func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_elapsed += delta
	if _exit_start >= 0.0:
		_exit_progress = minf((_elapsed - _exit_start) / (0.86 if _broken else 1.12), 1.0)
		if _exit_progress >= 1.0:
			set_process(false)
			dismissed.emit()
			return
	while not _impacts.is_empty() and _elapsed - _impacts[0].y > 0.6:
		_impacts.pop_front()
	_material.set_shader_parameter(&"elapsed", _elapsed)
	_material.set_shader_parameter(&"exit_progress", _exit_progress)
	_accents.queue_redraw()
	_ground_update -= delta
	if _ground_update <= 0.0:
		_ground_update = 0.075
		queue_redraw()

## 地面光印贴在植物脚边；撤销保护时与盾面的末端余辉一同淡出。
func _draw() -> void:
	var bloom: float = smoothstep(0.04, 0.48, _elapsed) * (1.0 - smoothstep(0.0, 0.43, _exit_progress)) # 光印只在实际保护期间稳定可见。
	if bloom <= 0.0:
		return
	for cell: PlantCell in _cells: # 伴生、壳层和底座共用格子的单道光印。
		if not is_instance_valid(cell) or cell.living_plants().is_empty():
			continue
		var rect: Rect2 = cell.get_global_rect() # 移动平台的格子位置以当前帧为准。
		var foot := to_local(Vector2(rect.get_center().x, rect.end.y - rect.size.y * 0.16)) # 椭圆落在株脚平面。
		draw_set_transform(foot, 0.0, Vector2(1.0, 0.31))
		var span: float = minf(32.0, rect.size.x * 0.37) * (1.0 + _exit_progress * 0.72) # 消散时光印向外散开。
		var phase: float = _elapsed * 1.25 + cell.row_col.y * 0.72 # 错开每株的环形流光。
		draw_arc(Vector2.ZERO, span, 0.0, TAU, 27, Color(GOLD, 0.38 * bloom), 3.2, true)
		draw_arc(Vector2.ZERO, span - 2.0, phase, phase + 2.35, 17, Color(IVORY, 0.87 * bloom), 2.6, true)
		draw_arc(Vector2.ZERO, span + 4.0, -phase, -phase + 1.25, 12, Color(MINT, 0.67 * bloom), 1.7, true)
	draw_set_transform(Vector2.ZERO)

## [param canvas] 比玻璃晚提交轮廓、碎片和接触光圈。
func _draw_glass(canvas: Node2D) -> void:
	for hit: Vector3 in _impacts: # 接触位置独立，错峰命中仍保留各自的扩散圈。
		var t: float = (_elapsed - hit.y) / 0.6 # 生命周期归一化。
		var strength: float = (1.0 - t) * (0.56 + hit.z * 0.44) * (1.0 - _exit_progress) # 越重的碰撞越亮。
		var p := Vector2(_width * 0.44, hit.x) # 受击圈从面向僵尸的镶边向外扩散。
		canvas.draw_set_transform(p, 0.0, Vector2(0.62, 1.0))
		canvas.draw_arc(Vector2.ZERO, 8.0 + 49.0 * t, 0.0, TAU, 32, Color(IVORY, strength), 1.8, true)
		canvas.draw_arc(Vector2.ZERO, 8.0 + 70.0 * t, 0.0, TAU, 28, Color(GOLD, strength * 0.44), 3.4, true)
		if hit.z > 0.55:
			canvas.draw_arc(Vector2.ZERO, 19.0 + 92.0 * t, -1.0, 2.0, 26, Color(IVORY, strength * 0.76), 3.1, true)
	canvas.draw_set_transform(Vector2.ZERO)
	var rise: float = smoothstep(0.0, 0.26, _elapsed) # 起势时花叶分层展开。
	var halo: float = (1.0 - _exit_progress) * rise # 退场阶段只剩余光。
	var center := Vector2(0.0, _height * 0.45) # 点亮中段嵌在玻璃上的花冠。
	_draw_seal_wave(canvas, center)
	_draw_crown(canvas, center, halo)
	_draw_motes(canvas, rise)

## [param canvas] 从 [param center] 画出两道沿横梁掠开的折线光波。
func _draw_seal_wave(canvas: Node2D, center: Vector2) -> void:
	var t: float = (_elapsed - (SEAL_BEAT - 0.09)) / 0.52 # 收束时残留相位清晰，光晕不遮挡全屏。
	if t < 0.0 or t >= 1.0:
		return
	var sweep: float = 1.0 - pow(1.0 - t, 2.5) # 快速弹开，尾端放缓。
	var glow: float = pow(1.0 - t, 1.6) # 金边滑过画面后迅速透回角色。
	for dir: float in [-1.0, 1.0]: # 一道向上掠过，一道向下收束到另一端框梁。
		var lower: float = dir * (13.0 + sweep * 155.0) # 保持光波与平直的侧框平行。
		var edge: float = _width * 0.5 + 6.0 + sweep * 21.0 # 尾部略微从框架散开。
		var points := PackedVector2Array([center + Vector2(-edge, lower - dir * 31.0),
				center + Vector2(-edge, lower - dir * 7.0), center + Vector2(-edge + 9.0, lower),
				center + Vector2(edge - 9.0, lower), center + Vector2(edge, lower - dir * 7.0),
				center + Vector2(edge, lower - dir * 31.0)]) # 转角以切面相接，与墙框结构一致。
		canvas.draw_polyline(points, Color(GOLD, glow * 0.48), 5.5, true)
		canvas.draw_polyline(points, Color(IVORY, glow * 0.83), 1.7, true)

## [param canvas] 上的 [param center] 为花冠中心，[param alpha] 控制展开及消散。
func _draw_crown(canvas: Node2D, center: Vector2, alpha: float) -> void:
	var beat: float = exp(-abs(_elapsed - SEAL_BEAT) * 6.2) # 闭锁时冠印短暂显现，平时只留玻璃内纹。
	var opacity: float = alpha * beat # 冠印不改变主墙轮廓。
	if opacity < 0.015:
		return
	var stems := PackedVector2Array([center + Vector2(-32.0, -12.0), center + Vector2(-24.0, 13.0),
			center + Vector2(24.0, 13.0), center + Vector2(32.0, -12.0)]) # 底梁与两支外侧花梗。
	canvas.draw_polyline(stems, Color(GOLD, opacity * 0.83), 2.4, true)
	for i: int in range(3): # 一朵主花和两朵伴花嵌在横梁上。
		var flower := center + Vector2((i - 1) * 28.0, -8.0 - 14.0 * float(i == 1)) # 中心主花略高。
		canvas.draw_line(flower, Vector2(flower.x * 0.8, center.y + 12.0), Color(MINT, opacity), 1.6, true)
		for petal: int in range(5): # 五片菱形高光，花心保持通透。
			var axis := Vector2.from_angle(petal * TAU / 5.0 - PI * 0.5) # 第一片花瓣朝上。
			var flank: Vector2 = axis.orthogonal() * 2.7 # 花瓣的窄侧受光。
			canvas.draw_colored_polygon(PackedVector2Array([flower + axis * 2.0, flower + axis * 6.0 + flank,
					flower + axis * 12.0, flower + axis * 6.0 - flank]), Color(IVORY, opacity))

## [param canvas] 上漂浮花瓣与玻璃碎粒共用固定序列，[param rise] 控制立盾时的可见度。
func _draw_motes(canvas: Node2D, rise: float) -> void:
	for i: int in range(36): # 可控数量的花瓣与细光点，每个粒子由时间和编号解析。
		var seed: float = float(i) * 2.39996 # 黄金角使花瓣与粒子在整面盾上均匀散开。
		var side: float = -1.0 if i % 2 == 0 else 1.0 # 两边沿玻璃边缘涌动。
		var y: float = fposmod(float(i) * 49.1 - _elapsed * (26.0 + float(i % 5) * 6.0), _height) # 稳态花粉上浮。
		var x: float = side * (_width * 0.5 + 4.0 + float(i % 7) * 4.7) + sin(seed + _elapsed * 1.8) * 12.0 # 分布集中在侧框。
		var life: float = rise * smoothstep(0.0, 35.0, minf(y, _height - y)) # 越过上下边缘前渐隐。
		if _exit_start >= 0.0:
			x += (_exit_progress * side * (93.0 if _broken else 49.0) + 21.0 * _exit_progress) * (0.4 + float(i % 6) / 5.0)
			y += _exit_progress * (58.0 if _broken else -58.0)
			life *= 1.0 - smoothstep(0.27, 0.99, _exit_progress)
		var p := Vector2(x, y) # 当前帧粒子坐标。
		var tint: Color = MINT if i % 5 == 0 else GOLD.lerp(IVORY, float(i % 3) * 0.35) # 冷绿晶片与暖金花瓣交替。
		if i % 3 == 0 or _exit_progress > 0.05:
			var axis := Vector2.from_angle(seed + _elapsed * (5.0 if _broken else 1.9)) # 退场脆裂时碎片翻转更快。
			var tip: Vector2 = axis * (3.0 + float(i % 4) + 3.3 * _exit_progress) # 长短交错的立体彩片。
			var width: Vector2 = axis.orthogonal() * 1.8 # 保持薄片轮廓。
			canvas.draw_colored_polygon(PackedVector2Array([p - tip, p + width, p + tip, p - width]), Color(tint, life * 0.76))
		else:
			canvas.draw_circle(p, 1.2 + float(i % 5) * 0.26, Color(tint, life * 0.77), true, -1.0, true)
