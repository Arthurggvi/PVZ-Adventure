## 安息平原战场入口：正式战斗读取 AdventureSession，编辑器直开才创建隔离预览。
extends MainGameManager

## 只在没有正式游戏参数时启用本场编辑器预览，不改玩家进度与关卡存档。
func set_game_para() -> void:
	if Global.game_para == null and game_para == null:
		var stage: StageDefinition = AdventureStageRegistry.resolve(AdventureStageRegistry.RESTING_PLAIN) # 本关私有模板。
		var phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(
			stage, StagePhaseDefinition.Kind.NORMAL) # 预览固定从普通阶段进入。
		if stage != null and phase != null:
			game_para = AdventureBattleEnvironmentAdapter.build(stage, phase)
			if game_para != null:
				game_para.look_show_zombie = false # 编辑器直开直接展示真实作战画面，正式进入仍保留选卡。
			preview_stage = stage
			preview_return_scene = "res://scenes/adventure/wonderland_map.tscn"
	super()
