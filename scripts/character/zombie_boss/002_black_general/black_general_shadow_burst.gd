## 黑影落地或碎裂的短演出。冲击圈先贴地展开，碎片和黑焰再被气流卷起。
extends Node2D
class_name BlackGeneralShadowBurst

## 与黑将军及令旗共用的黑焰动画。
const FLAME_FRAMES: SpriteFrames = preload("res://assets/adventure/zombies/black_general/parts/fx/generated/BlackSmoke_Back.tres")
## 覆盖冲击圈、碎片和最晚淡出的烟团，单位秒。
const DURATION: float = 1.12
## 不含燃烧区域的暗紫粒子轮廓。
const SOOT: Color = Color(0.09, 0.045, 0.14)
## 火线经过时使用的紫灰高光。
const RIM: Color = Color(0.72, 0.49, 0.84)

## 向上散开的单枚烟焰碎片。
class Shard:
	## 碎片飞出的初始局部位置。
	var start: Vector2
	## 碎片起飞速度，单位像素/秒。
	var velocity: Vector2
	## 碎片熄灭前的战斗秒数。
	var lifetime: float
	## 碎片核心的宽度，单位像素。
	var width: float

## 演出已消耗的战斗时间。
var _age: float = 0.0
## 冲击带出的碎片。
var _shards: Array[Shard] = []

## 在 [param host] 中以 [param feet] 为中心释放。 [param depth] 为绝对层级，[param power] 控制大小和碎片数量。
static func erupt(host: Node2D, feet: Vector2, depth: int, power: float) -> void:
	var burst := BlackGeneralShadowBurst.new() # 由场地或 Boss 承载，独立于被击破的设施。
	burst.top_level = true
	burst.z_as_relative = false
	burst.z_index = depth
	host.add_child(burst)
	burst.global_position = feet
	burst.scale = Vector2.ONE * power
	burst._start(power)

## 根据 [param power] 生成烟团和定向火屑，随机性与战斗抽选独立。
func _start(power: float) -> void:
	var rng := RandomNumberGenerator.new() # 仅用于表现。
	rng.randomize()
	for _index: int in range(roundi(24.0 * power)): # 每次迭代生成一枚向两侧抛出的火屑。
		var shard := Shard.new() # 单枚碎片的弹道和淡出数据。
		shard.start = Vector2(rng.randf_range(-21.0, 21.0), rng.randf_range(-31.0, -6.0))
		shard.velocity = Vector2(rng.randf_range(-145.0, 150.0), rng.randf_range(-226.0, -66.0))
		shard.lifetime = rng.randf_range(0.36, 0.91)
		shard.width = rng.randf_range(0.8, 2.7)
		_shards.append(shard)
	for index: int in range(3): # 中央烟柱先升，另外两团沿地面两侧卷开。
		_add_plume(index)

## [param index] 为烟团的层次和横向飘散方向。
func _add_plume(index: int) -> void:
	var plume := AnimatedSprite2D.new() # 使用原有动画帧细化烟团形状。
	var side: float = float(index - 1) # -1、0、1 对应左、中、右。
	var length: float = 0.83 - absf(side) * 0.11 # 中间烟柱比两侧存留更久。
	plume.sprite_frames = FLAME_FRAMES
	plume.position = Vector2(side * 19.0, -23.0)
	plume.scale = Vector2(0.34, 0.29)
	plume.modulate = Color(0.94, 0.76, 1.0, 0.0)
	add_child(plume)
	plume.play(&"loop")
	plume.frame = index * 7
	var drift := plume.create_tween() # 冲击后短促喷发，往上移动时逐渐松散。
	drift.tween_interval(index * 0.045)
	drift.tween_property(plume, "position", Vector2(side * 81.0 + 12.0, -113.0 + 28.0 * absf(side)), length) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	drift.parallel().tween_property(plume, "scale", Vector2(1.03, 0.81), length)
	var fade := plume.create_tween() # 单独控制透明度，烟团一闪后仍保留可读轮廓。
	fade.tween_interval(index * 0.045)
	fade.tween_property(plume, "modulate:a", 0.86, 0.09)
	fade.tween_property(plume, "modulate:a", 0.0, length - 0.09)

## [param delta] 为战斗秒数；演出结束时释放所有表现节点。
func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()

## 绘制先后两道地面冲击圈和渐暗的碎片。
func _draw() -> void:
	_draw_ring(_age / 0.46, 122.0, 1.0)
	_draw_ring((_age - 0.09) / 0.62, 151.0, 0.54)
	for shard: Shard in _shards: # 已熄灭的火屑跳过绘制。
		if _age >= shard.lifetime:
			continue
		var heat: float = 1.0 - _age / shard.lifetime # 火屑越冷越短、越暗。
		var point: Vector2 = shard.start + shard.velocity * _age + Vector2(0.0, 111.0 * _age * _age) # 弧形抛射。
		var tail: Vector2 = point - shard.velocity.normalized() * (4.0 + 12.0 * heat) # 沿飞行方向拖出火痕。
		draw_line(point, tail, Color(SOOT, heat * 0.95), shard.width * 2.8, true)
		draw_line(point, tail.lerp(point, 0.28), Color(RIM, heat * heat), shard.width, true)

## [param progress] 为归一化时间，[param distance] 为地面终点半径，[param opacity] 为冲击圈峰值透明度。
func _draw_ring(progress: float, distance: float, opacity: float) -> void:
	if progress < 0.0 or progress >= 1.0:
		return
	var radius: float = lerpf(13.0, distance, 1.0 - pow(1.0 - progress, 2.5)) # 初段迅速扩张。
	var alpha: float = (1.0 - progress) * opacity # 外圈先变细再隐没。
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.23))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 52, Color(SOOT, alpha * 0.90), 8.0, true)
	draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 52, Color(RIM, alpha * 0.85), 2.8, true)
	draw_set_transform(Vector2.ZERO)
