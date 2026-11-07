## 任务规则和领奖事务。玩法仅上报事实；UI 读取投影，所有写入由调用方统一保存。
extends RefCounted
class_name AdventureQuestService

## 同步领奖期间阻止资产变化信号引起重入；调用结束即释放，不写入存档。
static var _claiming := false

## 本机自然日作为日常周期；返回 YYYY-MM-DD。
static func today() -> String:
	return Time.get_date_string_from_system(false)

## 查询 [param id] 是否已完成；领奖后的任务仍满足前置条件。
static func completed(state: AdventureState, id: String) -> bool:
	return state.quests.records.get(id, {}).get("status", "") in ["complete", "claimed"]

## 查询 [param state] 中 [param id] 的奖励是否已成功提交；完成不等同领奖。
static func claimed(state: AdventureState, id: String) -> bool:
	return state.quests.records.get(id, {}).get("status", "") == "claimed"

## 任务入口在首关普通阶段通关后开放；历史档案也可从永久通关记录恢复。
static func quests_unlocked(state: AdventureState) -> bool:
	return completed(state, "first_expedition") or AdventureStageCatalog.is_cleared(
		state, &"zombie_island.lawn", StagePhaseDefinition.Kind.NORMAL)

## 查询 [param state] 是否存在当前周期可领取奖励；调用方先同步日常周期。
static func has_claimable(state: AdventureState) -> bool:
	for task: Dictionary in AdventureQuestCatalog.TASKS: # 不把已经移除的任务当作提示来源。
		if state.quests.records.get(task.id, {}).get("status", "") == "complete":
			return true
	return false

## 判断 [param task] 的生效条件；默认全部满足，any 为至少一个真实配置条件满足。
static func eligible(state: AdventureState, task: Dictionary) -> bool:
	var checks: Array[bool] = [] # 未配置等级门槛时不加入恒真项，避免破坏 any 语义。
	if int(task.min_level) > 0:
		checks.append(state.player_level >= int(task.min_level))
	for id: String in task.requires_completed: # 前置使用完成状态而非领取状态。
		checks.append(completed(state, id))
	for id: String in task.get("requires_claimed", []): # 领奖前置独立配置，保留原有完成与等级语义。
		checks.append(claimed(state, id))
	if checks.is_empty():
		return true
	return checks.has(true) if task.activation_mode == "any" else not checks.has(false)

## 在 [param day] 刷新周期并按前置依赖收敛生效状态；返回是否修改了存档数据。
## 生效是单向状态；事件目标仅在生效之后计数。历史通关补记必须显式启用 accept_history。
static func synchronize(state: AdventureState, day: String) -> bool:
	var before: Dictionary = state.quests.to_dict() # 比较完整任务域以通知调用方保存。
	state.quests.day = day if day > state.quests.day else state.quests.day
	for task: Dictionary in AdventureQuestCatalog.TASKS: # 跨日清除昨天的日常，包括未领取奖励。
		if task.daily and state.quests.records.get(task.id, {}).get("period", "") != state.quests.day:
			state.quests.records.erase(task.id)
	for iteration: int in AdventureQuestCatalog.TASKS.size(): # 有限次数处理目录中任意顺序的前置链。
		var changed := false # 无新生效或完成时立即停止。
		for task: Dictionary in AdventureQuestCatalog.TASKS: # 每个任务最多从缺失进入生效再完成。
			if not state.quests.records.has(task.id) and eligible(state, task):
				state.quests.records[task.id] = {"period": state.quests.day if task.daily else "", "status": "active", "progress": 0}
				changed = true
			if state.quests.records.has(task.id) and task.accept_history and task.event == "stage_cleared":
				var target: PackedStringArray = str(task.target).split("/") # 稳定关卡 ID 与阶段类型。
				var record: Dictionary = state.quests.records[task.id] # 在权威记录上完成历史事实补记。
				if record.status == "active" and target.size() == 2 and AdventureStageCatalog.is_cleared(state, StringName(target[0]), StagePhaseDefinition.Kind.NORMAL if target[1] == "normal" else StagePhaseDefinition.Kind.NIGHTMARE):
					record.progress = task.count
					record.status = "complete"
					changed = true
		if not changed:
			break
	return before != state.quests.to_dict()

## 接收 [param event]、[param target]，按 [param day] 计入当时已生效的任务；自身不写磁盘。
## 同一次事件完成前置后，后继任务从下一次事件开始计数。
static func record_event(state: AdventureState, event: String, target: String, day: String) -> bool:
	var before: Dictionary = state.quests.to_dict() # 上报事实前的任务域。
	synchronize(state, day)
	for task: Dictionary in AdventureQuestCatalog.TASKS: # 此轮只处理已生效任务，后置刷新统一解锁后继。
		var record: Dictionary = state.quests.records.get(task.id, {}) # 未生效任务没有记录。
		if record.get("status", "") != "active" or task.event != event or (not str(task.target).is_empty() and task.target != target):
			continue
		record.progress = mini(int(task.count), int(record.progress) + 1)
		if record.progress >= int(task.count):
			record.status = "complete"
	synchronize(state, day)
	return before != state.quests.to_dict()

## 返回 [param feature] 是否被已领奖的永久任务解锁，保存失败时随领取状态回滚。
static func feature_unlocked(state: AdventureState, feature: String) -> bool:
	for task: Dictionary in AdventureQuestCatalog.TASKS: # 不保存平行解锁开关。
		if not task.daily and feature in task.unlocks and claimed(state, task.id):
			return true
	return false

## 生成窗口显示数据；[param state] 已由外部同步周期，查询不会修改状态。
static func rows(state: AdventureState) -> Array[Dictionary]:
	var result: Array[Dictionary] = [] # 每条返回深拷贝，界面不能修改任务配置。
	var effects: PlayerEffects = PlayerEffects.resolve(state.equipment) # 整次查询共用一次装备解析。
	for task: Dictionary in AdventureQuestCatalog.TASKS: # 尚未生效的任务隐藏，达标后自动进入目录。
		var record: Dictionary = state.quests.records.get(task.id, {}) # 任务当前周期。
		if record.is_empty():
			continue
		var row: Dictionary = task.duplicate(true) # 展示层需要的进度和领奖状态。
		row["status"] = record.status
		row["period"] = record.period
		row["progress"] = "%d / %d" % [int(record.progress), int(task.count)]
		# 未领取展示当前可得经验；已领取展示当时实际奖励，旧档没有收据时保留基础数值。
		row["exp"] = int(record.get("awarded_experience", task.exp)) if record.status == "claimed" \
			else PlayerEffects.scale_amount(int(task.exp), effects.experience_multiplier)
		if record.status == "claimed":
			row.group = "已完成"
		result.append(row)
	return result

## 领取 [param id] 在 [param period] 的奖励；即时复核档案及周期，保存失败完整回滚。
static func claim(state: AdventureState, inventory: AdventureInventoryService, wallet: GlobalGameState,
		persist: Callable, id: String, period: String, day: String) -> String:
	if _claiming:
		return "正在领取奖励，请稍候。"
	_claiming = true
	var issue := _commit_claim(state, inventory, wallet, persist, id, period, day) # 同步事务无 await。
	_claiming = false
	return issue

## 在 [param state] 的 [param period] 内提交 [param id] 奖励，通过 [param persist] 保存。
## [param inventory] 和 [param wallet] 必须绑定同一档案，[param day] 用于重验周期。
static func _commit_claim(state: AdventureState, inventory: AdventureInventoryService, wallet: GlobalGameState,
		persist: Callable, id: String, period: String, day: String) -> String:
	if state == null or wallet == null or inventory == null or wallet.adventure_state != state or not inventory.owns_state(state) or not persist.is_valid():
		return "玩家档案已变化，请重新打开任务。"
	synchronize(state, day)
	var task: Dictionary = AdventureQuestCatalog.definition(id) # 权威奖励定义。
	var record: Dictionary = state.quests.records.get(id, {}) # 实时进度和周期。
	if task.is_empty() or record.get("status", "") != "complete" or record.get("period", "") != period:
		return "任务尚未完成、已领取，或日常任务已经刷新。"
	var effects: PlayerEffects = PlayerEffects.resolve(state.equipment) # 任务经验读取领取时装备，物品与金币不享受战场加成。
	var experience: int = PlayerEffects.scale_amount(int(task.exp), effects.experience_multiplier) # 单次确定本次奖励经验。
	if experience < 0 or state.experience > PlantCardInstance.MAX_JSON_INTEGER - experience:
		return "经验已达到存储上限。"
	var before_items: Dictionary = state.items.duplicate(true) # 资产回滚快照。
	var before_quests: Dictionary = state.quests.to_dict() # 领取标记回滚快照。
	var before_exp: int = state.experience # 玩家经验与任务奖励同步提交。
	var before_level: int = state.player_level # 升级和新任务解锁必须随领奖一同回滚。
	var before_coin: int = wallet.coin_value # 金币回滚值。
	var rewards: Dictionary = {} # 将配置奖励转换为库存服务接受的数量映射。
	for item: Dictionary in task.items: # 同种道具合并数量。
		rewards[item.id] = int(rewards.get(item.id, 0)) + int(item.count)
	if not AdventureRewardService.apply(rewards, task.coins, state, inventory, wallet):
		state.items.assign(before_items)
		wallet.coin_value = before_coin
		return "奖励入账失败，请检查库存容量。"
	if not PlayerProgression.grant(state, experience):
		state.items.assign(before_items)
		wallet.coin_value = before_coin
		return "经验入账失败，奖励已撤销。"
	record.status = "claimed"
	record["awarded_experience"] = experience
	synchronize(state, day)
	if persist.call() != true:
		state.items.assign(before_items)
		state.quests = AdventureQuestState.from_dict(before_quests)
		state.experience = before_exp
		state.player_level = before_level
		wallet.coin_value = before_coin
		return "保存失败，奖励已回滚，请重试。"
	return ""
