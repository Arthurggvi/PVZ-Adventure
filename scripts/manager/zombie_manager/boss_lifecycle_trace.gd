## Boss 登记、死亡、演出与遭遇退出的低频记录；以实例和分组编号关联同一场战斗。
extends RefCounted

## 记录 [param event] 对应的 [param boss] 和 [param manager]；[param encounter_id] 关联正式关卡配置。
static func member(event: StringName, boss: ZB000Base, manager: ZombieManager, encounter_id: StringName = &"") -> void:
	if not is_instance_valid(boss):
		return
	var data := _battle(manager) # 事件发生时的真实战场和清场计数。
	var health := boss.get_node_or_null(^"%HpComponent") as HpComponent # 入树前还没有初始化当前血量。
	data.merge({
		"event": event, "encounter": encounter_id, "boss": boss.get_boss_display_name(), "instance": str(boss.get_instance_id()),
		"group": str(boss.boss_encounter_group_id()), "boss_phase": boss.boss_phase,
		"hp": health.curr_hp if is_instance_valid(health) and health.is_node_ready() else -1,
		"max_hp": health.max_hp if is_instance_valid(health) else -1, "dead": boss.is_death,
		"forced_source": boss.forced_defeat_source,
	})
	if event == &"death" and OS.is_debug_build():
		data["stack"] = get_stack().slice(1, 9)
	print("[BossLifecycle] ", JSON.stringify(data))

## 把 [param encounter_id] 的 [param reason] 与正式 [param manager] 的状态写在同一条记录。
static func result(manager: ZombieManager, encounter_id: StringName, reason: int) -> void:
	var data := _battle(manager) # 正式遭遇退出时，编排器随后还会处理同批其他遭遇。
	data.merge({"event": "encounter_exit", "encounter": encounter_id,
		"exit": StageEventDefinition.BossExitReason.find_key(reason)})
	print("[BossLifecycle] ", JSON.stringify(data))

## 在 [param event] 记录 [param manager] 实际判胜入口返回的 [param blocker]。
static func victory(manager: ZombieManager, blocker: StringName, event: StringName = &"encounters_idle") -> void:
	var data := _battle(manager) # 此刻可以区分继续自然波次和等待清掉剩余敌人。
	data.merge({"event": event, "victory_blocker": blocker})
	print("[BossLifecycle] ", JSON.stringify(data))

## 读取 [param manager] 所属战斗；独立地图沿用其自己的波次与计数。
static func _battle(manager: ZombieManager) -> Dictionary:
	var waves := manager.zombie_wave_manager # 未启动的普通战场也可能登记外部实例。
	var adventure := AdventureSession.owns_battle(manager.game_para) # 只关联当前管理器真正拥有的冒险。
	return {
		"battle": str(manager.get_instance_id()), "stage": AdventureSession.active_stage_number if adventure else 0,
		"phase": StagePhaseDefinition.Kind.find_key(AdventureSession.active_phase_kind) if adventure else "classic",
		"wave": waves.curr_wave + 1 if is_instance_valid(waves) else 0,
		"waves": waves.max_wave if is_instance_valid(waves) else 0, "last_wave": manager.is_end_wave,
		"enemies": manager.curr_zombie_num, "spawn_instant_kill": manager.cheat_instant_kill_enabled,
	}
