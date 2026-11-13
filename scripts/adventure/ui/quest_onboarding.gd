## 任务解锁后的教学编排。工具栏提供真实入口，本组件只呈现公告、对话和定位提示。
extends CanvasLayer

## 教学顺序与存档提交独立于视觉层。
const Progress = preload("res://scripts/adventure/quests/quest_onboarding_service.gd")
## 可透传真实按钮的高亮遮罩。
const Spotlight = preload("res://scripts/adventure/ui/tutorial_spotlight.gd")
## 现有原生戴夫动画、语音与点击气泡。
const Conversation = preload("res://scripts/ui/native_dave_conversation.gd")
## 用户指定的六句台词，末句运行原版发疯动画。
const DIALOGUE = preload("res://resources/adventure/dave_research_intro.tres")
## 直捣黄龙的领奖剧情，最后一句复用原版发疯动作。
const SHOP_DIALOGUE = preload("res://resources/adventure/dave_shop_unlock.tres")
## 图书馆教学依次介绍真实页签和可执行的操作。
const LIBRARY_PAGES := [
	{"mode": "today", "text": "今日书籍\n每天免费换一批书，用金币购买。\n也可以花金币立即刷新书架。"},
	{"mode": "convert", "text": "书籍转换\n投入两本同阶转职书，\n随机换成一本不同的同阶转职书。"},
	{"mode": "synthesize", "text": "书籍合成\n投入三本同植物、同阶转职书，\n合成一本该植物的下一阶转职书。"},
]
## 工具栏入口提供宿主、窗口和玩家档案的快照。
var toolbar: Node
## 当前绑定的档案，跨档时销毁所有未完成表现。
var _state: AdventureState
## 本次会话中暂缓提示，不持久化为完成。
var _postponed := false
## 图书馆提示可单独暂缓，旧的新手提示不会阻止开馆公告。
var _library_postponed := false
## 当前图书馆教学页，-1 表示尚在解锁公告。
var _library_page := -1
## 当前高亮提示层。
var _spotlight: Control
## 原生对话和遮幕的共同根节点。
var _dialogue_root: Control
## 当前戴夫组件，结束时由封装层自行清理。
var _conversation: Control
## 对话保存失败时的辅助文字。
var _error: Label
## 只有步骤变化时更新文本和动画。
var _shown := ""

## 教学始终位于工具栏及模态窗口之上，仍低于切场过渡层。
func _ready() -> void:
	layer = 60
	_spotlight = Spotlight.new()
	add_child(_spotlight)
	_spotlight.postponed.connect(_postpone)
	get_viewport().size_changed.connect(_fit_dave)

## 切场或切档时释放旧对话和音频接管；[param resume] 决定是否恢复已暂缓的提示。
func reset(resume: bool = true) -> void:
	if is_instance_valid(_dialogue_root):
		_dialogue_root.free() # 先恢复旧对话接管的BGM，再允许新档案创建下一段对话。
	_dialogue_root = null
	_conversation = null
	_spotlight.hide()
	_shown = ""
	_library_page = -1
	if resume:
		_postponed = false
		_library_postponed = false

## 让玩家暂缓当前教学；不写入完成节点。
func _postpone() -> void:
	if _shown.begins_with("library"):
		_library_postponed = true
		_library_page = -1
	else:
		_postponed = true
	_spotlight.hide()
	_shown = ""

## 从真实窗口和存档派生当前教学位置，不通过计时猜测是否完成操作。
func _process(_delta: float) -> void:
	var context: Dictionary = toolbar.guide_context() # 工具栏验证存档、宿主和其他模态状态。
	var current: AdventureState = context.get("state") # 不持有跨档引用。
	if current != _state:
		reset()
		_state = current
	if _state != null and _state.facilities_unlocked_by_cheat:
		if not _shown.is_empty() or is_instance_valid(_dialogue_root):
			reset(false) # 解锁时若已有引导，立即释放遮罩和对话音频。
		visible = false
		return
	if not context.get("ready", false) or _state == null:
		visible = false
		return
	visible = true
	if is_instance_valid(_dialogue_root):
		return
	var step: String = Progress.next_step(_state) # 功能解锁和教学观看分别建模。
	var quests: Control = context.get("quests") # 当前任务窗口可能被用户关闭。
	var research: Control = context.get("research") # 研究室入口仍由工具栏校验。
	# 旧教学的暂缓不拦截戴夫的领奖剧情。
	var postponed: bool = _library_postponed if step == "library_tour" else _postponed and step != "shop_dave"
	if step.is_empty() or postponed:
		_spotlight.hide()
		_shown = ""
		return
	if is_instance_valid(quests) and quests.reward_playing:
		_spotlight.hide()
		_shown = ""
		return
	match step:
		"quest_notice":
			if _shown != step:
				_shown = step
				_spotlight.present("你已解锁任务功能！\n进入任务页面，领取「初次远征」奖励。", null, _acknowledge, "查看任务入口")
		"first_reward":
			if is_instance_valid(quests):
				_show_target("claim", "领取「初次远征」奖励\n解锁研究室，并接取「初次制卡」。", quests.guide_reward("first_expedition"))
			else:
				_show_target("quests", "点击任务图标\n你的第一份任务奖励已准备好！", toolbar.guide_feature("quests"))
		"research_dave":
			toolbar.close_quests_for_guide()
			_spotlight.hide()
			_show_dave(DIALOGUE, step, {0: 0.3, 3: 0.5})
		"research":
			if is_instance_valid(quests):
				toolbar.close_quests_for_guide()
			if is_instance_valid(research):
				_show_target("craft", "坚果配方和材料已就位\n点击「合成」，制作你的第一张坚果卡！", research.guide_recipe("recipe_wall_nut"))
			else:
				_show_target("research", "研究室已解锁！\n点击研究室图标，去合成坚果。", toolbar.guide_feature("research"))
		"library_tour":
			if is_instance_valid(research):
				return
			toolbar.close_quests_for_guide()
			_show_library(context.get("library"))
		"shop_dave":
			if is_instance_valid(research) or is_instance_valid(context.get("library")):
				return
			toolbar.close_quests_for_guide()
			_spotlight.hide()
			_show_dave(SHOP_DIALOGUE, step, {0: 0.5})

## 先显示解锁公告，再通过 [param library] 定位和介绍当前页签。
func _show_library(library: Control) -> void:
	if not is_instance_valid(library):
		_library_page = -1
	if _library_page < 0:
		if _shown != "library_notice":
			_shown = "library_notice"
			_spotlight.present("恭喜解锁了图书馆功能！\n在这里可以获得转职书，\n在研究室转职时为植物赋予特殊技能。", null, _advance_library, "查看图书馆")
		return
	var key: String = "library_page_%d" % _library_page # 只在切页时重新配置高亮及按钮。
	if _shown == key:
		return
	var page: Dictionary = LIBRARY_PAGES[_library_page] # 正文对应真实的图书馆页签。
	var tab: Control = library.guide_tab(page.mode) # 用原有切页入口，不触发买书或消耗材料。
	if not is_instance_valid(tab):
		return
	_shown = key
	_spotlight.present(page.text, tab, _advance_library, "完成" if _library_page == LIBRARY_PAGES.size() - 1 else "下一项")

## 进入图书馆或推进介绍；最后一页确认时保存已看过的标记。
func _advance_library() -> void:
	if _library_page < 0 and toolbar.modal_for("library") == null and not toolbar.request_feature("library"):
		return
	if _library_page < LIBRARY_PAGES.size() - 1:
		_library_page += 1
		_shown = ""
	elif _save_step("library_tour"):
		_library_page = -1
		_spotlight.hide()
		_shown = ""
	else:
		_spotlight.present("暂时无法保存引导进度，请重试。", _spotlight.target, _advance_library, "重试")

## [param key] 区分提示节点，[param message] 和 [param target] 只影响表现。
func _show_target(key: String, message: String, target: Control) -> void:
	if not is_instance_valid(target):
		_spotlight.hide()
		_shown = ""
		return
	if _shown != key:
		_shown = key
		_spotlight.present(message, target)
	else:
		_spotlight.target = target

## 公告点击先保存已读标记；写盘失败仍保留可重试按钮。
func _acknowledge() -> void:
	if _save_step("quest_notice"):
		_shown = ""
	else:
		_spotlight.present("暂时无法保存进度，请重试。\n任务奖励仍在任务页面等待领取。", null, _acknowledge, "重试")

## 只允许当前已加载档案提交 [param step]。
func _save_step(step: String) -> bool:
	return Global.save_service.is_current_profile_loaded() and Progress.mark_step(
		_state, Global.global_game_state, Global.save_service.save_now, step)

## 展示 [param dialogue]，最后一句保存 [param step]；[param holds] 为零基句号到停顿秒数的映射。
func _show_dave(dialogue: CrazyDaveDialogResource, step: String, holds: Dictionary) -> void:
	_dialogue_root = Control.new()
	_dialogue_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dialogue_root)
	_dialogue_root.size = get_viewport().get_visible_rect().size
	var shade := ColorRect.new() # 对话时阻止地图和工具栏误触。
	shade.color = Color(0.02, 0.06, 0.04, 0.4)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_conversation = Conversation.new()
	_conversation.suppress_bgm = true
	_conversation.configure(dialogue, _finish_dave.bind(step), holds)
	_conversation.finished.connect(_dave_left)
	_dialogue_root.add_child(_conversation)
	_error = Label.new()
	_error.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_root.add_child(_error)
	_error.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_error.position.y -= 50
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.add_theme_font_size_override("font_size", 22)
	_fit_dave()

## 原生对话保持1066×600比例，非宽屏视口居中显示。
func _fit_dave() -> void:
	if not is_instance_valid(_dialogue_root) or not is_instance_valid(_conversation):
		return
	var dimensions: Vector2 = get_viewport().get_visible_rect().size # 本层使用视口逻辑坐标。
	_dialogue_root.size = dimensions
	var factor: float = minf(dimensions.x / Conversation.NATIVE_SIZE.x, dimensions.y / Conversation.NATIVE_SIZE.y) # 等比缩放。
	_conversation.scale = Vector2.ONE * factor
	_conversation.position = (dimensions - Conversation.NATIVE_SIZE * factor) * 0.5

## 原版最后一句点击先保存 [param step]；失败留在气泡中等待重试。
func _finish_dave(step: String) -> bool:
	if _save_step(step):
		Global.quests_changed.emit()
		return true
	_error.text = "保存失败，请再次点击对话重试。"
	return false

## 原版离场后恢复输入，并允许下一个教学节点出现。
func _dave_left() -> void:
	_dialogue_root.queue_free()
	_dialogue_root = null
	_conversation = null
	_shown = ""

## 教学仍允许其真实工具栏目标，但背景场景入口统一停止响应。
func blocks_scene_entries() -> bool:
	return visible and ((is_instance_valid(_dialogue_root) and _dialogue_root.visible) or (is_instance_valid(_spotlight) and _spotlight.visible))
