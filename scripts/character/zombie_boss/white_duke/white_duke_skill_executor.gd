extends RefCounted
class_name WhiteDukeSkillExecutor
## Reuses the normal grave manager, wave spawner, tier binding and timed buffs.
## Boss controls timing/animation; this executor owns only immediate skill effects.
var boss: ZB003WhiteDuke
var game: MainGameManager
var config: WhiteDukeConfig
var graves: WhiteDukeGraveService

func configure(owner: ZB003WhiteDuke, battle: MainGameManager,
		settings: WhiteDukeConfig, grave_service: WhiteDukeGraveService) -> void:
	boss = owner
	game = battle
	config = settings
	graves = grave_service

func _active() -> bool:
	return is_instance_valid(boss) and not boss.is_death \
		and is_instance_valid(game) and game.zombie_manager.is_game_running()

func opening() -> void:
	if not _active():
		return
	var stones := graves.create_graves(config.entrance_graves)
	graves.last_flag_wave(stones)

func perform(action: WhiteDukeBehaviorTree.Action) -> void:
	if not _active():
		return
	match action:
		WhiteDukeBehaviorTree.Action.RESURRECT:
			var count: int = config.skill_graves \
				+ (config.skill_graves_phase2_bonus if boss.boss_phase >= 2 else 0)
			var stones := graves.create_graves(count)
			graves.recent_for(stones,count)
		WhiteDukeBehaviorTree.Action.COMMAND:
			var first: StringName = &"elite" if boss.boss_phase >= 2 else &"veteran"
			for row in [1,3]:
				_spawn(CharacterRegistry.ZombieType.Z009Jackson,row,first)
			if boss.boss_phase >= 2:
				for row in [0,2,4]:
					_spawn(CharacterRegistry.ZombieType.Z009Jackson,row,&"base")
		WhiteDukeBehaviorTree.Action.FRENZY:
			for zombie: Zombie000Base in game.zombie_manager.all_zombies_1d.duplicate():
				if is_instance_valid(zombie) and not zombie.is_death and not zombie.is_hypno:
					AdventureZombieTimedSpeedBoost.apply_to(zombie,config.fury_speed_multiplier,
						config.fury_seconds)
					AdventureZombieTimedCombatBuff.grant_immunity(zombie,config.immunity_seconds)
		WhiteDukeBehaviorTree.Action.BREACH:
			var tier: StringName = &"elite" if boss.boss_phase >= 2 else &"veteran"
			for row in range(game.zombie_manager.all_zombie_rows.size()):
				_spawn(CharacterRegistry.ZombieType.Z006Paper,row,tier)

func phase_change() -> void:
	if not _active():
		return
	var columns: Array[int] = []
	var total: int = game.plant_cell_manager.row_col.y
	for col in range(maxi(0,total-config.phase_grave_columns),total):
		columns.append(col)
	graves.create_graves(game.plant_cell_manager.row_col.x * columns.size(), columns)
	graves.recent_for(graves.graves_in_columns(columns),
		config.phase_revival_limit,true)

func lane_change() -> void:
	if _active():
		graves.create_graves(1)

func _spawn(zombie_type: CharacterRegistry.ZombieType,
		row: int, tier: StringName) -> void:
	if row < 0 or row >= game.zombie_manager.all_zombie_rows.size():
		return
	# 白爵士直接叫来的援军共用墓碑复生外观。
	var zombie: Zombie000Base = game.zombie_manager.zombie_wave_manager.zombie_wave_create_manager.wave_create_zombie(
		zombie_type,row,-1,Callable(),false,AdventureZombieTierBinding.new(tier))
	if is_instance_valid(zombie):
		zombie.body.start_white_flame_revival()
