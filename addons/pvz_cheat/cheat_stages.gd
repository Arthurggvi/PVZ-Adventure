## Stage cheat commands preserve authoritative stage IDs and normal save semantics.
extends RefCounted
const Progress = preload("res://scripts/adventure/island_progress.gd")

static func _response(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}

func unlock(stage: int, nightmare: bool, mark_target: bool) -> Dictionary:
	if not Global.save_service.is_current_profile_loaded():
		return _response(false, "玩家存档尚未加载。")
	if AdventureStageRegistry.stage_id(stage) == &"":
		return _response(false, "关卡编号无效。")
	var definition: StageDefinition = AdventureStageCatalog.load_stage(stage)
	var kind: int = StagePhaseDefinition.Kind.NIGHTMARE if nightmare else StagePhaseDefinition.Kind.NORMAL
	if definition == null or AdventureStageCatalog.find_phase(definition, kind) == null:
		return _response(false, "目标阶段配置不存在。")
	var state: AdventureState = Global.global_game_state.adventure_state
	var old_regions: Dictionary = state.regions.duplicate(true)
	var old_items: Dictionary = state.items.duplicate(true)
	var region: Dictionary = state.regions.get(AdventureStageCatalog.REGION_ID, {}).duplicate(true)
	region["started"] = true
	region["intro_completed"] = true
	state.regions[AdventureStageCatalog.REGION_ID] = region
	# Normal earlier stages are the real progression prerequisites.
	for index in range(1, stage):
		AdventureStageCatalog.mark_cleared(state, AdventureStageRegistry.stage_id(index), StagePhaseDefinition.Kind.NORMAL)
	if nightmare:
		AdventureStageCatalog.mark_cleared(state, AdventureStageRegistry.stage_id(stage), StagePhaseDefinition.Kind.NORMAL)
		var key: String = str(AdventureStageRegistry.key_id(stage))
		if Global.adventure_inventory.get_item_count(key) < 1 and not Global.adventure_inventory.add_item(key, 1):
			_restore(state, old_regions, old_items)
			return _response(false, "无法生成噩梦关卡钥匙。")
	if mark_target:
		AdventureStageCatalog.mark_cleared(state, AdventureStageRegistry.stage_id(stage), kind)
	if not Global.save_service.save_now():
		_restore(state, old_regions, old_items)
		return _response(false, "关卡进度保存失败，已回滚。")
	# This view is required by the game's existing stage-entry code.
	AdventureSession.progress = Progress.new(state)
	var desc: String = AdventureStageRegistry.display_name(stage)
	return _response(true, "%s%s%s；未发放通关奖励。" % [
		desc, "噩梦" if nightmare else "普通", "已标记通关" if mark_target else "已解锁"])

func _restore(state: AdventureState, regions: Dictionary, items: Dictionary) -> void:
	state.regions = regions
	state.items.clear()
	for key: String in items:
		state.items[key] = int(items[key])

func enter(stage: int, nightmare: bool) -> Dictionary:
	if Global.adventure_inventory == null or Global.adventure_inventory.list_cards().is_empty():
		return _response(false, "请先获取至少一张植物卡牌。")
	if AdventureSession.active_level != null:
		return _response(false, "当前正在战斗，请先退出这一局。")
	var prepared: Dictionary = unlock(stage, nightmare, false)
	if not prepared.ok:
		return prepared
	var kind: int = StagePhaseDefinition.Kind.NIGHTMARE if nightmare else StagePhaseDefinition.Kind.NORMAL
	if not AdventureSession.enter_stage(stage, kind):
		return _response(false, "关卡入口拒绝进入：" + AdventureSession.error_message)
	return {"ok": true, "navigate": true, "message": "进入 %s · %s（已写入所需解锁进度）。" % [
		AdventureStageRegistry.display_name(stage), "噩梦" if nightmare else "普通"]}

func settle_current() -> Dictionary:
	if AdventureSession.active_level == null:
		return _response(false, "当前不是冒险战斗。")
	if not AdventureSession.can_accept_victory():
		return _response(false, "Boss 或战斗事件尚未满足结算条件；可用“标记通关（无奖励）”。")
	if not AdventureSession.settle_victory():
		return _response(false, AdventureSession.error_message)
	AdventureSession.finish_victory()
	return {"ok": true, "navigate": true, "message": "已通过真实胜利奖励与进度结算。"}
