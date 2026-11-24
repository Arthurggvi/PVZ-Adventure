## 花园飞艇只订阅真实敌机入场和死亡视觉交接，提供可听飞行、破风以及局部结构响应。
extends Node

## 单一飞行单位的实际轨迹、归一位置和经过阈值。
const Aircraft := preload("res://scripts/adventure/garden_airship/garden_airship_aircraft_track.gd")
## 单声道螺旋桨转声。
const PROPELLER := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/engine_mono_r5.ogg")
## 火箭和大型机体的单声道喷气风压。
const JET := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/jet_r5.ogg")
## 带淡入淡出的单声道短掠过声。
const PASS := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/flyby_r5.ogg")
## 同时跟随的片区死亡风声；定位的致死短音由相同音效池合并。
const MAX_DEPARTURES: int = 3

## 正式战场的生成事件，不扫描场景树寻找飞机。
@export var zombies: ZombieManager
## 一致的听者坐标和固定声源池。
@export var audio: Node
## R4 的唯一环境风和局部近场扰动入口。
@export var flight: Node
## 真正的死亡交接完成后才生成离开的声音。
@export var deaths: Node

## [param world]、[param speed] 与 [param strength] 来自实际飞行轨迹，提供验收和整合观测。
signal flyby(world: Vector2, speed: float, strength: float)

## 较少的飞行单位在其生命周期内维持一个声源。
var _aircraft: Array[Aircraft] = []
## 一片区域中的代表性残骸声源。
class Departure:
	## 真正可见的残骸节点。
	var visual: Node2D
	## 不经浮点化的对象身份，播放器回收时使用。
	var key: int
	## 起点自然秒与体型权重。
	var born: float
	## 影响气流声轻重的归一化值。
	var weight: float

## 本关的可见残骸引用，释放后自动归还声音。
var _departures: Array[Departure] = []
## 视口尺寸变化触发测速重置，避免窗口跳动成为飞越。
var _view_size := Vector2.ZERO
## 飞行声定位按 30 Hz 提交，池内继续平滑并负责限流。
var _pending_step: float = 0.0
## 当前自然秒数和上一获准的真实飞越。
var _seconds: float = 0.0
## 向同一声场提交新破风的冷却结束时间。
var _next_pass: float = 0.0

## 配置各模块的局内生命周期；当前关卡离树统一解绑。
func _ready() -> void:
	zombies.signal_zombie_created.connect(_on_aircraft_spawned)
	deaths.connect(&"detached", _on_departure)
	set_process(false)

## [param actor] 启动于实际生成信号；运输舰使用其原舱门及旋翼状态，独立更新同一个池。
func _on_aircraft_spawned(actor: Zombie000Base) -> void:
	if not is_instance_valid(actor):
		return
	var entry: Aircraft # 只为三个实际动力类别记录轨迹。
	if actor is Zombie034Fighter:
		entry = Aircraft.new(actor, actor.fighter_visual.rotor, PROPELLER, Vector3(-11.0, 1.32, 1.25))
	elif actor is Zombie038ArbiterX:
		entry = Aircraft.new(actor, actor.arbiter_presentation.get("_airframe").near_exhaust,
			JET, Vector3(-15.5, 0.68, 1.75))
	elif actor.zombie_type == CharacterRegistry.ZombieType.Z041RocketImp:
		var animator: Node = actor.get_node_or_null("%AnimComponent") # 活体喷焰和动画共用的实际视觉根。
		var sprite: Node2D = animator.get("_sprite") if animator != null else null # 冻结或无绘制对象时不强行发声。
		if is_instance_valid(sprite):
			entry = Aircraft.new(actor, sprite, JET, Vector3(-10.5, 1.24, 0.58))
	if entry != null and is_instance_valid(entry.anchor):
		_aircraft.append(entry)
		set_process(true)

## [param world] 是同帧致命位置，[param visual] 为舞台接管的纯视觉残骸，[param weight] 表示重量调参。
func _on_departure(world: Vector2, visual: Node2D, weight: float) -> void:
	var kind: StringName = visual.get_meta(&"death_kind", &"") # 这些机体的短声和尾声已由爆炸导演接管。
	if flight.get_airship_blasts() != null and kind in [&"fighter", &"turret", &"arbiter", &"transport", &"rocket"]:
		return
	audio.play_at(PASS, world, -12.0, lerpf(1.35, 0.90, weight), &"death_pull", 0.2, 1)
	if _departures.size() >= MAX_DEPARTURES or not is_instance_valid(visual):
		return
	for source: Departure in _departures: # 同场的近处群杀为同一个代表声源。
		if is_instance_valid(source.visual) and source.visual.global_position.distance_squared_to(world) < 140.0 * 140.0:
			return
	var sound := Departure.new() # 本片区只持有一个短距离追踪身份。
	sound.visual = visual
	sound.key = visual.get_instance_id()
	sound.born = _seconds
	sound.weight = clampf(weight, 0.0, 1.0)
	_departures.append(sound)
	set_process(true)

## 以 [param delta] 推进自然声像更新，动作控制器和实际敌机运动独立运行。
func _process(delta: float) -> void:
	_pending_step += delta / maxf(Engine.time_scale, 0.001)
	if _pending_step < 0.032:
		return
	var step: float = _pending_step # 连续的声音参数以自然时间取样。
	_pending_step = 0.0
	_seconds += step
	var viewport: Viewport = get_viewport() # 使用实际游戏画面，和背景虚拟俯仰无关。
	var canvas: Transform2D = viewport.get_global_canvas_transform() * viewport.get_canvas_transform() # 世界到画面的同一坐标约定。
	var size: Vector2 = viewport.get_visible_rect().size # 按画面比例归一近场阈值。
	var resized: bool = size != _view_size # 窗口改变不属于真实机体位移。
	_view_size = size
	for index: int in range(_aircraft.size() - 1, -1, -1): # 逆序安全回收退役或死亡的声源。
		var entry: Aircraft = _aircraft[index] # 当前实际观测的飞机。
		if not is_instance_valid(entry.actor) or entry.actor.is_death or entry.actor.is_queued_for_deletion() or not is_instance_valid(entry.anchor):
			audio.end_loop(entry.key)
			_aircraft.remove_at(index)
			continue
		if resized:
			entry.reset_motion()
		_track_aircraft(entry, step, canvas, size)
	_update_departures()
	if _aircraft.is_empty() and _departures.is_empty():
		set_process(false)

## [param entry] 提供真实引擎挂点，[param step] 用于测速，[param canvas] 和 [param size] 归一当前战斗视口。
func _track_aircraft(entry: Aircraft, step: float, canvas: Transform2D, size: Vector2) -> void:
	if not zombies.is_game_running() or not entry.anchor.is_visible_in_tree() or entry.actor.retiring_from_battle:
		audio.end_loop(entry.key)
		entry.reset_motion()
		return
	var world: Vector2 = entry.anchor.global_position # 使用这一帧的实际引擎位置。
	var gain: float = entry.mix.x # 转速变化较小时仍听得见实际相对运动。
	if entry.anchor is AnimatedSprite2D and entry.actor.zombie_type == CharacterRegistry.ZombieType.Z041RocketImp:
		world = entry.anchor.to_global(Vector2(58.0, 38.0)) # 原图两个喷口之间的局部锚点，跟随机体镜像。
		if entry.anchor.animation == &"idle":
			gain -= 10.0 # 待机帧保留亮喷口和低功率悬停音。
	var relative: Vector2 = (canvas * world / size) * 2.0 - Vector2.ONE # x 向右，y 只影响飞越范围。
	audio.update_loop(entry.key, entry.stream, world, gain, entry.mix.y, entry.mix.z, true)
	var strength: float = entry.sample_pass(world, relative, step) # 跨帧检测当前对象唯一一次经过。
	if strength > 0.0 and _seconds >= _next_pass:
		_next_pass = _seconds + 0.31
		audio.play_at(PASS, world, -8.0 + 3.6 * strength, 0.92 + 0.24 * strength, &"flyby", 0.25, 2)
		flight.register_flyby(world, strength)
		flyby.emit(world, entry.pass_speed, strength)

## 已分离的典型残骸在切出画面前持续移动声像，在远离时沉息。
func _update_departures() -> void:
	for index: int in range(_departures.size() - 1, -1, -1): # 固定最多三个片区代表。
		var entry: Departure = _departures[index] # 不持有原活体对象。
		var visual: Node2D = entry.visual # 真正的残骸位置。
		var age: float = _seconds - entry.born # 冲量声之后保留短风尾音。
		if not is_instance_valid(visual) or visual.is_queued_for_deletion() or age > 0.74:
			audio.end_loop(entry.key)
			_departures.remove_at(index)
			continue
		var gain: float = -13.0 - 10.0 * smoothstep(0.10, 0.74, age) # 远去时自然退到环境风中。
		audio.update_loop(entry.key, JET, visual.global_position, gain, 0.87 + 0.28 * entry.weight, age * 2.6, true)
