## 花园飞艇正式战斗入口；独立编辑器预览不改变安息平原或现有玩家存档。
extends MainGameManager

## 仅无正式游戏参数时构建隔离的普通关预览，地图进入继续使用 AdventureSession。
func set_game_para() -> void:
	if Global.game_para == null and game_para == null:
		var stage: StageDefinition = AdventureStageRegistry.resolve(AdventureStageRegistry.GARDEN_AIRSHIP) # 本关独立配置。
		var phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(
			stage, StagePhaseDefinition.Kind.NORMAL) # 编辑器预览不消耗钥匙。
		if stage != null and phase != null:
			game_para = AdventureBattleEnvironmentAdapter.build(stage, phase)
			if game_para != null:
				game_para.look_show_zombie = false # 直开显示正式棋盘，不播放预览选卡。
				preview_stage = stage
				preview_return_scene = "res://scenes/adventure/wonderland_map.tscn"
	super()
