## 救主信徒的短暂余烬，位于教堂世界合成之后。
extends Node2D

## 信徒余烬只保存绘制所需的世界点和战斗时间。
class Burst:
	## 作用的世界中心，创建后不随来源移动。
	var point: Vector2
	## 已经播放的战斗秒数。
	var elapsed := 0.0

## 信徒余烬在半个战斗秒内退场。
const ASH_SECONDS := 0.50
## 追随者消散能使用的最大并发绘制容量。
const FOLLOWER_BUDGET := 16
## 以黄金角错开碎屑和火星，不消耗玩法随机数。
const GOLDEN_ANGLE := 2.39996323
## 深红外焰，适于小面积半透明叠加。
const CRIMSON := Color(0.90, 0.088, 0.203)
## 黑蜡和追随者灰烬的紫灰反光。
const VIOLET_EDGE := Color(0.48, 0.24, 0.40)
## 战斗世界画布，用来每帧读取实际镜头变换。
var _world: Node2D
## 所有尚在播放的短暂演出，按加入先后保存。
var _bursts: Array[Burst] = []
## 所有局部光晕共用的低分辨率柔边贴图。
var _glow: GradientTexture2D


## [param world] 持有战斗相机变换。所有输入均为该画布的全局坐标。
func configure(world: Node2D) -> void:
	_world = world
	queue_redraw()


## 在 [param point] 上方留下少量追随者灰烬，密集消散时限制并发数量。
func follower_burst(point: Vector2) -> void:
	if _bursts.size() >= FOLLOWER_BUDGET:
		return
	var burst := Burst.new() # 余烬保持在实际死亡或复生的世界点。
	burst.point = point
	_bursts.append(burst)
	_refresh_activity()

## 战斗结束时收走局部余焰。
func clear() -> void:
	_bursts.clear()
	_refresh_activity()


## 一次生成小型柔边贴图，停用无演出时的帧更新。
func _ready() -> void:
	var gradient := Gradient.new() # 从亮心向边缘多段衰减，避免外圈有接缝。
	gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.61, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.66), Color(1, 1, 1, 0.11), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.width = 48
	_glow.height = 48
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.gradient = gradient
	_refresh_activity()


## [param delta] 是随暂停与游戏速度变化的战斗秒数。
func _process(delta: float) -> void:
	for index: int in range(_bursts.size() - 1, -1, -1): # 从后往前回收，保留仍活动实例的顺序。
		var burst: Burst = _bursts[index] # 同一个对象中保存年龄和寿命。
		burst.elapsed += delta
		if burst.elapsed >= ASH_SECONDS:
			_bursts.remove_at(index)
	_refresh_activity()


## 画面仅在存在特效时继续刷新；撤去最后一个效果也强制重绘一次。
func _refresh_activity() -> void:
	set_process(not _bursts.is_empty())
	queue_redraw()


## 统一把技能的全局坐标变换到教堂合成画布，以实景镜头和缩放为准。
func _draw() -> void:
	if not is_instance_valid(_world) or not _world.is_inside_tree():
		return
	var world_to_local: Transform2D = get_global_transform_with_canvas().affine_inverse() * _world.get_canvas_transform() # 同时扣除本画布自身的变换。
	draw_set_transform_matrix(world_to_local)
	for burst: Burst in _bursts: # 以世界脚点叠加余波与碎屑。
		_draw_ashes(burst.point, burst.elapsed / ASH_SECONDS)


## [param point] 上方的少量灰烬随 [param progress] 沿不同高度解体。
func _draw_ashes(point: Vector2, progress: float) -> void:
	var fade: float = 1.0 - smoothstep(0.04, 1.0, progress) # 维持配角的低亮度与轻短余波。
	var size_factor: float = lerpf(0.42, 1.0, fade) # 淡出时保留最小碎点几何，避免退化。
	_halo(point - Vector2(0, 19), Vector2(26, 50) * (0.84 + 0.63 * progress), Color(VIOLET_EDGE, fade * 0.24))
	for index: int in range(9): # 粗黑的碎点间只混少数余火。
		var turn: float = index * GOLDEN_ANGLE + point.x * 0.09 # 同一死亡点的碎屑移动可复现。
		var speck: Vector2 = point + Vector2(cos(turn) * (5.0 + 23.0 * progress), -5.0 - float(index * 13 % 45) - sin(turn) * 18.0 * progress) # 从追随者身体附近脱离。
		var tint: Color = CRIMSON if index % 3 == 0 else VIOLET_EDGE # 部分碎点保留暗红沿边。
		_diamond(speck, Vector2(1.5 + index % 2, 2.4) * size_factor, Color(tint, fade * 0.51))


## 绘制 [param point] 为中心、世界宽高为 [param size] 的局部 [param tint] 光晕。
func _halo(point: Vector2, size: Vector2, tint: Color) -> void:
	draw_texture_rect(_glow, Rect2(point - size * 0.5, size), false, tint)


## 绘制以 [param point] 为中心、各轴半径为 [param radius] 的小切面，使用 [param tint] 填充。
func _diamond(point: Vector2, radius: Vector2, tint: Color) -> void:
	if radius.x > 0.0 and radius.y > 0.0:
		draw_colored_polygon(PackedVector2Array([point - Vector2(radius.x, 0), point - Vector2(0, radius.y), point + Vector2(radius.x, 0), point + Vector2(0, radius.y)]), tint)
