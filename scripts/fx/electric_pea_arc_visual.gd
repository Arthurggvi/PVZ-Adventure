## 电能豌豆的共享放电画布：真实端点间的分段电弧、短分叉和收束命中火花。
## 仅保存表现快照，不参与目标选择、碰撞或伤害；暂停时保持当前放电相位。
extends Node2D
class_name ElectricPeaArcVisual

## 每个战场只建立一个短时放电画布。
const NODE_NAME: StringName = &"ElectricPeaArcVisual"
## 高密度战斗最多同时保留的放电表现，超额仅淘汰最早的视觉快照。
const MAX_BURSTS: int = 64
## 单次放电连同命中余辉的游戏秒数。
const LIFETIME: float = 0.23
## 亮芯由起点传至终点的游戏秒数，不影响已经同步完成的伤害。
const TRAVEL_TIME: float = 0.024
## 电能豌豆独立的各阶电光颜色；不修改其他电系植物。
const PromotionArt = preload("res://scripts/adventure/plant_art/adventure_electric_peashooter_promotion_art.gd")
## 将全部弧线和火花组合为一个原生三角批次。
const StrokeBatch = preload("res://scripts/fx/electric_pea_stroke_batch.gd")


## 一次放电的端点和短时钟；首次可见时才生成各相位的固定几何。
class Burst extends RefCounted:
	## 原战场身份，换场、换轮次或结束后立即丢弃表现。
	var shot: ElectricPeaShotContext
	## 发射点在画布内的固定位置。
	var origin: Vector2
	## 电弧局部终点，也是命中火花的中心。
	var impact: Vector2
	## 由放电序号和来源生成的种子，不参与战斗随机序列。
	var seed: int
	## 实际出手等阶的细芯、边缘与辉光颜色。
	var colors: Dictionary
	## 负数代表仅视觉的跳跃等待，非负数为本次放电已经过去的游戏秒数。
	var age: float = 0.0
	## 首次强放电和随后较弱回闪的两条固定主路径。
	var paths: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
	## 每相位首次绘制完整主弧时留下的四色顶点，下一显示帧可直接复制。
	var strand_vertices: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
	## 两次主路径各自最多三条短枝，缓存为独立端点对供同色批绘。
	var branches: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
	## 命中时向外散开的六条固定碎电弧端点对，坐标相对终点。
	var sparks := PackedVector2Array()


## 当前有界的短时放电列表，原始和折射放电共用预算。
var _bursts: Array[Burst] = []
## 当前显示更新前有放电加入或被替换，暂停时也要同步这类变化。
var _redraw_pending: bool = false
## 每次生成递增的局部种子，不消耗战斗的全局随机序列。
var _serial: int = 0
## 当前帧共用的描边与光点绘制数据。
var _strokes := StrokeBatch.new()


## 在 [param shot] 原战场由 [param origin] 放电到 [param impact]。
## [param delay] 只延迟表现的游戏秒数，供折射逐段可读；不会延迟任何实际攻击。
static func spawn(shot: ElectricPeaShotContext, origin: Vector2, impact: Vector2, delay: float = 0.0) -> void:
	if not shot.is_active():
		return
	var canvas: ElectricPeaArcVisual = shot.game.bullets.get_node_or_null(NodePath(NODE_NAME)) as ElectricPeaArcVisual # 所有放电共用画布与预算。
	if canvas == null:
		canvas = ElectricPeaArcVisual.new()
		canvas.name = NODE_NAME
		canvas.z_index = 350
		canvas.process_mode = Node.PROCESS_MODE_ALWAYS
		shot.game.bullets.add_child(canvas)
	canvas._append(shot, canvas.to_local(origin), canvas.to_local(impact), delay)


## 对 [param seed] 的第 [param index] 个采样返回稳定的 0～1 小数，不读取或改写任何随机状态。
static func noise(seed: int, index: int) -> float:
	return fposmod(sin(float(posmod(seed, 65521)) * 0.731 + float(index) * 43.137) * 43758.5453, 1.0)


## 在 [param start] 与 [param finish] 之间生成端点固定的折线；[param seed] 决定稳定的不规则节距。
## [param deviation] 为最大侧偏像素，[param spacing] 为期望节距，[param max_segments] 限制远距离绘制预算。
static func make_path(start: Vector2, finish: Vector2, seed: int, deviation: float,
		spacing: float = 14.0, max_segments: int = 24) -> PackedVector2Array:
	var direction: Vector2 = finish - start # 两端固定，只在中间节点施加横向偏移。
	var count: int = clampi(ceili(direction.length() / maxf(1.0, spacing)), 3, maxi(3, max_segments)) # 长弧不无限增加顶点。
	var normal: Vector2 = direction.normalized().orthogonal() # 偏移始终垂直于真实端点连线。
	var points := PackedVector2Array([start]) # 首尾精确钉在真实发射点与命中点。
	for index: int in range(1, count): # 每段内部的采样位置互不交叉。
		var fraction: float = (float(index) + (noise(seed, index) - 0.5) * 0.44) / float(count) # 节距不等，避免规则锯齿。
		var envelope: float = sin(fraction * PI) # 两端收束，火花不会从目标旁边脱开。
		var offset: float = (noise(seed, index + 37) * 2.0 - 1.0) * deviation * envelope # 一次生成后固定到下一次回闪。
		points.append(start.lerp(finish, fraction) + normal * offset)
	points.append(finish)
	return points


## 在 [param canvas] 绘制 [param points]；[param colors] 使用 core/rim/glow 三色，[param energy] 为 0～1 强度。
## [param core_width] 只控制细亮芯，低透明外光不承担碰撞含义；少于两点时不绘制。
static func draw_strand(canvas: CanvasItem, points: PackedVector2Array, colors: Dictionary,
		energy: float, core_width: float = 1.1) -> void:
	if points.size() < 2 or energy <= 0.001:
		return
	canvas.draw_polyline(points, Color(colors.glow, energy * 0.065), core_width + 6.2, true)
	canvas.draw_polyline(points, Color(colors.rim, energy * 0.18), core_width + 3.0, true)
	canvas.draw_polyline(points, Color(colors.rim, energy * 0.62), core_width + 0.9, true)
	canvas.draw_polyline(points, Color(colors.core, energy), core_width, true)


## 记录 [param shot] 从 [param start] 至 [param finish] 的表现信息，[param delay] 只用于视觉接力。
## 密集放电中被提前挤出的快照跳过几何生成。
func _append(shot: ElectricPeaShotContext, start: Vector2, finish: Vector2, delay: float) -> void:
	if _bursts.size() >= MAX_BURSTS:
		_bursts.pop_front()
	_serial += 1
	var burst := Burst.new() # 首次可见时再绘制此快照的折线或火花。
	burst.shot = shot
	burst.origin = start
	burst.impact = finish
	var rank: int = clampi(shot.appearance_rank, 0, PromotionArt.EFFECT_PALETTES.size() - 1) # 当前画布只读取共享色表。
	burst.colors = PromotionArt.EFFECT_PALETTES[rank]
	burst.age = -maxf(0.0, delay)
	burst.seed = _serial * 97 + shot.source_id
	_bursts.append(burst)
	_redraw_pending = true
	set_process(true)


## 为 [param path] 生成最多三条短分叉；[param seed] 决定固定根部与方向，不产生新的命中点。
static func _make_branches(path: PackedVector2Array, seed: int) -> PackedVector2Array:
	var branches := PackedVector2Array() # 三条短枝转成互不连接的端点对，主线再长也不增加总数。
	var direction: Vector2 = (path[-1] - path[0]).normalized() # 短枝略朝原电流方向延伸。
	var normal: Vector2 = direction.orthogonal() # 奇偶分叉落在主线两侧。
	var reach: float = minf(path[0].distance_to(path[-1]) * 0.16, 17.0) # 极短连接不会长出比主线更大的分叉。
	if reach < 3.0:
		return branches
	for index: int in range(3): # 视觉预算固定且不可再递归分叉。
		var root_index: int = clampi(roundi((0.22 + float(index) * 0.26 + noise(seed, index) * 0.09) * float(path.size() - 1)), 1, path.size() - 2) # 根部避开真实端点。
		var root: Vector2 = path[root_index] # 枝线必须实际接到当前主线。
		var side: float = -1.0 if index % 2 == 0 else 1.0 # 两侧轮流出现，避免梳子状排布。
		var finish: Vector2 = root + (direction * 0.46 + normal * side) * reach * lerpf(0.55, 1.0, noise(seed, index + 20)) # 每枝长度不同。
		branches.append_array(_path_segments(make_path(root, finish, seed + index * 29, 2.4, 5.0, 4)))
	return branches


## 将 [param path] 的连续折线转换为独立端点对，保留每一段几何且不连接不同短枝；少于两点时返回空数组。
static func _path_segments(path: PackedVector2Array) -> PackedVector2Array:
	var segments := PackedVector2Array() # 只在放电建立时展开，绘制时直接复用。
	for index: int in range(1, path.size()): # 相邻两点各形成一段，拐角点供前后两段共用。
		segments.append(path[index - 1])
		segments.append(path[index])
	return segments


## [param delta] 为游戏秒；暂停只检查战场有效性，不推进放电、跳跃等待或命中余辉。
func _process(delta: float) -> void:
	var paused: bool = get_tree().paused # 自身始终处理，以便暂停期间换场仍及时清除旧表现。
	var redraw: bool = _redraw_pending or not paused # 暂停时只为增加或失效的快照刷新画面。
	_redraw_pending = false
	for index: int in range(_bursts.size() - 1, -1, -1): # 倒序可安全淘汰失效与过期快照。
		var burst: Burst = _bursts[index] # 本次放电完整共享同一时钟。
		if not burst.shot.is_active():
			_bursts.remove_at(index)
			redraw = true
			continue
		if not paused:
			burst.age += delta
		if burst.age >= LIFETIME:
			_bursts.remove_at(index)
	if _bursts.is_empty():
		# 保留空画布供后续半秒放电复用，避免同帧释放后再次添加的命名竞争。
		set_process(false)
	if redraw:
		queue_redraw()


## 按固定两次脉冲和局部命中衰减绘制全部快照。
func _draw() -> void:
	_strokes.clear()
	for burst: Burst in _bursts: # 预算内的每个命中拥有自己的端点与颜色。
		if burst.age < 0.0:
			continue
		var first: float = pow(maxf(0.0, 1.0 - burst.age / 0.076), 0.6) # 首次急亮，约四帧后迅速熄灭。
		var echo: float = maxf(0.0, 1.0 - absf(burst.age - 0.101) / 0.035) * 0.72 # 稍弱回闪形成明确放电节奏。
		var energy: float = maxf(first, echo) # 中间短暗隙可看清两次放电。
		var arrived: bool = burst.age >= TRAVEL_TIME # 前沿抵达后才能绘制短枝或命中光点。
		if energy > 0.001:
			var phase: int = 0 if burst.age < 0.076 else 1 # 回闪使用另一套固定折线。
			_append_strand(burst, phase, energy, arrived)
		if arrived:
			_append_impact(burst)
	_strokes.submit(self)


## 在此批次添加 [param burst] 的第 [param phase] 套主弧；[param energy] 为亮度，[param arrived] 控制短枝出现。
func _append_strand(burst: Burst, phase: int, energy: float, arrived: bool) -> void:
	if burst.paths[phase].is_empty():
		var length: float = burst.origin.distance_to(burst.impact) # 长弧侧偏略宽，但不铺成大片光带。
		var deviation: float = clampf(length * 0.045, 2.0, 7.0) # 沿用出手与回闪各自的确定性轮廓。
		burst.paths[phase] = make_path(burst.origin, burst.impact, burst.seed + phase * 193, deviation, 12.0, 32)
	var path: PackedVector2Array = burst.paths[phase] # 完整折线只在第一次需要时生成。
	if not arrived:
		_strokes.add_strand(_prefix(path, burst.age / TRAVEL_TIME), burst.colors, energy)
		return
	burst.strand_vertices[phase] = _strokes.add_complete_strand(path, burst.colors, energy, burst.strand_vertices[phase])
	if burst.branches[phase].is_empty():
		burst.branches[phase] = _make_branches(path, burst.seed + phase * 317)
	_append_filament(burst.branches[phase], burst.colors, energy * 0.48)


## 返回 [param path] 前 [param fraction] 比例的连续折线，末端插值让短放电前沿逐段行进。
static func _prefix(path: PackedVector2Array, fraction: float) -> PackedVector2Array:
	if fraction >= 1.0:
		return path
	var extent: float = clampf(fraction, 0.0, 1.0) * float(path.size() - 1) # 时间映射到已通过的折线段。
	var index: int = mini(floori(extent), path.size() - 2) # 最后一点通过插值补齐。
	var visible: PackedVector2Array = path.slice(0, index + 1) # 已经通过的节点维持原形。
	visible.append(path[index].lerp(path[index + 1], extent - float(index)))
	return visible


## 添加较暗的 [param points] 短枝或火花，使用 [param colors] 配色和 [param energy] 亮度。
## [param offset] 和 [param scale] 将固定火花移至落点并扩散。
func _append_filament(points: PackedVector2Array, colors: Dictionary, energy: float,
		offset: Vector2 = Vector2.ZERO, scale: float = 1.0) -> void:
	if points.is_empty() or energy <= 0.001:
		return
	_strokes.add_segment_layers(points, Color(colors.rim, energy * 0.28), 2.6,
		Color(colors.core, energy * 0.88), 0.7, offset, scale)


## 添加 [param burst] 抵达目标后的紧凑亮核与碎电弧。
func _append_impact(burst: Burst) -> void:
	var age: float = burst.age - TRAVEL_TIME # 命中从电弧前沿抵达时开始衰减。
	var fade: float = pow(maxf(0.0, 1.0 - age / 0.18), 1.7) # 火花比主线略晚熄灭，保留命中落点。
	var flash: float = maxf(0.0, 1.0 - age / 0.055) # 中心亮核仅保留三帧左右。
	if flash > 0.001:
		_strokes.add_disc(burst.impact, 8.0, Color(burst.colors.glow, flash * 0.07))
		_strokes.add_disc(burst.impact, 4.0, Color(burst.colors.rim, flash * 0.19))
		_strokes.add_disc(burst.impact, 1.8, Color(burst.colors.core, flash * 0.95))
	if fade * 0.82 <= 0.001:
		return
	if burst.sparks.is_empty():
		for index: int in range(6): # 保留六个固定、不均匀分布的火花轮廓。
			var angle: float = float(index) * TAU / 6.0 + (noise(burst.seed, index + 110) - 0.5) * 0.62 # 扇区内交错偏转。
			var ray: Vector2 = Vector2.from_angle(angle) # 命中点向外的局部方向。
			var reach: float = lerpf(7.0, 15.0, noise(burst.seed, index + 130)) # 保持爆点足够紧凑。
			burst.sparks.append_array(_path_segments(make_path(ray * 2.0, ray * reach, burst.seed + index * 17, 2.8, 4.0, 4)))
	var expansion: float = 1.0 + age * 1.6 # 六条碎弧共用原有短促外扩，不改变固定折角和宽度。
	_append_filament(burst.sparks, burst.colors, fade * 0.82, burst.impact, expansion)
