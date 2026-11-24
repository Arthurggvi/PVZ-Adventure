extends Node

## 任务状态、日期或成长条件变化后通知界面刷新。
signal quests_changed
## 当前档案的装备或成长提交成功后刷新角色表现。
signal player_changed
## 首次发现物种时通知已打开的图鉴刷新目录。
signal almanac_changed
## 战斗击杀已记入内存，等待任务时钟合并通知界面。
var _zombie_defeat_pending_refresh := false

## Android 系统返回键进入现有的取消输入链，由当前弹窗或场景处理。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_dispatch_android_back.call_deferred()

## 模拟完整的一次 Esc 按下与释放，让现有按键回调共享同一消费顺序。
func _dispatch_android_back() -> void:
	var pressed := InputEventKey.new() # Android 的返回动作交给 [code]ui_cancel[/code] 所绑定的按键。
	pressed.keycode = KEY_ESCAPE
	pressed.pressed = true
	var released := pressed.duplicate() as InputEventKey # 按下和释放分别提交，避免积攒事件时改写前一事件。
	released.pressed = false
	Input.parse_input_event(pressed)
	Input.parse_input_event(released)

## 仅由实战角色调用；[param kind] 和 [param type_id] 标识物种，展示和原版战斗不记录。
func record_almanac_encounter(kind: String, type_id: int) -> void:
	if save_service == null or not save_service.is_current_profile_loaded() \
			or not AdventureSession.owns_battle(game_para):
		return
	var state: AdventureState = global_game_state.adventure_state # 仅登记当前已加载档案的发现。
	if state == null or not state.discover_character(kind, type_id):
		return
	save_service.mark_dirty()
	almanac_changed.emit()

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
	_zombie_defeat_pending_refresh = false
	adventure_inventory = AdventureInventoryService.new(global_game_state.adventure_state)
	refresh_quests()
	config_service.load_and_apply_config()
	return true

## 同步当前玩家的任务与商店日期，并合并这一秒内的任务界面通知。
func refresh_quests() -> void:
	if not save_service.is_current_profile_loaded():
		return
	var state: AdventureState = global_game_state.adventure_state # 仅校正已加载档案的限购日期。
	var today: String = AdventureQuestService.today() # 同一次同步共用本机自然日。
	var shop_day_corrected: bool = state.shop.correct_future_day(today) # 登录或运行期间都可恢复未来日期的档案。
	var tasks_changed: bool = AdventureQuestService.synchronize(state, today) # 检测跨日与新开放的任务。
	if tasks_changed or shop_day_corrected:
		save_service.mark_dirty()
	if tasks_changed or _zombie_defeat_pending_refresh:
		_notify_quest_progress()

## 当前有效战斗上报 [param event] 与 [param target]；调用方负责确认真实玩法事实。
func record_quest_event(event: String, target: String = "") -> void:
	if not save_service.is_current_profile_loaded():
		return
	if AdventureQuestService.record_event(global_game_state.adventure_state, event, target, AdventureQuestService.today()):
		save_service.mark_dirty()
		_notify_quest_progress()

## 记录由战斗管理器确认的一次击杀，并将普通存档交由 SaveService 合并。
func record_zombie_defeat() -> void:
	if not save_service.is_current_profile_loaded():
		return
	if AdventureQuestService.record_zombie_defeat(global_game_state.adventure_state, AdventureQuestService.today()):
		_zombie_defeat_pending_refresh = true
		save_service.mark_dirty()

## 发布当前的合并任务变更。
func _notify_quest_progress() -> void:
	_zombie_defeat_pending_refresh = false
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

