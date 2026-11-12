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
	assert(normal.wave_profile.flag_wave_numbers() == [10, 20])
	assert(nightmare.wave_profile.flag_wave_numbers() == [10, 20, 30, 40])
	assert(normal.first_clear_items.get(&"plant_fiber", 0) == 1)
	var added_ids: Array[String] = [
		"recipe_p001", "recipe_p002", "recipe_wall_nut", "recipe_potato_mine",
		"pea_stem", "pea_pod", "sun_nectar", "flower_pollen", "plant_fiber",
		"nut_fragments", "unsaturated_fat", "explosive_seed", "plant_starch"]
	for phase: StagePhaseDefinition in [normal, nightmare]:
		assert(phase.drop_table.validate().is_empty())
		var drops: Dictionary = {}
		for entry: DropEntryDefinition in phase.drop_table.entries:
			drops[str(entry.asset_id)] = true
		for id: String in added_ids:
			assert(drops.has(id), "Drop missing from %s: %s" % [phase.phase_id, id])
		# 肥料只属于噩梦池，普通池不发放。
		assert(drops.has("fertilizer_lv1") == (phase == nightmare))
		assert(drops.has("fertilizer_lv2") == (phase == nightmare))
	# 闪电芦苇的材料来自没落营地噩梦，配方来自黑将军的击败事件。
	var camp_stage: StageDefinition = AdventureStageCatalog.load_stage(2) # 配方及材料的新来源关卡。
	var camp_nightmare: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		camp_stage, StagePhaseDefinition.Kind.NIGHTMARE) # 波次与 Boss 掉落都引用此阶段的配置。
	assert(camp_nightmare.drop_table.validate().is_empty())
	var crystal_chance: float = -1.0 # 电荷晶核未配置时保留非法概率作为哨兵。
	for item: DropEntryDefinition in camp_nightmare.drop_table.entries: # 仅遍历波次掉落。
		if item.asset_id == &"charge_crystal":
			crystal_chance = item.chance
		assert(item.asset_id != &"recipe_p050")
	assert(is_equal_approx(crystal_chance, 0.35))
	var boss_event: StageEventDefinition = camp_nightmare.events[0] # 黑将军的击败掉落事件。
	assert(boss_event.action_drop_table.entries[0].asset_id == &"recipe_p050")
	assert(stage.nightmare_key_id == &"lawn_nightmare_key")
	assert(stage.nightmare_key_use == StageDefinition.KeyUse.CONSUME)
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
	assert(nightmare.boss_encounters.is_empty() and nightmare.events.is_empty())
	assert(AdventureStageCatalog.entry_error(2, StagePhaseDefinition.Kind.NORMAL, state, inventory).is_empty())
	var level: ResourceLevelData = AdventureStageCatalog.build_level(1, StagePhaseDefinition.Kind.NORMAL)
	assert(level != null)
	assert(level.look_show_zombie and level.can_choosed_card)
	assert(level.max_wave == normal.wave_profile.wave_count)
	assert(level.max_choosed_card_num == stage.max_selected_cards)
	assert(level.zombie_refresh_types == [CharacterRegistry.ZombieType.Z001Norm, CharacterRegistry.ZombieType.Z003Cone])
	level.max_wave = 99
	# 独立副本延长两阶段末波，现有旗帜和预排出怪仍在有效范围内。
	var variant_stage: StageDefinition = stage.duplicate(true) as StageDefinition # 保留正式资源用于前面的入口校验。
	var variant_normal: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		variant_stage, StagePhaseDefinition.Kind.NORMAL) # 本副本的普通波段。
	var variant_nightmare: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		variant_stage, StagePhaseDefinition.Kind.NIGHTMARE) # 本副本的噩梦波段。
	variant_normal.wave_profile.wave_count = 21
	variant_normal.wave_profile.bands.back().last_wave = 21
	variant_nightmare.wave_profile.wave_count = 41
	variant_nightmare.wave_profile.bands.back().last_wave = 41
	assert(variant_stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	var variant_level := AdventureBattleEnvironmentAdapter.build(variant_stage, variant_normal) # 适配后的普通关卡参数。
	assert(variant_level != null and variant_level.max_wave == 21)
	assert(AdventureBattleEnvironmentAdapter.build(variant_stage, variant_nightmare).max_wave == 41)
	assert(stage.environment.initial_sun == 150)
	assert(state.to_dict().size() > 0)
	print("PASS: normal-only entry, key-gated continuation independent of prior clears, per-phase configs")
	get_tree().quit(0)
