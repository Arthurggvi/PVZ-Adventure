## 只验证阶段资源、钥匙门槛、普通战斗模板与单一玩家状态，不触碰真实档案。
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage: StageDefinition = AdventureStageCatalog.load_stage(1)
	assert(stage != null and stage.stage_id == AdventureStageCatalog.LAWN_ID)
	assert(stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	var normal: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.NORMAL)
	var nightmare: StagePhaseDefinition = AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.NIGHTMARE)
	assert(normal != null and nightmare != null)
	assert(nightmare.key_id == &"lawn_nightmare_key")
	assert(nightmare.unlock_rule == StagePhaseDefinition.UnlockRule.CONTINUE_WITH_KEY)
	assert(nightmare.key_use == StagePhaseDefinition.KeyUse.KEEP)
	var state := AdventureState.new()
	var inventory := AdventureInventoryService.new(state)
	assert(AdventureStageCatalog.entry_error(1, StagePhaseDefinition.Kind.NORMAL, state, inventory).contains("植物卡"))
	assert(not AdventureStageCatalog.entry_error(1, StagePhaseDefinition.Kind.NIGHTMARE, state, inventory).is_empty())
	assert(not inventory.add_card(CharacterRegistry.PlantType.P001PeaShooterSingle).is_empty())
	assert(AdventureStageCatalog.entry_error(1, StagePhaseDefinition.Kind.NORMAL, state, inventory).is_empty())
	assert(AdventureStageCatalog.entry_error(1, StagePhaseDefinition.Kind.NIGHTMARE, state, inventory).contains("只能从普通阶段"))
	assert(AdventureStageCatalog.continuation_error(stage, inventory).contains("钥匙"))
	assert(inventory.add_item("lawn_nightmare_key", 1))
	# 未持有任何历史首通标记，仅当前钥匙即可满足继续资格。
	assert(not AdventureStageCatalog.is_cleared(state, stage.stage_id, StagePhaseDefinition.Kind.NORMAL))
	assert(AdventureStageCatalog.continuation_error(stage, inventory).is_empty())
	AdventureStageCatalog.mark_cleared(state, stage.stage_id, StagePhaseDefinition.Kind.NORMAL)
	assert(AdventureStageCatalog.is_cleared(state, stage.stage_id, StagePhaseDefinition.Kind.NORMAL))
	assert(AdventureStageCatalog.continuation_error(stage, inventory).is_empty())
	assert(AdventureStageCatalog.entry_error(1, StagePhaseDefinition.Kind.NIGHTMARE, state, inventory).contains("只能从普通阶段"))
	assert(nightmare.boss_encounters.size() == 1 and nightmare.events.size() == 2)
	assert(AdventureStageCatalog.entry_error(2, StagePhaseDefinition.Kind.NORMAL, state, inventory).is_empty())
	var level: ResourceLevelData = AdventureStageCatalog.build_level(1, StagePhaseDefinition.Kind.NORMAL)
	assert(level != null)
	assert(level.look_show_zombie and level.can_choosed_card)
	assert(level.max_wave == normal.wave_profile.wave_count)
	assert(level.max_choosed_card_num == normal.max_selected_cards)
	assert(level.zombie_refresh_types.size() == 1)
	level.max_wave = 99
	# 两阶段独立波数：普通3波、噩梦7波，均可通过同一StageDefinition校验。
	var short_stage: StageDefinition = stage.duplicate(true) as StageDefinition
	var short_normal: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		short_stage, StagePhaseDefinition.Kind.NORMAL)
	var short_nightmare: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		short_stage, StagePhaseDefinition.Kind.NIGHTMARE)
	short_normal.wave_profile.wave_count = 3
	short_normal.wave_profile.bands[0].last_wave = 3
	short_nightmare.wave_profile.wave_count = 7
	short_nightmare.wave_profile.bands[1].last_wave = 7
	assert(short_stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	var short_level := AdventureBattleEnvironmentAdapter.build(short_stage.environment, short_normal)
	assert(short_level != null and short_level.max_wave == 3)
	assert(AdventureBattleEnvironmentAdapter.build(short_stage.environment, short_nightmare).max_wave == 7)
	assert(stage.environment.initial_sun == 150)
	assert(state.to_dict().size() > 0)
	print("PASS: normal-only entry, key-gated continuation independent of prior clears, per-phase configs")
	get_tree().quit(0)
