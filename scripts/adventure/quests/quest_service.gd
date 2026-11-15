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

## 查询 [param state] 的任务入口是否已由首关进度或修改器开放。
static func quests_unlocked(state: AdventureState) -> bool:
	return state.facilities_unlocked_by_cheat or completed(state, "first_expedition") or AdventureStageCatalog.is_cleared(
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
	if task.has("required_normal_clear"):
		checks.append(AdventureStageCatalog.is_cleared(state, task.required_normal_clear, StagePhaseDefinition.Kind.NORMAL))
	for id: String in task.requires_completed: # 前置使用完成状态而非领取状态。
		checks.append(completed(state, id))
	for id: String in task.get("requires_claimed", []): # 领奖前置独立配置，保留原有完成与等级语义。
		checks.append(claimed(state, id))
	if checks.is_empty():
		return true
	return checks.has(true) if task.activation_mode == "any" else not checks.has(false)

## 在 [param day] 刷新周期并按前置依赖收敛生效状态；返回是否修改了存档数据。
## 收集任务分别记录已找到的物品；历史通关补记须显式启用 accept_history。
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
				state.quests.records[task.id] = {"period": state.quests.day if task.daily else "",
					"status": "active", "progress": 0}
				changed = true
			var record: Dictionary = state.quests.records.get(task.id, {}) # 在权威记录上补记已满足的目标。
			if record.get("status") != "active":
				continue
			if task.has("collect_items"):
				_update_collection(state, task.collect_items, record)
			if _objective_met(state, task, record):
				record.progress = task.count
				record.status = "complete"
				changed = true
		if not changed:
			break
	return before != state.quests.to_dict()

## 根据 [param state] 及 [param record] 中可直接核实的事实判定 [param task]。
static func _objective_met(state: AdventureState, task: Dictionary, record: Dictionary) -> bool:
	if task.has("collect_items"):
		return int(record.progress) >= int(task.count)
	if str(task.event).is_empty():
		return state.player_level >= int(task.get("completion_level", 0))
	if not task.accept_history:
		return false
	if task.has("history_claim"):
		return state.claimed_rewards.get(task.history_claim, false) == true
	return task.event == "stage_cleared" and _was_stage_cleared(state, task.target)

## 将 [param target_id] 中的关卡和阶段映射到 [param state] 的永久通关记录。
static func _was_stage_cleared(state: AdventureState, target_id: String) -> bool:
	var target: PackedStringArray = target_id.split("/") # 前段为关卡 ID，后段为阶段。
	if target.size() != 2:
		return false
	var stage_id := StringName(target[0]) # 使用与关卡目录一致的稳定身份。
	match target[1]:
		"normal":
			return AdventureStageCatalog.is_cleared(state, stage_id, StagePhaseDefinition.Kind.NORMAL)
		"nightmare":
			return AdventureStageCatalog.is_cleared(state, stage_id, StagePhaseDefinition.Kind.NIGHTMARE)
		"terminal":
			return AdventureStageCatalog.is_cleared(state, stage_id, StagePhaseDefinition.Kind.TERMINAL)
	return false

## 把 [param state] 的持有或使用证据记到 [param record]；[param goals] 映射物品 ID 到对应通关证据。
static func _update_collection(state: AdventureState, goals: Dictionary, record: Dictionary) -> void:
	var previous: Array = record.get("collected_items", []) # 每种物品独立记录，后续消费不会丢掉进度。
	var collected: Array[String] = [] # 只计入当前目标中的物品，每种只计一次。
	for id: String in goals: # 目标值可为空，表示仅以库存或已记录的收集为证。
		var evidence: String = goals[id] # 兼容已经使用钥匙并通关相应阶段的存档。
		if id in previous or int(state.items.get(id, 0)) > 0 \
				or (not evidence.is_empty() and _was_stage_cleared(state, evidence)):
			collected.append(id)
	if collected != previous:
		record["collected_items"] = collected
		record.progress = collected.size()

## 接收 [param event]、[param target]，按 [param day] 计入当时已生效的任务；自身不写磁盘。
## [param played_plants] 为本次获胜阶段中实际使用的植物卡物种；其他事件留空。
## 同一次事件完成前置后，后继任务从下一次事件开始计数，允许补记的历史目标仍可在同步时完成。
static func record_event(state: AdventureState, event: String, target: String, day: String,
		played_plants: PackedInt32Array = PackedInt32Array()) -> bool:
	var before: Dictionary = state.quests.to_dict() # 上报事实前的任务域。
	synchronize(state, day)
	for task: Dictionary in AdventureQuestCatalog.TASKS: # 此轮只处理已生效任务，后置刷新统一解锁后继。
		var record: Dictionary = state.quests.records.get(task.id, {}) # 未生效任务没有记录。
		if record.get("status", "") != "active" or task.event != event or (not str(task.target).is_empty() and task.target != target):
			continue
		if task.has("required_plant_type") and not played_plants.has(int(task.required_plant_type)):
			continue
		record.progress = mini(int(task.count), int(record.progress) + 1)
		if record.progress >= int(task.count):
			record.status = "complete"
	synchronize(state, day)
	return before != state.quests.to_dict()

## 返回 [param feature] 是否已由 [param state] 的任务、剧情或修改器开放。
static func feature_unlocked(state: AdventureState, feature: String) -> bool:
	if state == null:
		return false
	for task: Dictionary in AdventureQuestCatalog.TASKS: # 只识别任务目录中配置过的设施。
		if task.daily or feature not in task.unlocks:
			continue
		if state.facilities_unlocked_by_cheat:
			return true
		var required_step: String = task.get("unlock_after_step", "") # 有剧情前置时也必须完成指定节点。
		if not required_step.is_empty() and not state.tutorial_steps.get(required_step, false):
			continue
		if claimed(state, task.id) or (task.get("unlock_on_completion", false) and completed(state, task.id)):
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
		if task.has("completion_level"):
			var goal: int = task.completion_level # 已完成记录保持满进度，避免开发调级影响已达成的任务。
			row["progress"] = "%d / %d" % [mini(state.player_level, goal) if record.status == "active" else goal, goal]
		# 未领取展示当前可得经验；已领取展示当时实际奖励，旧档没有收据时保留基础数值。
		row["exp"] = int(record.get("awarded_experience", task.exp)) if record.status == "claimed" \
			else PlayerEffects.scale_amount(int(task.exp), effects.experience_multiplier)
		if record.status == "claimed":
			row.group = "已完成"
		result.append(row)
	return result

## 通过 [param persist] 保存 [param id] 在 [param period] 的奖励，成功返回空字符串。
## [param state]、[param inventory] 和 [param wallet] 必须属于同一档案。[param day] 为当前自然日。
## [param force] 仅供修改器使用，跳过前置和完成条件，仍按当前周期防止重复领取。
static func claim(state: AdventureState, inventory: AdventureInventoryService, wallet: GlobalGameState,
		persist: Callable, id: String, period: String, day: String, force: bool = false) -> String:
	if _claiming:
		return "正在领取奖励，请稍候。"
	_claiming = true
	var issue := _commit_claim(state, inventory, wallet, persist, id, period, day, force) # 同步事务无 await。
	_claiming = false
	return issue

## 在 [param state] 的 [param period] 内提交 [param id] 奖励，通过 [param persist] 保存。
## [param inventory] 和 [param wallet] 必须绑定同一档案，[param day] 用于重验周期。
## [param force] 允许直接创建当前周期的领取记录，保存失败同时恢复任务进度和资产。
static func _commit_claim(state: AdventureState, inventory: AdventureInventoryService, wallet: GlobalGameState,
		persist: Callable, id: String, period: String, day: String, force: bool) -> String:
	if state == null or wallet == null or inventory == null or wallet.adventure_state != state or not inventory.owns_state(state) or not persist.is_valid():
		return "玩家档案已变化，请重新打开任务。"
	if not force:
		synchronize(state, day)
	var task: Dictionary = AdventureQuestCatalog.definition(id) # 权威奖励定义。
	if task.is_empty():
		return "任务不存在。" if force else "任务尚未完成、已领取，或日常任务已经刷新。"
	var record: Dictionary = state.quests.records.get(id, {}) # 实时进度和周期。
	var claim_period: String = period # 普通领取复核窗口周期，强制领取使用当前档案周期。
	if force:
		var current_day: String = day if day > state.quests.day else state.quests.day # 回拨时钟时保留已见最大日期。
		claim_period = current_day if task.daily else ""
		if task.daily and record.get("period", "") != claim_period:
			record = {}
		if record.get("status", "") == "claimed":
			return "本期任务奖励已领取。"
	elif record.get("status", "") != "complete" or record.get("period", "") != claim_period:
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
	var before_equipment_id: int = state.equipment.next_id # 保存失败时复原尚未成功发放的装备序号。
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
	var equipment_id: String = task.get("equipment_reward", "") # 装备奖励入角色背包。
	var equipment_uid := "" # 只记录本次实际发放的实例，已有同款时直接保留。
	var equipment := PlayerEquipmentService.new(state.equipment) # 和任务记录共用这次存档事务。
	if not equipment_id.is_empty() and not state.equipment.owned.values().has(equipment_id):
		equipment_uid = equipment.grant(StringName(equipment_id))
		if equipment_uid.is_empty():
			state.items.assign(before_items)
			state.experience = before_exp
			state.player_level = before_level
			wallet.coin_value = before_coin
			return "装备发放失败，请重试。"
	if force:
		record["period"] = claim_period
		record["progress"] = task.count
		state.quests.records[id] = record
	record["status"] = "claimed"
	record["awarded_experience"] = experience
	synchronize(state, day)
	if persist.call() != true:
		if not equipment_uid.is_empty():
			equipment.remove(equipment_uid)
			state.equipment.next_id = before_equipment_id
		state.items.assign(before_items)
		state.quests = AdventureQuestState.from_dict(before_quests)
		state.experience = before_exp
		state.player_level = before_level
		wallet.coin_value = before_coin
		return "保存失败，奖励已回滚，请重试。"
	return ""
