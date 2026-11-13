## Cheat operations use existing inventory and save services; never fork game data.
extends RefCounted
const Stage = preload("res://addons/pvz_cheat/cheat_stages.gd")
const Backup = preload("res://addons/pvz_cheat/cheat_backup.gd")
## 战斗模块仅通过当前战场处理生成与结算。
const Battle = preload("res://addons/pvz_cheat/cheat_battle.gd")
var stage_service := Stage.new()
var backup_service := Backup.new()

static func available() -> bool:
	return Global.save_service != null and Global.save_service.is_current_profile_loaded() \
		and Global.adventure_inventory != null and Global.global_game_state.adventure_state != null

static func result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}

## 通过正式事务授予 [param id] 装备；不直接写角色库存，不绕过保存与战斗限制。
func grant_equipment(id: String) -> Dictionary:
	if not available():
		return result(false, "请先选择有效的玩家存档。")
	var issue: String = PlayerTransaction.commit(Global.global_game_state.adventure_state, PlayerTransaction.Action.GRANT, id) # 复用产品边界。
	return result(issue.is_empty(), "装备已进入角色背包。" if issue.is_empty() else issue)

## 设置 [param level] 及对应累计经验，通过现有门面同步任务条件。
func set_player_level(level: int) -> Dictionary:
	if not available() or AdventureSession.owns_battle(Global.game_para):
		return result(false, "请先返回地图并选择有效存档。")
	var success: bool = Global.set_player_level(level) # 成长曲线决定可表示等级，不复制公式。
	return result(success, "角色等级已更新。" if success else "等级无效或保存失败。")

func add_cards(plant_type: int, stars: int, amount: int) -> Dictionary:
	if not available():
		return result(false, "请先选择有效的玩家存档。")
	if not PlantCardInstance.is_plant_type(plant_type) or stars < 0 or stars > 10 or amount < 1 or amount > 32:
		return result(false, "植物、星级或数量无效（一次最多32张，星级0–10）。")
	var state: AdventureState = Global.global_game_state.adventure_state
	var previous_next: int = state.next_card_id
	var created: Array[String] = []
	for i in amount:
		var uid: String = Global.adventure_inventory.add_card(plant_type, stars)
		if uid.is_empty():
			break
		created.append(uid)
	if created.size() == amount and Global.save_service.save_now():
		return result(true, "已获得 %d 张独立卡牌，最后UID：%s" % [amount, created[-1]])
	for uid: String in created:
		Global.adventure_inventory.remove_card(uid)
	state.next_card_id = previous_next
	return result(false, "生成或保存失败，已回滚。")

func change_item(id: String, amount: int) -> Dictionary:
	if not available():
		return result(false, "请先选择有效的玩家存档。")
	if not ItemRegistry.has_item(id) or amount == 0 or absi(amount) > 1000000:
		return result(false, "物品或数量非法（单次最多100万）。")
	var inventory: AdventureInventoryService = Global.adventure_inventory
	var before: int = inventory.get_item_count(id)
	var ok: bool = inventory.add_item(id, amount) if amount > 0 else inventory.consume_item(id, -amount)
	if not ok:
		return result(false, "库存不足或数量溢出。")
	if Global.save_service.save_now():
		return result(true, "%s %+d，现有 %d" % [ItemRegistry.get_item_definition(id).get("name", id), amount, inventory.get_item_count(id)])
	var state: AdventureState = Global.global_game_state.adventure_state
	if before == 0:
		state.items.erase(id)
	else:
		state.items[id] = before
	return result(false, "保存失败，库存已回滚。")

## 给当前玩家发放 [param category] 下每种已注册物品各 [param amount] 件；发放或保存失败时恢复原库存。
func grant_category(category: String, amount: int) -> Dictionary:
	if not available() or category not in ["material", "recipe", "promotion_book", "key", "consumable"] or amount < 1 or amount > 100:
		return result(false, "类别或数量无效（每种最多100）。")
	var state: AdventureState = Global.global_game_state.adventure_state # 本次发放与回滚都作用于当前存档。
	var previous: Dictionary = state.items.duplicate(true) # 保留批量发放前的完整库存以便回滚。
	var total := 0 # 已成功添加的物品种类数。
	for id: String in ItemRegistry.ITEMS: # 直接遍历正式目录，自动覆盖后续登记的同类物品。
		if str(ItemRegistry.get_item_definition(id).get("category", "")) != category:
			continue
		if not Global.adventure_inventory.add_item(id, amount):
			_restore_items(state, previous)
			return result(false, "批量发放失败，已回滚。")
		total += 1
	if total > 0 and Global.save_service.save_now():
		return result(true, "已发放 %d 种资源，每种 ×%d。" % [total, amount])
	_restore_items(state, previous)
	return result(false, "批量保存失败，已回滚。")

func _restore_items(state: AdventureState, items: Dictionary) -> void:
	state.items.clear()
	for id: String in items:
		state.items[id] = int(items[id])

func change_coin(value: int, operation: String) -> Dictionary:
	if not available():
		return result(false, "请先选择有效的玩家存档。")
	var old: int = Global.global_game_state.coin_value
	var target: int = value if operation == "set" else old + value if operation == "add" else old - value
	if value < 0 or value > 1000000000 or target < 0 or target > PlantCardInstance.MAX_JSON_INTEGER:
		return result(false, "金币数值无效或越界。")
	Global.global_game_state.coin_value = target
	if Global.save_service.save_now():
		return result(true, "金币：%d → %d" % [old, target])
	Global.global_game_state.coin_value = old
	return result(false, "保存失败，金币已回滚。")

func unlock_stage(stage: int, nightmare: bool) -> Dictionary:
	return stage_service.unlock(stage, nightmare, false)

func clear_stage(stage: int, nightmare: bool) -> Dictionary:
	return stage_service.unlock(stage, nightmare, true)

func enter_stage(stage: int, nightmare: bool) -> Dictionary:
	return stage_service.enter(stage, nightmare)

func settle_current() -> Dictionary:
	return stage_service.settle_current()

## 强制领取当前档案中 [param id] 对应的任务奖励；复用正常领奖的入账、保存和回滚。
func force_claim_quest(id: String) -> Dictionary:
	if not available():
		return result(false, "请先选择有效的玩家存档。")
	var wallet: GlobalGameState = Global.global_game_state # 领奖服务复核钱包和库存的档案归属。
	var issue: String = AdventureQuestService.claim(wallet.adventure_state, Global.adventure_inventory,
		wallet, Global.save_service.save_now, id, "", AdventureQuestService.today(), true) # 强制领取使用当前周期。
	if not issue.is_empty():
		return result(false, issue)
	Global.player_changed.emit()
	Global.quests_changed.emit()
	var task: Dictionary = AdventureQuestCatalog.definition(id) # 用正式名称反馈刚刚提交的任务。
	return result(true, "已领取「%s」的奖励。" % task.title)

## 为当前档案永久开放设施，保存成功后刷新入口，失败时恢复解锁状态。
func unlock_all_facilities() -> Dictionary:
	if not available():
		return result(false, "请先选择有效的玩家存档。")
	var state: AdventureState = Global.global_game_state.adventure_state # 解锁只作用于当前档案。
	if state.facilities_unlocked_by_cheat:
		return result(true, "全部设施已解锁。")
	state.facilities_unlocked_by_cheat = true
	if not Global.save_service.save_now():
		state.facilities_unlocked_by_cheat = false
		return result(false, "保存失败，设施解锁已回滚。")
	Global.quests_changed.emit()
	return result(true, "已解锁全部设施。")

## 返回当前战斗可用的开关状态，供修改器同步显示。
func battle_toggle_states() -> Dictionary:
	return Battle.toggle_states()

## 按 [param enabled] 设置本局秒杀开关，返回战斗命令结果。
func set_battle_instant_kill(enabled: bool) -> Dictionary:
	return Battle.set_instant_kill(enabled)

## 按 [param enabled] 切换本局卡牌无冷却，返回战斗命令结果。
func set_battle_no_card_cooldown(enabled: bool) -> Dictionary:
	return Battle.set_no_card_cooldown(enabled)

## 按 [param enabled] 切换本局无限阳光，返回战斗命令结果。
func set_battle_infinite_sun(enabled: bool) -> Dictionary:
	return Battle.set_infinite_sun(enabled)

## 生成指定 [param zombie_type] 和 [param tier_id]；[param all_lanes] 为 true 时每行一只。
func spawn_battle_zombies(zombie_type: int, tier_id: StringName, all_lanes: bool) -> Dictionary:
	return Battle.spawn(zombie_type as CharacterRegistry.ZombieType, tier_id, all_lanes)

## 召唤 [param boss_type] 所对应的注册 Boss，返回本次战斗命令的执行结果。
func spawn_battle_boss(boss_type: int) -> Dictionary:
	return Battle.spawn_boss(boss_type as CharacterRegistry.ZombieBossType)

## 请求当前战斗的一键通关。
func clear_current_battle() -> Dictionary:
	return Battle.clear_current()

func snapshot() -> Dictionary:
	return backup_service.snapshot()

func restore() -> Dictionary:
	return backup_service.restore()
