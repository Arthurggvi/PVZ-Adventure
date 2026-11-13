## 原生弹体的材质、连续尾迹和微光，不拥有运动或命中逻辑。
extends Node2D
class_name RepeaterProjectileVisual

## 最长尾迹只保留十二个时间采样，避免随飞行时间增长。
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
	visual._glow = Node2D.new()
	visual._glow.material = RepeaterVisualPalette.glow_material()
	visual._glow.draw.connect(visual._draw_glow)
	visual.add_child(visual._glow)
	# 第二代仅削弱光量，真实伤害和弹体比例由战斗层配置。
	visual._opacity = 0.74 if generation > 1 else 1.0
	visual.modulate.a = visual._opacity
	visual.call_deferred("_mount", weakref(bullet.get_parent()))
	return visual

## 在父节点完成本次入树后挂载；[param host] 是同场景宿主的弱引用。
func _mount(host: WeakRef) -> void:
	var parent: Node = host.get_ref() as Node # 退出场景时不能留下未挂载的孤儿节点。
	if not is_instance_valid(parent) or not parent.is_inside_tree() or parent.is_queued_for_deletion() \
			or not is_instance_valid(_bullet) or _bullet.is_queued_for_deletion():
		free()
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
	_ink.set_shader_parameter(&"effect_seconds", _age)
	if _retire_age < 0.0 and (not is_instance_valid(_bullet) or not is_instance_valid(_body) \
			or _bullet.is_queued_for_deletion() or not _bullet.is_visible_in_tree()):
		_retire_age = 0.0
	if _retire_age >= 0.0:
		_retire_age += delta
		modulate.a = _opacity * (1.0 - RepeaterVisualPalette.smooth(_retire_age / 0.22))
		if _retire_age >= 0.22:
			queue_free()
		queue_redraw()
		_glow.queue_redraw()
		return
	global_position = _body.global_position
	var first_time: float = _sample_wait # 这一显示帧内第一个采样时刻。
	var count: int = maxi(0, floori((delta - first_time) / SAMPLE_INTERVAL) + 1) # 所需数量仅用于计算相位。
	var skipped: int = maxi(count - SAMPLE_LIMIT, 0) # 长帧直接跳过最终一定被丢弃的旧样本。
	if count >= SAMPLE_LIMIT:
		_points.clear()
	for index: int in range(skipped, count): # 每帧最多补十二次，不随后台停顿长度增长。
		var cursor: float = first_time + float(index) * SAMPLE_INTERVAL # 当前有效样本在帧内的秒数。
		_points.append(_last_position.lerp(global_position, clampf(cursor / maxf(delta, 0.0001), 0.0, 1.0)))
		if _points.size() > SAMPLE_LIMIT:
			_points.remove_at(0)
	_sample_wait = clampf(first_time + float(count) * SAMPLE_INTERVAL - delta, 0.0, SAMPLE_INTERVAL)
	_last_position = global_position
	queue_redraw()
	_glow.queue_redraw()

## 绘制灰影、深色尾芯和细光丝；它们始终追随真实飞行轨迹。
func _draw() -> void:
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
	var onset: float = RepeaterVisualPalette.smooth(_age / 0.07) # 出膛光在数帧内展开。
	var pulse: float = 0.85 + 0.15 * sin(_age * 6.0) # 缓慢呼吸代替突变闪灭。
	var halo: float = 38.0 if _kind != &"shock" else 27.0 # 铅黑弹更克制。
	if _retire_age < 0.0:
		_glow.draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(Vector2.ONE * -halo * 0.5, Vector2.ONE * halo), false, Color(_palette[2], 0.24 * onset * pulse))
	for index: int in range(1, _points.size()): # 柔光沿实际尾迹连续渐细。
		var weight: float = float(index) / float(_points.size()) # 新片段透明度更高。
		_glow.draw_line(to_local(_points[index - 1]), to_local(_points[index]), Color(_palette[2], weight * weight * 0.22), 1.2 + weight * 1.8, true)
