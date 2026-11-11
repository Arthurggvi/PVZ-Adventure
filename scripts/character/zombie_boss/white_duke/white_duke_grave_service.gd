extends Node
class_name WhiteDukeGraveService
## Uses TombStoneManager, ZombieWaveCreateManager and the shared death archive.
## No shadow grave lists or independent zombie construction.

var _boss: ZB003WhiteDuke
var _game: MainGameManager
var _settings: WhiteDukeConfig
var _archive: AdventureZombieDeathArchive
var _clock := 0.0
var _boss_timer := 0.0
var _stone_timers: Dictionary[int, float] = {}
var _pending: Array[Dictionary] = []

func _ready() -> void:
	set_process(false)

func configure(boss: ZB003WhiteDuke, game: MainGameManager,
		settings: WhiteDukeConfig) -> void:
	_boss = boss
	_game = game
	_settings = settings
	_archive = game.zombie_manager.get_node("AdventureZombieDeathArchive") as AdventureZombieDeathArchive
	_boss_timer = settings.grave_boss_revive_seconds
	set_process(true)

func stop() -> void:
	set_process(false)
	_pending.clear()
	_stone_timers.clear()

func _alive() -> bool:
	return is_instance_valid(_boss) and not _boss.is_death \
		and is_instance_valid(_game) and _game.zombie_manager.is_game_running() \
		and _game.is_ancestor_of(_boss) and not _boss.is_queued_for_deletion()

## The only boss-target selector: never place or select revivals in col 0/1.
## Ordinary wave tombstones retain their own, unchanged candidate policy.
func _target_columns(requested: Array[int] = []) -> Array[int]:
	var result: Array[int] = []
	if not is_instance_valid(_game):
		return result
	var count: int = _game.plant_cell_manager.row_col.y
	for col in range(_settings.minimum_grave_column, count):
		if requested.is_empty() or requested.has(col):
			result.append(col)
	return result

func create_graves(count: int, columns: Array[int] = []) -> Array[TombStone]:
	if not _alive() or count <= 0:
		return []
	var targets := _target_columns(columns)
	if targets.is_empty():
		return []
	return _game.plant_cell_manager.tomb_stone_manager.spawn_boss_graves(count, targets)

func graves_in_columns(columns: Array[int] = []) -> Array[TombStone]:
	return _all_stones(columns)

func _all_stones(columns: Array[int] = []) -> Array[TombStone]:
	var result: Array[TombStone] = []
	for stone: TombStone in _game.plant_cell_manager.tombstone_list:
		if is_instance_valid(stone) and not stone.is_queued_for_deletion() \
				and stone.row_col.y >= _settings.minimum_grave_column:
			if columns.is_empty() or columns.has(stone.row_col.y):
				result.append(stone)
	return result

func last_flag_wave(stones: Array[TombStone]) -> void:
	queue_corpses(_archive.previous_flag_wave_deaths(), stones)

func recent_for(stones: Array[TombStone], count: int,
		buff: bool = false) -> void:
	var corpses: Array[Dictionary] = _archive.recent(_settings.recent_death_window)
	corpses.shuffle()
	if count < corpses.size():
		corpses.resize(count)
	queue_corpses(corpses,stones,buff)

## Select from explicit stones first, then existing field stones. When a skill
## has corpses but no usable grave, force two new graves on the same grid.
func _ensure_stones(preferred: Array[TombStone]) -> Array[TombStone]:
	var valid: Array[TombStone] = []
	for stone: TombStone in preferred:
		if is_instance_valid(stone) and not stone.is_queued_for_deletion() \
				and stone.row_col.y >= _settings.minimum_grave_column:
			valid.append(stone)
	if valid.is_empty():
		valid = _all_stones()
	if valid.is_empty():
		valid = create_graves(2)
	return valid

func queue_corpses(corpses: Array[Dictionary], stones: Array[TombStone],
		buff: bool = false) -> void:
	if corpses.is_empty() or not _alive():
		return
	var available := _ensure_stones(stones)
	if available.is_empty():
		return
	for i in corpses.size():
		if _pending.size() >= 120:
			break
		_pending.append({
			"corpse": corpses[i],
			"stone": weakref(available[i % available.size()]),
			"buff": buff,
		})
	_drain()

func _process(delta: float) -> void:
	if not _alive():
		stop()
		return
	_clock += delta
	var stones := _all_stones()
	var live_ids: Dictionary[int, bool] = {}
	for stone: TombStone in stones:
		var id := stone.get_instance_id()
		live_ids[id] = true
		if not _stone_timers.has(id):
			_stone_timers[id] = _clock+_settings.grave_auto_revive_seconds
		elif _clock >= _stone_timers[id]:
			_stone_timers[id] = _clock+_settings.grave_auto_revive_seconds
			_enqueue_random(stone)
	for id: int in _stone_timers.keys():
		if not live_ids.has(id):
			_stone_timers.erase(id)
	_boss_timer -= delta
	if _boss_timer <= 0:
		_boss_timer += _settings.grave_boss_revive_seconds
		if stones.is_empty() and not _archive.recent(INF).is_empty():
			stones = _ensure_stones(stones)
		if not stones.is_empty():
			_enqueue_random(stones.pick_random())
	_drain()

func _enqueue_random(stone: TombStone) -> void:
	var corpses: Array[Dictionary] = _archive.recent(INF)
	if corpses.is_empty():
		return
	if _pending.size() < 120:
		_pending.append({"corpse": corpses.pick_random(),"stone": weakref(stone),"buff":false})

func _drain() -> void:
	if not _alive():
		return
	var spawned := 0
	for i in range(_pending.size() - 1, -1, -1):
		if spawned >= 8:
			break
		var task: Dictionary = _pending[i]
		var stone: TombStone = (task["stone"] as WeakRef).get_ref() as TombStone
		if not is_instance_valid(stone) or stone.is_queued_for_deletion():
			var replacements := _ensure_stones([])
			if replacements.is_empty():
				_pending.remove_at(i)
				continue
			stone = replacements.pick_random()
		if is_instance_valid(stone.new_zombie):
			continue
		var record: Dictionary = task["corpse"]
		var on_created: Callable = Callable()
		if task["buff"]:
			on_created = _grant_phase_buff
		var zombie: Zombie000Base = stone.spawn_from_grave(record["type"],
			AdventureZombieTierBinding.new(record["tier"]), 0.5, on_created, false)
		_pending.remove_at(i)
		if is_instance_valid(zombie):
			spawned += 1

func _grant_phase_buff(zombie: Zombie000Base) -> void:
	AdventureZombieTimedSpeedBoost.apply_to(zombie, _settings.fury_speed_multiplier,
		_settings.immunity_seconds)
	AdventureZombieTimedCombatBuff.grant_immunity(zombie, _settings.immunity_seconds)
