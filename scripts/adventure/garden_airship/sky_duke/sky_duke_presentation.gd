## 花园飞艇的公爵演出接线。消费实际登记、动作和阶段事件，无法产生战斗单位或伤害。
extends Node

## 一个实际公爵的当前演出动作和锚点。
const Subject := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_subject.gd")
## 关卡级的短时编队、齐射和爆压资源。
const Effects := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_effects.gd")
## 实际身体前、后两层常驻风暴。
const Storm := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_storm.gd")
## 动作外部唯一共享的关卡风场入口。
const Flight := preload("res://scripts/adventure/garden_airship/garden_airship_flight.gd")

## 只在真实登记路径上收集 Boss。
@export var zombies: ZombieManager
## 现有花园飞艇飞行环境。
@export var flight: Flight
## 本局独占的实际空间声池。
@export var spatial_audio: GardenAirshipSpatialAudio
## 位于战斗图层下方的原有飞艇背景。
@export var background: CanvasLayer
## 比 HUD 更远的贴身空气层。
@export var air: CanvasLayer
## 后景节点允许在天空底色与真实云层之间插入齐射。
@export var sky: Node2D

## [param kind] 和 [param phase] 标识已释放的纯表现。[param event_id] 在场景内唯一。
signal presentation_released(kind: StringName, phase: int, event_id: int)

## 正式场景本身是默认世界画布的挂点。
@onready var _world: Node2D = get_parent() as Node2D
## 本轮真实登记成员的演出状态，按实例 ID 仅接线一次。
var _subjects: Dictionary[int, Subject] = {}
## 本场战斗演出时钟，跟随暂停与倍速。
var _seconds: float = 0.0
## 稳定的场景内事件序号，供编队、余烬种子和验收观测。
var _serial: int = 0
## 角色绑定顺序，用于确定性装饰随机数。
var _subject_serial: int = 0
## 最近一次重要演出后，暂不新排装饰气爆的截止秒数。
var _busy_until: float = 0.0
## 实装层的实际句柄，仅在本关有公爵演出时存在。
var _effects: Effects
## 本场只允许一个公爵使用完整常驻风暴，额外召唤仍可发令。
var _storm: Storm
## 场景级演出开关，供同一战场的验证对照。
var _enabled: bool = true


## 在实体精灵、飞行环境均已更新后取样画面。本场外没有订阅和像素成本。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 80
	zombies.boss_member_registered.connect(_register)
	set_process(false)


## [param enabled] 仅切换这场的纯视听表现，保留全部正式战斗节点及事件。
func set_presentation_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not is_node_ready():
		return
	if enabled and not _subjects.is_empty() and zombies.is_game_running():
		_ensure_layers()
	elif not enabled:
		_stop()


## 绑定 [param member] 的表现事件。正式工厂登记时成员可以尚未入树。
func _register(member: ZB000Base) -> void:
	var duke := member as Subject.Duke # 其它 Boss 的信号不接入这个作用域。
	if duke == null or duke.is_queued_for_deletion():
		return
	var key: int = duke.get_instance_id() # 只作成员身份，随机序列独立于引擎实例编号。
	if _subjects.has(key):
		return
	_subject_serial += 1
	var subject := Subject.new(duke, 4477 + _subject_serial * 1093) # 阶段锁定和动作记录使用同一成员。
	_subjects[key] = subject
	duke.action_started.connect(subject.begin)
	duke.action_cue.connect(_on_cue.bind(key))
	duke.action_finished.connect(subject.finish)
	duke.signal_boss_phase_changed.connect(_on_phase.bind(key))
	duke.signal_character_death.connect(_forget.bind(key), CONNECT_ONE_SHOT)
	duke.tree_exiting.connect(_forget.bind(key), CONNECT_ONE_SHOT)
	if _enabled:
		_ensure_layers()


## 消费 [param key] 本轮 [param action] 的一次表现标记。
func _on_cue(action: StringName, key: int) -> void:
	var subject: Subject = _subjects.get(key) # 保证同一动作重复回调不会多开出动窗口。
	if subject == null or action != subject.action or subject.cue_seen:
		return
	subject.cue_seen = true
	if action == &"teleport_out":
		if _can_present() and subject.actor.is_visible_in_tree():
			_update_teleport(subject, subject.actor.action_elapsed(), _reduced())
		subject.departed = true
	elif action in [&"command", &"sky_order"] and _can_present() and subject.actor.is_visible_in_tree():
		_release(subject, action, 0.0, _reduced())


## [param key] 的 [param phase] 由原生命组件提交，切换只增加短时演出。
func _on_phase(phase: int, key: int) -> void:
	var subject: Subject = _subjects.get(key) # 传送消隐中的人物不重新亮相。
	if phase == 2 and subject != null and not subject.departed and _can_present() and subject.actor.is_visible_in_tree():
		_release(subject, &"phase", 0.0, _reduced())


## 在 [param delta] 后同步真实动作与环境。正常清理不影响已经从 Boss 分离的尾流。
func _process(delta: float) -> void:
	if not zombies.is_game_running():
		_stop()
		return
	_seconds += delta
	var reduced: bool = _reduced() # 本帧统一沿用用户已有画质和兼容选择。
	var charge := 0.0 # 所有蓄势的最大压暗包络。
	var ambient: Subject # 最多选择一位可见的 Boss 使用完整常驻风暴。
	for subject: Subject in _subjects.values(): # 只检查已登记的公爵，从不遍历战斗场景。
		if not is_instance_valid(subject.actor) or not subject.actor.is_node_ready() or subject.departed \
				or not subject.actor.is_visible_in_tree():
			continue
		var age: float = subject.actor.action_elapsed() # 原精灵动作经过的有效秒数。
		charge = maxf(charge, subject.anticipation(age))
		if subject.action == &"teleport_out":
			_update_teleport(subject, age, reduced)
			if _effects == null:
				return # 观测者可在回调后关闭演出。
		if ambient == null or (ambient.actor.boss_phase < 2 and subject.actor.boss_phase >= 2):
			ambient = subject
	_update_ambient(ambient, reduced)
	if _effects == null:
		return
	_effects.update_frame(_seconds, charge * (0.62 if reduced else 1.0))
	if _subjects.is_empty() and _effects.active_count() == 0:
		_stop()


## 为 [param subject] 的 [param age] 对齐母版吸入及收束点。[param reduced] 沿用上层兼容档。
func _update_teleport(subject: Subject, age: float, reduced: bool) -> void:
	if age >= 1.43 and not subject.inhaled:
		subject.inhaled = true
		if age < 1.57:
			_effects.inhale(subject.origin(&"teleport_out"), subject.actor.boss_phase)
	if age >= 1.64 and not subject.collapsed:
		subject.collapsed = true
		if age < 2.18:
			_release(subject, &"teleport_out", age - 1.64, reduced)


## 在 [param subject] 的身体排序中保持风暴与收势；[param reduced] 使用兼容粒子预算。
func _update_ambient(subject: Subject, reduced: bool) -> void:
	if subject == null:
		if is_instance_valid(_storm):
			_storm.hide()
		return
	if not is_instance_valid(_storm) or _storm.get_parent() != subject.actor:
		_remove_storm()
		_storm = Storm.new()
		_storm.name = &"SkyDukeStorm"
		_storm.configure(subject.seed_value)
		subject.actor.add_child(_storm)
	_storm.show()
	var pressure_age: float = subject.idle_pressure_age(_seconds, _seconds < _busy_until) # 限制装饰气爆干扰真实信号。
	if pressure_age >= Subject.GATHER_SECONDS and not subject.pressure_released:
		subject.pressure_released = true
		_release(subject, &"pressure", pressure_age - Subject.GATHER_SECONDS, reduced)
		if not is_instance_valid(_storm):
			return
	var wind: Vector2 = flight.wind_for_visual(subject.origin(&"pressure")) # 实际船尾风，不直接等于机身飞掠方向。
	var local_wind: Vector2 = subject.actor.global_transform.affine_inverse().basis_xform(wind) # 将世界速度投影到身体。
	var age: float = subject.actor.action_elapsed() if pressure_age < 0.0 else pressure_age # 原动作秒或装饰气爆秒。
	var action: StringName = subject.action if pressure_age < 0.0 else &"pressure" # 只改变常驻粒子流向和半径。
	var strength: float = 1.0 - smoothstep(1.54, 1.89, age) if action == &"teleport_out" else 1.0 # 避免透明尾帧留下人物的前后层。
	_storm.update_frame(_seconds, subject.actor.boss_phase, local_wind, action, age, strength, reduced)


## 从 [param subject] 稳定锚点释放 [param kind]。[param lag] 为越过关键帧的动作秒，[param reduced] 为兼容档。
func _release(subject: Subject, kind: StringName, lag: float, reduced: bool) -> void:
	_serial += 1
	if kind != &"pressure":
		_busy_until = _seconds + 0.87
	var phase: int = subject.actor.boss_phase # 留在场地的余波使用触发当帧的阶段。
	_effects.release(kind, phase, subject.origin(kind), subject.axis(kind), _seconds - lag, _seconds,
		subject.seed_value + _serial * 181, reduced)
	presentation_released.emit(kind, phase, _serial)


## 确认动作和阶段通知仍属于此局有效战斗。
func _can_present() -> bool:
	return _enabled and _effects != null and can_process() and zombies.is_game_running()


## 使用原花园飞艇自动画质与现有关闭渲染选项，保留核心号令。
func _reduced() -> bool:
	return flight.quality_mode == 1 or (flight.quality_mode == 0 and OS.has_feature("mobile")) \
		or (is_instance_valid(Global.config_service) and Global.config_service.optional_rendering_disabled)


## 按需建立当前场地的纯表现画布对象。
func _ensure_layers() -> void:
	if _effects == null:
		_effects = Effects.new()
		_effects.install(_world, background, air, sky, flight, spatial_audio)
	set_process(true)


## [param key] 的人物死亡或离树后放弃剩余动作，不回收整个场地的尾流。
func _forget(key: int) -> void:
	_subjects.erase(key)
	if is_instance_valid(_storm) and _storm.get_parent().get_instance_id() == key:
		_remove_storm()


## 先隐藏身体前后两层，再释放批次。
func _remove_storm() -> void:
	if is_instance_valid(_storm) and not _storm.is_queued_for_deletion():
		_storm.hide()
		_storm.queue_free()
	_storm = null


## 战斗结束、重开和退出都立即交还场地层和演出声部。
func _stop() -> void:
	set_process(false)
	_remove_storm()
	if _effects != null:
		_effects.release_layers()
		_effects = null


## 离树后不会保留摄像、光照、近景音频或常驻粒子。
func _exit_tree() -> void:
	_stop()
	_subjects.clear()
