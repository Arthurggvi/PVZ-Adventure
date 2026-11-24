## 地面锁定以同平台四格为边界，依次演出扫光捕获、持续追踪、俯冲收束和脱锁。
extends Node2D
class_name CannonTurretWarning

## 第一束扫光横过两排目标格的时间，单位为战斗秒。
const ACQUIRE_SECONDS: float = 0.52
## 空爆退锁或落地亮闪之后的消退时间，单位为战斗秒。
const RELEASE_SECONDS: float = 0.30
## 让路标在草地、木板和亮色植物上都有清晰的暗边。
const INK := Color(0.11, 0.035, 0.028)
## 巡航使用高亮琥珀色。
const TRACK_COLOR := Color(1.0, 0.66, 0.16)
## 末段用红橙将范围与一般追踪状态区分。
const IMPACT_COLOR := Color(1.0, 0.28, 0.17)
## 瞄准点和边角的亮芯，比主色更浅。
const HOT_COLOR := Color(1.0, 0.95, 0.73)

## 四格在首次锁定时的世界轮廓偏移。刚性浮台只平移本节点。
var _tiles: Array[PackedVector2Array] = []
## 各格朝向锁定范围外部的角索引。
var _outer_corners := PackedInt32Array()
## 扫光只在凸四边形内做边间插值，凹格仍保留填色和轮廓。
var _sweepable := PackedByteArray()
## 中央准星的局部半径，根据格距缩放。
var _dial_radius: float = 21.0
## 自第一帧可见起累计的战斗秒数。
var _age: float = 0.0
## 巡航扫光和红色呼吸使用连续相位，导弹转向不会重置。
var _pulse_phase: float = 0.0
## 飞行逻辑报告的末段俯冲进度，取值从 0 到 1。
var _approach: float = 0.0
## 经过插值的俯冲进度。浮台移开时平滑退回琥珀色。
var _urgency: float = 0.0
## 负值表示警告仍有效，非负值表示退锁经过的秒数。
var _release_age: float = -1.0
## 地爆使用短暂热闪，拦截使用暗回收。
var _landed: bool = false


## 战斗结算暂停会停止逐帧更新，先订阅现有同步通知收掉地面标记。
func _ready() -> void:
	TreePauseManager.pause_factors_changed.connect(_on_pause_factors_changed)


## 结算或换轮暂停时隐藏预警，菜单暂停保留当前帧。若结算撤回，有效锁定会同步恢复。
func _on_pause_factors_changed() -> void:
	var settling: bool = TreePauseManager.is_paused_for(TreePauseManager.E_PauseFactor.GameOver) \
			or TreePauseManager.is_paused_for(TreePauseManager.E_PauseFactor.AdventureContinue) \
			or TreePauseManager.is_paused_for(TreePauseManager.E_PauseFactor.ReChooseCard) # 只处理结束战斗的暂停因素。
	visible = not settling and _release_age < RELEASE_SECONDS


## 用 [param cells] 的实际轮廓和 [param center] 构建四格警告。各格留出窄缝用于区分范围。
func lock_cells(cells: Array[PlantCell], center: Vector2) -> void:
	global_position = center
	var shortest: float = INF # 以最短格边约束准星尺寸。
	for cell: PlantCell in cells: # 飞艇平台与有坡度的地块使用同一几何。
		var frame: Transform2D = cell.get_global_transform() # 当前格子完整变换。
		var midpoint: Vector2 = frame * (cell.size * 0.5) - center # 逐格内缩和寻找外角的基准。
		var outline := PackedVector2Array([Vector2.ZERO, Vector2(cell.size.x, 0.0), cell.size,
			Vector2(0.0, cell.size.y)]) # 常规矩形按左上、右上、右下、左下顺序。
		if cell.board_definition != null and cell.board_definition.hit_polygon.size() == 4:
			outline = cell.board_definition.hit_polygon
		var tile := PackedVector2Array() # 画布内的四角，给扫描带插值。
		var outer: int = 0 # 至锁定中心最远的角。
		for index: int in range(outline.size()): # 不假定逻辑列方向等于画面朝向。
			var point: Vector2 = (frame * outline[index] - center).lerp(midpoint, 0.092) # 留出约一条描边宽的间隙。
			tile.append(point)
			if point.length_squared() > tile[outer].length_squared():
				outer = index
		shortest = minf(shortest, minf(tile[0].distance_to(tile[1]), tile[0].distance_to(tile[3])))
		_tiles.append(tile)
		_outer_corners.append(outer)
		_sweepable.append(1 if _can_sweep(tile) else 0)
	_dial_radius = clampf(shortest * 0.30, 11.0, 25.0)
	queue_redraw()


## 判断 [param tile] 的四角是否严格凸出，避免扫线穿过凹角或退化成自交多边形。
static func _can_sweep(tile: PackedVector2Array) -> bool:
	var winding: float = (tile[1] - tile[0]).cross(tile[2] - tile[1]) # 初始边段的转向。
	for index: int in range(1, 4): # 其余角必须具有相同转向。
		var edge: Vector2 = tile[(index + 1) % 4] - tile[index] # 当前边。
		var next_edge: Vector2 = tile[(index + 2) % 4] - tile[(index + 1) % 4] # 与当前边相邻的下一边。
		if winding * edge.cross(next_edge) <= 0.0:
			return false
	return true


## [param center] 是本帧地面落点。[param approach] 来自导弹的俯冲进度。
func track(center: Vector2, approach: float) -> void:
	global_position = center
	_approach = clampf(approach, 0.0, 1.0)


## [param landed] 区分命中时的短热闪和弹体被拦截时的退锁。
func release(landed: bool) -> void:
	_landed = landed
	_release_age = 0.0
	if landed:
		_urgency = 1.0
	queue_redraw()


## [param delta] 为战斗时间。场景暂停同时暂停预警、扫光和俯冲。
func _process(delta: float) -> void:
	_age += delta
	if _release_age >= 0.0:
		_release_age += delta
		if _release_age >= RELEASE_SECONDS:
			hide()
			set_process(false)
			return
	else:
		_urgency = lerpf(_urgency, _approach, 1.0 - exp(-12.0 * delta))
		_pulse_phase = fposmod(_pulse_phase + delta * lerpf(3.0, 9.4, _urgency), TAU)
	queue_redraw()


## 四格轮廓保持可见，扫光在面板内走过，中心准星随实际俯冲逐级收拢。
func _draw() -> void:
	if _tiles.is_empty():
		return
	var acquire: float = smoothstep(0.0, ACQUIRE_SECONDS, _age) # 初始短促聚焦，边界从首帧即出现。
	var fading: float = smoothstep(0.0, RELEASE_SECONDS, _release_age) # 在途时为零。
	var alpha: float = (1.0 - fading) * lerpf(0.58, 1.0, smoothstep(0.0, 0.17, _age)) # 轮廓在整个巡航段可见。
	var pulse: float = 0.5 - 0.5 * cos(_pulse_phase) # 光强有保底，不会随呼吸消失。
	var flash: float = (1.0 - smoothstep(0.0, 0.12, _release_age)) if _landed else 0.0 # 落地时接上爆光。
	var accent: Color = TRACK_COLOR.lerp(IMPACT_COLOR, _urgency).lerp(HOT_COLOR, 0.80 * flash) # 亮芯叠加在警告主色上。
	var sweep_phase: float = _age / ACQUIRE_SECONDS if _age < ACQUIRE_SECONDS \
		else fposmod((_pulse_phase - ACQUIRE_SECONDS * 3.0) / TAU, 1.0) # 捕获结束时扫线先出边，再从上方进入。
	var scan: float = lerpf(-0.24, 2.24, sweep_phase) # 归一化的两行扫描位置。
	var closure: float = lerpf(0.92, 1.0, acquire) - (0.16 * fading if not _landed else 0.0) # 空爆时逐格收拢。
	for index: int in range(_tiles.size()): # 逐格绘制，留出相邻甲板或坡格的真实缝隙。
		var tile: PackedVector2Array = _tiles[index] # 当前目标格内沿。
		var mid: Vector2 = (tile[0] + tile[2]) * 0.5 # 面板缩放原点及世界排行。
		var local_scan: float = scan - (1.0 if mid.y > 0.0 else 0.0) if _sweepable[index] == 1 else -1.0 # 跳过凹格内部扫线。
		draw_set_transform(mid * (1.0 - closure), 0.0, Vector2.ONE * closure)
		_draw_panel(tile, _outer_corners[index], accent, alpha, local_scan, pulse)
	draw_set_transform(Vector2.ZERO)
	_draw_reticle(accent, alpha, acquire, pulse, fading)


## 画 [param tile] 的双层边框及危险扫光。[param outer] 指定加强的外角。
## [param accent] 和 [param alpha] 是当前警告色和整体包络，[param scan] 和 [param pulse] 是局部扫光进度与呼吸强度。
func _draw_panel(tile: PackedVector2Array, outer: int, accent: Color, alpha: float, scan: float, pulse: float) -> void:
	var face: float = alpha * (0.09 + 0.12 * _urgency + 0.035 * pulse) # 上层淡填色保留植物细节。
	draw_polygon(tile, PackedColorArray([Color(accent, face), Color(accent, face * 0.52),
		Color(accent, face * 0.80), Color(accent, face * 1.52)]))
	if _release_age < 0.0 and scan > -0.056 and scan < 1.116:
		var lead: float = clampf(scan - 0.12, 0.0, 1.0) # 扫描带柔和前沿，限制在当前格内。
		var trail: float = clampf(scan + 0.06, 0.0, 1.0) # 短亮沿扫过格面。
		var beam := PackedVector2Array([tile[0].lerp(tile[3], lead), tile[1].lerp(tile[2], lead),
			tile[1].lerp(tile[2], trail), tile[0].lerp(tile[3], trail)]) # 在四边形内插出发光条。
		draw_polygon(beam, PackedColorArray([Color(accent, 0.0), Color(accent, 0.0),
			Color(HOT_COLOR, alpha * 0.24), Color(accent, alpha * 0.39)]))
		var beam_mix: float = sin(PI * clampf(scan, 0.0, 1.0)) # 扫线进出面板时逐步隐去。
		draw_line(beam[3], beam[2], Color(HOT_COLOR, alpha * beam_mix * 0.72), 1.6, true)
	var rim := PackedVector2Array([tile[0], tile[1], tile[2], tile[3], tile[0]]) # 完整边界使四个格子始终可数。
	draw_polyline(rim, Color(INK, alpha * 0.77), 5.4, true)
	draw_polyline(rim, Color(accent, alpha * (0.62 + 0.26 * pulse)), 2.2, true)
	var corner: Vector2 = tile[outer] # 加强锁定范围的四个外侧角。
	var a: Vector2 = tile[(outer + 3) % 4] - corner # 第一条边的向内轴线。
	var b: Vector2 = tile[(outer + 1) % 4] - corner # 第二条边的向内轴线。
	var hook := PackedVector2Array([corner + a * 0.37, corner + a * 0.057,
		corner + b * 0.057, corner + b * 0.37]) # 切去角尖，形成斜面括线。
	draw_polyline(hook, Color(INK, alpha * 0.90), 7.1, true)
	draw_polyline(hook, Color(accent, alpha), 4.1, true)
	var tick: Vector2 = corner + (a + b) * 0.137 # 内侧短划给外角增加方向。
	draw_line(tick + a * 0.10, tick + b * 0.10, Color(HOT_COLOR, alpha * 0.76), 2.1, true)


## [param accent] 和 [param alpha] 控制准星颜色及淡出。
## [param acquire]、[param pulse] 推进捕获与呼吸，[param fading] 在退锁时收掉准星。
func _draw_reticle(accent: Color, alpha: float, acquire: float, pulse: float, fading: float) -> void:
	var radius: float = _dial_radius * lerpf(1.62, 1.0, acquire) * lerpf(1.0, 0.70, _urgency) # 捕获和压低弹道时各收拢一次。
	radius += 1.6 * pulse # 少量连续呼吸。
	radius *= 1.0 + (0.33 * fading if _landed else -0.24 * fading) # 命中略向外散，拦截向内退。
	var angle: float = lerpf(-0.46, 0.0, acquire) # 捕获时四个环段对齐地面十字。
	var glow: Color = accent.lerp(HOT_COLOR, 0.44 + 0.25 * _urgency) # 中央亮度始终高于格边。
	for quarter: int in range(4): # 四段开口圆弧留出清晰的轴向槽。
		var axis: float = angle + float(quarter) * PI * 0.5 # 当前圆弧的起始方向。
		draw_arc(Vector2.ZERO, radius, axis + 0.22, axis + 1.34, 16, Color(INK, alpha * 0.88), 6.0, true)
		draw_arc(Vector2.ZERO, radius, axis + 0.22, axis + 1.34, 16, Color(glow, alpha), 2.8, true)
		var inward: Vector2 = Vector2.from_angle(axis) # 以四轴的短箭头指出真正爆心。
		var side: Vector2 = inward.orthogonal() * 3.8 # 箭头的两个翼端。
		var tip: Vector2 = inward * (radius + 3.0 + (1.0 - _urgency) * 9.0) # 末段短箭头压向圆环。
		var tail: Vector2 = tip + inward * 6.2 # 翼线保持有方向的轮廓。
		var arrow := PackedVector2Array([tail - side, tip, tail + side]) # 外侧成为两段连续折角。
		draw_polyline(arrow, Color(INK, alpha * 0.88), 4.4, true)
		draw_polyline(arrow, Color(accent, alpha), 2.0, true)
	var diamond := PackedVector2Array([Vector2(-4.2, 0.0), Vector2(0.0, -4.2),
		Vector2(4.2, 0.0), Vector2(0.0, 4.2)]) # 中心菱形在草皮与角色轮廓上都可读。
	draw_circle(Vector2.ZERO, 6.5, Color(INK, alpha * 0.79), true, -1.0, true)
	draw_colored_polygon(diamond, Color(HOT_COLOR, alpha))
