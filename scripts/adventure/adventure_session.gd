## 连接独立冒险状态与原版战斗；只有本次创建的关卡资源可结算。
extends Node

## 独立地图场景入口。
const MAP_SCENE := "res://scenes/adventure/zombie_island.tscn"
## 独立存档实现，不引入新的战斗数据模型。
const Progress = preload("res://scripts/adventure/island_progress.gd")
## 第二阶段可监听的结果事件；[param result] 为 victory、defeat 或 abandoned。
signal battle_finished(stage_id: int, result: String)
## 当前用户的独立状态。
var progress: RefCounted
## 当前冒险战斗资源身份；null 表示没有冒险战斗。
var active_level: ResourceLevelData
## 返回地图显示的一次性结果文字。
var notice := ""
## 进屋失败优先于迟到的奖杯回调。
var battle_failed := false
## 从进入地图到返回主菜单的会话范围，涵盖切场景的空帧。
var adventure_active := false

## 菜单入口重新绑定当前用户，兼容原有用户切换。
func refresh_profile() -> bool:
	# 沿用 UserManager 的用户目录，改名与删除自然迁移；文件仍与原版存档隔离。
	var profile: String = Global.user_manager.curr_user_name
	var path := "user://adventure_guest/zombie_island_v1.json" # 未登录的独立游客状态。
	if not profile.is_empty():
		path = "user://%s/adventure/zombie_island_v1.json" % profile
	progress = Progress.new(path)
	return progress.load_progress()

## 开始新游戏；调用方负责在已有进度时给出游戏内确认。
func start_new_game() -> void:
	refresh_profile()
	if progress.start_new():
		notice = ""
		return_to_map()

## 继续只回到世界地图；未完成的新手对话从头恢复且不重复发卡。
func continue_game() -> void:
	if refresh_profile() and progress.started:
		notice = ""
		return_to_map()

## 返回关卡是否解锁；第二关当前仅展示已开放状态。
func is_unlocked(stage_id: int) -> bool:
	return stage_id == 1 or (stage_id == 2 and progress != null and progress.stage_1_cleared)

## 将已拥有的两张卡适配为原版预选卡，加载现有草坪场景。
func enter_lawn() -> void:
	if progress == null or not progress.intro_completed or progress.cards.size() != 2:
		return
	active_level = load("res://resources/adventure/island_lawn.tres").duplicate(true)
	active_level.prechosen_cards = [
		ResourceCardReference.create(ResourceCardReference.CardType.Plant, CharacterRegistry.PlantType.P002SunFlower),
		ResourceCardReference.create(ResourceCardReference.CardType.Plant, CharacterRegistry.PlantType.P001PeaShooterSingle),
	]
	battle_failed = false
	Global.game_para = active_level
	# 场景切换失败不会把地图误当作正在进行的战斗。
	var error := get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[active_level.game_sences])
	if error != OK:
		active_level = null
		Global.game_para = null
		notice = "草坪场景加载失败。"

## [param level] 必须是本次冒险创建的同一个资源，而非同名关卡。
func owns_battle(level: ResourceLevelData) -> bool:
	return active_level != null and active_level == level

## 战斗管理器已通过原有结算防护后调用；写入失败保留可重试的胜利状态。
func finish_victory() -> void:
	if active_level == null or battle_failed:
		return
	if not progress.record_victory():
		_show_save_retry()
		return
	notice = "草坪已通关，没落营地已开放！"
	battle_finished.emit(1, "victory")
	return_to_map()

## 保存失败时提供重试，不能假装已保存或重新开始对局。
func _show_save_retry() -> void:
	# 弹窗挂在单例下，场景切换期间也能完成回调。
	var retry := AcceptDialog.new()
	retry.dialog_text = progress.error_message
	retry.ok_button_text = "重试保存"
	retry.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(retry)
	retry.confirmed.connect(func():
		retry.queue_free()
		finish_victory())
	retry.canceled.connect(func():
		retry.queue_free()
		_show_save_retry.call_deferred())
	retry.popup_centered(Vector2i(520, 150))

## 真实进屋失败后调用；从不清除已经获得的历史通关状态。
func finish_defeat() -> void:
	if active_level == null:
		return
	notice = "草坪挑战失败，再试一次吧。"
	battle_finished.emit(1, "defeat")
	return_to_map()

## 主动离开战斗，无胜利奖励或解锁。
func abandon_battle() -> void:
	if active_level != null:
		notice = "已离开草坪，本次未结算通关。"
		battle_finished.emit(1, "abandoned")
	return_to_map()

## 清理原版暂停与游戏速度，并进入地图；不触碰原版存档。
func return_to_map() -> void:
	adventure_active = true
	active_level = null
	Global.game_para = null
	TreePauseManager.end_tree_pause_clear_all_pause_factors()
	Global.time_scale = 1.0
	Engine.time_scale = 1.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file(MAP_SCENE)
