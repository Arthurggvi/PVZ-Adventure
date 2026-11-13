## 短命的命中星尘与吸取链；只绘制有限粒子，不创建碰撞或伤害事件。
extends Node2D
class_name RepeaterImpactVisual

## 命中演出最长秒数；吸取链使用更短的寿命。
const DURATION: float = 0.64
## 原版细星作为碎屑主体，不使用占位几何代替。
const STAR: Texture2D = preload("res://assets/image/projectile/Projectile_star.png")
## 已经过的表现秒数。
var _age: float = 0.0
## 发生此次命中的弹种。
var _kind: StringName
## 暗、中、亮三个配色。
var _palette: PackedColorArray
## 每枚碎屑的初始角、目标距离、寿命和错相。
var _shards: Array[Vector4] = []
## 冲击方向只用于偏转碎屑，不控制实际伤害区域。
var _direction: Vector2 = Vector2.RIGHT
## 链的终点为局部坐标，空值表示普通命中。
var _chain_end: Vector2 = Vector2.INF
## 独立加色画层保持黑红内外轮廓清晰。
var _glow: Node2D

## 在 [param parent] 下按世界 [param position] 播放 [param kind] 命中；[param direction] 是来向。
static func spawn(parent: Node, kind: StringName, position: Vector2, direction: Vector2 = Vector2.RIGHT) -> Node2D:
	if not is_instance_valid(parent):
		return null
	var effect := RepeaterImpactVisual.new() # 命中特效不依赖已经消失的弹体。
	effect._kind = kind
	effect._palette = RepeaterVisualPalette.colors(kind)
	effect._direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	effect._mount(parent, position)
	effect._seed_shards()
	return effect

## 在 [param parent] 中连接世界坐标 [param from] 与 [param to]，一闪后顺滑消散。
static func chain(parent: Node, from: Vector2, to: Vector2) -> Node2D:
	if not is_instance_valid(parent):
		return null
	var effect := RepeaterImpactVisual.new() # 每次实际吸取对应一条瞬时黑红链。
	effect._kind = &"chain"
	effect._palette = PackedColorArray([Color("#07040b"), Color("#9f183d"), Color("#ff9b9d")])
	effect._mount(parent, from)
	effect._chain_end = to - from
	return effect

## [param parent] 是当前场景宿主；[param position] 是世界锚点。
func _mount(parent: Node, position: Vector2) -> void:
	top_level = true
	z_index = 5
	parent.add_child(self)
	global_position = position
	material = RepeaterVisualPalette.make_material(&"neutral")
	_glow = Node2D.new()
	_glow.material = RepeaterVisualPalette.glow_material()
	_glow.draw.connect(_draw_glow)
	add_child(_glow)

## 视觉随机源只使用本节点身份，不消耗玩法的随机序列。
func _seed_shards() -> void:
	var rng := RandomNumberGenerator.new() # 每次碰撞有独立但稳定的粒子参数。
	rng.seed = get_instance_id() * 104729
	var count: int = 20 if _kind in [&"morning", &"kaguya", &"hell"] else 13 # 控制单次绘制预算。
	for index: int in range(count): # 每枚粒子只保存四个标量，不创建节点或补间。
		var angle: float = TAU * (float(index) + rng.randf_range(0.1, 0.9)) / float(count) # 分层随机避免一边拥挤。
		_shards.append(Vector4(angle, rng.randf_range(18.0, 54.0), rng.randf_range(0.30, DURATION), rng.randf() * TAU))

## [param delta] 受场景暂停控制；所有运动从归一化寿命直接求值。
func _process(delta: float) -> void:
	_age += delta
	if _age >= (0.24 if _chain_end.is_finite() else DURATION):
		queue_free()
		return
	queue_redraw()
	_glow.queue_redraw()

## 每枚星屑先扩散再柔停，切向弧线让轨迹自然舒展。
func _draw() -> void:
	if _chain_end.is_finite():
		_draw_chain(false)
		return
	for index: int in range(_shards.size()): # 过期碎屑直接跳过，演出仍在最长寿命内。
		var shard: Vector4 = _shards[index] # 该碎屑固定的解析参数。
		var t: float = clampf(_age / shard.z, 0.0, 1.0) # 不使用逐帧累加速度，慢帧不会跳变。
		if t >= 1.0:
			continue
		var direction: Vector2 = Vector2.from_angle(shard.x) # 初始放射方向。
		var point: Vector2 = direction * shard.y * RepeaterVisualPalette.out_cubic(t) # 径向减速。
		point += direction.orthogonal() * sin(t * PI) * sin(shard.w) * 12.0
		point += _direction * 8.0 * t
		var fade: float = (1.0 - RepeaterVisualPalette.smooth(t)) * RepeaterVisualPalette.smooth(t / 0.12) # 轻入、缓退。
		var size: float = lerpf(7.5, 2.0, t) * (0.8 + 0.2 * sin(shard.w)) # 尺寸连续收束。
		var tint: Color = _palette[2].lerp(_palette[1], t * 0.7) # 冷却时回到主体色。
		if _kind == &"kaguya" or _kind == &"morning":
			tint = RepeaterVisualPalette.LIGHT_STARS[index % 5]
		tint.a = fade * 0.92
		draw_set_transform(point, shard.w + t * 2.1)
		draw_texture_rect(STAR, Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size), false, tint)
	draw_set_transform(Vector2.ZERO)
	var ring: float = clampf(_age / 0.30, 0.0, 1.0) # 冲击环保持很短，随后交给碎屑。
	draw_arc(Vector2.ZERO, 4.0 + RepeaterVisualPalette.out_cubic(ring) * 26.0, 0.0, TAU, 40, Color(_palette[1], pow(1.0 - ring, 2.0) * 0.78), 1.0 + 2.0 * (1.0 - ring), true)

## 黑色外链加暗红内芯；[param glow] 控制细高光层，曲线不承担拉拽。
func _draw_chain(glow: bool) -> void:
	var fade: float = RepeaterVisualPalette.smooth(_age / 0.025) * (1.0 - RepeaterVisualPalette.smooth((_age - 0.04) / 0.20)) # 快起缓灭。
	var normal: Vector2 = _chain_end.normalized().orthogonal() # 轻微下垂的连接曲线。
	var points := PackedVector2Array() # 十六段已足够表现短促而顺滑的链。
	for index: int in range(17): # 两端固定，不出现跳动的落点。
		var t: float = float(index) / 16.0 # 当前链节的归一化位置。
		points.append(_chain_end * t + normal * sin(t * PI) * (9.0 + sin(t * TAU) * 3.0))
	if glow:
		_glow.draw_polyline(points, Color(_palette[2], fade * 0.43), 1.0, true)
		return
	draw_polyline(points, Color(_palette[0], fade), 6.0, true)
	draw_polyline(points, Color(_palette[1], fade * 0.92), 2.3, true)
	for index: int in range(1, 16, 2): # 隔节绘制扁椭圆，形成真正的链环外观。
		draw_set_transform(points[index], (points[index + 1] - points[index - 1]).angle(), Vector2(1.45, 0.62))
		draw_arc(Vector2.ZERO, 3.8, 0.0, TAU, 12, Color(_palette[1], fade), 1.4, true)
	draw_set_transform(Vector2.ZERO)

## 命中白芯只短暂出现，避免持续亮斑淹没原画。
func _draw_glow() -> void:
	if _chain_end.is_finite():
		_draw_chain(true)
		return
	var flash: float = exp(-_age * 18.0) # 指数衰退没有硬切的末帧。
	var size: float = 34.0 + RepeaterVisualPalette.out_cubic(_age / 0.16) * 28.0 # 光团先开再暗。
	_glow.draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size), false, Color(_palette[2], flash * 0.82))
