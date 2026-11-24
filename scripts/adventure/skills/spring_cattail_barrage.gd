## 四次双圈仙人掌散射，弹道与 GPU 尖刺使用同一组发射参数。
extends Node2D

## 原生仙人掌尖刺贴图，由整批针弹共享。
const CACTUS: Texture2D = preload("res://assets/image/projectile/ProjectileCactus.png")
## 针弹面片绘制真实尖刺、双层拖尾和尾端余光。
const NEEDLE_SHADER: Shader = preload("res://shaders/adventure/spring_cattail_needles.gdshader")
## 每个落点的蓄光、双层冲击环和碎光由同一张面片绘制。
const BLOOM_SHADER: Shader = preload("res://shaders/adventure/spring_cattail_bloom.gdshader")
## 第一处蓄光在 Cut-in 即将退出时开始，单位实际秒。
const CUT_IN_LEAD: float = 1.13
## 单处蓄光与相邻爆点的间隔，单位战斗秒。
const FUSE_SECONDS: float = 0.23
## 后三处按此战斗秒间隔依次蓄光。
const BURST_GAP: float = 0.43
## 内圈比外圈晚出手的战斗秒数。
const RING_GAP: float = 0.135
## 每圈均分十四个方向，内圈旋转半格。
const NEEDLES_PER_RING: int = 14
## 每支针可以命中多个不同实例，每次送入普通仙人掌伤害路由的基础伤害。
const DAMAGE: int = 50
## 单支针的有限飞行战斗秒数。
const FLIGHT_SECONDS: float = 1.71
## 已飞时间的二次项系数，控制尾段减速，GPU 与碰撞共用。
const DECELERATION: float = 0.105
## MultiMesh 自定义数据以此尺度保存时间和速度，供两个 Shader 解码。
const INSTANCE_SCALE := Vector2(4.0, 720.0)
## 真实扫掠探针的世界半宽，略小于贴图本体。
const PROBE_RADIUS: float = 5.5

## 每处选中的真实地块和入场时冻结的备用格心。
class Burst:
	## 已抽中的格子，移动平台在该处蓄光前仍可更新它的世界位置。
	var cell: PlantCell
	## 蓄光开始后固定的弹道中心，世界坐标。
	var center: Vector2
	## 外圈离开格心的时刻，单位战斗秒。
	var fired_at: float
	## 是否已提交中心与声音；命中事件不重复发射。
	var prepared: bool = false
	## 是否已播放这处爆点的声响。
	var sounded: bool = false

## 一支针的冻结飞行参数与本支针专属的命中记录。
class Needle:
	## 本针所属的爆点索引。
	var burst_index: int
	## 等分圆周后的方向角，弧度。
	var angle: float
	## 与显示共用的单位运动方向。
	var direction: Vector2
	## 离开格心的战斗秒时刻，区分内外两圈。
	var born_at: float
	## 初速，单位世界像素每战斗秒。
	var speed: float
	## 本弹已穿过的受击者，避免相邻物理步反复扣血。
	var contacted: Dictionary[int, bool] = {}
	## 真实承伤去重，只有发生首次碰撞时才创建。
	var hit_scope: CombatHitScope

## 整次技能的来源快照，避免尖刺带入下一阶段。
var _battle: RepeaterShotContext
## 已抽取的四个落点，最后一处使用暖金色加强收拍。
var _bursts: Array[Burst] = []
## 整次施放的有限弹道数据，按落点再按圈排列。
var _needles: Array[Needle] = []
## 固定尺寸的连续碰撞查询器，复用原生受击形状扫掠。
var _query := ElectricPeaFlightQuery.new(PROBE_RADIUS / ElectricPeaFlightQuery.HALF_SIZE)
## 统一的两批绘制对象；只在各爆点开始蓄光时写位置。
var _needle_batch: MultiMeshInstance2D
## 四个局部爆光的批次。
var _bloom_batch: MultiMeshInstance2D
## 当前战斗年龄与上一物理步年龄，单位游戏秒。
var _age: float = 0.0
## 渲染插值的起点，保持低物理帧率下尖刺连续移动。
var _previous_age: float = 0.0
## Cut-in 离场前画布保持隐藏。
var _started: bool = false

## 入树前冻结 [param battle] 的 [param cells]，用 [param random] 分别旋转两圈并轻微扰动速度。
func configure(battle: RepeaterShotContext, cells: Array[PlantCell], random: RandomNumberGenerator) -> void:
	_battle = battle
	for burst_index: int in range(cells.size()): # 以抽中的原顺序保留前后三加一节奏。
		var burst := Burst.new() # 每个爆点只保留一份棋盘身份和时间。
		burst.cell = cells[burst_index]
		burst.center = _cell_center(burst.cell)
		burst.fired_at = FUSE_SECONDS + burst_index * BURST_GAP
		_bursts.append(burst)
		var phase: float = random.randf_range(0.0, TAU) # 四处爆点不会一起沿相同的方向排列。
		for ring: int in range(2): # 外圈先行、内圈后发并错开角度。
			for index: int in range(NEEDLES_PER_RING): # 两圈都完整覆盖圆周。
				var needle := Needle.new() # 各针的方向、速度和命中身份互不串用。
				needle.burst_index = burst_index
				needle.angle = phase + (index + ring * 0.5) * TAU / NEEDLES_PER_RING
				needle.direction = Vector2.from_angle(needle.angle)
				needle.born_at = burst.fired_at + ring * RING_GAP
				needle.speed = (590.0 if ring == 0 else 425.0) * random.randf_range(0.94, 1.06)
				_needles.append(needle)

## 创建局部爆光与弹体批次。暂停时冻结演出，阶段改变时回收整次技能。
func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	z_as_relative = false
	z_index = 380
	global_transform = Transform2D.IDENTITY
	_needle_batch = _make_batch(NEEDLE_SHADER, Vector2(124.0, 48.0), _needles.size())
	_needle_batch.texture = CACTUS
	_bloom_batch = _make_batch(BLOOM_SHADER, Vector2(270.0, 270.0), _bursts.size())
	_bloom_batch.z_index = -1
	for index: int in range(_bursts.size()): # 首次配置静态队列，实际发射只刷新对应一组坐标。
		_submit_burst(index)
	hide()
	var lead: Tween = create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_STOP) # 等 Cut-in 露出棋盘。
	lead.tween_interval(CUT_IN_LEAD)
	lead.finished.connect(_begin)

## 建立 [param count] 个实例共用的 [param shader] 与 [param quad_size] 面片。
func _make_batch(shader: Shader, quad_size: Vector2, count: int) -> MultiMeshInstance2D:
	var quad := QuadMesh.new() # 每个软光或尖刺只需两个三角形。
	quad.size = quad_size
	var instances := MultiMesh.new() # 固定实例上限，整段播放不分配弹体节点。
	instances.transform_format = MultiMesh.TRANSFORM_2D
	instances.use_custom_data = true
	instances.mesh = quad
	instances.instance_count = count
	var bounds: Rect2 = BoardQueries.bounds(_battle.board.cells()).grow(1110.0) # Shader 推进的位置也纳入批次裁剪范围。
	instances.custom_aabb = AABB(Vector3(bounds.position.x, bounds.position.y, -1.0), Vector3(bounds.size.x, bounds.size.y, 2.0))
	var material := ShaderMaterial.new() # 时间参数只属于本次施放。
	material.shader = shader
	material.set_shader_parameter(&"instance_scale", INSTANCE_SCALE)
	var batch := MultiMeshInstance2D.new() # 同类对象走一次 Canvas 绘制。
	batch.multimesh = instances
	batch.material = material
	add_child(batch)
	return batch

## [param cell] 的世界格心稍微抬高，让各行弹道穿过角色受击框。
func _cell_center(cell: PlantCell) -> Vector2:
	var rect: Rect2 = cell.get_global_rect() # 读取移动平台、屋顶或稀疏棋盘的实时几何。
	return rect.get_center() - Vector2(0.0, minf(10.0, rect.size.y * 0.12))

## 为 [param index] 的落点写光效和两圈的原点；只在布置和蓄光开始时调用。
func _submit_burst(index: int) -> void:
	var burst: Burst = _bursts[index] # 光效和尖刺引用同一个格心。
	var last: float = float(index == _bursts.size() - 1) # 末爆暖金色更强，不参与伤害计算。
	_bloom_batch.multimesh.set_instance_transform_2d(index, Transform2D(0.0, burst.center))
	_bloom_batch.multimesh.set_instance_custom_data(index, Color(burst.fired_at / INSTANCE_SCALE.x, last, index / 4.0, 1.0))
	var first: int = index * NEEDLES_PER_RING * 2 # 该落点的首支外圈尖刺。
	for slot: int in range(first, first + NEEDLES_PER_RING * 2): # 内外圈常量一起提交给批次。
		var needle: Needle = _needles[slot] # 方向变换和物理扫掠来自同一条数据。
		var inner: float = float(slot - first >= NEEDLES_PER_RING) # 颜色偏移区分内外圈。
		_needle_batch.multimesh.set_instance_transform_2d(slot, Transform2D(needle.angle, burst.center))
		_needle_batch.multimesh.set_instance_custom_data(slot, Color(needle.born_at / INSTANCE_SCALE.x,
			needle.speed / INSTANCE_SCALE.y, inner, last))

## Cut-in 后才推进蓄光和运动；命中与画面共用寿命和减速参数。
func _begin() -> void:
	(_needle_batch.material as ShaderMaterial).set_shader_parameter(&"flight_seconds", FLIGHT_SECONDS)
	(_needle_batch.material as ShaderMaterial).set_shader_parameter(&"deceleration", DECELERATION)
	(_bloom_batch.material as ShaderMaterial).set_shader_parameter(&"fuse_seconds", FUSE_SECONDS)
	(_bloom_batch.material as ShaderMaterial).set_shader_parameter(&"ring_gap", RING_GAP)
	_started = true
	_advance_bursts()
	show()

## 每处开始蓄光时固定真正落点；外圈发射时只播放一次爆裂声。
func _advance_bursts() -> void:
	for index: int in range(_bursts.size()): # 按原顺序处理跨低帧率的多个爆点。
		var burst: Burst = _bursts[index] # 到点前只保存选择结果，不绑定物理对象。
		if not burst.prepared and _age >= burst.fired_at - FUSE_SECONDS:
			burst.prepared = true
			if is_instance_valid(burst.cell) and not burst.cell.is_queued_for_deletion():
				burst.center = _cell_center(burst.cell)
			_submit_burst(index)
		if not burst.sounded and _age >= burst.fired_at:
			burst.sounded = true
			SoundManager.play_character_SFX(&"CherryBomb", self, burst.center, 2)

## [param delta] 是推进两端扫掠段的战斗秒；每步只读取一次敌人受击包围盒。
func _physics_process(delta: float) -> void:
	if not _started or get_tree().paused or not _battle.is_active():
		return
	_previous_age = _age
	_age += delta
	_advance_bursts()
	if _age < FUSE_SECONDS:
		return
	var targets: Array[Character000Base] = ElectricPeaFlightQuery.all_targets(_battle.game) # 复用真实友敌与状态掩码。
	var bounds: Array[Rect2] = [] # 与敌人位置同序，减少每支针重复读取形状几何。
	for target: Character000Base in targets: # 每个候选只在本步合并一次全部受击区。
		bounds.append(_hurt_bounds(target.hurt_box_component.hurt_box_real))
	for needle: Needle in _needles: # 发射前和飞行结束后不做碰撞查询。
		if _age < needle.born_at or _previous_age >= needle.born_at + FLIGHT_SECONDS:
			continue
		var origin: Vector2 = _bursts[needle.burst_index].center # 此坐标从蓄光开始就冻结。
		var start: Vector2 = origin + needle.direction * _travel(needle, _previous_age) # 上一物理步的针心。
		var finish: Vector2 = origin + needle.direction * _travel(needle, _age) # 本步连续扫掠终点。
		_sweep(needle, start, finish, targets, bounds)
		if not _battle.is_active() or get_tree().paused:
			return

## [param needle] 在 [param time] 时的累计路程，与针弹 Shader 使用同一公式。
func _travel(needle: Needle, time: float) -> float:
	var age: float = clampf(time - needle.born_at, 0.0, FLIGHT_SECONDS) # 首末帧只扫掠实际存活部分。
	return needle.speed * age * (1.0 - DECELERATION * age)

## [param area] 内所有启用的精确形状合并为粗筛矩形；无形状时返回空矩形。
func _hurt_bounds(area: Area2D) -> Rect2:
	var bounds := Rect2() # 只在这一物理步内有效的世界包围盒。
	if not is_instance_valid(area):
		return bounds
	for shape_owner: int in area.get_shape_owners(): # 多形状 Boss 共用同一个候选。
		if area.is_shape_owner_disabled(shape_owner):
			continue
		var pose: Transform2D = area.global_transform * area.shape_owner_get_transform(shape_owner) # 计入实际偏移和缩放。
		for index: int in range(area.shape_owner_get_shape_count(shape_owner)): # 粗筛之外仍由原生形状判定。
			var shape: Shape2D = area.shape_owner_get_shape(shape_owner, index) # 当前启用形状。
			if shape != null:
				var extent: Rect2 = pose * shape.get_rect() # 世界空间保守包围盒。
				bounds = bounds.merge(extent) if bounds.has_area() else extent
	return bounds

## [param needle] 从 [param start] 连续扫掠到 [param finish]，按 [param bounds] 粗筛 [param targets]。
## 同一支针仍可穿过其他敌人，碰到同一个真实承伤者时只扣一次血。
func _sweep(needle: Needle, start: Vector2, finish: Vector2, targets: Array[Character000Base], bounds: Array[Rect2]) -> void:
	var reach: Rect2 = Rect2(start.min(finish), (finish - start).abs()).grow(PROBE_RADIUS + 0.01) # 宽相位边缘保留精确扫掠余量。
	var contacts: Array[Vector2] = [] # x 保存接触比例，y 保存本步候选索引。
	for index: int in range(bounds.size()): # 优先检查数字矩形，绝大多数针弹不进入形状检查。
		if not reach.intersects(bounds[index], true):
			continue
		var target: Character000Base = targets[index] # 前一支针可能已经杀死或释放此对象。
		if not ElectricPeaFlightQuery.can_hit(target) or needle.contacted.has(target.get_instance_id()):
			continue
		var fraction: float = _query.contact_fraction(target.hurt_box_component.hurt_box_real, start, finish) # 拒绝包围盒假命中。
		if is_finite(fraction):
			contacts.append(Vector2(fraction, index))
	if contacts.size() > 1:
		contacts.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x) # 同一步仍沿飞行方向先近后远。
	for contact: Vector2 in contacts: # 伤害信号可能改变阶段或使下一对象失效。
		if not _battle.is_active() or get_tree().paused:
			return
		var target: Character000Base = targets[int(contact.y)] # 逐次核对当前的敌人资格。
		if not ElectricPeaFlightQuery.can_hit(target):
			continue
		needle.contacted[target.get_instance_id()] = true
		if needle.hit_scope == null:
			needle.hit_scope = CombatHitScope.new()
		target.be_attacked_bullet(DAMAGE, BulletRegistry.AttackMode.Norm, true, false, 0, -1, null, needle.hit_scope)

## [param _delta] 不作为额外时钟；两批渲染使用上一物理步的插值年龄。
func _process(_delta: float) -> void:
	if not _battle.is_active():
		queue_free()
		return
	if not _started or get_tree().paused:
		return
	var paint_age: float = lerpf(_previous_age, _age, Engine.get_physics_interpolation_fraction()) # 只改变表现采样，不改权威命中。
	(_needle_batch.material as ShaderMaterial).set_shader_parameter(&"age", paint_age)
	(_bloom_batch.material as ShaderMaterial).set_shader_parameter(&"age", paint_age)
	if paint_age >= _needles[-1].born_at + FLIGHT_SECONDS:
		queue_free()
