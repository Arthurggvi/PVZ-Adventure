## 花园飞艇独占的击毁表现入口。瞬态爆点、移动锚点、预算和世界粒子由各自的生命周期管理。
extends Node2D

## 复用正式战斗的共享风、画布换算和解析阻力。
const Wind := preload("res://scripts/adventure/garden_airship/garden_airship_wind.gd")
const FlowSpace := preload("res://scripts/adventure/garden_airship/garden_airship_flow_space.gd")
const Motion := preload("res://scripts/adventure/garden_airship/garden_airship_blast_motion.gd")
## 局内事件只握有可失效的部件身份，画层和移动音效单独处理。
const Burst := preload("res://scripts/adventure/garden_airship/garden_airship_blast_event.gd")
const Fx := preload("res://scripts/adventure/garden_airship/garden_airship_blast_fx.gd")
const Audio := preload("res://scripts/adventure/garden_airship/garden_airship_blast_audio.gd")
const FlightAudio := preload("res://scripts/adventure/garden_airship/garden_airship_audio.gd")

## 延续各机型的共享特效预算类别。主爆即使失去完整额度也有核心反馈。
const BUDGET_FAMILY := {
	&"fighter": &"fighter_death_blast",
	&"turret": &"cannon_turret_death_blast",
	&"arbiter": &"arbiter_x_impact",
	&"transport": &"transport_airship_breakup",
	&"rocket": &"rocket_exhaust_cut",
}
## 独立帧没有超过四个需要追踪的部件阶段。留有正在淡出的世界粒子和移动声音余量。
const EVENT_SECONDS: float = 0.94
## 同时用真实残骸位置续约的最多声部数。总上限仍由 R5 移动池管理。
const MAX_TAILS: int = 3
## 后续爆点达到右缘以外这个参考距离就取消。主爆允许更宽的边缘覆盖。
const FOLLOWUP_MARGIN: float = 42.0

## [param id] 对应同次爆炸，[param kind] 和 [param phase] 指其机型及发生阶段。
## [param world] 为当帧爆点，[param inherited] 是发射前世界速度，[param layered] 表示完整预算。
signal burst_spawned(id: int, kind: StringName, phase: StringName, world: Vector2, inherited: Vector2, layered: bool)
## [param id] 的 [param world]、[param volume_db] 已提交给移动声场，[param active] 为否时表示开始回收。
signal tail_sampled(id: int, world: Vector2, volume_db: float, active: bool)

## 当局实际的 R6 风场与战斗共享额度。
var _wind: Wind
var _budget: BattleBlastFxBudget
## 飞行混音仅对原环境风床让位。短爆和移动声可借用原声场。
var _beds: FlightAudio
var _sound := Audio.new()
## 首次真实爆炸时才创建的固定批次。
var _fx: Fx
## 同步消费者可用顺序编号绑定实际快照。循环使用稠密事件列表。
var _by_id: Dictionary[int, Burst] = {}
var _active: Array[Burst] = []
var _serial: int = 0
## 低画质和停用可选渲染仍绘制主爆核心。
var _reduced: bool = false


## [param wind] 和 [param budget] 属于当前战斗。[param spatial]、[param beds] 分别是定位池和原风床。
func setup(wind: Wind, budget: BattleBlastFxBudget, spatial: GardenAirshipSpatialAudio, beds: FlightAudio) -> void:
	_wind = wind
	_budget = budget
	_beds = beds
	_sound.setup(spatial)
	process_priority = 2 # R5 扫离和载具的局部姿态先提交。
	set_process(false)


## [param reduced] 沿用当前关卡兼容画质或玩家的可选动效开关。
func set_reduced(reduced: bool) -> void:
	if _reduced == reduced:
		return
	_reduced = reduced
	if is_instance_valid(_fx):
		_fx.set_reduced(reduced)


## 立即在 [param origin] 发射 [param kind] 主爆，返回可绑定快照的正序号，零表示只保留即时反馈。
## [param size] 为原效果尺寸，[param velocity] 为战斗世界 px/s，[param depth] 记录发射者原绘制层。
## [param local_points] 可在可见快照建立前保存其相对部件点。
func start_burst(kind: StringName, origin: Vector2, size: float, velocity: Vector2,
		depth: int, local_points: PackedVector2Array = PackedVector2Array()) -> int:
	if _wind == null or not BUDGET_FAMILY.has(kind) or not is_in_view(origin, 176.0):
		return 0
	_serial += 1
	var id: int = _serial # 只供本局使用，移动声音会另加保留前缀。
	var family: StringName = BUDGET_FAMILY[kind] # 参加原战斗表现预算，伤害路径从不等此结果。
	var heavy: bool = kind != &"rocket" # 小鬼尾部熄火不申请完整爆炸额度。
	var full: bool = _active.size() < BattleBlastFxBudget.MAX_ACTIVE and (not heavy or _budget.can_start(family, origin))
	_batch().emit_burst(origin, velocity, size, kind, _seed(origin, id), true, full)
	_sound.primary(kind, origin, size, full)
	if heavy and is_instance_valid(_beds):
		_beds.cue_blast(clampf(size + 0.20, 0.55, 1.0))
		if kind == &"transport" or kind == &"arbiter":
			_wind.disturb_blast(origin.x, 0.36)
	if full:
		var burst := Burst.new() # 仅一个寿命令牌，粒子均由关卡内固定批次持有。
		burst.token = id
		burst.born_frame = Engine.get_process_frames()
		burst.kind = kind
		burst.size = size
		burst.points = local_points
		burst.initial_velocity = velocity
		burst.z_index = depth
		add_child(burst)
		if heavy:
			_budget.track(burst, family, origin)
		_active.append(burst)
		_by_id[id] = burst
		set_process(true)
	burst_spawned.emit(id, kind, &"main", origin, velocity, full)
	return id if full else 0


## [param id] 的尾声跟随 [param anchor]；次爆按 [param local_points] 采样实际 [param pieces]。
## [param tail_offset] 是相对锚点的声源位置。无片体时使用锚点的本地坐标。
func track_burst(id: int, anchor: Node2D, local_points: PackedVector2Array = PackedVector2Array(),
		pieces: Array[Node2D] = [], tail_offset: Vector2 = Vector2.ZERO) -> void:
	var burst: Burst = _by_id.get(id) # 未获准的演出只有已发射的核心，不补播。
	if burst != null:
		burst.bind_pose(anchor, local_points, pieces, tail_offset)


## [param origin] 是真实触地的固定爆点。[param velocity] 继承首触惯性，[param size] 和 [param depth] 来自机体。
func contact(origin: Vector2, velocity: Vector2, size: float, depth: int) -> void:
	if _wind == null or not is_in_view(origin, 176.0):
		return
	_serial += 1
	_batch().emit_contact(origin, velocity, size, _seed(origin, _serial + depth))
	_sound.contact(origin)
	burst_spawned.emit(_serial, &"arbiter", &"contact", origin, velocity, false)


## [param point] 处的战斗平面气流，单位为世界 px/战斗秒。[param factor] 可复用同帧的画布标尺。
func fragment_airflow(point: Vector2, factor: float = 0.0) -> Vector2:
	return Motion.flow_velocity(_wind, point, factor if factor > 0.0 else blast_world_factor(), 0.06)


## 返回参考 1920px 到本战斗画布的世界速度倍率。
func blast_world_factor() -> float:
	return FlowSpace.reference_to_world(get_viewport_rect().size.x, get_canvas_transform(), Wind.DIRECTION)


## 检查 [param point] 在真实可见画布或 [param margin_ref] 个参考像素的扩展区内。
func is_in_view(point: Vector2, margin_ref: float = FOLLOWUP_MARGIN) -> bool:
	var rect: Rect2 = get_viewport_rect() # 黑边不参与投影，也没有虚拟背景缩放。
	return point.is_finite() and rect.grow(margin_ref * rect.size.x / FlowSpace.REFERENCE_WIDTH).has_point(get_canvas_transform() * point)


## 返回尚在接管后续锚点的事件数及可独立收束的当前粒子数。
func get_active_burst_count() -> int:
	return _active.size()


## 当前仍在局内的热团、压力、烟和火星数。
func get_active_particle_count() -> int:
	return _fx.get_active_particle_count() if is_instance_valid(_fx) else 0


## 返回本局粒子瞬时峰值，供外部复现实测。
func get_peak_particle_count() -> int:
	return _fx.get_peak_particle_count() if is_instance_valid(_fx) else 0


## [param delta] 是战斗秒，和 R5 扫离一起受倍速和暂停控制。
func _process(delta: float) -> void:
	var frame: int = Engine.get_process_frames() # 出生于本帧的事件在下次实际战斗帧推进。
	var spacing: float = 83.0 * blast_world_factor() # 运输舰短尾迹每隔一段实际距离发射。
	var seats: int = MAX_TAILS # 声部优先留下较早爆开的持续源，避免来回起音。
	var index: int = 0 # 事件结束就地移除，不创建逐帧副本。
	while index < _active.size():
		var burst: Burst = _active[index] # 这里只访问仍在本局的纯表现令牌。
		if burst.born_frame == frame:
			index += 1
			continue
		burst.age += delta
		var world: Vector2 = burst.sample_pose(delta) # 接管后真实机体或碎片的代表位置。
		if not world.is_finite() or burst.age >= EVENT_SECONDS:
			_end_tail(burst)
			_by_id.erase(burst.token)
			_active.remove_at(index)
			burst.queue_free()
			continue
		_fire_parts(burst)
		if not _reduced and burst.take_ember(world, spacing) and is_in_view(world):
			_fx.emit_ember_wake(world, burst.anchor_velocity, burst.size, _seed(world, burst.token))
		if seats > 0 and _follow_tail(burst, world):
			seats -= 1
		elif burst.tail_active:
			_end_tail(burst)
		index += 1
	if _active.is_empty():
		set_process(false)


## [param burst] 的部件跨过发射时机时，只使用当帧仍存续的真实变换。
func _fire_parts(burst: Burst) -> void:
	while burst.part_due():
		var world: Vector2 = burst.next_position() # 丢失的片体不会回到最初爆心。
		var velocity: Vector2 = burst.next_velocity() # 包含当前平移和部件自身转动。
		var part: int = burst.next_part # 先消费时点，任何可见性拒绝都不会二次补发。
		burst.next_part += 1
		if not is_in_view(world):
			continue
		_fx.emit_burst(world, velocity, burst.size * lerpf(0.70, 0.50, float(part) / 2.0),
			burst.kind, _seed(world, burst.token * 5 + part), false, true)
		_sound.secondary(burst.kind, world, part)
		burst_spawned.emit(burst.token, burst.kind, &"followup", world, velocity, true)


## 尾声续约与 [param burst] 的实际 [param world] 一起更新，离场后由原 R5 播放器淡出。
func _follow_tail(burst: Burst, world: Vector2) -> bool:
	var life: float = 0.23 if burst.kind == &"rocket" else 0.82 # 轻型熄火不保留燃烧循环。
	if burst.tail_done or burst.age < 0.055 or burst.age >= life or not is_in_view(world, 105.0):
		return false
	var screen_x: float = (get_canvas_transform() * world - get_viewport_rect().position).x / get_viewport_rect().size.x # 黎明和云层变换不影响声像。
	var db: float = _sound.tail(burst.token, burst.kind, world, burst.age, screen_x, burst.tail_active) # 只统计真实获准的移动槽。
	if not is_finite(db):
		return false
	burst.tail_active = true
	tail_sampled.emit(burst.token, world, db, true)
	return true


## 结束 [param burst] 的声音，同一事件不会从边缘跳回重新起音。
func _end_tail(burst: Burst) -> void:
	if burst.tail_active:
		burst.tail_active = false
		burst.tail_done = true
		_sound.end_tail(burst.token)
		tail_sampled.emit(burst.token, Vector2.INF, -80.0, false)


## 第一次爆炸时建立批次，普通开场巡航不持有额外可绘制实例。
func _batch() -> Fx:
	if not is_instance_valid(_fx):
		_fx = Fx.new()
		_fx.name = &"BurstParticles"
		_fx.setup(_wind)
		add_child(_fx)
		_fx.set_reduced(_reduced)
	return _fx


## [param origin] 和 [param id] 组成稳定的局内美术种子，不消费战斗随机流。
func _seed(origin: Vector2, id: int) -> int:
	return hash(Vector3i(roundi(origin.x * 0.25), roundi(origin.y * 0.25), id))
