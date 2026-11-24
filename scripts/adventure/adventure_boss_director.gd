## 管理同场遭遇的先后顺序及同一触发批次的自然波次登场屏障。
extends Node
class_name AdventureBossDirector

## 一次遭遇结束，报告该遭遇的 ID 和离场原因。
signal exited(encounter_id: StringName, reason: int)
## 某个活动遭遇的 Boss 血量变化。
signal hp_changed(encounter_id: StringName, ratio: float)
## 所有排队及活动遭遇均已结束。
signal idle
## 指定遭遇无法启动。
signal failed(encounter_id: StringName)

## 编排器自有的波次挂起标记，独立于战斗的其他挂起源。
const PAUSE_SOURCE := &"adventure_boss_director"

## 自然波次调度器，负责在同组 Boss 完成登记后启动允许的自然波次。
var waves: ZombieWaveManager
## 本次战斗的 Boss 注册与出怪入口。
var zombies: ZombieManager
## 首个活动遭遇，供单 Boss 的旧读取入口使用。
var current: AdventureBossEncounter:
	get:
		return null if _active.is_empty() else _active[0]
## 已准备启动的遭遇组；空并行 ID 总是单独成组。
var _queue: Array[Array] = []
## 正在运行的同一组遭遇。
var _active: Array[AdventureBossEncounter] = []
## 本阶段已经请求的遭遇，防止事件重复调度。
var _scheduled: Dictionary[StringName, bool] = {}
## 等待或执行登场、处理退出通知时，防止回调重入调度。
var _dispatching: bool = false
## 遭遇启动失败后，等待战斗运行时结算失败。
var _has_failed: bool = false
## 编排器是否持有自然波次暂停，避免释放别的流程设置的暂停。
var _owns_pause: bool = false

## [param wave_manager] 为自然波次调度器，[param zombie_manager] 为所属战场。
func setup(wave_manager: ZombieWaveManager, zombie_manager: ZombieManager) -> void:
	waves = wave_manager
	zombies = zombie_manager

## 把单个事件引用的 [param encounter] 加入队列。
func enqueue(encounter: BossEncounterDefinition) -> void:
	var batch: Array[BossEncounterDefinition] = [encounter] # 单事件单独成批。
	enqueue_batch(batch)

## 一次接收相同触发点的 [param encounters]，同组 Boss 在同一帧登场。
func enqueue_batch(encounters: Array[BossEncounterDefinition]) -> void:
	if _has_failed:
		return
	var groups: Dictionary[StringName, int] = {} # 本次触发组在队列中的位置。
	var added: bool = false # 空批次不触发 idle 通知。
	for encounter: BossEncounterDefinition in encounters: # 保持首次出现的组和组内顺序。
		if encounter == null or _scheduled.has(encounter.encounter_id):
			continue
		_scheduled[encounter.encounter_id] = true
		var group_id: StringName = encounter.parallel_group # 空名称始终独立启动。
		if group_id != &"" and groups.has(group_id):
			_queue[groups[group_id]].append(encounter)
		else:
			if group_id != &"":
				groups[group_id] = _queue.size()
			var group: Array[BossEncounterDefinition] = [encounter] # 当前遭遇组。
			_queue.append(group)
		added = true
	if added:
		_start_next()

## 活动、排队或启动失败待处理的遭遇都会阻止清场结算。
func has_pending() -> bool:
	return _has_failed or _dispatching or not _queue.is_empty() or not _active.is_empty()

## 当前组结束后安排下一组；登场登记前先挂起自然波次。
func _start_next() -> void:
	if _dispatching or _has_failed or not _active.is_empty():
		return
	if _queue.is_empty():
		_release_wave_pause()
		idle.emit()
		return
	if not _owns_pause:
		_owns_pause = true
		waves.suspend_advancement(PAUSE_SOURCE)
	# 清波和 Boss 退出都可能源自碰撞回调。同步挂起自然波次，延后创建带碰撞体的节点。
	_dispatching = true
	_spawn_next_group.call_deferred()

## 在物理查询结束且空位足够时让整组 Boss 同帧登场；战斗结束时取消等待。
func _spawn_next_group() -> void:
	var group: Array[BossEncounterDefinition] = _queue.front() # 等待期间保留队首，其他触发批次可继续入队。
	while true:
		if not is_inside_tree() or is_queued_for_deletion() \
				or not is_instance_valid(zombies) or not zombies.is_game_running():
			_dispatching = false
			return
		if zombies.has_enemy_slots(group.size()) \
				or (zombies.max_live_enemies > 0 and group.size() > zombies.max_live_enemies):
			break # 超出战场最大容量的遭遇交给正常失败结算。
		await get_tree().process_frame
	_queue.pop_front()
	for encounter: BossEncounterDefinition in group: # 每个成员均走统一登记入口。
		var controller := AdventureBossEncounter.new() # 持有单一 Boss 及其援军计时。
		add_child(controller)
		_active.append(controller)
		controller.encounter_exited.connect(_on_exit.bind(controller))
		controller.health_changed.connect(_on_hp_changed.bind(controller))
		if not controller.begin(encounter, waves, zombies, AdventureStageCatalog.tier_ids(), false):
			_active.erase(controller)
			controller.queue_free()
			_has_failed = true
			failed.emit(encounter.encounter_id)
			break
	_dispatching = false
	_apply_wave_policy()
	_start_next() # 整组在登场回调中同步退出时也会重新检查胜利或启动下一组。

## 当前组全部允许自然出怪时释放登场屏障，混合组等最后一名挂起者离场。
func _apply_wave_policy() -> void:
	if _has_failed or _active.is_empty():
		return
	for controller: AdventureBossEncounter in _active: # 同组尚未退出的独立遭遇。
		if controller.config.natural_waves == BossEncounterDefinition.NaturalWaves.PAUSE_UNTIL_BOSS_EXIT:
			return
	_release_wave_pause()

## 只释放本编排器持有的自然波次暂停。
func _release_wave_pause() -> void:
	if _owns_pause:
		_owns_pause = false
		waves.resume_advancement(PAUSE_SOURCE)

## 传递 [param controller] 计算的实际遭遇血量比例 [param ratio]。
func _on_hp_changed(ratio: float, controller: AdventureBossEncounter) -> void:
	if not is_instance_valid(controller) or not controller.active:
		return
	hp_changed.emit(controller.config.encounter_id, ratio)

## [param encounter_id] 与 [param reason] 是 [param controller] 的离场结果。
func _on_exit(encounter_id: StringName, reason: int, controller: AdventureBossEncounter) -> void:
	_active.erase(controller)
	# 先写入退出结果，再允许同步事件请求新的遭遇。
	var was_dispatching := _dispatching # 同步退出时，由最外层的启动或退出操作继续处理队列。
	_dispatching = true
	exited.emit(encounter_id, reason)
	_dispatching = was_dispatching
	controller.queue_free()
	if not _dispatching:
		_apply_wave_policy()
		_start_next()
