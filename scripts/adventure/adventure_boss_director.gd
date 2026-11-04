## 同一战斗内的 Boss 排队和生命周期所有者。一个时刻只运行一个遭遇。
extends Node
class_name AdventureBossDirector

signal exited(encounter_id: StringName, reason: int)
signal hp_changed(encounter_id: StringName, ratio: float)
signal idle
signal failed(encounter_id: StringName)

var waves: ZombieWaveManager
var zombies: ZombieManager
var current: AdventureBossEncounter
var _queue: Array[BossEncounterDefinition] = []
var _scheduled: Dictionary[StringName, bool] = {}

func setup(wave_manager: ZombieWaveManager, zombie_manager: ZombieManager) -> void:
	waves = wave_manager
	zombies = zombie_manager

func enqueue(encounter: BossEncounterDefinition) -> void:
	if encounter == null or _scheduled.has(encounter.encounter_id):
		return
	_scheduled[encounter.encounter_id] = true
	_queue.append(encounter)
	_start_next()

func has_pending() -> bool:
	return not _queue.is_empty() or (is_instance_valid(current) and current.active)

func _start_next() -> void:
	if is_instance_valid(current) and current.active:
		return
	current = null
	if _queue.is_empty():
		idle.emit()
		return
	var encounter: BossEncounterDefinition = _queue.pop_front()
	var controller := AdventureBossEncounter.new()
	add_child(controller)
	if not controller.begin(encounter, waves, zombies, AdventureStageCatalog.tier_ids()):
		controller.queue_free()
		failed.emit(encounter.encounter_id)
		return
	current = controller
	controller.encounter_exited.connect(_on_exit)
	controller.boss.hp_component.signal_hp_loss.connect(_on_hp_changed.bind(encounter.encounter_id))

func _on_hp_changed(_remaining: int, _dropped: bool, encounter_id: StringName) -> void:
	if not is_instance_valid(current) or not current.active:
		return
	var hp: HpComponent = current.boss.hp_component
	hp_changed.emit(encounter_id, float(hp.curr_hp) / maxf(1.0, float(hp.max_hp)))

func _on_exit(encounter_id: StringName, reason: int) -> void:
	var finished: AdventureBossEncounter = current
	current = null
	# 先将结果交给战斗运行时，再启动下一场遭遇。
	exited.emit(encounter_id, reason)
	if is_instance_valid(finished):
		finished.queue_free()
	if is_instance_valid(current) and current.active:
		return
	if not _queue.is_empty():
		waves.suspend_advancement() # 消除相邻 Boss 间自然刷新窗口
	_start_next()
