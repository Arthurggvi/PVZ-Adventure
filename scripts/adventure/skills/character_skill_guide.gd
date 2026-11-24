## 首次可操作战斗中的技能入口说明；只呈现与保存教学，不施放技能或修改冷却。
extends CanvasLayer

## 与任务教学共用的已确认步骤事务。
const Progress = preload("res://scripts/adventure/tutorial/tutorial_progress.gd")
## 复用木质说明卡、真实目标高亮和确认按钮。
const Spotlight = preload("res://scripts/adventure/ui/tutorial_spotlight.gd")
## 独占自身教学暂停，不清除菜单、结算或其他系统的因素。
const PAUSE_REASON := TreePauseManager.E_PauseFactor.CharacterSkillTutorial
## 当前战斗宿主，离场后不得继续提示或写档。
var _game: MainGameManager
## 唯一技能运行时，仅查询输入资格与技能是否存在。
var _runtime: CharacterSkillRuntime
## 真实头像控件，位置和缩放由原战斗 HUD 决定。
var _avatar: Control
## 创建时绑定的玩家档案，确认前再次核对归属。
var _state: AdventureState
## 两个平台分别保存首次说明，跨端读档仍能了解本端操作。
var _step: String
## 手机宿主提供全部原始触点的空闲查询；桌面仍使用引擎的按键与鼠标状态。
var _pointer_idle: Callable
## 仅在真正展示时构造的教学视图。
var _spotlight: Control
## 本组件是否持有教学暂停，确保退出与关闭可以重复调用。
var _pause_owned := false
## 确认或暂缓后不在同一场战斗重新出现。
var _finished := false
## 尚未开始时的资格轮询累计，单位为真实秒。
var _poll_elapsed := 0.0

## 绑定 [param game]、[param runtime]、[param avatar] 与可选 [param pointer_idle]，不参与角色配置。
func setup(game: MainGameManager, runtime: CharacterSkillRuntime, avatar: Control,
		pointer_idle: Callable = Callable()) -> void:
	_game = game
	_runtime = runtime
	_avatar = avatar
	_state = Global.global_game_state.adventure_state if Global.global_game_state != null else null
	_step = "character_skill_mobile" if OS.has_feature("mobile") else "character_skill_desktop"
	_pointer_idle = pointer_idle

## 位于战斗 UI 上方、水下透镜和切场遮幕下方；暂停期间仍可确认或暂缓。
func _ready() -> void:
	name = "CharacterSkillGuide"
	layer = 92
	process_mode = Node.PROCESS_MODE_ALWAYS

## [param delta] 只用于等待资格；教学展开后不能用被自身暂停关闭的技能门禁判断存活。
func _process(delta: float) -> void:
	if _finished:
		return
	if not _same_profile() or not is_instance_valid(_game) or not is_instance_valid(_runtime) \
			or not is_instance_valid(_avatar) or _game.is_queued_for_deletion():
		_finish()
		return
	if _pause_owned:
		if get_tree().current_scene != _game or not AdventureSession.owns_battle(_game.game_para) \
				or _game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
				or not TreePauseManager.is_paused_for(PAUSE_REASON):
			_finish()
		return
	_poll_elapsed += delta
	if _poll_elapsed < 0.1:
		return
	_poll_elapsed = 0.0
	if _state.tutorial_steps.get(_step, false):
		_finish()
		return
	if _runtime.definition() == null and _game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME:
		_finish() # 没有角色技能时不展示、不写完成；以后装备有效技能仍可获得说明。
		return
	if not _runtime.is_input_enabled() or not _avatar.is_visible_in_tree() \
			or not get_window().has_focus() or Input.is_anything_pressed() \
			or (_pointer_idle.is_valid() and not bool(_pointer_idle.call())):
		return # 等开场、弹窗和当前按压结束，不能在一次种植点按中途插入引导。
	_present()

## 当前安全加载的档案必须仍是创建时的同一对象，避免切档后写入旧玩家进度。
func _same_profile() -> bool:
	return _state != null and is_instance_valid(Global.save_service) \
		and Global.save_service.is_current_profile_loaded() and Global.global_game_state != null \
		and Global.global_game_state.adventure_state == _state

## 高亮头像并暂停真实战斗；说明两端入口，开局冷却无需强迫试放。
func _present() -> void:
	_spotlight = Spotlight.new()
	_spotlight.allow_target_input = false
	add_child(_spotlight)
	_spotlight.postponed.connect(_finish)
	_pause_owned = true # 暂停信号可能同步回调，先记录本组件的所有权。
	TreePauseManager.start_tree_pause(PAUSE_REASON)
	var message := "点击左上角头像释放角色技能。\n" # 桌面与手机共用头像入口说明。
	if OS.has_feature("mobile"):
		message += "也可双指向外张开（放大手势）。\n"
	message += "技能冷却结束后可使用。"
	_spotlight.present(message, _avatar, _acknowledge, "知道了")

## 用户确认后通过现有存档事务提交；失败保留重试与暂缓出口，不提前消耗首次提示。
func _acknowledge() -> void:
	if _finished:
		return
	if not _same_profile() or get_tree().current_scene != _game:
		_finish()
		return
	if not Progress.mark_step(_state, Global.global_game_state, Global.save_service.save_now, _step):
		_spotlight.present("暂时无法保存引导进度。\n请重试，或稍后继续。", _avatar, _acknowledge, "重试")
		return
	_finish()

## [param event] 为返回键时暂缓本场说明，不把返回当作已经确认学习。
func _unhandled_key_input(event: InputEvent) -> void:
	if _pause_owned and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_finish()

## 确认、暂缓或上下文失效都同步收回视图，再释放自己持有的暂停。
func _finish() -> void:
	if _finished:
		return
	_finished = true
	if is_instance_valid(_spotlight):
		_spotlight.hide()
	set_process(false)
	set_process_unhandled_key_input(false)
	_release_pause()
	queue_free()

## 幂等交还教学暂停，其他暂停因素继续由各自所有者维护。
func _release_pause() -> void:
	if not _pause_owned:
		return
	_pause_owned = false
	TreePauseManager.end_tree_pause(PAUSE_REASON)

## 场景被外部切换时同样释放自己的暂停，不留下跨战斗冻结。
func _exit_tree() -> void:
	_release_pause()
