extends Node
class_name AdventureZombieDeathArchive
## Battle-local immutable death snapshots; listens to the canonical spawn signal.
## Supports both timed resurrection and last-flag-wave resurrection.

var _manager: ZombieManager
var _seconds := 0.0
var _records: Array[Dictionary] = []
const MAX_RECORDS := 4096

func _ready() -> void:
	_manager = get_parent() as ZombieManager
	_manager.signal_zombie_created.connect(_on_spawned)

func _process(delta: float) -> void:
	if _manager.is_game_running():
		_seconds += delta

func _on_spawned(zombie: Zombie000Base) -> void:
	if zombie == null:
		return
	zombie.signal_character_death.connect(_on_died.bind(weakref(zombie)), CONNECT_ONE_SHOT)

func _on_died(reference: WeakRef) -> void:
	var zombie: Zombie000Base = reference.get_ref() as Zombie000Base
	if not is_instance_valid(zombie) or zombie.is_hypno or zombie.is_queued_for_deletion():
		return
	_records.append({
		"type": zombie.zombie_type,
		"tier": zombie.adventure_tier_id if zombie.adventure_tier_id != &"" else &"base",
		"lane": zombie.lane,
		"wave": zombie.curr_wave,
		"seconds": _seconds,
	})
	if _records.size() > MAX_RECORDS:
		_records.pop_front()

func recent(seconds: float, limit: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(_records.size()-1, -1, -1):
		var record: Dictionary = _records[i]
		if _seconds-float(record["seconds"]) > seconds:
			break
		result.append(record.duplicate())
		if limit >= 0 and result.size() >= limit:
			break
	return result

func previous_flag_wave_deaths() -> Array[Dictionary]:
	var waves: ZombieWaveManager = _manager.zombie_wave_manager
	var current: int = waves.curr_wave
	var profile: WaveProfile = waves.zombie_wave_create_manager.adventure_wave_profile
	var flag_index := -1
	for wave in range(current, -1, -1):
		if (profile.is_flag_wave(wave+1) if profile != null else wave%10==9):
			flag_index = wave
			break
	if flag_index < 0:
		return []
	var result: Array[Dictionary] = []
	for entry: Dictionary in _records:
		if int(entry["wave"]) == flag_index:
			result.append(entry.duplicate())
	return result

func clear_history() -> void:
	_seconds = 0.0
	_records.clear()
