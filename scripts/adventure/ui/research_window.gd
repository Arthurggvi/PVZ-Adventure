## Single research window: UI state and input only; all asset writes use ResearchService.
extends Control
class_name AdventureResearchWindow
signal closed

const Builder = preload("res://scripts/adventure/ui/research_panel_skin.gd")
const Meta = preload("res://scripts/adventure/ui/research_ui_meta.gd")
const View = preload("res://scripts/adventure/ui/research_panel_view.gd")
const Service = preload("res://scripts/adventure/research/research_service.gd")
const Enhancement = preload("res://scripts/adventure/research/research_enhancement_rules.gd")
var mode := "craft"
var choice := 0
var with_background := false
var ui: Dictionary = {}
var selection: Dictionary = {}
var _options: Array[Dictionary] = []
var _preview: Dictionary = {}
var _service: RefCounted
var _opened_state: AdventureState
var _opened_profile := ""
var _picking_material := false
var _closing := false
var _busy := false
var _notice := ""
var _confirmation: ConfirmationDialog

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Global.global_game_state != null:
		_opened_state = Global.global_game_state.adventure_state
	_opened_profile = Global.user_manager.curr_user_name if Global.user_manager else ""
	if _is_current_profile():
		_service = Service.new(_opened_state, Global.adventure_inventory,
			Global.global_game_state, Global.save_service.save_now)
	ui = Builder.build(self, with_background)
	resized.connect(_fit)
	_fit()
	_render()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

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
	if _closing or _busy or not Meta.MODES.has(value) or value == mode:
		return
	mode = value
	choice = 0
	selection.clear()
	_picking_material = false
	_notice = ""
	_render()

func choose_entry(index: int) -> void:
	if _closing or _busy or index < 0 or index >= _options.size():
		return
	var entry: Dictionary = _options[index]
	if mode == "upgrade" and _picking_material:
		var uid: String = str(entry.uid)
		var consumed: Array = selection.get("materials", []).duplicate()
		if uid != str(selection.get("uid", "")) and not consumed.has(uid) and consumed.size() < 3:
			consumed.append(uid)
			selection["materials"] = consumed
			if consumed.size() == 3:
				_picking_material = false
	else:
		choice = index
		selection = ({"recipe_id": entry.id} if mode == "craft" else
			{"uid": entry.uid})
		_picking_material = false
	_notice = ""
	_render()

func toggle_material_pick() -> void:
	if mode != "upgrade" or selection.is_empty():
		return
	_picking_material = not _picking_material
	_render()

func remove_material(uid: String) -> void:
	var consumed: Array = selection.get("materials", []).duplicate()
	consumed.erase(uid)
	selection["materials"] = consumed
	_render()

func toggle_protection() -> void:
	if mode == "upgrade":
		selection["use_pot"] = not selection.get("use_pot", false)
		_render()

func cycle_fertilizer() -> void:
	if mode != "upgrade":
		return
	var ids: Array = [""]
	ids.append_array(Enhancement.FERTILIZERS)
	var next_index := (ids.find(str(selection.get("fertilizer", ""))) + 1) % ids.size()
	selection["fertilizer"] = ids[next_index]
	_render()

func choose_branch(id: String) -> void:
	if mode == "promotion":
		selection["book_id"] = id
		_notice = ""
		_render()

func _render() -> void:
	if ui.is_empty():
		return
	_options = _service.options(mode) if _service != null and _is_current_profile() else []
	choice = clampi(choice, 0, maxi(0, _options.size() - 1))
	# Deleting fodder changes inventory order; keep the main card highlighted by UID.
	if mode == "upgrade" and selection.has("uid"):
		for index: int in _options.size():
			if str(_options[index].get("uid", "")) == str(selection.uid):
				choice = index
				break
	if not _options.is_empty() and selection.is_empty():
		var first: Dictionary = _options[choice]
		selection = {"recipe_id": first.id} if mode == "craft" else {"uid": first.uid}
	_preview = _service.quote(mode, selection) if _service != null and _is_current_profile() \
		else {"ready": false, "message": "请先加载有效玩家档案。"}
	for key: String in ui.tabs:
		var tab: TextureButton = ui.tabs[key]
		tab.texture_normal = Builder.Art.texture(
			"tabs/tab_selected.png" if key == mode else "tabs/tab_normal.png")
	ui.action_text.text = Meta.title(mode)
	ui.action.disabled = _busy or not _preview.get("ready", false)
	ui.status.text = _notice if not _notice.is_empty() else str(_preview.get("message", ""))
	ui.coin.text = "金币：$%d" % Global.global_game_state.coin_value
	View.render(self, ui.content, mode, _options, choice, _preview, selection, _picking_material)

func perform_action() -> void:
	if _busy or _closing or _service == null or not _is_current_profile():
		return
	var chosen: Dictionary = selection.duplicate(true)
	if mode == "promotion":
		_confirm_promotion(chosen)
		return
	_execute_action(mode, chosen)

## The player must explicitly approve the irreversible branch and its fee.
func _confirm_promotion(chosen: Dictionary) -> void:
	if is_instance_valid(_confirmation):
		return
	var preview: Dictionary = _service.quote("promotion", chosen)
	if not preview.get("ready", false):
		_notice = str(preview.get("message", "转职条件不满足。"))
		_render()
		return
	var dialog := Builder.promotion_confirmation(self, preview, chosen,
		Callable(self, "_execute_action").bind("promotion", chosen))
	_confirmation = dialog
	dialog.tree_exited.connect(func(): _confirmation = null)

func _execute_action(operation_mode: String, chosen: Dictionary) -> void:
	if _busy or _closing or _service == null or not _is_current_profile():
		return
	_busy = true
	ui.action.disabled = true
	var result: Dictionary = _service.execute(operation_mode, chosen)
	_notice = str(result.get("message", "操作失败。"))
	if result.get("ok", false):
		if operation_mode == "craft":
			_notice = "合成成功，新植物卡 UID：" + str(result.get("uid", ""))
		elif operation_mode == "promotion":
			_notice = "转职成功，星级保持不变。"
		elif operation_mode == "upgrade":
			var outcome := "成功" if result.get("success", false) else "失败"
			_notice = "强化%s，主卡当前为 %d 星。" % [
				outcome, int(result.get("stars", 0))]
			selection = {"uid": str(chosen.get("uid", "")),
				"use_pot": bool(chosen.get("use_pot", false))}
		if operation_mode != "upgrade":
			choice = 0
			selection.clear()
		_picking_material = false
	_busy = false
	_render()

func _input(event: InputEvent) -> void:
	if _closing or not is_visible_in_tree():
		return
	if event.is_action_pressed(&"ui_cancel"):
		request_close()
		get_viewport().set_input_as_handled()

func request_close() -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.15)
	fade.finished.connect(func(): closed.emit(); queue_free())
