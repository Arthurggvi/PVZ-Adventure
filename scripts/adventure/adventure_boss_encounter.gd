## 独立 Boss 遭遇，按配置控制自然波次与独立周期援军。
## 不调用原版 win_on_boss_death；可配置等待死亡演出完成，再恢复自然波次。
extends Node
class_name AdventureBossEncounter

## 记录同一实例的登场、死亡、离场和阶段清场条件。
const BossTrace = preload("res://scripts/manager/zombie_manager/boss_lifecycle_trace.gd")

signal encounter_exited(encounter_id: StringName, exit_reason: int)
## 活动遭遇的当前生命比例。分裂遭遇按实际存活成员的总血量计算。
signal health_changed(ratio: float)

var config: BossEncounterDefinition
var wave_manager: ZombieWaveManager
var zombie_manager: ZombieManager
var boss: ZB000Base
var active := false
var summon_timer: Timer
var _summons: Dictionary[int, WeakRef] = {}
var _rng := RandomNumberGenerator.new()
## 可独立承伤且仍未完成退出演出的遭遇成员。
var _members: Dictionary[int, ZB000Base] = {}
## 单体遭遇为零。非零时观察后续加入同一稳定分组的实际 Boss。
var _group_id := 0
## 任一成员活着撤退时，整场遭遇最终按撤退结算。
var _member_escaped := false
## 直接启动时控制暂停；编排器批量启动时由编排器管理整组的暂停。
var _manage_wave_pause: bool = true
## 工厂配置初始生命时已经观察死亡与离树；战斗血量阈值从登场完成后开始计算。
var _starting := false

## 启动 [param encounter]；[param waves] 提供波次调度，[param manager] 负责登记 Boss。
## [param known_tiers] 是等阶目录；[param manage_wave_pause] 为 false 时调用者负责挂起与恢复。
func begin(encounter: BossEncounterDefinition, waves: ZombieWaveManager,
		manager: ZombieManager, known_tiers: Array[StringName], manage_wave_pause: bool = true) -> bool:
	if active or encounter == null or waves == null or manager == null:
		return false
	if not encounter.validate(waves.max_wave_one_round, known_tiers).is_empty():
		return false
	config = encounter
	wave_manager = waves
	zombie_manager = manager
	_manage_wave_pause = manage_wave_pause and config.natural_waves == BossEncounterDefinition.NaturalWaves.PAUSE_UNTIL_BOSS_EXIT
	_rng.randomize()
	if _manage_wave_pause:
		wave_manager.suspend_advancement()
	# 先进入可接收退出结果的状态；入树及登场通知都可能同步触发死亡。
	active = true
	_member_escaped = false
	_starting = true
	var spawned := zombie_manager.try_create_adventure_boss(config, _on_registered) # 工厂在登记成功、入树前交付成员。
	_starting = false
	if not active:
		return true # 已经完整交付并退出；不能重新启动该遭遇的援军。
	if not is_instance_valid(spawned):
		active = false
		if _manage_wave_pause:
			wave_manager.resume_advancement()
		return false
	if config.summon_rule == BossEncounterDefinition.SummonRule.NONE:
		return true
	summon_timer = Timer.new()
	summon_timer.wait_time = config.summon_interval_seconds
	summon_timer.one_shot = false
	add_child(summon_timer)
	summon_timer.timeout.connect(_on_summon_tick)
	summon_timer.start()
	return true

## Boss AI 可显式报告撤退；正式战斗中未死亡即离树也视为撤退。
## 显式撤退包含遭遇结束和实体离场，不能留下一个仍占敌方计数的“已逃跑 Boss”。
func notify_escaped() -> void:
	if not active or not zombie_manager.is_game_running():
		return
	var escaping: Array[ZB000Base] = _members.values() # 完成回调可能同步拆除整个遭遇。
	_finish(StageEventDefinition.BossExitReason.ESCAPED)
	for member: ZB000Base in escaping: # 本次撤退不能遗留占敌方计数的分身。
		if is_instance_valid(member) and not member.is_queued_for_deletion():
			member.queue_free()

## 在 [param member] 入树前接管它的正式遭遇，确保登场首帧也能报告死亡或撤离。
func _on_registered(member: ZB000Base) -> void:
	boss = member
	_group_id = member.boss_encounter_group_id()
	_observe(member)
	if _group_id != 0:
		zombie_manager.boss_member_registered.connect(_observe_reinforcement)

## 将 [param member] 的死亡、演出和血量变化纳入同一个正式遭遇。
func _observe(member: ZB000Base) -> void:
	var id: int = member.get_instance_id() # 按实例跟踪，即使之后本体先死也能结算分身。
	if _members.has(id):
		return
	_members[id] = member
	BossTrace.member(&"encounter_member", member, zombie_manager, config.encounter_id)
	member.signal_character_death.connect(_on_boss_defeated.bind(id))
	member.tree_exiting.connect(_on_boss_tree_exiting.bind(id))
	member.signal_trophy_requested.connect(_on_death_presentation_finished.bind(id))
	var health := member.get_node(^"%HpComponent") as HpComponent # 登记发生在角色 @onready 引用赋值之前。
	health.signal_hp_loss.connect(_on_health_changed)

## [param member] 已通过工厂整组预检；同组增援在入树前就进入正式遭遇。
func _observe_reinforcement(member: ZB000Base) -> void:
	if active and member.boss_encounter_group_id() == _group_id:
		_observe(member)

## [param id] 指向一名完成实际死亡的成员。其余成员继续维持遭遇和援军。
func _on_boss_defeated(id: int) -> void:
	if not active or not _members.has(id):
		return
	if summon_timer != null and _first_living_member() == null:
		summon_timer.stop()
	if not config.wait_for_death_presentation:
		_remove_member(id, StageEventDefinition.BossExitReason.DEFEATED)

## [param _position] 是原有死亡演出落点，[param id] 只完成对应成员的退出。
func _on_death_presentation_finished(_position: Vector2, id: int) -> void:
	var member: ZB000Base = _members.get(id) # 可能已由直接离场入口从组中移除。
	if active and is_instance_valid(member) and member.is_death:
		_remove_member(id, StageEventDefinition.BossExitReason.DEFEATED)

## [param id] 对应的真实角色离树。场景卸载不能触发遭遇奖励。
func _on_boss_tree_exiting(id: int) -> void:
	# 正式战斗中离树按死亡/撤退区分；场景卸载不能触发结算。
	if active and is_instance_valid(zombie_manager) and zombie_manager.is_game_running() \
		and zombie_manager.main_game == get_tree().current_scene \
		and not zombie_manager.main_game.is_queued_for_deletion():
		var member: ZB000Base = _members.get(id) # 演出正常完成时早已结算这一位。
		if is_instance_valid(member):
			_remove_member(id, StageEventDefinition.BossExitReason.DEFEATED if member.is_death else StageEventDefinition.BossExitReason.ESCAPED)

## 从遭遇移除 [param id]，保存 [param reason]。只有最后一位离场才发布一次结果。
func _remove_member(id: int, reason: int) -> void:
	if not _members.erase(id):
		return
	_member_escaped = _member_escaped or reason == StageEventDefinition.BossExitReason.ESCAPED
	if _members.is_empty():
		_finish(StageEventDefinition.BossExitReason.ESCAPED if _member_escaped else StageEventDefinition.BossExitReason.DEFEATED)

## 仍在战斗的首个成员，供援军规则继续使用实际阶段。
func _first_living_member() -> ZB000Base:
	for member: ZB000Base in _members.values(): # 死亡演出成员暂时留在集合中。
		if is_instance_valid(member) and not member.is_death and not member.is_queued_for_deletion():
			return member
	return null

## [param _remaining] 和 [param _dropped] 为单一组件的原信号；对外使用整个遭遇的生命比例。
func _on_health_changed(_remaining: int, _dropped: bool) -> void:
	if not active or _starting:
		return
	var remaining := 0 # 已死亡成员在演出期间也不再贡献生命。
	var maximum := 0 # 独立 Boss 采用自己的最大值。
	var encounter_maximum := 0 # 对分裂遭遇保留开始战斗时的完整上限。
	for member: ZB000Base in _members.values(): # 本体和增援的血量组件均是真实来源。
		if not is_instance_valid(member):
			continue
		var health := member.get_node(^"%HpComponent") as HpComponent # 子节点先于角色完成初始化。
		if not member.is_death:
			remaining += health.curr_hp if health.is_node_ready() else health.max_hp
		maximum += health.max_hp
		encounter_maximum = maxi(encounter_maximum, member.boss_encounter_maximum_hp())
	health_changed.emit(float(remaining) / maxf(1.0, float(encounter_maximum if encounter_maximum > 0 else maximum)))

func _on_summon_tick() -> void:
	if not active or not zombie_manager.is_game_running():
		return
	var living: ZB000Base = _first_living_member() # 本体先死后仍由存活分身维持该遭遇。
	if living == null:
		return
	var capacity: int = config.max_alive_periodic_summons - _summons.size() # 当前场上剩余名额。
	var count: int = config.summon_count # 一阶段及未配置二阶段时的批量。
	if living.boss_phase >= 2 and config.phase_two_summon_count > 0:
		count = config.phase_two_summon_count
	count = zombie_manager.available_zombie_slots(mini(count, capacity))
	for _i: int in range(count): # 每个剩余名额独立抽取物种与等阶。
		var type_key: Variant = _weighted_pick(config.summon_zombie_weights)
		var tier_key: Variant = _weighted_pick(config.summon_tier_weights)
		if type_key == null or tier_key == null:
			return
		var zombie: Zombie000Base = wave_manager.zombie_wave_create_manager.spawn_stage_support(
			type_key as CharacterRegistry.ZombieType, tier_key as StringName)
		if zombie == null:
			continue
		var instance_id: int = zombie.get_instance_id()
		_summons[instance_id] = weakref(zombie)
		zombie.signal_character_death.connect(_remove_summon.bind(instance_id))
		zombie.signal_character_be_hypno.connect(_remove_summon.bind(instance_id))
		zombie.tree_exiting.connect(_remove_summon.bind(instance_id))

func _weighted_pick(weights: Dictionary) -> Variant:
	var total := 0
	for key: Variant in weights:
		total += maxi(0, int(weights[key]))
	if total <= 0:
		return null
	var draw: int = _rng.randi_range(1, total)
	for key: Variant in weights:
		draw -= maxi(0, int(weights[key]))
		if draw <= 0:
			return key
	return null

func _remove_summon(instance_id: int) -> void:
	_summons.erase(instance_id)

func _finish(reason: int) -> void:
	if not active:
		return
	active = false
	if zombie_manager.boss_member_registered.is_connected(_observe_reinforcement):
		zombie_manager.boss_member_registered.disconnect(_observe_reinforcement)
	if summon_timer != null:
		summon_timer.stop()
		summon_timer.queue_free()
		summon_timer = null
	if _manage_wave_pause and is_instance_valid(wave_manager) \
			and is_instance_valid(zombie_manager) and zombie_manager.is_game_running():
		wave_manager.resume_advancement()
	encounter_exited.emit(config.encounter_id, reason)
	_summons.clear()
	_members.clear()

func _exit_tree() -> void:
	active = false
	if summon_timer != null:
		summon_timer.stop()
	_summons.clear()
	_members.clear()
