## 修改器的战斗命令；借用当前战场的生成、等阶与胜利入口。
extends RefCounted

## 返回当前正在进行的战斗；地图、选卡和切场期间没有可操作战斗。
static func _active_battle() -> MainGameManager:
	var game: MainGameManager = Global.main_game # 全局引用须同时匹配当前场景。
	if not is_instance_valid(game) or not game.is_inside_tree() or game.is_queued_for_deletion():
		return null
	if game.get_tree().current_scene != game or not is_instance_valid(game.zombie_manager) \
			or not game.zombie_manager.is_game_running():
		return null
	return game

## 返回当前战斗可用的开关状态，缺少的键表示该开关不可用。
static func toggle_states() -> Dictionary:
	var game: MainGameManager = _active_battle() # 从当前场景读取状态，避免沿用上一局的显示。
	if game == null:
		return {}
	var states: Dictionary = {&"instant_kill": game.zombie_manager.cheat_instant_kill_enabled} # 秒杀独立于卡槽模式。
	var mowers: GIM_LawnMover = game.game_item_manager.gim_lawn_mover # 小推车开关由本局管理器维护。
	if is_instance_valid(mowers):
		states[&"fixed_mowers"] = mowers.cheat_fixed_enabled
	var slot: CardSlotBattle = game.card_manager.card_slot_battle # 阳光和冷却开关由普通卡槽维护。
	if is_instance_valid(slot):
		states[&"no_card_cooldown"] = slot.cheat_no_cooldown_enabled
		states[&"infinite_sun"] = slot.cheat_infinite_sun_enabled
	return states

## 在当前战斗中按 [param enabled] 开关新出场敌人的秒杀，返回操作结果。
static func set_instant_kill(enabled: bool) -> Dictionary:
	var game: MainGameManager = _active_battle() # 秒杀开关只修改正在进行的战斗。
	if game == null:
		return {"ok": false, "message": "请在正式战斗中切换秒杀。"}
	game.zombie_manager.cheat_instant_kill_enabled = enabled
	return {"ok": true, "message": "已开启秒杀。" if enabled else "已关闭秒杀。"}

## 按 [param enabled] 切换本局普通出战卡槽的无冷却状态，返回操作结果。
static func set_no_card_cooldown(enabled: bool) -> Dictionary:
	var game: MainGameManager = _active_battle() # 只操作当前正在进行的战斗。
	if game == null:
		return {"ok": false, "message": "请在正式战斗中切换卡牌无冷却。"}
	var slot: CardSlotBattle = game.card_manager.card_slot_battle # 普通出战卡槽负责用卡后的冷却。
	if not is_instance_valid(slot):
		return {"ok": false, "message": "当前战斗没有使用普通出战卡槽。"}
	slot.set_cheat_no_cooldown(enabled)
	return {"ok": true, "message": "已开启卡牌无冷却。" if enabled else "已关闭卡牌无冷却。"}

## 按 [param enabled] 切换本局普通出战卡槽的无限阳光，返回操作结果。
static func set_infinite_sun(enabled: bool) -> Dictionary:
	var game: MainGameManager = _active_battle() # 只操作当前正在进行的战斗。
	if game == null:
		return {"ok": false, "message": "请在正式战斗中切换无限阳光。"}
	var slot: CardSlotBattle = game.card_manager.card_slot_battle # 只有普通出战卡槽使用阳光费用。
	if not is_instance_valid(slot):
		return {"ok": false, "message": "当前战斗没有使用普通出战卡槽。"}
	slot.set_cheat_infinite_sun(enabled)
	return {"ok": true, "message": "已开启无限阳光。" if enabled else "已关闭无限阳光。"}

## 按 [param enabled] 固定本局现有及后续补充的小推车，保留碰撞击杀并返回操作结果。
static func set_fixed_mowers(enabled: bool) -> Dictionary:
	var game: MainGameManager = _active_battle() # 切场、选卡和结算期间不操作旧战场。
	if game == null:
		return {"ok": false, "message": "请在正式战斗中切换固定小推车。"}
	var mowers: GIM_LawnMover = game.game_item_manager.gim_lawn_mover # 不复活已消耗的小推车。
	if not is_instance_valid(mowers):
		return {"ok": false, "message": "当前战斗没有小推车管理器。"}
	mowers.set_cheat_fixed(enabled)
	return {"ok": true, "message": "已开启固定小推车。" if enabled else "已关闭固定小推车。"}

## 在兼容的行生成 [param zombie_type]，并应用 [param tier_id]。
## [param all_lanes] 为 true 时预检整张战场，每条实际存在的行各生成一个实例。
static func spawn(zombie_type: CharacterRegistry.ZombieType, tier_id: StringName, all_lanes: bool) -> Dictionary:
	var game: MainGameManager = _active_battle() # 操作时重新获取战斗，不持有旧场景引用。
	if game == null:
		return {"ok": false, "message": "请在正式战斗中生成僵尸。"}
	if not CharacterRegistry.ZombieInfo.has(zombie_type) or AdventureZombieTierCatalog.get_tier(tier_id).is_empty():
		return {"ok": false, "message": "僵尸类型或等阶无效。"}
	var manager: ZombieManager = game.zombie_manager # 复用管理器的水陆预检和僵尸登记。
	var lanes: Array[int] = [] # 当前类型能够生成的行。
	var bungi_targets: Dictionary[int, PlantCell] = {} # 蹦极须在入树前绑定对应格子。
	for lane: int in range(manager.all_zombie_rows.size()): # 使用战场实际行数。
		if not manager.can_spawn_zombie_in_lane(zombie_type, lane):
			continue
		if zombie_type == CharacterRegistry.ZombieType.Z021Bungi:
			var target: PlantCell = _bungi_target(game, lane) # 有植物优先，否则仍可在有效空格下降。
			if target == null:
				continue
			bungi_targets[lane] = target
		lanes.append(lane)
	if lanes.is_empty():
		return {"ok": false, "message": "当前战场没有适合该僵尸的行。"}
	if all_lanes and lanes.size() != manager.all_zombie_rows.size():
		return {"ok": false, "message": "部分行与该僵尸的地形要求不兼容，无法各路生成。"}
	if not all_lanes:
		var lane: int = lanes.pick_random() # 随机挑选一条合法行，不更新自然选行权重。
		lanes.clear()
		lanes.append(lane)
	var spawned := 0 # 报告管理器实际创建成功的实例数。
	for lane: int in lanes: # 每行只请求一个主要实例。
		if _spawn_one(manager, zombie_type, tier_id, lane, bungi_targets.get(lane)):
			spawned += 1
	if spawned != lanes.size():
		return {"ok": false, "message": "已生成 %d / %d 只僵尸，其余生成失败。" % [spawned, lanes.size()]}
	return {"ok": true, "message": "已生成 %d 只僵尸。" % spawned}

## 在当前战场的 Boss 出生点召唤 [param boss_type]，走正常出战登记并返回操作结果。
static func spawn_boss(boss_type: CharacterRegistry.ZombieBossType) -> Dictionary:
	var game: MainGameManager = _active_battle() # 点击时重新确认战斗仍在进行。
	if game == null:
		return {"ok": false, "message": "请在正式战斗中召唤 Boss。"}
	if not CharacterRegistry.ZombieBossInfo.has(boss_type):
		return {"ok": false, "message": "Boss 类型无效。"}
	# 复用 Boss 卡牌与关卡遭遇共用的生成入口，完整接入血条、音乐与击杀统计。
	if game.zombie_manager.try_create_boss_from_card(boss_type) == null:
		return {"ok": false, "message": "无法在当前战场召唤该 Boss。"}
	return {"ok": true, "message": "已召唤 Boss。"}

## 在 [param game] 的 [param lane] 中选取蹦极格子；无植物时使用本行的一个空格。
static func _bungi_target(game: MainGameManager, lane: int) -> PlantCell:
	var cells: Array = game.plant_cell_manager.all_plant_cells # 每个子数组对应一条实际战斗行。
	if lane >= cells.size():
		return null
	var fallback: PlantCell # 行内没有植物时使用最右侧有效格。
	for cell: PlantCell in cells[lane]: # 优先找有可抓取植物的格。
		if not is_instance_valid(cell) or not cell.is_inside_tree() or cell.is_queued_for_deletion():
			continue
		if cell.get_bungi_target() != null:
			return cell
		fallback = cell
	return fallback

## 在 [param manager] 的 [param lane] 创建 [param zombie_type]，应用 [param tier_id]。
## [param target] 仅蹦极使用，所有手动生成仍计入场上敌人，不参与自然波次提前刷新。
static func _spawn_one(manager: ZombieManager, zombie_type: CharacterRegistry.ZombieType,
		tier_id: StringName, lane: int, target: PlantCell) -> bool:
	var row: ZombieRow = manager.all_zombie_rows[lane] # 生成到实际僵尸行，保留层级与换行登记。
	var position: Vector2 = row.zombie_create_position.global_position # 默认从右侧出怪点进入。
	var initialize := Callable() # 蹦极在目标格上空生成并复用常规入场初始化。
	if target != null:
		position.x = target.global_position.x + target.size.x * 0.5
		initialize = GlobalUtils.get_special_zombie_callable(zombie_type, target)
	if not position.is_finite():
		return false
	var parameters := {
		Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
		Zombie000Base.E_ZInitAttr.Lane: lane,
		Zombie000Base.E_ZInitAttr.CurrWave: -1,
		Zombie000Base.E_ZInitAttr.ParticipatesNaturalRefresh: false,
	} # 不给测试出怪伪造自然波次编号。
	return manager.create_norm_zombie(zombie_type, row, parameters, position, initialize,
		AdventureZombieTierBinding.new(tier_id)) != null

## 结束当前战斗并进入原有胜利结算流程。
static func clear_current() -> Dictionary:
	var game: MainGameManager = _active_battle() # 选卡或已在结算时拒绝再次通关。
	if game == null:
		return {"ok": false, "message": "请在正式战斗中使用一键通关。"}
	if Global.save_service == null or not Global.save_service.is_current_profile_loaded():
		return {"ok": false, "message": "请先加载有效的玩家存档。"}
	if not game.request_cheat_victory():
		return {"ok": false, "message": "战斗已结束或正在结算。"}
	return {"ok": true, "navigate": true, "message": "已进入当前战斗的胜利结算。"}
