## 同一战斗场景内普通、噩梦及终末续战的唯一调度器。
## 负责结算检查点、暂停期间的玩家选择、运行时交接；原版多轮流程完全隔离。
extends Node
class_name AdventureContinuationController

## 续战复用背包的素材确认框，战场暂停时仍接收输入。
const InventoryDialog = preload("res://scripts/adventure/ui/inventory_dialog.gd")
## 所属战斗场景，负责实际结算与阶段交接。
var game: MainGameManager
## 当前唯一的续战提示，退出战斗时一并释放。
var dialog: InventoryDialog

func setup(battle: MainGameManager) -> void:
	game = battle
	process_mode = Node.PROCESS_MODE_ALWAYS

## [param glo_pos] 为清场位置；先保存本阶段奖励，再询问是否续战。
func complete_checkpoint(glo_pos: Vector2) -> void:
	game.zombie_manager.zombie_wave_manager.stop_wave_refresh()
	if not TreePauseManager.curr_pause_factor.get(TreePauseManager.E_PauseFactor.AdventureContinue, false):
		TreePauseManager.start_tree_pause(TreePauseManager.E_PauseFactor.AdventureContinue)
	if not AdventureSession.settle_victory():
		AdventureSession.prompt_victory_retry(complete_checkpoint.bind(glo_pos))
		return
	game.drop_item_manager.spawn_first_clear_coins(AdventureSession.active_phase, glo_pos)
	if _can_offer_followup():
		_show_offer(glo_pos)
	else:
		_finish_challenge(glo_pos)

## 显示当前钥匙规则和最近一次失败原因；[param glo_pos] 用于结束挑战时生成奖杯。
func _show_offer(glo_pos: Vector2) -> void:
	_dispose_dialog()
	var terminal: bool = AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NIGHTMARE # 从噩梦续战时使用下半钥匙。
	var stage: StageDefinition = AdventureSession.active_stage # 当前关卡的钥匙配置。
	var key_id: StringName = stage.terminal_key_id if terminal else stage.nightmare_key_id # 本次续战实际使用的物品。
	var key_name: String = str(ItemRegistry.get_item_definition(str(key_id)).get("name", "钥匙")) # 使用背包显示名。
	var action: String = "消耗" if terminal or stage.nightmare_key_use == StageDefinition.KeyUse.CONSUME else "使用" # 显示实际扣除规则。
	var next_phase: String = "终末" if terminal else "噩梦" # 确认按钮对应的目标阶段。
	var prompt: String = "%s%s来开启%s阶段吗？" % [action, key_name, next_phase] # 明确提示钥匙与阶段。
	if not AdventureSession.error_message.is_empty():
		prompt += "\n" + AdventureSession.error_message
	dialog = InventoryDialog.new()
	dialog.setup_confirmation("", prompt, "继续挑战", "结束挑战")
	dialog.animated_feedback = true
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.confirmed.connect(_continue.bind(glo_pos))
	dialog.canceled.connect(_finish_challenge.bind(glo_pos))
	game.canvas_layer_ui.add_child(dialog)

## [param glo_pos] 为奖杯位置；结束已保存的当前阶段。
func _finish_challenge(glo_pos: Vector2) -> void:
	_dispose_dialog()
	if not AdventureSession.complete_checkpoint_challenge():
		return
	TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.AdventureContinue)
	game._finish_round_victory(glo_pos)

## [param _quantity] 是共用弹窗的固定确认值；实际钥匙数量来自关卡配置。
## [param glo_pos] 用于续战资格失效时完成已保存的阶段结算。
func _continue(_quantity: int, glo_pos: Vector2) -> void:
	_dispose_dialog()
	# 这两个条件来自本阶段自然清场边界，钥匙再次查询当前库存。
	if not _can_offer_followup():
		_finish_challenge(glo_pos)
		return
	var terminal: bool = AdventureSession.active_phase_kind == StagePhaseDefinition.Kind.NIGHTMARE # 噩梦清场后进入终末。
	var next_kind: StagePhaseDefinition.Kind = StagePhaseDefinition.Kind.TERMINAL if terminal else StagePhaseDefinition.Kind.NIGHTMARE # 关卡中的目标阶段类型。
	var next_phase: StagePhaseDefinition = AdventureStageCatalog.find_phase(AdventureSession.active_stage, next_kind) # 已通过入场校验的阶段快照。
	# 先完成不会改变资产的战场预检；成功后本次同步交接不再包含可失败步骤。
	if next_phase == null or not game.zombie_manager.can_begin_adventure_phase(next_phase):
		push_error("冒险连续阶段的战场前置条件无效。")
		_finish_challenge(glo_pos)
		return
	var entered: bool = AdventureSession.begin_terminal() if terminal else AdventureSession.begin_nightmare() # 校验并提交钥匙事务。
	if not entered:
		_show_offer(glo_pos)
		return
	# 先卸载旧阶段全部事件监听，再配置下一阶段；植物与卡牌维持原状。
	if is_instance_valid(game.adventure_runtime):
		# 同步释放旧阶段监听器；下一阶段首波不能被尚未 queue_free 的旧节点收到。
		game.remove_child(game.adventure_runtime)
		game.adventure_runtime.free()
		game.adventure_runtime = null
	# 旧 ResourceLevelData 是投影，所有阶段动态读取应以 Session.active_phase 为准。
	AdventureBattleEnvironmentAdapter.project_phase(game.game_para, AdventureSession.active_phase)
	game.zombie_manager.zombie_refresh_types = game.game_para.zombie_refresh_types
	game.zombie_manager.begin_adventure_phase(next_phase)
	game.adventure_runtime = AdventureBattleRuntime.new()
	game.adventure_runtime.setup(game.zombie_manager.zombie_wave_manager,
		game.zombie_manager, AdventureSession.active_phase)
	game.add_child(game.adventure_runtime)
	game._round_end_claimed = false
	game._round_end_by_boss = false
	TreePauseManager.end_tree_pause(TreePauseManager.E_PauseFactor.AdventureContinue)
	game.refresh_battle_bgm()
	game.background_manager.apply_phase_weather(AdventureSession.active_phase)
	if terminal:
		game.adventure_runtime.start_phase()
	else:
		game.zombie_manager.zombie_wave_manager.start_first_wave()

## 只对本次已保存且符合钥匙条件的关卡检查点提供续战。
func _can_offer_followup() -> bool:
	return AdventureSession.can_offer_nightmare() or AdventureSession.can_offer_terminal()

func _dispose_dialog() -> void:
	if is_instance_valid(dialog):
		dialog.hide()
		dialog.queue_free()
	dialog = null

func _exit_tree() -> void:
	_dispose_dialog()
