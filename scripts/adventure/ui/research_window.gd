## Single research window: UI state and input only; all asset writes use ResearchService.
extends Control
class_name AdventureResearchWindow
signal closed

const Builder = preload("res://scripts/adventure/ui/research_panel_skin.gd")
const Meta = preload("res://scripts/adventure/ui/research_ui_meta.gd")
const View = preload("res://scripts/adventure/ui/research_panel_view.gd")
const Service = preload("res://scripts/adventure/research/research_service.gd")
## 研究槽位的选择状态及候选查询。
const Picker = preload("res://scripts/adventure/ui/research_slot_picker.gd")
## 独立绘制操作结果，不把提示混在工作槽刷新逻辑中。
const Feedback = preload("res://scripts/adventure/ui/research_feedback.gd")
## 与背包复用面板、按钮与模态交互。
const InventoryDialog = preload("res://scripts/adventure/ui/inventory_dialog.gd")
var mode := "craft"
var with_background := false
## 进出动画的共同根节点，由组合窗口在入树前设置。独立窗口默认使用自身。
var transition_root: CanvasItem
var ui: Dictionary = {}
## 每个页签各自维护工作槽和当前候选区的焦点。
var _pickers: Dictionary[String, Picker] = {}
## 当前页签的槽位选择，由玩家配置恢复。
var _picker: Picker
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
## 当前打开的转职确认；关闭后解除对研究槽位的输入限制。
var _confirmation: InventoryDialog
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
	_select_mode(mode)
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

## 切换到 [param value] 页签，并恢复该页各槽位的选择。
func choose_mode(value: String) -> void:
	if _closing or _busy or is_instance_valid(_confirmation) or not Meta.MODES.has(value) or value == mode:
		return
	_select_mode(value)
	SoundManager.play_other_SFX(&"buttonclick")
	_render()

## 激活 [param value] 对应的选择状态，首次进入该页时从当前档案加载。
func _select_mode(value: String) -> void:
	mode = value
	if not _pickers.has(mode):
		var saved: Dictionary = Global.config_service.get_research_selection(mode) if _is_current_profile() else {} # 只读取当前有效玩家的选择。
		_pickers[mode] = Picker.new(mode, saved)
	_picker = _pickers[mode]

## 记住当前页实际填入的槽位，供同一玩家下次打开研究室使用。
func _remember_selection() -> void:
	if _is_current_profile():
		Global.config_service.remember_research_selection(mode, _picker.saved_selection(mode))

## 把选择区 [param index] 对应的候选填入当前工作槽。
func choose_entry(index: int) -> void:
	if not _can_select() or index < 0 or index >= _options.size():
		return
	var entry: Dictionary = _options[index] # 当前点击的候选行。
	var issue := "" # 使用当前库存验证植物卡，候选列表不隐藏星级或路线不符的卡。
	match _picker.active_slot:
		Picker.Slot.MAIN_CARD:
			issue = _service.main_card_issue(mode, str(entry.uid))
		Picker.Slot.MATERIAL_CARD:
			issue = AdventureEnhancementRules.validate(_service.state,
				_picker.key_for(Picker.Slot.MAIN_CARD), [str(entry.uid)], false, "")
	if not issue.is_empty():
		_show_result(mode, issue, false)
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
	_remember_selection()

## 点击 [param slot]、[param index] 后刷新左侧候选，当前填入内容保留到玩家选中替代项。
func focus_slot(slot: Picker.Slot, index: int) -> void:
	if not _can_select() or not _picker.focus(mode, slot, index):
		return
	SoundManager.play_other_SFX(&"tap")
	_render()

## 右键清空 [param slot]、[param index] 的选择，并保存其他槽位的内容。
func clear_slot(slot: Picker.Slot, index: int) -> void:
	if not _can_select() or not _picker.focus(mode, slot, index):
		return
	_picker.clear_active()
	SoundManager.play_other_SFX(&"tap2")
	_render()
	_remember_selection()

## 仅当前有效档案能交互，确认弹窗和退出动效期间锁定槽位。
func _can_select() -> bool:
	return not _closing and not _busy and not is_instance_valid(_confirmation) \
		and _service != null and _is_current_profile()

## 依据实时库存重绘当前页，并保留仍可用的工作槽选择。
func _render() -> void:
	if ui.is_empty():
		return
	var service: AdventureResearchService = _service if _is_current_profile() else null # 切档后不继续读取旧库存。
	var primary: Array[Dictionary] = [] # 当前页的主卡或配方候选。
	if service != null:
		primary = service.options(mode, _picker.key_for(Picker.Slot.RECIPE))
		_picker.refresh_selection(mode, service, primary)
	_preview = service.quote(mode, _picker.operation_choice(mode)) if service != null \
		else {"ready": false, "message": "请先加载有效玩家档案。"}
	_options = _picker.candidates(service, primary, _preview)
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
		_confirm_promotion(chosen)
		return
	_execute_action(mode, chosen)

## 用素材弹窗确认 [param chosen]；确认时由研究服务重新校验并执行。
func _confirm_promotion(chosen: Dictionary) -> void:
	var dialog: InventoryDialog = InventoryDialog.new() # 只收集确认，不直接修改资产。
	dialog.setup_confirmation("确认转职吗？", "转职后将无法撤销", "是", "算了", Color("a32824"))
	_confirmation = dialog
	dialog.closed.connect(func(): _confirmation = null)
	dialog.confirmed.connect(func(_quantity: int): _execute_action("promotion", chosen))
	dialog.canceled.connect(SoundManager.play_other_SFX.bind(&"tap"))
	add_child(dialog)
	dialog.z_index = _feedback.z_index + 1 # 模态遮罩覆盖仍在淡出的结果提示。
	SoundManager.play_other_SFX(&"buttonclick")

## 执行 [param operation_mode] 的 [param chosen] 快照，结算后按新库存刷新并保存槽位。
func _execute_action(operation_mode: String, chosen: Dictionary) -> void:
	if _busy or _closing:
		return
	if _service == null or not _is_current_profile():
		_show_result(operation_mode, "玩家档案已变更，请重新打开研究室。", false)
		return
	_busy = true
	ui.action.disabled = true
	var result: Dictionary = _service.execute(operation_mode, chosen) # 资产和星级以事务提交结果为准。
	var committed: bool = result.get("ok", false) # 事务完成不等于强化成功，强化可能正常结算失败。
	var succeeded: bool = committed # 动效对应玩家看到的实际结果。
	var detail: String = str(result.get("message", "操作失败。")) # 失败时展示服务给出的具体原因。
	if committed:
		Global.quests_changed.emit()
		if operation_mode == "craft":
			detail = "新植物卡已放入背包。"
		elif operation_mode == "promotion":
			detail = "星级保持不变。"
		elif operation_mode == "upgrade":
			succeeded = result.get("success", false)
			detail = "主卡当前为 %d 星。" % int(result.get("stars", 0))
	_busy = false
	_render()
	if committed:
		_remember_selection()
	_show_result(operation_mode, detail, succeeded)

## 教学预选 [param recipe_id]，仍由玩家点击真实按钮并通过原合成事务消耗材料。
func guide_recipe(recipe_id: String) -> Control:
	if not _can_select():
		return null
	if _service.inventory.get_item_count(recipe_id) < 1:
		return null
	if mode != "craft" or _picker.key_for(Picker.Slot.RECIPE) != recipe_id:
		_select_mode("craft")
		_picker.pick(mode, {"id": recipe_id})
		_render()
	return ui.action

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
