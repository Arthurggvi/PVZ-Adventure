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

func create_graves(count: int, columns: Array[int] = []) -> Array[TombStone]:
	if not _alive():
		return []
	return _game.plant_cell_manager.tomb_stone_manager.spawn_boss_graves(count,columns)

func graves_in_columns(columns: Array[int] = []) -> Array[TombStone]:
	return _all_stones(columns)

func _all_stones(columns: Array[int] = []) -> Array[TombStone]:
	var result: Array[TombStone] = []
	for stone: TombStone in _game.plant_cell_manager.tombstone_list:
		if stone is TombStone and is_instance_valid(stone) \
				and not stone.is_queued_for_deletion():
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

func queue_corpses(corpses: Array[Dictionary], stones: Array[TombStone],
		buff: bool = false) -> void:
	if stones.is_empty() or not _alive():
		return
	for i in corpses.size():
		if _pending.size() >= 120:
			break
		_pending.append({
			"corpse": corpses[i],
			"stone": weakref(stones[i % stones.size()]),
			"buff": buff
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
	for i in range(_pending.size()-1,-1,-1):
		if spawned >= 8:
			break
		var task: Dictionary = _pending[i]
		var stone: TombStone = (task["stone"] as WeakRef).get_ref() as TombStone
		if not is_instance_valid(stone) or stone.is_queued_for_deletion():
			_pending.remove_at(i)
			continue
		if is_instance_valid(stone.new_zombie):
			continue
		if _raise(stone,task["corpse"],bool(task["buff"])):
			spawned += 1
		_pending.remove_at(i)

func _raise(stone: TombStone, record: Dictionary,
		buff: bool) -> bool:
	var creator: ZombieWaveCreateManager = _game.zombie_manager.zombie_wave_manager.zombie_wave_create_manager
	var zombie: Zombie000Base = creator.wave_create_zombie(
		record["type"],stone.row_col.x,-1,Callable(),false,
		AdventureZombieTierBinding.new(record["tier"]))
	if not is_instance_valid(zombie):
		return false
	zombie.global_position.x = stone.global_position.x
	var hp: HpComponentZombie = zombie.hp_component as HpComponentZombie
	hp.curr_hp = maxi(1,ceili(hp.max_hp*.5))
	if hp.max_hp_armor1 > 0:
		hp.curr_hp_armor1 = maxi(1,ceili(hp.max_hp_armor1*.5))
	if hp.max_hp_armor2 > 0:
		hp.curr_hp_armor2 = maxi(1,ceili(hp.max_hp_armor2*.5))
	if buff:
		AdventureZombieTimedSpeedBoost.apply_to(zombie,_settings.fury_speed_multiplier,
			_settings.immunity_seconds)
		AdventureZombieTimedCombatBuff.grant_immunity(zombie,_settings.immunity_seconds)
	stone.new_zombie = zombie
	zombie.tree_exiting.connect(_clear_busy.bind(weakref(stone),weakref(zombie)),CONNECT_ONE_SHOT)
	_rise(stone,zombie)
	return true

func _rise(stone: TombStone, zombie: Zombie000Base) -> void:
	await zombie.zombie_up_from_tombstone(1.0)
	if is_instance_valid(stone) and stone.new_zombie == zombie:
		stone.new_zombie = null

func _clear_busy(stone_ref: WeakRef, zombie_ref: WeakRef) -> void:
	var stone: TombStone = stone_ref.get_ref() as TombStone
	if is_instance_valid(stone) and stone.new_zombie == zombie_ref.get_ref():
		stone.new_zombie = null
