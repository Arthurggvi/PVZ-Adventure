## Single research window: UI state and input only; all asset writes use ResearchService.
extends Control
class_name AdventureResearchWindow
signal closed

const Builder = preload("res://scripts/adventure/ui/research_panel_skin.gd")
const Meta = preload("res://scripts/adventure/ui/research_ui_meta.gd")
const View = preload("res://scripts/adventure/ui/research_panel_view.gd")
const Service = preload("res://scripts/adventure/research/research_service.gd")
## 研究槽位的临时选择状态及候选查询。
const Picker = preload("res://scripts/adventure/ui/research_slot_picker.gd")
## 独立绘制操作结果，不把提示混在工作槽刷新逻辑中。
const Feedback = preload("res://scripts/adventure/ui/research_feedback.gd")
var mode := "craft"
var with_background := false
## 进出动画的共同根节点，由组合窗口在入树前设置。独立窗口默认使用自身。
var transition_root: CanvasItem
var ui: Dictionary = {}
## 当前槽位选择随窗口销毁，不写入玩家状态。
var _picker: Picker = Picker.new()
## 左侧选择区当前显示的过滤结果。
var _options: Array[Dictionary] = []
var _preview: Dictionary = {}
var _service: AdventureResearchService
var _opened_state: AdventureState
var _opened_profile := ""
var _closing := false
var _busy := false
## 可复用的屏幕提示条，随研究室进出。
var _feedback: Feedback
var _confirmation: ConfirmationDialog
## 当前进出动画，入场途中关闭时从当前透明度转为淡出。
var _fade: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if transition_root == null:
		transition_root = self
	transition_root.modulate.a = 0.0
	if Global.global_game_state != null:
		_opened_state = Global.global_game_state.adventure_state
	_opened_profile = Global.user_manager.curr_user_name if Global.user_manager else ""
	if _is_current_profile():
		_service = Service.new(_opened_state, Global.adventure_inventory,
			Global.global_game_state, Global.save_service.save_now)
	ui = Builder.build(self, with_background)
	if Global.global_game_state != null:
		Global.global_game_state.coin_value_changed.connect(_on_coin_value_changed, CONNECT_DEFERRED)
	_feedback = Feedback.new()
	add_child(_feedback)
	resized.connect(_fit)
	_fit()
	_render()
	_fade_to(1.0, 0.18)

## 在 [param duration] 秒内将共同根节点淡入或淡出至 [param alpha]，替换正在运行的动画。
func _fade_to(alpha: float, duration: float) -> void:
	if is_instance_valid(_fade):
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(transition_root, "modulate:a", alpha, duration)

func _fit() -> void:
	if ui.is_empty() or size.x <= 0 or size.y <= 0:
		return
	var canvas: Control = ui.canvas
	var factor := minf(size.x / Builder.DESIGN.x,
		size.y / Builder.DESIGN.y) * 0.8
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - Builder.DESIGN * factor) * 0.5

func _is_current_profile() -> bool:
	return _opened_state != null and Global.save_service != null \
		and Global.save_service.is_current_profile_loaded() \
		and Global.user_manager.curr_user_name == _opened_profile \
		and Global.global_game_state.adventure_state == _opened_state \
		and Global.adventure_inventory != null

func choose_mode(value: String) -> void:
	if _closing or _busy or is_instance_valid(_confirmation) or not Meta.MODES.has(value) or value == mode:
		return
	mode = value
	_picker.reset(mode)
	SoundManager.play_other_SFX(&"buttonclick")
	_render()

## 把选择区 [param index] 对应的候选填入当前工作槽。
func choose_entry(index: int) -> void:
	if not _can_select() or index < 0 or index >= _options.size():
		return
	var entry: Dictionary = _options[index] # 当前点击的候选行。
	if mode == "promotion" and _picker.active_slot == Picker.Slot.MAIN_CARD:
		var card: Dictionary = _service.inventory.get_card(str(entry.uid)) # 点击时读取最新的卡片星级。
		if card.is_empty():
			_render()
			return
		if not Picker.meets_promotion_minimum(card):
			_show_result(mode, "%d 星及以上的植物卡才能进行转职。" % AdventurePromotionCatalog.REQUIREMENTS[0], false)
			return
	if mode == "upgrade" and _picker.active_slot == Picker.Slot.POT:
		var quote: Dictionary = _service.quote(mode, _picker.operation_choice(mode)) # 点击时检查当前主卡的需求与真实库存。
		var required: int = int(quote.get("pot_required", 0)) # 当前目标星级所需花盆数。
		var owned: int = int(quote.get("pot_owned", 0)) # 报价中的实时持有量。
		if required <= 0:
			_render()
			return
		if owned < required:
			_show_result(mode, "育苗花盆不足，本次需要 %d 个，现有 %d 个。" % [required, owned], false)
			_render()
			return
	_picker.pick(mode, entry)
	SoundManager.play_other_SFX(&"seedlift")
	_render()

## 点击 [param slot]、[param index] 后刷新左侧候选，当前填入内容保留到玩家选中替代项。
func focus_slot(slot: Picker.Slot, index: int) -> void:
	if not _can_select() or not _picker.focus(mode, slot, index):
		return
	SoundManager.play_other_SFX(&"tap")
	_render()

## 右键清空 [param slot]、[param index] 的临时选择，只改变报价预览。
func clear_slot(slot: Picker.Slot, index: int) -> void:
	if not _can_select() or not _picker.focus(mode, slot, index):
		return
	_picker.clear_active()
	SoundManager.play_other_SFX(&"tap2")
	_render()

## 仅当前有效档案能交互，确认弹窗和退出动效期间锁定槽位。
func _can_select() -> bool:
	return not _closing and not _busy and not is_instance_valid(_confirmation) \
		and _service != null and _is_current_profile()

func _render() -> void:
	if ui.is_empty():
		return
	var service: AdventureResearchService = _service if _is_current_profile() else null # 切档后不继续读取旧库存。
	var primary: Array[Dictionary] = service.options(mode) if service != null else [] # 保留服务的主卡和制作书资格规则。
	_picker.ensure_primary(mode, primary)
	_preview = service.quote(mode, _picker.operation_choice(mode)) if service != null \
		else {"ready": false, "message": "请先加载有效玩家档案。"}
	_options = _picker.candidates(mode, service, primary, _preview)
	for key: String in ui.tabs:
		var tab: TextureButton = ui.tabs[key]
		tab.texture_normal = Builder.Art.texture(
			"tabs/tab_selected.png" if key == mode else "tabs/tab_normal.png")
	ui.action_text.text = Meta.title(mode)
	# 有效档案可点击操作按钮查看不足原因，真正执行前仍重新报价。
	ui.action.disabled = _busy or _closing or service == null
	var coin_balance: int = Global.global_game_state.coin_value if Global.global_game_state != null else 0 # 页首与操作报价使用同一余额。
	ui.coin.text = "$%d" % coin_balance
	View.render(self, ui.content, mode, _options, _preview, _picker,
		service.inventory if service != null else null, coin_balance)

## 钱包余额变化后刷新页首与价格颜色；[param _balance] 的最新值由渲染统一读取。
func _on_coin_value_changed(_balance: int) -> void:
	if not _closing:
		_render()

func perform_action() -> void:
	if _busy or _closing or is_instance_valid(_confirmation):
		return
	if _service == null or not _is_current_profile():
		_show_result(mode, "请先加载有效玩家档案。", false)
		_render()
		return
	var chosen: Dictionary = _picker.operation_choice(mode) # 在确认与执行间保留独立的操作快照。
	var preview: Dictionary = _service.quote(mode, chosen) # 点击时用实时库存和余额重新校验。
	if not preview.get("ready", false):
		_show_result(mode, str(preview.get("message", "操作条件不满足。")), false)
		_render()
		return
	if mode == "promotion":
		_confirm_promotion(chosen, preview)
		return
	_execute_action(mode, chosen)

## 根据 [param chosen] 和最新 [param preview] 显示不可撤销的转职确认。
func _confirm_promotion(chosen: Dictionary, preview: Dictionary) -> void:
	var dialog := Builder.promotion_confirmation(self, preview, chosen,
		Callable(self, "_execute_action").bind("promotion", chosen))
	_confirmation = dialog
	SoundManager.play_other_SFX(&"buttonclick")
	dialog.canceled.connect(SoundManager.play_other_SFX.bind(&"tap"))
	# 系统弹窗关闭时只隐藏节点，释放它才能继续操作工作槽或再次确认。
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free())
	dialog.tree_exited.connect(func(): _confirmation = null)

func _execute_action(operation_mode: String, chosen: Dictionary) -> void:
	if _busy or _closing:
		return
	if _service == null or not _is_current_profile():
		_show_result(operation_mode, "玩家档案已变更，请重新打开研究室。", false)
		return
	_busy = true
	ui.action.disabled = true
	var result: Dictionary = _service.execute(operation_mode, chosen)
	var committed: bool = result.get("ok", false) # 事务完成不等于强化成功，强化可能正常结算失败。
	var succeeded: bool = committed # 动效对应玩家看到的实际结果。
	var detail: String = str(result.get("message", "操作失败。")) # 失败时展示服务给出的具体原因。
	if committed:
		if operation_mode == "craft":
			detail = "新植物卡已放入背包。"
		elif operation_mode == "promotion":
			detail = "星级保持不变。"
		elif operation_mode == "upgrade":
			succeeded = result.get("success", false)
			detail = "主卡当前为 %d 星。" % int(result.get("stars", 0))
			_picker.reset(operation_mode, str(chosen.get("uid", "")))
		if operation_mode != "upgrade":
			_picker.reset(operation_mode)
	_busy = false
	_render()
	_show_result(operation_mode, detail, succeeded)

## 将 [param operation_mode] 的 [param detail] 与 [param succeeded] 转为统一的屏幕与声音反馈。
func _show_result(operation_mode: String, detail: String, succeeded: bool) -> void:
	var heading: String = Meta.title(operation_mode) + ("成功" if succeeded else "失败") # 模式名和结算结果组成标题。
	_feedback.present(heading, detail, succeeded)
	SoundManager.play_other_SFX(&"prize" if succeeded else &"buzzer")

func _input(event: InputEvent) -> void:
	if _closing or not is_visible_in_tree() or is_instance_valid(_confirmation):
		return
	if event.is_action_pressed(&"ui_cancel"):
		request_close()
		get_viewport().set_input_as_handled()

## 开始关闭动效；外部入口已播放按键音时将 [param play_sound] 设为 false。
func request_close(play_sound: bool = true) -> void:
	if _closing:
		return
	_closing = true
	if play_sound:
		SoundManager.play_other_SFX(&"buttonclick")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_to(0.0, 0.15)
	_fade.finished.connect(func():
		closed.emit()
		queue_free())
