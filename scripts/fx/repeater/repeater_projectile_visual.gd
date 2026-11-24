## 原生弹体的材质、连续尾迹和微光，不拥有运动或命中逻辑。
extends Node2D
class_name RepeaterProjectileVisual

## 普通弹体十二点轻尾迹；晨星与地狱使用单独的有界采样上限。
const SAMPLE_LIMIT: int = 12
## 以秒采样，显示帧率不会改变尾迹密度。
const SAMPLE_INTERVAL: float = 1.0 / 60.0
## 负责运动的原生弹体。
var _bullet: Node2D
## 原生弹体可视身体，只读取其当前世界位置。
var _body: Node2D
## 此弹种的独立材质。
var _ink: ShaderMaterial
## 弹种决定尾迹和微光风格。
var _kind: StringName
## 当前弹种的暗、中、亮三色。
var _palette: PackedColorArray
## 已经过的视觉秒数。
var _age: float = 0.0
## 距离下一次尾迹采样的秒数。
var _sample_wait: float = 0.0
## 世界坐标采样，身体动画或平台移动不会拉长旧尾迹。
var _points: PackedVector2Array = PackedVector2Array()
## 上一视觉帧的位置，用于按时间在两帧之间补齐采样。
var _last_position: Vector2
## 单独加色的柔光层，不影响原本的深色主体。
var _glow: Node2D
## 原弹体结束后的尾迹衰退秒数；负数表示仍在飞行。
var _retire_age: float = -1.0
## 弱化星的基础透明度，独立于结束时的衰退。
var _opacity: float = 1.0
## 冥弹的专用长距离尾迹，与其他弹体的十二点轻尾迹独立。
var _hades_trail: RepeaterHadesTrail
## 晨星、辉夜和两代分裂星共用彗光路径，配色与核心各自独立。
var _celestial: bool = false
## 本枚弹体启用专属彗尾或熔火尾迹。
var _ornate: bool = false
## 有界采样数量：母弹二十点、子星十四点、其他十二点。
var _sample_limit: int = SAMPLE_LIMIT
## 本枚错相使同时发射的尾焰与星光不会同步闪烁。
var _phase: float = 0.0
## 视觉绘制的最后时刻；低预算只限制绘制，不跳过运动采样。
var _last_draw_age: float = -1.0

## 给已入树的 [param bullet] 附加 [param kind] 表现，重复调用返回已有节点。
## [param generation] 是星弹代数，[param color_index] 选择同轮不同颜色；空种类保持原画。
static func attach(bullet: Node2D, kind: StringName, generation: int = 0, color_index: int = 0) -> Node2D:
	if not is_instance_valid(bullet) or kind == &"" or kind == &"none":
		return null
	var previous: Variant = bullet.get_meta(&"repeater_visual") if bullet.has_meta(&"repeater_visual") else null # 缺少元数据时不触发引擎错误。
	if previous is WeakRef and is_instance_valid(previous.get_ref()):
		return previous.get_ref() as Node2D
	if bullet.get_parent() == null:
		return null
	var visual := RepeaterProjectileVisual.new() # 每枚弹体的时间及材质独立。
	visual.name = &"RepeaterVisual"
	visual._bullet = bullet
	visual._body = bullet.get_node_or_null(^"Body") as Node2D
	if visual._body == null:
		visual._body = bullet
	visual._kind = kind
	visual._celestial = kind in [&"morning", &"kaguya", &"star_dark", &"star_light"]
	visual._ornate = visual._celestial or kind == &"hell"
	visual._sample_limit = 20 if kind in [&"morning", &"kaguya", &"hell"] else (14 if visual._celestial else SAMPLE_LIMIT)
	visual._phase = float(bullet.get_instance_id() % 131) * 0.37
	visual._palette = RepeaterVisualPalette.colors(kind, color_index)
	visual._ink = RepeaterVisualPalette.make_material(kind, color_index, float(bullet.get_instance_id() % 97))
	visual._paint(visual._body)
	if kind == &"ember" or kind == &"hell":
		var impact: Node = bullet.get_node_or_null(^"BulletEffect") # 原生火豆退场动画保留同一色系。
		if impact != null:
			visual._paint(impact)
	visual.top_level = true
	visual.z_index = bullet.z_index - 1
	# 材质同步接入，纯尾迹延后挂入同一场景，避免在弹体ready中修改忙碌的父节点。
	bullet.set_meta(&"repeater_visual", weakref(visual))
	visual.global_position = visual._body.global_position
	visual._last_position = visual.global_position
	visual._points.append(visual.global_position)
	if kind != &"hades": # 冥弹仅用专属单画布尾迹，不能再创建重复的尾光层。
		visual._glow = Node2D.new()
		visual._glow.material = RepeaterVisualPalette.glow_material()
		visual._glow.z_index = 2 if visual._ornate else 0 # 尖锐星核只在专属弹体上覆一层细光，尾迹仍在原画后面。
		visual._glow.draw.connect(visual._draw_glow)
		visual.add_child(visual._glow)
	if kind == &"hades":
		visual._hades_trail = RepeaterHadesTrail.new() # 冥弹使用独立历史采样及残影管线。
		visual.add_child(visual._hades_trail)
		visual._hades_trail.configure(visual._body)
	# 第二代仅削弱光量，真实伤害和弹体比例由战斗层配置。
	visual._opacity = 0.74 if generation > 1 else 1.0
	visual.modulate.a = visual._opacity
	visual.call_deferred("_mount", weakref(bullet.get_parent()))
	return visual

## 晨星和熔火尾迹入树时登记成本，密集分裂也能自动降低装饰绘制频率。
func _enter_tree() -> void:
	if _ornate:
		RepeaterVisualBudget.enter(&"trail")

## 尾迹淡出或战斗场景销毁均对称退还预算；冥弹仍由其专用节点登记。
func _exit_tree() -> void:
	if _ornate:
		RepeaterVisualBudget.leave(&"trail")

## 在父节点完成本次入树后挂载；[param host] 是同场景宿主的弱引用。
func _mount(host: WeakRef) -> void:
	var parent: Node = host.get_ref() as Node # 退出场景时不能留下未挂载的孤儿节点。
	if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion() \
			or not is_instance_valid(_bullet) or _bullet.is_queued_for_deletion():
		queue_free()
		return
	parent.add_child(self)

## 将同一私有材质递归赋给 [param root] 的原生纹理节点，不复制动画或纹理。
func _paint(root: Node) -> void:
	for child: Node in root.get_children(): # 原生火豆的分件纹理由动画继续替换。
		if child is Sprite2D or child is AnimatedSprite2D:
			child.material = _ink
		_paint(child)

## [param delta] 是受场景暂停控制的表现时间；尾迹按固定时间间隔采样。
func _process(delta: float) -> void:
	_age += delta
	if _kind != &"hades": # 冥弹没有逐帧着色动画，避免大量子弹反复提交材质参数。
		_ink.set_shader_parameter(&"effect_seconds", _age)
	if _retire_age < 0.0 and (not is_instance_valid(_bullet) or not is_instance_valid(_body) \
			or _bullet.is_queued_for_deletion() or not _bullet.is_visible_in_tree()):
		_retire_age = 0.0
	if _retire_age >= 0.0:
		_retire_age += delta
		var fade_seconds: float = 0.47 if _kind == &"hades" else 0.22 # 冥界烟雾在弹体消失后继续平滑消散。
		modulate.a = _opacity * (1.0 - RepeaterVisualPalette.smooth(_retire_age / fade_seconds))
		if _retire_age >= fade_seconds:
			queue_free()
		if _kind != &"hades":
			queue_redraw()
			if is_instance_valid(_glow):
				_glow.queue_redraw()
		return
	global_position = _body.global_position
	if _kind == &"hades": # 尾迹子节点自行节流渲染，弹体只更新一次世界锚点。
		return
	var first_time: float = _sample_wait # 这一显示帧内第一个采样时刻。
	var count: int = maxi(0, floori((delta - first_time) / SAMPLE_INTERVAL) + 1) # 所需数量仅用于计算相位。
	var skipped: int = maxi(count - _sample_limit, 0) # 长帧直接跳过最终一定被丢弃的旧样本。
	if count >= _sample_limit:
		_points.clear()
	for index: int in range(skipped, count): # 每帧最多补本弹种的固定上限，不随后台停顿长度增长。
		var cursor: float = first_time + float(index) * SAMPLE_INTERVAL # 当前有效样本在帧内的秒数。
		_points.append(_last_position.lerp(global_position, clampf(cursor / maxf(delta, 0.0001), 0.0, 1.0)))
		if _points.size() > _sample_limit:
			_points.remove_at(0)
	_sample_wait = clampf(first_time + float(count) * SAMPLE_INTERVAL - delta, 0.0, SAMPLE_INTERVAL)
	_last_position = global_position
	if _ornate and _last_draw_age >= 0.0 and _age - _last_draw_age < RepeaterVisualBudget.interval():
		return
	_last_draw_age = _age
	queue_redraw()
	_glow.queue_redraw()

## 绘制灰影、深色尾芯和细光丝；它们始终追随真实飞行轨迹。
func _draw() -> void:
	if _ornate:
		_draw_ornate_trail()
		return
	for index: int in range(1, _points.size()): # 时间较新的片段更亮、更粗。
		var weight: float = float(index) / float(_points.size()) # 使尾端自然收尖。
		var a: Vector2 = to_local(_points[index - 1]) # 旧世界采样转为当前局部画布。
		var b: Vector2 = to_local(_points[index]) # 新世界采样。
		var color: Color = _palette[1] # 保留主体色，不靠纯白堆亮。
		color.a = weight * weight * 0.42
		draw_line(a, b, color, 1.0 + 4.0 * weight, true)
		if _kind == &"hades" and index % 3 == 0:
			draw_texture_rect(RepeaterVisualPalette.PEA_TEXTURE, Rect2(a - Vector2.ONE * 9.0, Vector2.ONE * 18.0), false, Color(0.025, 0.02, 0.035, weight * 0.55))
		if _kind == &"morning" or _kind == &"kaguya" or _kind == &"star_dark" or _kind == &"star_light":
			var pulse: float = pow(0.5 + 0.5 * sin(_age * 8.0 + index * 1.9), 3.0) # 错相闪烁不整齐开关。
			var spark: Vector2 = a + Vector2(0.0, sin(index * 3.7 + _age * 2.0) * 6.0) # 小幅旁逸的纯装饰。
			draw_texture_rect(RepeaterVisualPalette.STAR_TEXTURE, Rect2(spark - Vector2.ONE * 3.0, Vector2.ONE * 6.0), false, Color(_palette[2], pulse * weight * 0.65))

## 细柔光和核心呼吸叠加在深色轮廓后面，不遮住原版豌豆形状。
func _draw_glow() -> void:
	if _ornate:
		_draw_ornate_glow()
		return
	var onset: float = RepeaterVisualPalette.smooth(_age / 0.07) # 出膛光在数帧内展开。
	var pulse: float = 0.85 + 0.15 * sin(_age * 6.0) # 缓慢呼吸代替突变闪灭。
	var halo: float = 38.0 if _kind != &"shock" else 27.0 # 铅黑弹更克制。
	if _retire_age < 0.0:
		_glow.draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(Vector2.ONE * -halo * 0.5, Vector2.ONE * halo), false, Color(_palette[2], 0.24 * onset * pulse))
	for index: int in range(1, _points.size()): # 柔光沿实际尾迹连续渐细。
		var weight: float = float(index) / float(_points.size()) # 新片段透明度更高。
		_glow.draw_line(to_local(_points[index - 1]), to_local(_points[index]), Color(_palette[2], weight * weight * 0.22), 1.2 + weight * 1.8, true)

## 专属尾迹使用三层渐尖网格；母弹与子星的尺寸有别，其他弹种完全保持原路径。
func _draw_ornate_trail() -> void:
	if _points.size() < 2:
		return
	var daughter: bool = _kind in [&"star_dark", &"star_light"] # 子星控制面积，密集分裂仍能看清轨迹。
	var width: float = 5.0 if daughter else (9.5 if _celestial else 12.0) # 尾部最宽半径，单位原生像素。
	var path: PackedVector2Array = _trail_path(1.2 if _celestial else 2.8, _phase) # 真实弹道旁仅作小幅波动。
	var shadow: Color = Color(0.055, 0.025, 0.13, 0.0) if _celestial else Color(0.11, 0.016, 0.025, 0.0) # 最旧采样完全透明。
	var rim: Color = Color(0.22, 0.10, 0.48, 0.62) if _celestial else Color(0.28, 0.025, 0.065, 0.73) # 深轮廓在明亮草地上托住光芯。
	_draw_ribbon(self, path, width, shadow, rim)
	var tail: Color = Color(0.28, 0.15, 0.76, 0.0) if _celestial else Color(0.58, 0.04, 0.08, 0.0) # 尾端冷色或暗火。
	var head: Color = Color(0.45, 0.65, 0.96, 0.62) if _celestial else Color(1.0, 0.28, 0.055, 0.78) # 主体附近的饱和色层。
	if daughter:
		tail = Color(_palette[1], 0.0)
		head = Color(_palette[2].lerp(Color(0.45, 0.65, 0.96), 0.28), 0.62) # 同轮子星保留各自的棱彩色相。
	_draw_ribbon(self, path, width * 0.56, tail, head)
	var core: Color = Color(1.0, 0.84, 0.47, 0.82) if _celestial else Color(1.0, 0.79, 0.30, 0.88) # 窄暖芯使亮度集中，不铺开白雾。
	if _kind == &"kaguya":
		core = Color(0.67, 0.91, 1.0, 0.84) # 辉夜用冰蓝银芯与晨星的日金色分开。
	_draw_ribbon(self, path, width * 0.16, Color(core, 0.0), core)
	if _kind in [&"morning", &"kaguya"] and _retire_age < 0.0:
		_draw_orbit(self, Color(0.23, 0.12, 0.43, 0.78), 2.5) # 星核背后的斜轨先描暗边，再由光层描细边。

## 返回追随世界采样的有限曲线；[param amplitude] 为侧摆像素，[param phase] 错开流丝。
func _trail_path(amplitude: float, phase: float) -> PackedVector2Array:
	var result := PackedVector2Array() # 上限二十一点，运行时间不会增加顶点数。
	var stride: int = 2 if RepeaterVisualBudget.quality() == RepeaterVisualBudget.CHEAP else 1 # 低预算跳过中间采样，端点仍准确。
	for index: int in range(0, _points.size(), stride): # 装饰偏移由真实轨迹局部法线决定。
		var unit: float = float(index) / maxf(1.0, float(_points.size() - 1)) # 从旧尾到新头的归一化距离。
		var next: int = mini(index + 1, _points.size() - 1) # 末段使用前一采样避免零向量。
		var previous: int = maxi(0, index - 1) # 局部切线覆盖一前一后的实际轨迹。
		var normal: Vector2 = (_points[next] - _points[previous]).normalized().orthogonal() # 不假设水平发射。
		var wave: float = sin(unit * TAU * 1.45 - _age * 14.0 + phase) * amplitude * sin(unit * PI) # 首尾收敛到真实弹道。
		var point: Vector2 = to_local(_points[index]) + normal * wave # 当前候选曲线顶点。
		if result.is_empty() or result[result.size() - 1].distance_squared_to(point) > 0.0025:
			result.append(point) # 静止或低速时去掉重合顶点，避免零面积网格。
	if result.is_empty() or result[result.size() - 1].length_squared() > 0.0025:
		result.append(Vector2.ZERO) # 最近一次采样之后的当前头部位置。
	return result

## [param canvas] 接收渐尖色带；[param path] 是中心线，[param width] 为头端半宽。
## [param tail] 和 [param head] 分别指定尾端与头端颜色；显式三角带仅用一条绘制指令，零面积尖端由GPU自然忽略。
func _draw_ribbon(canvas: Node2D, path: PackedVector2Array, width: float, tail: Color, head: Color) -> void:
	if path.size() < 2:
		return
	var vertices := PackedVector2Array() # 每个采样左右成对，交给GPU直接画三角带。
	var colors := PackedColorArray() # 逐顶点颜色保持尾端透明到头端发亮的渐变。
	var indices := PackedInt32Array() # 显式三角形索引不依赖凹多边形三角化，急转和短轨迹也安全。
	for index: int in range(path.size()): # 顶点总数不超过四十二。
		var unit: float = float(index) / float(path.size() - 1) # 尾尖到头端的宽度权重。
		var tangent: Vector2 = path[mini(index + 1, path.size() - 1)] - path[maxi(0, index - 1)] # 有限差分获取连续法线。
		var normal: Vector2 = tangent.normalized().orthogonal() # 轨迹静止时偏移为零。
		var taper: float = pow(unit, 0.72) * (0.80 + 0.20 * sin(unit * PI)) # 中段稍丰厚，尾尖快速收细。
		vertices.append(path[index] + normal * width * taper)
		vertices.append(path[index] - normal * width * taper)
		colors.append(tail.lerp(head, unit))
		colors.append(tail.lerp(head, unit))
		if index > 0:
			var previous: int = (index - 1) * 2 # 前一对顶点起点，每段固定两个三角形。
			indices.append_array(PackedInt32Array([previous, previous + 1, previous + 2, previous + 1, previous + 3, previous + 2]))
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, vertices, colors)

## 专属细光包含两股错相光丝与有限闪点；光量集中在芯部，不使用大面积白色叠加。
func _draw_ornate_glow() -> void:
	var daughter: bool = _kind in [&"star_dark", &"star_light"] # 子星的装饰减半，保持分裂识别度。
	var quality: int = RepeaterVisualBudget.quality() # 预算只削减装饰数量。
	var onset: float = RepeaterVisualPalette.smooth(_age / 0.08) # 出膛时平滑点亮。
	var shine: Color = Color(1.0, 0.86, 0.55, onset * 0.64) if _celestial else Color(1.0, 0.46, 0.15, onset * 0.64) # 暖主光。
	if _kind == &"kaguya":
		shine = Color(0.51, 0.85, 1.0, onset * 0.69) # 银蓝主光延续辉夜的冰晶星核。
	if _retire_age < 0.0:
		var halo_size: Vector2 = Vector2(30.0, 26.0) if daughter else Vector2(48.0, 34.0) # 仅核心附近有软光。
		_glow.draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(-halo_size * 0.5, halo_size), false, Color(shine, onset * 0.24))
		if _celestial:
			var nucleus: Color = Color(0.72, 0.94, 1.0) if _kind == &"kaguya" else Color(1.0, 0.91, 0.67) # 两种母弹的核心色温明确不同。
			_draw_spark(_glow, Vector2.ZERO, 9.0 if daughter else 16.0, _age * 0.12, Color(nucleus, onset * (0.58 if daughter else 0.76)))
			if _kind == &"kaguya":
				_draw_spark(_glow, Vector2.ZERO, 10.0, PI * 0.25 - _age * 0.18, Color(0.45, 0.58, 1.0, onset * 0.42)) # 辉夜双层反转星冠。
			if not daughter:
				_draw_orbit(_glow, Color(0.60, 0.76, 1.0, onset * 0.46), 0.85)
		else:
			_glow.draw_line(Vector2(-9.0, 0.0), Vector2(5.0, 0.0), Color(1.0, 0.81, 0.38, onset * 0.74), 2.0, true)
	if _points.size() < 3:
		return
	var strands: int = 1 if daughter or quality == RepeaterVisualBudget.CHEAP else 2 # 两条细光形成绞合的彗尾或火舌。
	for strand: int in range(strands): # 每股各一条有界色带，不分配粒子节点。
		var path: PackedVector2Array = _trail_path(4.0 if _celestial else 6.0, _phase + float(strand) * PI) # 绞合幅度限制在原生弹体宽度内。
		var hue: Color = Color(0.42, 0.64, 1.0, 0.40) if _celestial and strand == 0 else shine # 晨星冷暖两股，地狱保持火焰色。
		_draw_ribbon(_glow, path, 0.75 if daughter else 1.1, Color(hue, 0.0), hue)
	var sparks: int = 2 if daughter or quality != RepeaterVisualBudget.FULL else 4 # 每枚最多四个侧逸闪点。
	for index: int in range(sparks): # 固定索引保证降级时闪点不会重新随机跳位。
		var unit: float = 0.18 + float(index) * 0.19 # 闪点沿已有尾迹分散，不在头部挤成一团。
		var sample: int = clampi(int(unit * float(_points.size() - 1)), 0, _points.size() - 2) # 留下一点用于法线。
		var normal: Vector2 = (_points[sample + 1] - _points[sample]).normalized().orthogonal() # 星屑在弧线两侧摆动。
		var phase: float = _phase + float(index) * 2.73 # 每粒独立闪烁相位。
		var pulse: float = pow(0.5 + 0.5 * sin(_age * 9.0 + phase), 3.0) # 闪亮尖峰之间保留暗部。
		var point: Vector2 = to_local(_points[sample]) + normal * sin(_age * 4.0 + phase) * (6.0 + unit * 7.0) # 不脱离实际飞行轨迹太远。
		if _celestial:
			_draw_spark(_glow, point, 1.5 + pulse * (2.0 if daughter else 3.2), phase, Color(0.73, 0.83, 1.0, unit * pulse * 0.78))
		else:
			_glow.draw_line(point, point - normal * (2.0 + pulse * 3.0), Color(1.0, 0.49 + pulse * 0.25, 0.12, unit * pulse * 0.85), 1.15, true)

## [param canvas] 上的四尖星使用尖细菱形，避免贴图小星星的粗黑描边。
## [param point] 为局部位置，[param radius] 为像素半径，[param angle] 为弧度旋角，[param tint] 为含透明度的颜色。
func _draw_spark(canvas: Node2D, point: Vector2, radius: float, angle: float, tint: Color) -> void:
	var vertices := PackedVector2Array() # 四个长尖与四个短内角组成八顶点星芒。
	for index: int in range(8): # 按圆周顺序闭合，始终为简单凹多边形。
		var length: float = radius if index % 2 == 0 else radius * 0.14 # 内角细窄，光核不会变成方块。
		vertices.append(point + Vector2.from_angle(angle + float(index) * TAU / 8.0) * length)
	canvas.draw_colored_polygon(vertices, tint)

## [param canvas] 绘制不闭合的斜椭圆星轨；[param tint] 为轨道颜色，[param width] 为像素线宽。
func _draw_orbit(canvas: Node2D, tint: Color, width: float) -> void:
	var path := PackedVector2Array() # 只绘制一段偏心轨道，避免完整圆环套住弹体。
	for index: int in range(17): # 十六线段足以表现原生尺寸的平滑轨道。
		var angle: float = float(index) / 16.0 * TAU * 0.72 + _age * 2.7 + _phase # 缺口绕核旋转。
		path.append(Vector2(cos(angle) * 19.0, sin(angle) * 6.5).rotated(-0.55))
	canvas.draw_polyline(path, tint, width, true)
