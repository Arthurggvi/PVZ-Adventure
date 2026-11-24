## 战场持有的一次 TMC-112。受影响的僵尸和僵王共享施放时长及恢复曲线。
extends Node

## 自然到期且所有目标恢复后通知演出；切阶段和离树只做清理。
signal expired

## 施放时冻结的战局身份；普通暂停不会让来源失效。
var _source: RepeaterShotContext
## 仍受本次施放影响的存活敌人；离场与转阵营会撤销来源。
var _targets: Array[Character000Base] = []
## 本次战场负责发布普通僵尸和僵王的登记事件。
var _manager: ZombieManager
## 初始行动倍率，1 为正常速度。
var _initial_rate: float
## 单次施放的持续战斗秒数，不因新目标入场而重新开始。
var _duration: float
## 两个 Bézier 恢复控制点，X 为时间进度，Y 为已恢复比例。
var _recovery_handles: PackedVector2Array
## 本帧剩余减速强度，视觉与所有新旧敌人使用同一份。
var _strength := 1.0
## 最近一次物理帧结算的行动倍率，新敌人立即继承这个值。
var _current_rate := 1.0
## 禁止到期后、排队释放前再次接纳信号。
var _finished := false
## 已经过的战斗秒数，表盘和镜片也从这里读取。
var elapsed := 0.0

## [param source] 为本局身份，[param targets] 为施放时快照。
## [param seconds] 为持续的战斗秒数，[param rate] 为起始行动倍率。
## [param first_handle] 与 [param second_handle] 的 X 为时间进度，Y 为恢复比例。
func _init(source: RepeaterShotContext, targets: Array[Character000Base], seconds: float,
		rate: float, first_handle: Vector2, second_handle: Vector2) -> void:
	_source = source
	for target: Character000Base in targets: # 表盘初始化前按钟表匠的受效资格筛选快照。
		if is_instance_valid(target) and target.can_receive_clockmaker_slowdown():
			_targets.append(target)
	_duration = seconds
	_initial_rate = rate
	_recovery_handles = PackedVector2Array([first_handle, second_handle])
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -50

## 先接入出生信号，再应用施放帧速率；同步补齐两步之间可能加入的敌人。
func _ready() -> void:
	_manager = _source.game.zombie_manager if is_instance_valid(_source.game) else null
	_current_rate = _initial_rate
	if is_instance_valid(_manager):
		_manager.signal_zombie_created.connect(_on_zombie_created)
		_manager.signal_living_bosses_changed.connect(_on_bosses_changed)
	_apply_rate(_current_rate)
	_capture_existing_arrivals()

## 只有本次施放推进时钟。普通暂停保持时间和倍率；失效立即撤销。
func _physics_process(delta: float) -> void:
	if not _source.is_active():
		_finish(false)
		return
	if get_tree().paused:
		return
	elapsed = minf(elapsed + delta, _duration)
	if elapsed >= _duration - 0.000001:
		_finish(true)
		return
	_strength = 1.0 - _sample_recovery(1.0 - remaining_fraction())
	_current_rate = lerpf(1.0, _initial_rate, _strength)
	_apply_rate(_current_rate)

## [param zombie] 完成登记后接入本次施放的剩余时长和倍率。
func _on_zombie_created(zombie: Zombie000Base) -> void:
	_track_arrival(zombie)

## 僵王及分身正式登记后共用当前倍率。已经接入的成员由目标集合去重。
func _on_bosses_changed() -> void:
	if not is_instance_valid(_manager):
		return
	for boss: ZB000Base in _manager.get_living_bosses(): # 已确认入树的存活僵王快照。
		_track_arrival(boss)

## 施放到入树间若恰有新实体进入，按真实管理器名单补齐且不重复登记。
func _capture_existing_arrivals() -> void:
	if not is_instance_valid(_manager):
		return
	for row: Array in _manager.all_zombies_2d:
		for zombie: Zombie000Base in row.duplicate():
			_track_arrival(zombie)
	_on_bosses_changed()

## [param candidate] 须属于本局的存活敌人，接入时继承当前倍率及剩余秒数。
func _track_arrival(candidate: Character000Base) -> void:
	if _finished or not _source.is_active() or elapsed >= _duration \
			or not is_instance_valid(candidate) or candidate.is_queued_for_deletion() \
			or not candidate.can_receive_clockmaker_slowdown() \
			or not candidate.is_inside_tree() or candidate.is_death or candidate.is_hypno \
			or candidate.character_init_type != Character000Base.E_CharacterInitType.IsNorm \
			or not _source.game.is_ancestor_of(candidate) or _targets.has(candidate):
		return
	_targets.append(candidate)
	candidate.set_clockmaker_slowdown(get_instance_id(), _current_rate)

## 返回线性剩余时间供表盘刻度读取；新目标不改变该值。
func remaining_fraction() -> float:
	return clampf(1.0 - elapsed / _duration, 0.0, 1.0)

## 返回与战斗倍率同步的剩余减速强度。
func slowdown_strength() -> float:
	return _strength

## 给定时间进度，以二分法反解 Bézier 参数再读取 Y 轴恢复量。
func _sample_recovery(progress: float) -> float:
	var left := 0.0
	var right := 1.0
	for _iteration: int in range(16):
		var middle: float = (left + right) * 0.5
		var point: Vector2 = Vector2.ZERO.bezier_interpolate(
			_recovery_handles[0], _recovery_handles[1], Vector2.ONE, middle)
		if point.x < progress:
			left = middle
		else:
			right = middle
	return Vector2.ZERO.bezier_interpolate(
		_recovery_handles[0], _recovery_handles[1], Vector2.ONE, (left + right) * 0.5).y

## 表现层只读目标列表；出生目标的脚下表盘沿用同一次剩余刻度。
func targets_for_visual() -> Array[Character000Base]:
	return _targets

## 为本次施放更新 [param rate]，并撤销不再属于战局或已失去受效资格的目标。
func _apply_rate(rate: float) -> void:
	var source_id: int = get_instance_id() # 只更新本次施放的倍率分量。
	for index: int in range(_targets.size() - 1, -1, -1): # 倒序移除失效引用。
		var target: Character000Base = _targets[index] # 本帧待更新或撤销的实体。
		if not is_instance_valid(target):
			_targets.remove_at(index)
		elif target.is_death or target.is_hypno or not target.is_inside_tree() \
				or target.is_queued_for_deletion() or not target.can_receive_clockmaker_slowdown() \
				or not _source.game.is_ancestor_of(target):
			target.set_clockmaker_slowdown(source_id, 1.0)
			_targets.remove_at(index)
		else:
			target.set_clockmaker_slowdown(source_id, rate)

## 先切断出生订阅与登记，再撤销来源，防止过期前一帧重入。
func _finish(expired_naturally: bool) -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	_disconnect_arrivals()
	_strength = 0.0
	_release_targets()
	if expired_naturally and _source.is_active():
		expired.emit()
	queue_free()

## 只断开本次施放的监听；关卡其它订阅者保持原样。
func _disconnect_arrivals() -> void:
	if not is_instance_valid(_manager):
		return
	if _manager.signal_zombie_created.is_connected(_on_zombie_created):
		_manager.signal_zombie_created.disconnect(_on_zombie_created)
	if _manager.signal_living_bosses_changed.is_connected(_on_bosses_changed):
		_manager.signal_living_bosses_changed.disconnect(_on_bosses_changed)

## 撤销此来源的独立倍率，不干涉其它行动或寒冷控制。
func _release_targets() -> void:
	var source_id: int = get_instance_id() # 终止本次时间轴对应的来源。
	for target: Character000Base in _targets: # 每名仍有效的角色各撤销一次。
		if is_instance_valid(target):
			target.set_clockmaker_slowdown(source_id, 1.0)
	_targets.clear()

## 意外换场或场景释放时仍必须解除信号与速度来源。
func _exit_tree() -> void:
	_finished = true
	_disconnect_arrivals()
	_release_targets()
