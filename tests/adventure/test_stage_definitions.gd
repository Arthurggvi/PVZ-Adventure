## 单次入场 / 连续阶段的静态契约负例；无游戏进程与真实存档。
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var stage := AdventureStageCatalog.load_stage(1)
	assert(stage != null)
	assert(stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	var normal := AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.NORMAL)
	var nightmare := AdventureStageCatalog.find_phase(stage, StagePhaseDefinition.Kind.NIGHTMARE)
	assert(normal != null and nightmare != null)
	assert(stage.max_selected_cards == 2)
	assert(stage.nightmare_key_id == &"lawn_nightmare_key")
	assert(stage.nightmare_key_use == StageDefinition.KeyUse.KEEP)
	# 单次入场约束归整关，任何无效钥匙或卡槽都不能通过。
	stage.max_selected_cards = 0
	assert(not stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	stage.max_selected_cards = 2
	stage.nightmare_key_id = &"missing_key"
	assert(not stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	stage.nightmare_key_id = &"lawn_nightmare_key"
	# EVENT_ONLY Boss 必须有确定会经过的触发；玩家放置植物不能作为必需遭遇触发。
	var encounter: BossEncounterDefinition = nightmare.boss_encounters[0]
	var old_timing := encounter.timing
	var old_wave := encounter.wave
	encounter.timing = BossEncounterDefinition.Timing.EVENT_ONLY
	encounter.wave = 0
	assert(not stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	var start_event := StageEventDefinition.new()
	start_event.event_id = &"fixture_boss_start"
	start_event.trigger = StageEventDefinition.Trigger.BATTLE_START
	start_event.action = StageEventDefinition.Action.BEGIN_BOSS_ENCOUNTER
	start_event.action_target_id = encounter.encounter_id
	start_event.order = 1
	start_event.repeat_rule = StageEventDefinition.RepeatRule.ONCE_PER_PHASE
	nightmare.events.append(start_event)
	assert(stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	start_event.trigger = StageEventDefinition.Trigger.PLANT_PLACED
	start_event.plant_filter = StageEventDefinition.PlantFilter.ANY
	assert(not stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	start_event.trigger = StageEventDefinition.Trigger.BATTLE_START
	start_event.plant_filter = StageEventDefinition.PlantFilter.UNSET
	# 波次暂停/恢复仅由 BossDirector 控制；独立事件以及提前胜利静态拒绝。
	start_event.action = 1 # 预留序列化值，已不属于合法可配置事件动作
	start_event.action_target_id = &""
	assert(not start_event.validate(nightmare.wave_profile.wave_count, AdventureStageCatalog.tier_ids()).is_empty())
	start_event.action = StageEventDefinition.Action.FINISH_BATTLE
	start_event.action_battle_result = 1 # 历史胜利事件值已禁用
	assert(not start_event.validate(nightmare.wave_profile.wave_count, AdventureStageCatalog.tier_ids()).is_empty())
	nightmare.events.pop_back()
	encounter.timing = old_timing
	encounter.wave = old_wave
	assert(stage.validate(AdventureStageCatalog.tier_ids(), AdventureStageCatalog.key_ids()).is_empty())
	print("PASS: stage-owned admission, mandatory boss reachability, event-owned wave lock rejected")
	get_tree().quit(0)
