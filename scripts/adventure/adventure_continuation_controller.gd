## 同一战斗场景内普通清场与噩梦续战的唯一调度器。
## 负责结算检查点、暂停期间的玩家选择、运行时交接；原版多轮流程完全隔离。
extends Node
class_name AdventureContinuationController

## 续战复用背包的素材确认框，战场暂停时仍接收输入。
const InventoryDialog = preload("res://scripts/adventure/ui/inventory_dialog.gd")
## 所属战斗场景，负责实际结算与阶段交接。
var game: MainGameManager
## 当前唯一的续战提示，退出战斗时一并释放。
var dialog: InventoryDialog

func setup(owner: MainGameManager) -> void:
	game = owner
	process_mode = Node.PROCESS_MODE_ALWAYS

## 主战斗的清场请求已通过统一胜利判定后，普通阶段从这里完成独立结算。
func complete_normal(glo_pos: Vector2) -> void:
	game.zombie_manager.zombie_wave_manager.stop_wave_refresh()
	if not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false):
		TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.AdventureContinue)
	if not AdventureSession.settle_victory():
		AdventureSession.prompt_victory_retry(complete_normal.bind(glo_pos))
		return
	if AdventureSession.can_offer_nightmare():
		_show_offer(glo_pos)
	else:
		_finish_normal(glo_pos)

## 显示当前钥匙规则和最近一次失败原因；[param glo_pos] 用于结束挑战时生成奖杯。
func _show_offer(glo_pos: Vector2) -> void:
	_dispose_dialog()
	var prompt: String = "消耗钥匙来继续挑战吗？" # 与现有关卡确认时的扣除行为一致。
	if AdventureSession.active_stage.nightmare_key_use == StageDefinition.KeyUse.KEEP:
		prompt = "使用钥匙来继续挑战吗？"
	if not AdventureSession.error_message.is_empty():
		prompt += "\n" + AdventureSession.error_message
	dialog = InventoryDialog.new()
	dialog.setup_confirmation("", prompt, "继续挑战", "结束挑战")
	dialog.animated_feedback = true
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.confirmed.connect(_continue.bind(glo_pos))
	dialog.canceled.connect(_finish_normal.bind(glo_pos))
	game.canvas_layer_ui.add_child(dialog)

func _finish_normal(glo_pos: Vector2) -> void:
	_dispose_dialog()
	if not AdventureSession.complete_normal_challenge():
		return
	TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.AdventureContinue)
	game._finish_round_victory(glo_pos)

## [param _quantity] 是共用弹窗的固定确认值；实际钥匙数量来自关卡配置。
## [param glo_pos] 用于续战资格失效时完成普通关卡结算。
func _continue(_quantity: int, glo_pos: Vector2) -> void:
	_dispose_dialog()
	# 这两个条件来自本阶段自然清场边界，钥匙再次查询当前库存。
	if not AdventureSession.can_offer_nightmare():
		_finish_normal(glo_pos)
		return
	if game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or not game.zombie_manager.is_end_wave or game.zombie_manager.curr_zombie_num != 0:
		push_error("冒险连续阶段的战场清空前置条件失效。")
		_finish_normal(glo_pos)
		return
	var nightmare: StagePhaseDefinition = AdventureStageCatalog.find_phase(
		AdventureSession.active_stage, StagePhaseDefinition.Kind.NIGHTMARE)
	# 先完成不会改变资产的战场预检；成功后本次同步交接不再包含可失败步骤。
	if nightmare == null or not game.zombie_manager.can_begin_adventure_phase(nightmare.wave_profile):
		push_error("噩梦阶段的战场前置条件无效。")
		_finish_normal(glo_pos)
		return
	if not AdventureSession.begin_nightmare():
		_show_offer(glo_pos)
		return
	# 先卸载旧阶段全部事件监听，再配置下一阶段；植物与卡牌维持原状。
	if is_instance_valid(game.adventure_runtime):
		# 同步释放旧阶段监听器；下一阶段首波不能被尚未 queue_free 的旧节点收到。
		game.remove_child(game.adventure_runtime)
		game.adventure_runtime.free()
		game.adventure_runtime = null
	game.zombie_manager.begin_adventure_phase(AdventureSession.active_wave_profile)
	# 旧 ResourceLevelData 是投影，所有阶段动态读取应以 Session.active_phase 为准。
	AdventureBattleEnvironmentAdapter.project_phase(game.game_para, AdventureSession.active_phase)
	game.zombie_manager.zombie_refresh_types = game.game_para.zombie_refresh_types
	game.adventure_runtime = AdventureBattleRuntime.new()
	game.adventure_runtime.setup(game.zombie_manager.zombie_wave_manager,
		game.zombie_manager, AdventureSession.active_phase)
	game.add_child(game.adventure_runtime)
	game._round_end_claimed = false
	game._round_end_by_boss = false
	TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.AdventureContinue)
	game.refresh_battle_bgm()
	game.background_manager.apply_phase_weather(AdventureSession.active_phase)
	game.zombie_manager.zombie_wave_manager.start_first_wave()

func _dispose_dialog() -> void:
	if is_instance_valid(dialog):
		dialog.hide()
		dialog.queue_free()
	dialog = null

func _exit_tree() -> void:
	_dispose_dialog()
