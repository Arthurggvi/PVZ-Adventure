## AdventureStage 运行规则与旧 PVZ 战斗内核的唯一协议转换。
## 新建 ResourceLevelData，不复制任何原版关卡/存档/胜负配置。
extends RefCounted
class_name AdventureBattleEnvironmentAdapter

static func build(env: AdventureBattleEnvironment,
		phase: StagePhaseDefinition) -> ResourceLevelData:
	if env == null or phase == null or phase.wave_profile == null:
		return null
	if not env.validate().is_empty() or phase.max_selected_cards < 1 or phase.max_selected_cards > 15:
		return null
	var level := ResourceLevelData.new()
	level.game_sences = env.scene
	level.game_BG = env.background
	level.game_BGM = env.music
	level.is_fog = env.fog
	level.is_rain = env.rain
	level.is_day = env.daytime
	level.is_day_sun = env.daytime_sun
	level.is_lawn_mover = env.lawn_mowers
	level.is_zombie_can_home = env.zombie_can_reach_home
	level.start_sun = env.initial_sun
	level.zombie_multy = env.zombie_power_multiplier
	level.boss_spawn_position = env.boss_spawn_position
	level.is_shovel = env.shovel_enabled
	level.all_pre_plant_data = env.preplanted.duplicate(true)
	level.max_wave = phase.wave_profile.wave_count
	level.max_choosed_card_num = phase.max_selected_cards
	level.monster_mode = ConstLevelData.E_MonsterMode.Norm
	level.card_mode = ConstLevelData.E_CardMode.Norm
	level.look_show_zombie = true
	level.can_choosed_card = true
	level.game_round = 1
	level.win_on_boss_death = false
	level.boss_type = CharacterRegistry.ZombieBossType.Null
	level.boss_spawn_wave = 0
	level.prechosen_cards.clear()
	level.save_game_data_main_game = null
	level.zombie_refresh_types.clear()
	for band: WaveBandDefinition in phase.wave_profile.bands:
		for zombie_type: int in band.zombie_weights:
			if band.zombie_weights[zombie_type] > 0 and not level.zombie_refresh_types.has(zombie_type):
				level.zombie_refresh_types.append(zombie_type as CharacterRegistry.ZombieType)
	return level if level.max_wave >= 2 and not level.zombie_refresh_types.is_empty() else null
