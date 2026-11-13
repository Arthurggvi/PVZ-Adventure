## 冥弹的冥河刃影：墨色魂焰、银白裂丝与幽灵残影共享固定采样和单画布，不干预子弹运动。
extends Node2D
class_name RepeaterHadesTrail

## 原40点压缩到24点，密集弹幕时不再不断重建四套曲线。
const MAX_SAMPLES: int = 24
## 统一采样间隔（战斗秒），独立于渲染帧率。
const SAMPLE_STEP: float = 1.0 / 45.0
## 限制世界空间烟痕长度，不因速度或帧率变化而无限延伸。
const MAX_LENGTH: float = 170.0

## 子弹原生可见身体，只有位置依赖。
var _body: Node2D
## 截断的世界坐标历史。
var _history := PackedVector2Array()
## 上一帧弹头坐标，用于时间采样插值。
var _previous: Vector2
## 下一个时间采样前的剩余秒数。
var _sample_age: float = 0.0
## 用于烟丝错相的可暂停显示时间。
var _age: float = 0.0
## 最近一次真正重绘的显示秒数。
var _last_draw: float = -1.0
## 弹头不可见后保持旧纹理渐隐，不再重新生成尾迹。
var _stopped: bool = false

## 读取真实弹头坐标并生成一个固定长度队列；父类负责退场淡化。
func configure(body: Node2D) -> void:
	_body = body
	_previous = body.global_position
	_history.append(_previous)

## 进入场景才计算活跃尾迹，未挂载而释放的对象不泄漏预算。
func _enter_tree() -> void:
	RepeaterVisualBudget.enter(&"trail")

## 弹体结束、跨轮或释放时归还预算。
func _exit_tree() -> void:
	RepeaterVisualBudget.leave(&"trail")

## 低开销轨迹采样；不再在每个渲染帧里逐点复制多条PackedArray。
func _process(delta: float) -> void:
	_age += delta
	if not _stopped and is_instance_valid(_body) and _body.is_inside_tree() \
			and not _body.is_queued_for_deletion() and _body.is_visible_in_tree():
		var now: Vector2 = _body.global_position # 运动真实来源，不在尾迹内部推进弹体。
		_sample_age += delta
		var count: int = mini(MAX_SAMPLES, floori(_sample_age / SAMPLE_STEP))
		for i: int in range(count):
			var t: float = float(i + 1) / float(maxi(count, 1))
			_history.append(_previous.lerp(now, t))
			if _history.size() > MAX_SAMPLES:
				_history.remove_at(0)
		_sample_age = fposmod(_sample_age, SAMPLE_STEP)
		while _history.size() > 2 and _history[0].distance_to(now) > MAX_LENGTH:
			_history.remove_at(0)
		_previous = now
	else:
		_stopped = true
	if _last_draw < 0.0 or _age - _last_draw >= RepeaterVisualBudget.interval():
		_last_draw = _age
		queue_redraw()

## 墨刃、薄烟、银裂与幽影共享同一轨迹；用显式三角带避免短尾和弯曲时的三角化错误。
func _draw() -> void:
	var sample_count: int = _history.size() # 当前有效的世界空间采样数。
	if sample_count < 2:
		return
	var quality: int = RepeaterVisualBudget.quality() # 并发只影响装饰层，黑色主刃始终保留。
	var stride: int = 1 if quality == RepeaterVisualBudget.FULL else (2 if quality == RepeaterVisualBudget.MEDIUM else 3) # 单次最多二十四点。
	var path := PackedVector2Array() # 真实飞行曲线，不以固定方向假造尾迹。
	for index: int in range(0, sample_count, stride): # 先过滤重复采样，静止弹体不会产生退化画布数据。
		var point: Vector2 = to_local(_history[index]) # 旧世界点映射到当前弹头所在的画布。
		if path.is_empty() or path[-1].distance_squared_to(point) > 0.0025:
			path.append(point)
	var head: Vector2 = to_local(_history[-1]) # 精确连接最后采样点，低预算也不提前断尾。
	if path.is_empty() or path[-1].distance_squared_to(head) > 0.0025:
		path.append(head)
	if path.size() < 2:
		return
	var shadow_path: PackedVector2Array = _wisp_path(path, 3.0, 0.0) # 主刃轻微摆动，轮廓仍紧贴真实轨迹。
	_ribbon(shadow_path, 12.0, Color(0.12, 0.10, 0.21, 0.0), Color(0.13, 0.14, 0.23, 0.40)) # 大轮廓薄雾只铺低透明度。
	_ribbon(shadow_path, 8.2, Color(0.035, 0.025, 0.070, 0.0), Color(0.016, 0.020, 0.035, 0.92)) # 不透明主刃与草地建立明确黑色剪影。
	var silver_path: PackedVector2Array = _wisp_path(path, 3.2, PI) # 银裂在黑色魂焰中穿行，与主刃反相。
	_ribbon(silver_path, 1.3, Color(0.26, 0.34, 0.52, 0.0), Color(0.70, 0.84, 0.98, 0.84))
	_ribbon(silver_path, 0.42, Color(0.50, 0.63, 0.80, 0.0), Color(0.96, 0.98, 1.0, 0.91)) # 白色只保留亚像素裂芯，不形成整片白尾。
	if quality != RepeaterVisualBudget.CHEAP:
		for side: int in range(2): # 两条宽度和错相不同的分叉幽烟。
			var wisp: PackedVector2Array = _wisp_path(path, 9.0 + float(side) * 3.0, float(side) * PI + 0.8) # 两侧飘逸幅度仍在单格范围内。
			var hue: Color = Color(0.40, 0.54, 0.70, 0.31) if side == 0 else Color(0.40, 0.31, 0.63, 0.27) # 青银与紫影仅作边缘辅色。
			_ribbon(wisp, 2.8, Color(hue, 0.0), hue)
			_ribbon(wisp, 0.55, Color(hue, 0.0), Color(0.69, 0.79, 0.91, 0.46))
	if quality == RepeaterVisualBudget.FULL:
		_draw_echoes(path) # 低预算去掉鬼影，主刃层级仍完整。
	if not _stopped:
		var heading: Vector2 = (path[-1] - path[-2]).normalized() # 刃尖跟随真实弹道转向。
		var normal: Vector2 = heading.orthogonal() # 上下两道银裂抱住原生深银弹体。
		draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(head - Vector2(22.0, 17.0), Vector2(44.0, 34.0)), false, Color(0.29, 0.40, 0.66, 0.19))
		for side: int in [-1, 1]: # 向后拉长的两个弯刃构成锋利的弹头外轮廓。
			var fin := PackedVector2Array([head + heading * 11.0, head - heading * 2.0 + normal * float(side) * 10.0, head - heading * 26.0 + normal * float(side) * 7.0, head - heading * 7.0 + normal * float(side) * 5.0]) # 四点简单凹刃，不依赖曲线自动三角化。
			draw_colored_polygon(fin, Color(0.075, 0.085, 0.14, 0.84))
			draw_polyline(PackedVector2Array([fin[2], fin[1], fin[0]]), Color(0.63, 0.77, 0.94, 0.78), 0.9, true)

## [param path] 为真实局部轨迹；[param amplitude] 控制像素侧摆，[param phase] 让各层魂烟错开。
func _wisp_path(path: PackedVector2Array, amplitude: float, phase: float) -> PackedVector2Array:
	var result := PackedVector2Array() # 与原路径同样有界的装饰中心线。
	var opening: float = clampf(path[0].distance_to(path[-1]) / 45.0, 0.0, 1.0) # 出膛短轨迹压低波幅，避免轮廓突然张开。
	for index: int in range(path.size()): # 两端侧摆归零，始终准确接回弹头。
		var unit: float = float(index) / float(path.size() - 1) # 旧尾到新头的比例。
		var tangent: Vector2 = path[mini(index + 1, path.size() - 1)] - path[maxi(0, index - 1)] # 实际路径的近似切线。
		var displacement: float = sin(unit * TAU * 1.15 - _age * 6.2 + phase) * sin(unit * PI) * amplitude * opening # 水墨般连续蜿蜒，不随机抖动。
		result.append(path[index] + tangent.normalized().orthogonal() * displacement)
	return result

## [param path]、[param width] 决定刃形，[param tail]、[param head] 决定透明度与色阶；所有三角形显式提交。
func _ribbon(path: PackedVector2Array, width: float, tail: Color, head: Color) -> void:
	var vertices := PackedVector2Array() # 每个采样左右一对顶点。
	var colors := PackedColorArray() # 每一岸使用相同的连续渐变。
	var indices := PackedInt32Array() # 一段两个三角形，重叠或尖端零面积不会触发多边形三角化。
	for index: int in range(path.size()): # 最多四十八个顶点，随预算跳点进一步缩减。
		var unit: float = float(index) / float(path.size() - 1) # 尾尖至头部的宽度因子。
		var tangent: Vector2 = path[mini(index + 1, path.size() - 1)] - path[maxi(0, index - 1)] # 曲线方向。
		var half: Vector2 = tangent.normalized().orthogonal() * width * pow(unit, 0.72) # 刃尖向后自然收细。
		vertices.append(path[index] + half)
		vertices.append(path[index] - half)
		colors.append(tail.lerp(head, unit))
		colors.append(tail.lerp(head, unit))
		if index > 0:
			var previous: int = (index - 1) * 2 # 当前片段左端顶点索引。
			indices.append_array(PackedInt32Array([previous, previous + 1, previous + 2, previous + 1, previous + 3, previous + 2]))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, vertices, colors)

## [param path] 上三处残影沿真实方向拉长，深色主体与极薄银边呈现穿行后的灵体回声。
func _draw_echoes(path: PackedVector2Array) -> void:
	for echo: int in range(3): # 固定三枚残影，无额外节点或生命周期。
		var unit: float = 0.25 + float(echo) * 0.23 # 分散在尾迹中段，避开实际弹头。
		var index: int = mini(int(unit * float(path.size() - 1)), path.size() - 2) # 留一后继点计算方向。
		var angle: float = (path[index + 1] - path[index]).angle() # 原生豌豆形状的长轴朝向飞行方向。
		var size: Vector2 = Vector2(14.0 + unit * 11.0, 8.0 + unit * 7.0) # 越接近弹头越接近原生尺寸。
		draw_set_transform(path[index], angle)
		draw_texture_rect(RepeaterVisualPalette.PEA_TEXTURE, Rect2(-size * 0.57, size * 1.14), false, Color(0.59, 0.67, 0.84, unit * 0.18))
		draw_texture_rect(RepeaterVisualPalette.PEA_TEXTURE, Rect2(-size * 0.5, size), false, Color(0.025, 0.028, 0.055, unit * 0.48))
	draw_set_transform(Vector2.ZERO) # 后续刃尖绘制必须恢复原坐标。
