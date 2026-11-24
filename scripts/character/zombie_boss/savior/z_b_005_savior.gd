## 教堂救主的入场、个体战斗状态和二阶段。本体和分身向同一行动树登记真实抬掌帧。
extends "res://scripts/character/zombie_boss/savior/savior_prayer_actor.gd"
class_name ZB005Savior

## 根据本局棋盘准备完整增援队形，再提交原体生命变化。
const SplitFormation = preload("res://scripts/character/zombie_boss/savior/savior_split_formation.gd")
## 仅在第三行登场，内部使用零起始行号。
const FIXED_LANE := 2
## 满血单体的遭遇总量；分裂时底部血条仍以此为分母。
const ENCOUNTER_HP := 120000
## 本体和两个分身在二阶段各自独立拥有的最大生命。
const MEMBER_HP := 20000

## 分身设为本体的 HUD 分组编号，其余救主各自建立分组。
var _joined_group := 0
## 是否已取得二阶段的独立战斗血池。
var _split_member := false
## 分身实际所在的零起始行，本体以第三路默认坐标定位。
var _reinforcement_lane := -1

## 正式登场后绑定所在战场的棋盘、共享行动树和角色状态。
func ready_norm() -> void:
	super.ready_norm()
	# 血量由底部合计显示，通用战斗血量开关也不应把分身变成额外的血条。
	hp_component.is_can_look_hp = false
	hp_component.hide()
	var ancestor: Node = get_parent() # Boss 根节点位于战场的僵王容器下。
	while ancestor != null and not ancestor is MainGameManager:
		ancestor = ancestor.get_parent()
	var game := ancestor as MainGameManager # 角色独立预览不会创建战斗逻辑。
	if game == null:
		set_physics_process(false)
		return
	var arena: SaviorBattle = SaviorBattle.for_battle(game) # 手动召唤与配置出场共用同一个战斗宿主。
	_bind_prayer(game, arena)
	arena.hold_plant_remains(self)
	# 大额攻击也在刚低于半血处接到剧情，不越过分裂直接击杀。
	if not _split_member:
		hp_component.combat_minimum_hp = ceili(hp_component.max_hp * phase_two_threshold_ratio) - 1
	begin_ritual()
	_visual.set_teleport_pose(0.0)
	$Body/ChurchLight.hide()
	if not _split_member:
		arena.savior_cinematic.queue_entrance(self)

## 底栏同一组始终共享血条，分身即使在本体死亡后仍保留这个编号。
func boss_encounter_group_id() -> int:
	return _joined_group if _joined_group != 0 else -get_instance_id()

## 返回本局从单体阶段开始计算的最大总血量。
func boss_encounter_maximum_hp() -> int:
	return ENCOUNTER_HP

## 半血分裂的生命锁尚在时保留两个分身的名额，成功登记或降级后归还普通出怪。
func reserved_enemy_spawn_slots() -> int:
	return SplitFormation.PREFERRED.size() if is_instance_valid(hp_component) and hp_component.combat_minimum_hp > 0 else 0

## 正式战斗让通用钻石在白光收尽后出现，避免盖住仍在传送的原画。
func drop_diamond_after_presentation() -> bool:
	return _combat != null

## 在本体半血仪式的落黑帧一次提交分裂。返回两名已登记的分身；不足以分裂时保留当前实血进入单体二阶段。
func split_in_battle() -> Array[ZB000Base]:
	if _combat == null or not _combat.active() or not _ritual_locked or _split_member or boss_phase != 2:
		return []
	var members: Array[ZB000Base] = SplitFormation.spawn(self, _combat.game, _prepare_split_clone, _commit_split_health)
	if members.is_empty():
		hp_component.combat_minimum_hp = 0
	elif not is_death:
		# 遭遇已一次收齐两名增援，再发布基于真实三人名册的合计生命比例。
		hp_component.signal_hp_loss.emit(hp_component.curr_hp, false)
	return members

## [param member] 是尚未入树的正式注册角色；[param assigned_lane] 来自本次选择的真实行。类型不符时放弃整组。
func _prepare_split_clone(member: ZB000Base, assigned_lane: int) -> bool:
	var clone := member as ZB005Savior # 实例来自原生的类型注册表。
	if clone == null:
		return false
	clone._configure_split_spawn(boss_encounter_group_id(), assigned_lane)
	return true

## 入树前把当前分身加入 [param group]，按 [param assigned_lane] 定位并独立初始化二阶段血量。
func _configure_split_spawn(group: int, assigned_lane: int) -> void:
	_joined_group = group
	_split_member = true
	_reinforcement_lane = assigned_lane
	boss_phase = 2
	var health := get_node(^"%HpComponent") as HpComponent # 子节点在正式 ready 前读取其初始上限。
	health.set_spawn_max_health(MEMBER_HP)

## 黑幕遮住分裂时切换本体的实际血池，并让原有观察者同步总血量。
func _commit_split_health() -> void:
	if is_death or is_queued_for_deletion():
		return # 增援登记的同步回调已移除本体，不能再次写入满血。
	_split_member = true
	hp_component.combat_minimum_hp = 0
	hp_component.set_spawn_max_health(MEMBER_HP)

## 由仪式的黑场关键帧触发一次战场级入场伤害与亡影复生。
func resolve_entrance_impact() -> void:
	_combat.resolve_entrance()

## [param manager] 提供第三行几何，[param _spawn_lane] 为公共工厂参数。
## 返回该行最右格外缘的待机位置，短射程植物仍可攻击本体。
func get_default_boss_spawn_position(manager: ZombieManager, _spawn_lane: int = -1) -> Vector2:
	if manager.all_zombie_rows.size() <= FIXED_LANE:
		return super.get_default_boss_spawn_position(manager)
	var foot: Vector2 = manager.all_zombie_rows[FIXED_LANE].zombie_create_position.global_position # 偏僻地形仍有默认出怪脚点。
	var cells: Array[PlantCell] = manager.main_game.board.row_cells(FIXED_LANE) # 使用当前实际列宽和右缘。
	if not cells.is_empty():
		foot.x = BoardQueries.bounds(cells).end.x
	return manager.zombie_boss_root.to_local(foot)

## 将 [param spawn_position] 和 [param home_local_x] 交给 [param manager] 的真实行坐标，本体初次登场固定第三路。
func place_boss_at_spawn(manager: ZombieManager, spawn_position: Vector2, home_local_x: float = INF) -> void:
	if not _split_member:
		spawn_position.y = get_default_boss_spawn_position(manager).y
	super.place_boss_at_spawn(manager, spawn_position, home_local_x)
	if _reinforcement_lane >= 0:
		lane = _reinforcement_lane
		set_boss_depth(lane)
	elif manager.all_zombie_rows.size() > FIXED_LANE:
		lane = FIXED_LANE
		set_boss_depth(lane)

## 拒绝换行；[param _manager] 和 [param _distance] 仅用于兼容共用换行入口。
func advance_boss_lane_change(_manager: ZombieManager, _distance: float) -> bool:
	boss_target_lane = -1
	return true

## [param phase] 为新的阶段；[param animated] 只在正常战斗跨过阈值时发起分裂仪式。
func _apply_boss_visual_phase(phase: int, animated: bool) -> void:
	body.set_boss_phase_pulse(false)
	if phase < 2 or _combat == null:
		return
	TreePauseManager.block_menu_pause(_combat.game)
	if animated:
		begin_ritual()
		_combat.arena.savior_cinematic.queue_split(self, split_in_battle)

## 按原死亡流程关闭受击，撤除未完成的技能并完成遭遇退场。
func character_death() -> void:
	if is_death:
		return
	super.character_death()
	set_physics_process(false)
	_end_prayer_on_death()
	if _combat != null:
		var arena: SaviorBattle = _combat.arena # 实战由白光的完成帧交接奖励。
		if is_instance_valid(arena):
			arena.savior_actions.unregister(self)
		_combat.clear()
		if is_instance_valid(arena) and is_instance_valid(arena.savior_teleport):
			arena.savior_teleport.depart(self, _finish_death)
			return
	var out: Tween = create_tween().bind_node(self) # 独立角色预览使用简短的退场淡出。
	out.tween_property(body, ^"modulate:a", 0.0, 0.72)
	out.tween_callback(_finish_death)

## 当最后一道白光收拢后，按原基础 Boss 生命周期申请奖励并移除本体。
func _finish_death() -> void:
	request_trophy()
	queue_free()

## 场景移除或脚本撤退时回收在途技能，正常死亡保留自己的退场余波。
func _exit_tree() -> void:
	if _combat != null:
		if is_instance_valid(_combat.arena):
			_combat.arena.savior_actions.unregister(self)
		if not is_death:
			_combat.clear()
		_combat.release_tracks()
