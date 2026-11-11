extends Node

## 任务状态、日期或成长条件变化后通知界面刷新。
signal quests_changed
## 当前档案的装备或成长提交成功后刷新角色表现。
signal player_changed
## 首次发现物种时通知已打开的图鉴刷新目录。
signal almanac_changed
## 同一帧的多次遇敌合并保存，避免一波僵尸逐只写盘。
var _almanac_save_queued := false

## 仅由实战角色调用；[param kind] 和 [param type_id] 标识物种，展示和原版战斗不记录。
func record_almanac_encounter(kind: String, type_id: int) -> void:
	if save_service == null or not save_service.is_current_profile_loaded() \
			or not AdventureSession.owns_battle(game_para):
		return
	var state: AdventureState = global_game_state.adventure_state # 捕获所属档案，延迟保存前再次校验。
	if state == null or not state.discover_character(kind, type_id):
		return
	almanac_changed.emit()
	if not _almanac_save_queued:
		_almanac_save_queued = true
		_save_almanac_encounters.call_deferred(state)

## 合并保存 [param state] 的发现记录；切档后放弃旧回调，失败时交给统一自动保存重试。
func _save_almanac_encounters(state: AdventureState) -> void:
	_almanac_save_queued = false
	if global_game_state.adventure_state == state and save_service.is_current_profile_loaded():
		if not save_service.save_now():
			push_warning("图鉴发现记录待保存，将随下次自动保存重试。")

## 约定：业务/UI 只通过本脚本暴露的引用访问（如 `Global.user_manager`、`Global.save_service`、`Global.config_service`），
## 不要直接 `get_node` / `%` 访问 Global 场景里的子节点，避免绕过门面、破坏初始化顺序假设。

## 全局注册表（Character/MainScene/Bullet/Item registry）
# 这里提供便捷的 registry 引用给全局使用者
@onready var character_registry: CharacterRegistry = %CharacterRegistry
@onready var main_scene_registry: MainSceneRegistry = %MainSceneRegistry
@onready var bullet_registry: BulletRegistry = %BulletRegistry
@onready var item_registry: ItemRegistry = %ItemRegistry
## 用户管理（已从 Global 拆分）
@onready var user_manager: UserManager = %UserManager
## 存档服务
@onready var save_service: SaveService = %SaveService
## 配置服务（用户音量、控制台）
@onready var config_service: ConfigService = %ConfigService
## 全局游戏状态（金币、花园数据、关卡数据、当前植物、当前僵尸）
@onready var global_game_state: GlobalGameState = %GlobalGameState
## 数据服务随当前玩家状态重建，不额外设 Autoload 或第二个存档入口。
@onready var adventure_inventory: AdventureInventoryService = AdventureInventoryService.new(global_game_state.adventure_state)
## 全局只读数据（图鉴数据、刷怪白名单、罐子白名单等）
@onready var global_read_data: GlobalReadData = %GlobalReadData



func _ready() -> void:

	## 读取当前用户名
	var is_have_user := user_manager.load_current_user()
	if is_have_user and not user_manager.curr_user_name.is_empty():
		reload_session_for_current_user()
	## 创建全局数据自动存档计时器（由 SaveService 负责）
	save_service.start_autosave(60.0)
	# 周期检查使用真实时间，暂停游戏时仍跨日刷新。
	var quest_clock := Timer.new()
	quest_clock.wait_time = 1.0
	quest_clock.ignore_time_scale = true
	quest_clock.process_mode = Node.PROCESS_MODE_ALWAYS
	quest_clock.timeout.connect(refresh_quests)
	add_child(quest_clock)
	quest_clock.start()


## 在 `user_manager.curr_user_name` 已更新后，加载该用户下的全局存档与配置（与启动时一致）。
func reload_session_for_current_user() -> bool:
	if user_manager.curr_user_name.is_empty() or not save_service.load_global_game_data():
		return false
	adventure_inventory = AdventureInventoryService.new(global_game_state.adventure_state)
	refresh_quests()
	config_service.load_and_apply_config()
	return true

## 同步当前玩家任务的生效条件及自然日；写盘失败保留已赚取进度供自动保存重试。
func refresh_quests() -> void:
	if not save_service.is_current_profile_loaded():
		return
	if AdventureQuestService.synchronize(global_game_state.adventure_state, AdventureQuestService.today()):
		if not save_service.save_now():
			push_warning("任务进度待保存，将在下次保存时重试。")
		quests_changed.emit()

## 当前有效战斗上报 [param event] 与 [param target]；调用方负责确认真实玩法事实。
func record_quest_event(event: String, target: String = "") -> void:
	if not save_service.is_current_profile_loaded():
		return
	if AdventureQuestService.record_event(global_game_state.adventure_state, event, target, AdventureQuestService.today()):
		if not save_service.save_now():
			push_warning("任务进度待保存，将在下次保存时重试。")
		quests_changed.emit()

## 成长系统设置 [param level] 时统一重新判断任务门槛；保存失败回滚整个任务域。
func set_player_level(level: int) -> bool:
	var threshold: int = PlayerProgression.threshold(level) # 显式设置等级也必须保持累计经验与曲线一致。
	if not save_service.is_current_profile_loaded() or threshold < 0:
		return false
	var state: AdventureState = global_game_state.adventure_state # 当前玩家唯一状态。
	var before: Dictionary = state.quests.to_dict() # 等级及依赖任务一起回滚。
	var before_level: int = state.player_level # 成长字段独立于任务记录。
	var before_experience: int = state.experience # 与等级一起持久化，不能留下两份相互矛盾的成长事实。
	state.experience = threshold
	state.player_level = level
	AdventureQuestService.synchronize(state, AdventureQuestService.today())
	if not save_service.save_now():
		state.quests = AdventureQuestState.from_dict(before)
		state.player_level = before_level
		state.experience = before_experience
		return false
	quests_changed.emit()
	player_changed.emit()
	return true

var main_game:MainGameManager
var game_para:ResourceLevelData

## 游戏倍速
var time_scale := 1.0

