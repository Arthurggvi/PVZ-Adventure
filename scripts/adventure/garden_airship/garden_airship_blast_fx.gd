## 花园飞艇战斗画布共用的定容爆炸池。死亡节点释放后，已发出的世界粒子可独立离场。
extends Node2D

## 经现有飞行状态取得局部空气速度，不创建独立风场。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
## 统一有效画幅、参考像素和战斗世界像素的换算。
const FlowSpace := preload("res://scripts/adventure/garden_airship/garden_airship_flow_space.gd")
## 活跃槽位的状态和外观。
const Particle := preload("res://scripts/adventure/garden_airship/garden_airship_blast_particle.gd")
## 真实爆点的确定性散射和距离发烟。
const Emitter := preload("res://scripts/adventure/garden_airship/garden_airship_blast_emitter.gd")
## 同一画布批量绘制已裁剪的可见物。
const Batch := preload("res://scripts/adventure/garden_airship/garden_airship_blast_batch.gd")
## 固定整场容量，其中保留十四槽保证密集主爆的初热核。
const CAPACITY: int = 224
## 通常只使用前 [code]CAPACITY - CORE_RESERVE[/code] 个槽。
const CORE_RESERVE: int = 14
## 兼容档减少并发装饰，保留同一场的必要主热核额度。
const REDUCED_DETAIL_LIMIT: int = 126
## 按 [enum Particle.Kind] 的顺序统计可见物质类别。
const CATEGORY_NAMES: Array[StringName] = [&"glow", &"smoke", &"pressure", &"rays", &"flame", &"core", &"spark", &"metal"]

## 本局实际飞行风场。
var _wind: Wind
## 沿用当前动效档位，下一批发射和共享额度读取。
var _reduced: bool = false
## 固定长度，活跃对象使用前缀，回收交换到休眠区。
var _slots: Array[Particle] = []
## 已实际占用的槽位数。
var _active_count: int = 0
## 单局实际峰值，供性能验收查询。
var _high_water: int = 0
## 已在本处理帧排入即时发布。
var _flush_queued: bool = false
## 发射后尚未更新批次，避免同一批实例重复上传。
var _needs_publish: bool = false
## 按机型发射并使用本池分配槽。
var _emitter: Emitter
## 共用纹理、兼容材质及顶点缓冲。
var _batch := Batch.new()

## 在场景生命周期内一次配置定容槽和批次。没有可更新产物时保持休眠。
func _ready() -> void:
	_slots.resize(CAPACITY)
	for index: int in CAPACITY: # 预分配所有槽，爆炸和推进时都不逐粒子建对象。
		_slots[index] = Particle.new()
	_emitter = Emitter.new(_claim_slot)
	_batch.bind(self, CAPACITY)
	set_process(false)

## 共用 FlightEnvironment 提供的 [param wind]，环境和战斗两种时钟各自遵循现有定义。
func setup(wind: Wind) -> void:
	_wind = wind

## 用 [param reduced] 缩减画面装饰密度，但保留原主爆坐标和速度。
func set_reduced(reduced: bool) -> void:
	_reduced = reduced

## 本帧立刻以 [param origin] 世界点发射；[param inherited] 为锚点的世界像素/战斗秒。
## [param visual_scale] 继承机体视觉倍率，[param profile] 和 [param seed] 决定分组。
## [param primary] 标记首次爆点，[param full] 为重型视觉预算；拒绝时仍发出简洁反馈。
func emit_burst(origin: Vector2, inherited: Vector2, visual_scale: float, profile: StringName,
		seed: int, primary: bool, full: bool) -> void:
	if not _valid_emission(origin, inherited, visual_scale):
		return
	_emitter.burst(origin, inherited, visual_scale, profile, seed, primary, full, _reduced, _world_factor())
	_request_publish()

## 发射 [param origin] 真实触地点的 [param size] 倍擦地粒子。
## [param inherited] 为真实接触初速，[param seed] 决定局部确定性形状；不发机体爆炸。
func emit_contact(origin: Vector2, inherited: Vector2, size: float, seed: int) -> void:
	if not _valid_emission(origin, inherited, size):
		return
	_emitter.contact(origin, inherited, size, seed, _world_factor(), _reduced)
	_request_publish()

## 从 [param origin] 处已经独立的舰壳发射一小团燃烧尾迹，由导演限定每次解体的脉冲数。
## [param inherited] 是该片速度，[param size] 和 [param seed] 仅调节本次外观。
func emit_ember_wake(origin: Vector2, inherited: Vector2, size: float, seed: int) -> void:
	if _reduced or not _valid_emission(origin, inherited, size):
		return
	_emitter.ember_wake(origin, inherited, size, seed, _world_factor())
	_request_publish()

## 确认 [param origin] 和 [param inherited] 为有效世界向量，[param size] 为正的有限美术倍率。
func _valid_emission(origin: Vector2, inherited: Vector2, size: float) -> bool:
	return is_node_ready() and origin.is_finite() and inherited.is_finite() and is_finite(size) and size > 0.0

## 返回真实画幅的参考像素到世界像素倍率。
func _world_factor() -> float:
	return FlowSpace.reference_to_world(get_viewport_rect().size.x, get_canvas_transform(), Wind.DIRECTION)

## 返回当前粒子池占用。画面外或透明的存活粒子也计入。
func get_active_particle_count() -> int:
	return _active_count

## 返回本局达到的最高活跃槽位数，采样不扫描粒子池。
func get_peak_particle_count() -> int:
	return _high_water

## 返回一次诊断快照，不进入正常逐帧路径。热核及压力波使用实际世界坐标。
func get_probe_snapshot() -> Dictionary:
	var categories: Dictionary[StringName, int] = {} # 归档时保留所有物质的零计数。
	var profiles: Dictionary[StringName, int] = {} # 本帧真正存在的机型或触地来源。
	var cores := PackedVector2Array() # 热核已经受风时报告其当前的位置。
	var pressures := PackedVector2Array() # 压力波的位置始终是实际发射点。
	for kind: StringName in CATEGORY_NAMES: # 在采样中保证各分类有确定的字段。
		categories[kind] = 0
	for index: int in _active_count: # 不影响逐帧运动与发布。
		var particle: Particle = _slots[index] # 读取当前活跃前缀。
		categories[CATEGORY_NAMES[particle.kind]] += 1
		profiles[particle.profile] = int(profiles.get(particle.profile, 0)) + 1
		if particle.kind == Particle.Kind.CORE:
			cores.append(particle.position)
		elif particle.kind == Particle.Kind.PRESSURE:
			pressures.append(particle.position)
	return {&"active_count": _active_count, &"high_water": _high_water, &"capacity": CAPACITY,
		&"visible_count": _batch.visible_count(), &"categories": categories, &"profiles": profiles,
		&"core_positions": cores, &"pressure_positions": pressures}

## [param critical] 允许必要热核使用保留槽。池完全写满时优先替换非热核。
func _claim_slot(critical: bool) -> Particle:
	var detail_limit: int = REDUCED_DETAIL_LIMIT if _reduced else CAPACITY - CORE_RESERVE # 兼容档减轻透明重绘。
	if not critical and _active_count >= detail_limit:
		return null
	if _active_count == CAPACITY:
		for index: int in range(_active_count - 1, -1, -1): # 极端并发时优先释放非必要点缀。
			if _slots[index].kind != Particle.Kind.CORE:
				return _slots[index]
		return _slots[0]
	var particle: Particle = _slots[_active_count] # 占用预分配下一个槽。
	_active_count += 1
	_high_water = maxi(_high_water, _active_count)
	return particle

## [param delta] 是 Godot 提交的战斗秒。异常帧至多分三步，暂停时不自行走钟。
func _process(delta: float) -> void:
	var canvas: Transform2D = get_canvas_transform() # 世界到实际战斗画布。
	var screen: Rect2 = get_viewport_rect() # 包含场景伸缩后的有效可见区域。
	var view: Rect2 = canvas.affine_inverse() * screen # 在同一世界坐标下裁剪和回收。
	var factor: float = FlowSpace.reference_to_world(screen.size.x, canvas, Wind.DIRECTION) # 速度单位与 R6 一致。
	var frame: int = Engine.get_process_frames() # 让同一帧出生的核心在真实起点显示。
	var steps: int = clampi(ceili(delta / 0.05), 1, 3) # 有限分步避免异常长帧无界补算。
	var step: float = delta / steps # 保留整个战斗时间步，避免重复除倍速。
	for index: int in range(_active_count - 1, -1, -1): # 倒序交换时已推进的旧粒子不会再推进。
		var particle: Particle = _slots[index] # 发烟附加的新槽从下一帧进入主循环。
		if particle.born_frame == frame:
			continue
		if particle.age + delta >= particle.life:
			_release_slot(index)
			continue
		for substep: int in steps: # 普通 30/60/120 FPS 共用一个解析步。
			var before: Vector2 = particle.position # 留给距离采样，烟源不会回到爆心。
			particle.advance(_wind, factor, step)
			if particle.trail_left > 0:
				_emitter.wake(particle, before, _wind, factor, step)
		var margin: float = maxf(110.0 * factor, particle.size * 2.3) # 保留仍可进入画幅的滚动尾部。
		if particle.tau > 0.0 and particle.position.x > view.end.x + margin:
			_release_slot(index)
	_publish(view)
	if _active_count == 0:
		set_process(false)

## 交换 [param index] 的槽和活跃前缀的末槽，使归还不产生分配。
func _release_slot(index: int) -> void:
	_active_count -= 1
	var previous: Particle = _slots[index] # 下次发射才写入该槽的新状态。
	_slots[index] = _slots[_active_count]
	_slots[_active_count] = previous

## 多次同帧发射共享一次发布；战斗进程其他阶段发射也可在本帧提交。
func _request_publish() -> void:
	if _active_count == 0:
		return
	set_process(true)
	_needs_publish = true
	if not _flush_queued:
		_flush_queued = true
		_flush_emissions.call_deferred()

## 只有正常进程尚未上传本次发射时才提前提交，保留真正的首帧爆心。
func _flush_emissions() -> void:
	_flush_queued = false
	if _needs_publish and is_inside_tree():
		_publish(get_canvas_transform().affine_inverse() * get_viewport_rect())

## 用当前世界 [param view] 提交实际可见面片。位置保持世界空间直至此处。
func _publish(view: Rect2) -> void:
	_needs_publish = false
	_batch.publish(_slots, _active_count, view, get_global_transform().affine_inverse())
