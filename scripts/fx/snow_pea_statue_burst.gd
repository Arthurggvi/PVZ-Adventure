## 冰雕形成、深寒结晶和破碎共用的短寿命画布；霜雾先散、冰片后落。
extends Node2D
class_name SnowPeaStatueBurst

## 同场暂态效果上限，密集冻结时只省略视觉，不影响状态或伤害。
const MAX_ACTIVE: int = 28
## 此组只含短暂结晶画布，用于限制并发数量。
const VISUAL_GROUP: StringName = &"snow_pea_crystal_visual"
## 形成持续秒数，略长于冰壳扫描。
const FORM_SECONDS: float = 0.58
## 破碎持续秒数，碎片在末段落下并透明消散。
const BREAK_SECONDS: float = 0.72
## 所属战斗快照，切换阶段后立即清理。
var _battle: RepeaterShotContext
## 原角色局部原画范围，粒子从轮廓附近散出。
var _bounds: Rect2
## 是否为已受击破碎；false 为从脚下升起的结晶。
var _broken: bool = false
## 只随有效战斗时间推进的效果年龄。
var _age: float = 0.0
## 各冰片的初始位置，创建时一次计算。
var _starts: PackedVector2Array = PackedVector2Array()
## 各冰片的世界像素速度，不使用战斗随机数。
var _velocities: PackedVector2Array = PackedVector2Array()
## 各冰片的尺寸、初始角度和角速度。
var _shapes: Array[Vector3] = []

## 在 [param battle] 的 [param feet] 显示 [param bounds] 大小的结晶或碎裂。
## [param broken] 决定生命周期；[param z] 保持与来源角色的绝对遮挡顺序。
static func spawn(battle: RepeaterShotContext, feet: Vector2, bounds: Rect2, broken: bool, z: int) -> void:
	if not battle.is_active() or battle.game.get_tree().get_nodes_in_group(VISUAL_GROUP).size() >= MAX_ACTIVE:
		return
	var visual := SnowPeaStatueBurst.new() # 单节点承载整组冰片及霜雾。
	visual._battle = battle
	visual._bounds = bounds
	visual._broken = broken
	visual.position = battle.game.bullets.to_local(feet)
	visual.z_as_relative = false
	visual.z_index = clampi(z + 2, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)
	visual._seed()
	battle.game.bullets.add_child(visual)
	visual.add_to_group(VISUAL_GROUP)

## [param target] 首次进入深寒冻结时，在 [param battle] 中显示克制的结晶。
## 只读取真实受击形状；调用方保证续冻及抗冻目标不会重复触发。
static func crystallize(battle: RepeaterShotContext, target: Character000Base) -> void:
	if not is_instance_valid(target) or not is_instance_valid(target.hurt_box_component):
		return
	var bounds := Rect2(-20.0, -82.0, 40.0, 82.0) # 缺失真实形状时使用普通僵尸的紧凑范围。
	var first: bool = true # 第一个有效形状替换回退范围，后续形状合并。
	for node: Node in target.hurt_box_component.hurt_box_real.get_children(): # 仅合并仍活动的原生受击形状。
		var shape := node as CollisionShape2D # 角色变换与形状偏移均包含在全局变换内。
		if shape == null or shape.disabled or shape.shape == null:
			continue
		var relative_frame := Transform2D(0.0, -target.global_position) * shape.global_transform # 归一到脚点原点。
		var extent: Rect2 = relative_frame * shape.shape.get_rect() # 保留大型角色或倾斜形状的外包范围。
		bounds = extent if first else bounds.merge(extent)
		first = false
	spawn(battle, target.global_position, bounds, false, target.z_index)

## 固定散布序列避免视觉消耗全局 RNG；破碎不复制原画或任何角色组件。
func _seed() -> void:
	var count: int = 22 if _broken else 11 # 形成时只留少量亮棱，破碎拥有大小两层冰片。
	for index: int in range(count): # 互质序列打散位置、角度和尺寸，避免等距烟花形态。
		var unit := Vector2(float(index * 7 % 23) / 22.0, float(index * 13 % 29) / 28.0) # 独立归一化散布。
		var point: Vector2 = _bounds.position + _bounds.size * Vector2(0.12 + unit.x * 0.76, 0.12 + unit.y * 0.80) # 源自整个身体。
		var direction := Vector2((unit.x - 0.5) * 2.0, -0.35 - unit.y * 0.65).normalized() # 先外扩上抛，随后重力下落。
		var speed: float = 42.0 + float(index * 19 % 67) # 近景大片较快，微小冰尘较慢。
		_starts.append(point)
		_velocities.append(direction * speed if _broken else Vector2((unit.x - 0.5) * 15.0, -18.0 - unit.y * 22.0))
		_shapes.append(Vector3(3.0 + float(index * 5 % 8), float(index) * 2.399, (-1.0 if index % 2 == 0 else 1.0) * 2.6))

## [param delta] 为有效战斗秒；暂停、阶段失效或节点回收不会留下计时器。
func _process(delta: float) -> void:
	_age += delta
	if not _battle.is_active() or _age >= (BREAK_SECONDS if _broken else FORM_SECONDS):
		queue_free()
		return
	queue_redraw()

## 柔雾承担体积，窄切面承担材质；不用整片白闪遮挡相邻敌人。
func _draw() -> void:
	var duration: float = BREAK_SECONDS if _broken else FORM_SECONDS # 本模式统一的视觉期限。
	var progress: float = clampf(_age / duration, 0.0, 1.0) # 整段动画的归一化时间。
	var opacity: float = smoothstep(0.0, 0.09, progress) * (1.0 - smoothstep(0.30, 1.0, progress)) # 快速成形、缓慢褪去。
	var spread: float = 1.0 - pow(1.0 - progress, 3.0) # 霜雾扩展在前半段完成。
	for index: int in range(6): # 六片软雾只描述体积，不产生整片发光圆盘。
		var point: Vector2 = _bounds.get_center() + Vector2(float(index * 17 % 31) - 15.0,
			float(index * 11 % 27) - 13.0) * (0.5 + spread) # 非对称错位的局部薄雾。
		if not _broken:
			point.y = _bounds.end.y - _bounds.size.y * progress * 0.86 + sin(float(index)) * 8.0
		var size := Vector2(30.0 + spread * 32.0, 12.0 + spread * 13.0) # 水平方向更柔薄的霜雾。
		draw_texture_rect(SnowPeaFrostVisual.mist_texture(), Rect2(point - size * 0.5, size),
			false, Color(0.69, 0.90, 0.98, opacity * (0.22 if _broken else 0.14)))
	for index: int in range(_starts.size()): # 每片为双切面四边形，重力只作用于破碎片。
		var shape: Vector3 = _shapes[index] # 尺寸与旋转在创建后保持稳定。
		var point: Vector2 = _starts[index] + _velocities[index] * _age # 平移不依赖角色是否已释放。
		point.y += 88.0 * _age * _age if _broken else 0.0
		var visibility: float = opacity # 结晶按高度依次亮起，破碎立即散出。
		if not _broken:
			var height: float = (_bounds.end.y - _starts[index].y) / maxf(_bounds.size.y, 1.0) # 从脚部到头部的相位。
			visibility *= smoothstep(height * 0.52, height * 0.52 + 0.13, progress)
		SnowPeaFrostVisual.draw_shard(self, point, shape.x * (1.0 if _broken else 0.46),
			shape.y + shape.z * _age, visibility * (0.86 if _broken else 0.60))
