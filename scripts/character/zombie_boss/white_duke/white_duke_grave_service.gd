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
			"autonomous": false,
		})
	_drain()

## 用 [param delta] 推进墓碑自主复生与白爵士本体复生的独立计时。
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
			var first_delay: float = _settings.grave_auto_revive_seconds # 普通墓碑沿用原间隔。
			if stone.get_tombstone_kind() == TombStoneManager.WHITE_DUKE_GRAVE_KIND:
				first_delay = maxf(first_delay, _settings.grave_auto_revive_min_age)
			_stone_timers[id] = _clock + first_delay
		elif _clock >= _stone_timers[id]:
			_stone_timers[id] = _clock+_settings.grave_auto_revive_seconds
			_enqueue_random(stone, true)
	for id: int in _stone_timers.keys():
		if not live_ids.has(id):
			_stone_timers.erase(id)
	_boss_timer -= delta * _boss.action_rate()
	if _boss_timer <= 0:
		_boss_timer += _settings.grave_boss_revive_seconds
		if stones.is_empty() and not _archive.recent(INF).is_empty():
			stones = _ensure_stones(stones)
		if not stones.is_empty():
			_enqueue_random(stones.pick_random())
	_drain()

## 在 [param stone] 排入随机阵亡僵尸。[param autonomous] 表示墓碑自己的触发，随原墓碑失效。
func _enqueue_random(stone: TombStone, autonomous: bool = false) -> void:
	var corpses: Array[Dictionary] = _archive.recent(INF)
	if corpses.is_empty():
		return
	if _pending.size() < 120:
		_pending.append({"corpse": corpses.pick_random(), "stone": weakref(stone),
			"buff": false, "autonomous": autonomous})

## 释放可用墓碑上的任务，白爵士的任务在原墓碑被毁时改用同场可用墓碑。
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
			if task["autonomous"]:
				_pending.remove_at(i)
				continue
			var replacements := _ensure_stones([])
			if replacements.is_empty():
				_pending.remove_at(i)
				continue
			stone = replacements.pick_random()
		if is_instance_valid(stone.new_zombie):
			continue
		var record: Dictionary = task["corpse"]
		var on_created: Callable = _on_grave_emergence.bind(task["buff"]) # 所有白爵士墓碑出土共用入场效果。
		var zombie: Zombie000Base = stone.spawn_from_grave(record["type"],
			AdventureZombieTierBinding.new(_boss.encounter_summon_tier(record["tier"])), 0.5, on_created, false)
		_pending.remove_at(i)
		if is_instance_valid(zombie):
			spawned += 1

## [param zombie] 开始出土的僵尸。[param phase_buff] 为真时叠加转阶段原有增益。
func _on_grave_emergence(zombie: Zombie000Base, phase_buff: bool) -> void:
	var slowdown: Tween = zombie.create_tween() # 计时随僵尸暂停和释放，按未减速的战斗秒推进。
	var source_id: int = slowdown.get_instance_id() # 到期只移除这一份入场减速。
	var movement: MoveComponent = zombie.move_component # 独立作用于出土个体的位移。
	movement.set_move_rate_source(source_id, WhiteDukeConfig.GRAVE_ENTRY_SPEED_MULTIPLIER)
	slowdown.tween_interval(_settings.grave_entry_slow_seconds)
	slowdown.tween_callback(movement.set_move_rate_source.bind(source_id, 1.0))
	if phase_buff:
		AdventureZombieTimedSpeedBoost.apply_to(zombie, _settings.fury_speed_multiplier,
			_settings.immunity_seconds)
		AdventureZombieTimedCombatBuff.grant_immunity(zombie, _settings.immunity_seconds)
