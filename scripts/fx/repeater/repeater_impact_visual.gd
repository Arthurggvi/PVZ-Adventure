## 普通变种命中碎光和黑红吸取链；单画布、固定寿命、限并发，无粒子节点。
extends Node2D
class_name RepeaterImpactVisual

## 最长普通弹体命中时间，吸取链缩短到0.24秒。
const DURATION: float = 0.64
## 原版星纹理仍用于非冥弹的瞬时命中。
const STAR: Texture2D = preload("res://assets/image/projectile/Projectile_star.png")

## 可暂停效果年龄，控制进退与生命周期。
var _age: float = 0.0
## 当前弹种，用来决定命中碎片的形态。
var _kind: StringName
## 原有每种弹体独立的三色系。
var _palette: PackedColorArray
## 生成时冻结的碎片运动参数，不逐帧分配。
var _shards: Array[Vector4] = []
## 弹体来向只影响视觉偏转，不改变伤害范围。
var _direction: Vector2 = Vector2.RIGHT
## 吸取链相对终点；INF代表正常命中。
var _chain_end: Vector2 = Vector2.INF
## 上次实际重绘秒数，用于大量特效时减少画布提交。
var _last_draw_age: float = -1.0
## 所属战斗宿主的池；不允许跨战斗保留缓存。
var _pool: RepeaterVisualPool

## 在 [param parent] 中播放命中；[param z] 保证与本行弹体处在同一绘制层。
static func spawn(parent: Node, kind: StringName, position: Vector2,
		direction: Vector2 = Vector2.RIGHT, z: int = 5) -> Node2D:
	if not is_instance_valid(parent) or not RepeaterVisualBudget.may_add_impact():
		return null
	var pool: RepeaterVisualPool = RepeaterVisualPool.under(parent) # 缓存的寿命不超过本战斗宿主。
	if pool == null:
		return null
	var fx: RepeaterImpactVisual = pool.acquire(&"impact") as RepeaterImpactVisual
	if fx == null:
		fx = RepeaterImpactVisual.new() # 对象池耗尽时创建新的单节点视觉。
	fx._pool = pool
	fx._age = 0.0
	fx._last_draw_age = -1.0
	fx._chain_end = Vector2.INF
	fx._shards.clear()
	fx._kind = kind
	fx._palette = RepeaterVisualPalette.colors(kind)
	fx._direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	fx._seed_shards()
	fx._mount(parent, position, z)
	return fx

## [param from] 和 [param to] 是真实吸血帧中双方世界坐标，不读后续尸体状态。
static func chain(parent: Node, from: Vector2, to: Vector2, z: int = 5) -> Node2D:
	if not is_instance_valid(parent) or not RepeaterVisualBudget.may_add_impact():
		return null
	var pool: RepeaterVisualPool = RepeaterVisualPool.under(parent) # 缓存的寿命不超过本战斗宿主。
	if pool == null:
		return null
	var fx: RepeaterImpactVisual = pool.acquire(&"impact") as RepeaterImpactVisual
	if fx == null:
		fx = RepeaterImpactVisual.new()
	fx._pool = pool
	fx._age = 0.0
	fx._last_draw_age = -1.0
	fx._shards.clear()
	fx._kind = &"chain"
	fx._palette = PackedColorArray([Color("#08040d"), Color("#a51a40"), Color("#ff999c")])
	fx._chain_end = to - from
	fx._mount(parent, from, z)
	return fx

## 命中碎片短寿命且有限额，退出场景自动释放预算。
func _enter_tree() -> void:
	RepeaterVisualBudget.enter(&"impact")

## 正常完成、跨轮删除或场景销毁都会释放视觉预算。
func _exit_tree() -> void:
	RepeaterVisualBudget.leave(&"impact")

## 一次挂载只生成单个画布；不创建旧版私有ShaderMaterial和额外光节点。
func _mount(parent: Node, at: Vector2, z: int) -> void:
	top_level = true
	z_as_relative = false
	z_index = mini(z + 1, RenderingServer.CANVAS_ITEM_Z_MAX)
	parent.add_child(self)
	global_position = at

## [param kind] 的固定星屑角度在出生时抽取，不使用全局战斗随机流。
func _seed_shards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id() * 104729
	var count: int = 18 if _kind in [&"morning", &"kaguya", &"hell"] else 12
	for i: int in range(count):
		var angle: float = TAU * (float(i) + rng.randf_range(0.10, 0.90)) / float(count)
		_shards.append(Vector4(angle, rng.randf_range(18.0, 54.0), rng.randf_range(0.30, DURATION), rng.randf() * TAU))

## 高负载压低纯视觉重绘频率；命中只在原有战斗入口结算。
func _process(delta: float) -> void:
	_age += delta
	if _age >= (0.24 if _chain_end.is_finite() else DURATION):
		if is_instance_valid(_pool):
			_pool.release(&"impact", self) # 场景池统一回收且保证预算注销。
		else:
			queue_free()
		return
	if _last_draw_age < 0.0 or _age - _last_draw_age >= RepeaterVisualBudget.interval():
		_last_draw_age = _age
		queue_redraw()

## 命中闪光、冲击环与有界星屑共享唯一绘制指令流。
func _draw() -> void:
	if _chain_end.is_finite():
		_draw_chain()
		return
	var quality: int = RepeaterVisualBudget.quality()
	var stride: int = 1 if quality == RepeaterVisualBudget.FULL else (2 if quality == RepeaterVisualBudget.MEDIUM else 3)
	for i: int in range(0, _shards.size(), stride):
		var shard: Vector4 = _shards[i] # 每粒的半径、方向和寿命都不因LOD变化。
		var t: float = clampf(_age / shard.z, 0.0, 1.0)
		if t >= 1.0:
			continue
		var heading: Vector2 = Vector2.from_angle(shard.x)
		var point: Vector2 = heading * shard.y * RepeaterVisualPalette.out_cubic(t)
		point += heading.orthogonal() * sin(PI * t) * sin(shard.w) * 12.0
		point += _direction * 8.0 * t
		var opacity: float = (1.0 - RepeaterVisualPalette.smooth(t)) * RepeaterVisualPalette.smooth(t / 0.12)
		var hue: Color = RepeaterVisualPalette.LIGHT_STARS[i % 5] if _kind in [&"kaguya", &"morning"] else _palette[2].lerp(_palette[1], t * 0.7)
		hue.a = opacity * 0.90
		var size: float = lerpf(7.5, 2.0, t)
		draw_set_transform(point, shard.w + t * 2.1)
		draw_texture_rect(STAR, Rect2(Vector2.ONE * -size * 0.5, Vector2.ONE * size), false, hue)
	draw_set_transform(Vector2.ZERO)
	var phase: float = clampf(_age / 0.30, 0.0, 1.0)
	draw_arc(Vector2.ZERO, 4.0 + RepeaterVisualPalette.out_cubic(phase) * 26.0,
		0.0, TAU, 28, Color(_palette[1], pow(1.0 - phase, 2.0) * 0.78), 1.3, true)
	var flash: float = exp(-_age * 18.0)
	if flash > 0.07:
		var radius: float = 23.0 + phase * 22.0
		draw_texture_rect(RepeaterVisualPalette.halo_texture(), Rect2(-radius, -radius, radius * 2.0, radius * 2.0),
			false, Color(_palette[2], flash * 0.48))

## 吸取链使用一条有限折线而非每个链节都创建环形弧线。
func _draw_chain() -> void:
	var fade: float = RepeaterVisualPalette.smooth(_age / 0.025) * (1.0 - RepeaterVisualPalette.smooth((_age - 0.04) / 0.20))
	var normal: Vector2 = _chain_end.normalized().orthogonal()
	var segments: int = 12 if RepeaterVisualBudget.quality() == RepeaterVisualBudget.FULL else 7
	var points := PackedVector2Array()
	for i: int in range(segments + 1):
		var t: float = float(i) / float(segments)
		points.append(_chain_end * t + normal * sin(t * PI) * (9.0 + sin(t * TAU) * 3.0))
	draw_polyline(points, Color(_palette[0], fade), 5.0, true)
	draw_polyline(points, Color(_palette[1], fade * 0.95), 2.0, true)
	draw_polyline(points, Color(_palette[2], fade * 0.43), 0.9, true)
