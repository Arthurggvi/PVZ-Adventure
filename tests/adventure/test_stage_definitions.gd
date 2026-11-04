## P1-A 静态 Resource 契约短测；不创建关卡场景、不执行事件或奖励。
extends Node

## 测试显式提供的等阶目录，仅是夹具，不声明运行时已实现任何等阶。
const TIERS: Array[StringName] = [&"fixture_base"]
## 测试显式提供的钥匙目录，不设置实际关卡的耗钥匙规则。
const KEYS: Array[StringName] = [&"fixture_key"]
## 动态调用也保留元素类型的空目录夹具。
const NO_TIERS: Array[StringName] = []

## 延迟加载 StageDefinition，避免命令行测试解析期提前载入现有角色场景。
var _stage_model: GDScript
## 延迟加载 StagePhaseDefinition，避免命令行测试解析期提前载入现有角色场景。
var _phase_model: GDScript
## 延迟加载 WaveProfile，避免命令行测试解析期提前载入现有角色场景。
var _wave_model: GDScript
## 延迟加载 WaveBandDefinition，避免命令行测试解析期提前载入现有角色场景。
var _band_model: GDScript
## 延迟加载 DropTable，避免命令行测试解析期提前载入现有角色场景。
var _drop_model: GDScript
## 延迟加载 DropEntryDefinition，避免命令行测试解析期提前载入现有角色场景。
var _entry_model: GDScript
## 延迟加载 BossEncounterDefinition，避免命令行测试解析期提前载入现有角色场景。
var _boss_model: GDScript
## 延迟加载 StageEventDefinition，避免命令行测试解析期提前载入现有角色场景。
var _event_model: GDScript

## 延迟到脚本类加载完成；断言失败由短超时返回非零退出码。
func _ready() -> void:
	get_tree().create_timer(25.0, true, false, false).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

## 构造一个仅用于校验的掉落资源，不预填任何游戏关卡配置。
func _drop_table() -> Resource:
	var entry: Resource = _entry_model.new() # 独立夹具的固定发放条目。
	entry.entry_id = &"fixture_drop"
	entry.rule = _entry_model.Rule.GUARANTEED
	entry.asset_kind = _entry_model.AssetKind.ITEM
	entry.asset_id = &"unsaturated_fat"
	entry.quantity_min = 1
	entry.quantity_max = 1
	var table: Resource = _drop_model.new() # 无加权池时不设置抽取策略。
	table.table_id = &"fixture_table"
	table.entries.append(entry)
	return table

## 为 [param kind] 创建合法的两波阶段夹具，所有规则都显式赋值。
func _phase(kind: int) -> Resource:
	var band: Resource = _band_model.new() # 测试波段，不是实际关卡概率。
	band.band_id = &"fixture_band"
	band.first_wave = 1
	band.last_wave = 2
	band.zombie_weights[1] = 1
	band.tier_weights[&"fixture_base"] = 1
	var profile: Resource = _wave_model.new() # 阶段自己的自然波次配置。
	profile.profile_id = &"fixture_waves"
	profile.wave_count = 2
	profile.bands.append(band)
	var phase: Resource = _phase_model.new() # normal/nightmare 均强制选卡与预览。
	phase.phase_id = &"fixture_normal" if kind == _phase_model.Kind.NORMAL else &"fixture_nightmare"
	phase.kind = kind
	phase.unlock_rule = _phase_model.UnlockRule.OPEN if kind == _phase_model.Kind.NORMAL else _phase_model.UnlockRule.NORMAL_CLEARED
	phase.key_use = _phase_model.KeyUse.NOT_REQUIRED
	phase.card_mode = _phase_model.CardMode.CHOOSE_CARDS
	phase.max_selected_cards = 2
	phase.require_card_selection = true
	phase.require_zombie_preview = true
	phase.wave_profile = profile
	phase.drop_table = _drop_table()
	return phase

## 构造仅元数据的 Boss 遭遇，用于校验自然波次暂停与持续召唤字段。
func _boss() -> Resource:
	var boss: Resource = _boss_model.new() # 不实例化任何 Boss AI 或场景。
	boss.encounter_id = &"fixture_boss"
	boss.boss_type = 1
	boss.timing = _boss_model.Timing.EVENT_ONLY
	boss.natural_waves = _boss_model.NaturalWaves.PAUSE_UNTIL_BOSS_EXIT
	boss.summon_rule = _boss_model.SummonRule.PERIODIC
	boss.summon_while_paused = _boss_model.SummonWhilePaused.CONTINUE
	boss.summon_end = _boss_model.SummonEnd.BOSS_EXIT
	boss.summon_interval_seconds = 1.0
	boss.summon_count = 1
	boss.max_alive_summons = 2
	boss.summon_zombie_weights[1] = 1
	boss.summon_tier_weights[&"fixture_base"] = 1
	return boss

## 覆盖合法配置、概率/权重区别、波段、锁、事件及无执行副作用的边界。
func _run() -> void:
	assert(OS.get_user_data_dir().contains("stage-definition-test"), "必须隔离 APPDATA")
	_stage_model = load("res://scripts/adventure/stages/stage_definition.gd")
	_phase_model = load("res://scripts/adventure/stages/stage_phase_definition.gd")
	_wave_model = load("res://scripts/adventure/stages/wave_profile.gd")
	_band_model = load("res://scripts/adventure/stages/wave_band_definition.gd")
	_drop_model = load("res://scripts/adventure/stages/drop_table.gd")
	_entry_model = load("res://scripts/adventure/stages/drop_entry_definition.gd")
	_boss_model = load("res://scripts/adventure/stages/boss_encounter_definition.gd")
	_event_model = load("res://scripts/adventure/stages/stage_event_definition.gd")
	var stage: Resource = _stage_model.new() # 一关恰好 normal 和 nightmare 两阶段。
	stage.stage_id = &"fixture_stage"
	stage.environment = AdventureBattleEnvironment.new()
	stage.phases.append(_phase(_phase_model.Kind.NORMAL))
	stage.phases.append(_phase(_phase_model.Kind.NIGHTMARE))
	assert(stage.validate(TIERS, KEYS).is_empty())
	stage.environment = null
	assert(not stage.validate(TIERS, KEYS).is_empty())
	stage.environment = AdventureBattleEnvironment.new()
	var phase: Resource = stage.phases[0] # 以下负例修改独立夹具并立即还原。
	var band: Resource = phase.wave_profile.bands[0] # 唯一自然波段。
	assert(not stage.validate(NO_TIERS, KEYS).is_empty()) # 未知等阶不能静态引用。
	band.tier_weights[&"missing_tier"] = 0
	assert(not stage.validate(TIERS, KEYS).is_empty())
	band.tier_weights.erase(&"missing_tier")
	band.tier_weights[&"fixture_base"] = -1
	assert(not band.validate(TIERS).is_empty())
	band.tier_weights[&"fixture_base"] = 0
	assert(not band.validate(TIERS).is_empty())
	band.tier_weights[&"fixture_base"] = 1
	band.zombie_weights.clear()
	assert(not band.validate(TIERS).is_empty())
	band.zombie_weights[1] = 1
	var overlap: Resource = band.duplicate(true) # 相交的闭区间不允许出现。
	overlap.band_id = &"overlap"
	phase.wave_profile.bands.append(overlap)
	assert(not stage.validate(TIERS, KEYS).is_empty())
	phase.wave_profile.bands.pop_back()
	band.last_wave = 3
	assert(not stage.validate(TIERS, KEYS).is_empty())
	band.last_wave = 2
	phase.require_card_selection = false
	assert(not stage.validate(TIERS, KEYS).is_empty())
	phase.require_card_selection = true
	phase.require_zombie_preview = false
	assert(not stage.validate(TIERS, KEYS).is_empty())
	phase.require_zombie_preview = true
	phase.card_mode = _phase_model.CardMode.CONVEYOR
	assert(not stage.validate(TIERS, KEYS).is_empty())
	phase.card_mode = _phase_model.CardMode.CHOOSE_CARDS
	phase.unlock_rule = _phase_model.UnlockRule.KEY
	assert(not stage.validate(TIERS, KEYS).is_empty())
	phase.key_id = &"fixture_key"
	phase.key_count = 1
	phase.key_use = _phase_model.KeyUse.KEEP
	assert(stage.validate(TIERS, KEYS).is_empty())
	phase.key_id = &"missing_key"
	assert(not stage.validate(TIERS, KEYS).is_empty())
	phase.key_id = &"fixture_key"
	phase.key_use = _phase_model.KeyUse.CONSUME
	assert(stage.validate(TIERS, KEYS).is_empty())
	var table: Resource = phase.drop_table # 三种规则分别校验，不能把概率当权重。
	var entry: Resource = table.entries[0] # 原夹具为固定一份。
	entry.quantity_max = 2
	assert(not table.validate().is_empty())
	entry.rule = _entry_model.Rule.CHANCE
	entry.chance = 0.25
	assert(table.validate().is_empty())
	for chance: float in [-0.1, 1.1, NAN]: # 非有限值及 0–1 之外均非法。
		entry.chance = chance
		assert(not table.validate().is_empty())
	entry.chance = -1.0
	entry.rule = _entry_model.Rule.WEIGHTED
	assert(not table.validate().is_empty())
	entry.weight = 2
	table.weighted_draw_count = 1
	table.weighted_selection = _drop_model.WeightedSelection.WITHOUT_REPLACEMENT
	assert(table.validate().is_empty())
	table.entries.clear()
	assert(not table.validate().is_empty())
	phase.drop_table = _drop_table()
	var boss := _boss() # 验证暂停自然波次不会隐式决定召唤规则。
	assert(boss.validate(2, TIERS).is_empty())
	boss.summon_while_paused = _boss_model.SummonWhilePaused.UNSET
	assert(not boss.validate(2, TIERS).is_empty())
	boss.summon_while_paused = _boss_model.SummonWhilePaused.CONTINUE
	phase.boss_encounters.append(boss)
	for trigger: int in _event_model.Trigger.values(): # 每个受支持触发时机都具备可验证的参数。
		if trigger == _event_model.Trigger.UNSET:
			continue
		var event: Resource = _event_model.new() # 动作只是枚举参数，不会在 validate 中执行。
		event.event_id = StringName("fixture_event_%d" % trigger)
		event.trigger = trigger
		event.repeat_rule = _event_model.RepeatRule.ONCE_PER_PHASE
		event.order = 0
		event.action = _event_model.Action.PAUSE_NATURAL_WAVES
		match trigger:
			_event_model.Trigger.WAVE_BEFORE, _event_model.Trigger.WAVE_STARTED, _event_model.Trigger.WAVE_CLEARED:
				event.wave = 1
			_event_model.Trigger.ELAPSED_TIME:
				event.elapsed_seconds = 1.0
			_event_model.Trigger.ZOMBIE_COUNT:
				event.zombie_count = 0
				event.comparison = _event_model.Comparison.LESS_OR_EQUAL
			_event_model.Trigger.PLANT_PLACED:
				event.plant_filter = _event_model.PlantFilter.ANY
			_event_model.Trigger.BOSS_HP_THRESHOLD:
				event.encounter_id = boss.encounter_id
				event.boss_hp_ratio = 0.5
				event.comparison = _event_model.Comparison.LESS_OR_EQUAL
			_event_model.Trigger.BOSS_EXITED:
				event.encounter_id = boss.encounter_id
				event.boss_exit_reason = _event_model.BossExitReason.ANY
		var encounter_ids: Array[StringName] = [boss.encounter_id] # 动态调用保留参数元素类型。
		assert(event.validate(2, TIERS, encounter_ids).is_empty())
		phase.events.append(event)
	assert(stage.validate(TIERS, KEYS).is_empty())
	phase.events[0].action = _event_model.Action.BEGIN_BOSS_ENCOUNTER
	phase.events[0].action_target_id = &"missing_encounter"
	assert(not stage.validate(TIERS, KEYS).is_empty())
	# 新版自然波段必须覆盖每波，不能留给原版算法静默兜底。
	band.first_wave = 2
	assert(not phase.wave_profile.validate(TIERS).is_empty())
	band.first_wave = 1
	# 冒险 Boss 必须挂起普通波次，持续刷援军，离场后停止。
	boss.natural_waves = _boss_model.NaturalWaves.CONTINUE
	assert(not boss.validate(2, TIERS).is_empty())
	boss.natural_waves = _boss_model.NaturalWaves.PAUSE_UNTIL_BOSS_EXIT
	boss.summon_end = _boss_model.SummonEnd.PHASE_END
	assert(not boss.validate(2, TIERS).is_empty())
	boss.summon_end = _boss_model.SummonEnd.BOSS_EXIT
	assert(boss.validate(2, TIERS).is_empty())
	# 冷却事件分别支持未来冷却倍率和立即调整剩余冷却。
	var cooling: Resource = _event_model.new()
	cooling.event_id = &"fixture_cooling"
	cooling.trigger = _event_model.Trigger.BATTLE_START
	cooling.repeat_rule = _event_model.RepeatRule.ONCE_PER_PHASE
	cooling.order = 1
	cooling.action = _event_model.Action.MODIFY_CARD_COOLDOWN
	cooling.cooldown_scope = _event_model.CooldownScope.ALL_SELECTED
	cooling.cooldown_operation = _event_model.CooldownOperation.NEXT_USE_MULTIPLIER
	cooling.cooldown_value = 1.5
	cooling.cooldown_duration_seconds = 20.0
	assert(cooling.validate(2, TIERS).is_empty())
	cooling.cooldown_duration_seconds = 0.0
	assert(not cooling.validate(2, TIERS).is_empty())
	cooling.cooldown_operation = _event_model.CooldownOperation.ADJUST_REMAINING_SECONDS
	cooling.cooldown_value = -3.0
	assert(cooling.validate(2, TIERS).is_empty())
	cooling.cooldown_value = 0.0
	assert(not cooling.validate(2, TIERS).is_empty())
	print("PASS: P1-A static stage/phase/waves/tiers/keys/drop/boss/events contracts")
	get_tree().quit(0)
