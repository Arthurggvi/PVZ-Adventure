extends MainGameSubManager
## 管理手持角色（植物、僵尸）及战斗道具。
## 类似状态机
class_name HandManager

@onready var hm_character: HM_Character = $HM_Character
@onready var hm_item: HM_Item = $HM_Item
@onready var hm_null: HM_NUll = $HM_Null

## 触控放置手套时拖动所需的距离，单位为视口像素，避免轻触时的手指偏移搬动植物。
const TOUCH_GLOVE_DRAG_THRESHOLD := 12.0

## 手持管理器状态
enum E_HandManagerStatus{
	Null, 		## 手上什么都没拿
	Character,	## 手持角色 植物、僵尸
	Item,		## 手持铲子或手套
}

## 当前手持管理器状态
var curr_hm_status := E_HandManagerStatus.Null:
	set(value):
		hm_status_change(curr_hm_status, value)
		curr_hm_status = value
## 当前植物格子
var curr_plant_cell:PlantCell = null

func _ready() -> void:
	# 战斗独享的轻量触控拾取，不在启动时构造或预载掉落资源。
	add_child(preload("res://scripts/battle/drops/touch_pickup_sweep.gd").new())
	EventBus.subscribe("main_game_click_card", _click_card)
	EventBus.subscribe("main_game_click_shovel", _click_shovel)

func _process(_delta: float) -> void:
	_refresh_board_hover()
	match curr_hm_status:
		E_HandManagerStatus.Null:
			hm_null.null_process()
		E_HandManagerStatus.Character:
			hm_character.character_process()
		E_HandManagerStatus.Item:
			hm_item.item_process()

## [param what] 为暂停、退后台或失焦时丢弃未收到松开的手势，恢复后仍可操作已选植物。
func _notification(what: int) -> void:
	if (what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT) \
			and is_node_ready() and is_holding_glove():
		hm_item.clear_glove_press()

## 手持管理器状态改变
func hm_status_change(ori_status:E_HandManagerStatus, _new_status:E_HandManagerStatus):
	match ori_status:
		E_HandManagerStatus.Null:
			hm_null.exit_status()
		E_HandManagerStatus.Character:
			hm_character.exit_status()
		E_HandManagerStatus.Item:
			hm_item.exit_status()

func init_manager() -> void:
	hm_character.init_hm_character()

## 手持 [param card] 前确认卡片可用性；僵王只建立预览，召唤等待战场格子确认。
func _click_card(card:Card) -> void:
	if not is_instance_valid(card) or card.is_queued_for_deletion() or not AllCards.is_battle_card(card.card_reference):
		return
	if OS.has_feature("mobile") and curr_hm_status == E_HandManagerStatus.Character and hm_character.curr_card == card:
		_cancel_selection()
		return
	if not card.is_can_click:
		SoundManager.play_other_SFX("buzzer")
		return
	if card.card_reference.card_type == ResourceCardReference.CardType.ZombieBoss \
		and not main_game.zombie_manager.can_summon_boss(card.card_reference.content_id):
		SoundManager.play_other_SFX("buzzer")
		return
	SoundManager.play_other_SFX("seedlift")
	curr_hm_status = E_HandManagerStatus.Character
	if not hm_character.click_card(card):
		curr_hm_status = E_HandManagerStatus.Null
		return
	_refresh_board_hover(true)

## 点击工具栏切换到铲子；移动端再次轻触同一工具位可以收回铲子。
func _click_shovel() -> void:
	if main_game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or get_tree().paused or not hm_item.ui_shovel.is_visible_in_tree():
		return
	if OS.has_feature("mobile") and curr_hm_status == E_HandManagerStatus.Item \
			and hm_item.curr_hm_item_status == HM_Item.E_HmItemStatus.Shovel:
		_cancel_selection()
		return
	SoundManager.play_other_SFX("shovel")
	curr_hm_status = E_HandManagerStatus.Item
	hm_item.click_shovel()
	_refresh_board_hover(true)

## 点击图标切换手套；同一局中卡片、铲子和手套由同一个手持状态互斥管理。
func _click_glove() -> void:
	if main_game.battle_glove_button.disabled or not main_game.has_battle_glove() \
			or main_game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
			or get_tree().paused:
		main_game.battle_glove_button.set_pressed_no_signal(false)
		return
	SoundManager.play_other_SFX(&"tap2")
	if is_holding_glove():
		cancel_glove()
		return
	curr_hm_status = E_HandManagerStatus.Item
	hm_item.click_glove()
	_refresh_board_hover(true)
	hm_item.item_process()

## 返回当前手持道具是否是手套，供取消操作和玉米加农炮输入分流。
func is_holding_glove() -> bool:
	return curr_hm_status == E_HandManagerStatus.Item and hm_item.curr_hm_item_status == HM_Item.E_HmItemStatus.Glove

## 返回玩家是否正在战斗中使用卡片或工具。此时触控滑动留给本次棋盘操作。
func has_active_board_action() -> bool:
	return curr_hm_status != E_HandManagerStatus.Null and is_inside_tree() and not get_tree().paused \
		and is_instance_valid(main_game) \
		and main_game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and main_game.board != null and main_game.board.configured

## [param viewport_point] 为已映射的视口坐标。手持时只在真实地块范围内优先处理棋盘点击。
func has_board_action_at(viewport_point: Vector2) -> bool:
	if not has_active_board_action():
		return false
	var world_point: Vector2 = main_game.get_canvas_transform().affine_inverse() * viewport_point # 换算到地块所在的战斗画布。
	return main_game.board.pick_cell(world_point) != null

## 结束手套交互并撤销其高亮；其他道具和卡片沿用原手持状态。
func cancel_glove() -> void:
	if is_holding_glove():
		curr_hm_status = E_HandManagerStatus.Null

## 收回选中的卡片或工具，并让各手持状态恢复自身的高亮和按钮。
func _cancel_selection() -> void:
	SoundManager.play_other_SFX(&"tap2")
	curr_hm_status = E_HandManagerStatus.Null

## 确认 [param plant_cell] 的棋盘操作；落点无效时保留可继续使用的手持卡片。
func _on_click_cell(plant_cell: PlantCell) -> void:
	_refresh_board_hover()
	if plant_cell != curr_plant_cell or not is_instance_valid(plant_cell):
		return
	match curr_hm_status:
		E_HandManagerStatus.Null:
			hm_null.click_cell(plant_cell)
		E_HandManagerStatus.Character:
			if hm_character.click_cell(plant_cell) or not is_instance_valid(hm_character.curr_card) \
					or hm_character.curr_card.is_queued_for_deletion():
				curr_hm_status = E_HandManagerStatus.Null
		E_HandManagerStatus.Item:
			if hm_item.click_cell(plant_cell):
				curr_hm_status = E_HandManagerStatus.Null

## 鼠标进入cell
func _on_cell_mouse_enter(_plant_cell: PlantCell) -> void:
	_refresh_board_hover(true)

## 鼠标移出cell
func _on_cell_mouse_exit(_plant_cell: PlantCell) -> void:
	_refresh_board_hover()

## [param event] 通过棋盘命中处理手套手势；移动端返回键先取消手持再交给暂停菜单。
func _input(event: InputEvent) -> void:
	if curr_hm_status != E_HandManagerStatus.Null and event.is_action_pressed(&"ui_cancel") \
			and (is_holding_glove() or OS.has_feature("mobile")):
		_cancel_selection()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	_refresh_board_hover()
	if is_holding_glove():
		_handle_glove_pointer(event)
		return
	var touch: bool = OS.has_feature("mobile") and event.device == InputEvent.DEVICE_ID_EMULATION # 无悬停设备走明确的取消入口。
	if curr_hm_status != E_HandManagerStatus.Null and event.pressed \
			and (event.button_index == MOUSE_BUTTON_RIGHT \
			or (event.button_index == MOUSE_BUTTON_LEFT and not touch and not is_instance_valid(curr_plant_cell))):
		_cancel_selection()


## [param event] 只捕获从棋盘起手的左键手势；工具栏仍由自己的按钮接收点击。
func _handle_glove_pointer(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		SoundManager.play_other_SFX(&"tap2")
		cancel_glove()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		var physical_position: Vector2 = event.get_meta(BattleEnvironmentLens.PHYSICAL_POINTER_POSITION, event.position) # 只有实际移动才算拖动，落点仍使用折射后的棋盘命中。
		if event.pressed:
			if not is_instance_valid(curr_plant_cell):
				return
			hm_item.press_glove(curr_plant_cell, physical_position)
		elif not hm_item.has_glove_press():
			return
		elif event.is_canceled():
			hm_item.clear_glove_press()
		else:
			var drag_threshold: float = TOUCH_GLOVE_DRAG_THRESHOLD if event.device == InputEvent.DEVICE_ID_EMULATION \
				else HM_Item.GLOVE_DRAG_THRESHOLD # 触屏允许轻触偏移，桌面保留原有拖动手感。
			if hm_item.release_glove(curr_plant_cell, physical_position, drag_threshold):
				cancel_glove()
	else:
		return
	get_viewport().set_input_as_handled()


## 移动平台经过静止鼠标时同样重新拾取；菜单/卡槽等 GUI 优先，不穿透界面种植。
func _refresh_board_hover(force_refresh: bool = false) -> void:
	if not is_instance_valid(main_game) or main_game.board == null or not main_game.board.configured:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control() # GUI 遮挡优先。
	var candidate: PlantCell = main_game.board.pick_cell(BattleEnvironmentLens.mouse_position(main_game)) # 与完整画面的折射及原版按钮使用同一鼠标映射。
	if hovered != null and not hovered.get_parent() is PlantCell and not hovered is PlantCell:
		# 按键选卡时，GUI 可能还缓存着上一次空手时命中的掉落按钮。
		if not hovered.get_parent().is_in_group(&"touch_collectibles") or not has_active_board_action():
			candidate = null
	if candidate == curr_plant_cell and not force_refresh:
		return
	if candidate != curr_plant_cell and is_instance_valid(curr_plant_cell):
		match curr_hm_status:
			E_HandManagerStatus.Null: hm_null.mouse_exit(curr_plant_cell)
			E_HandManagerStatus.Character: hm_character.mouse_exit(curr_plant_cell)
			E_HandManagerStatus.Item: hm_item.mouse_exit(curr_plant_cell)
	curr_plant_cell = candidate
	if candidate != null:
		match curr_hm_status:
			E_HandManagerStatus.Null: hm_null.mouse_enter(candidate)
			E_HandManagerStatus.Character: hm_character.mouse_enter(candidate)
			E_HandManagerStatus.Item: hm_item.mouse_enter(candidate)
