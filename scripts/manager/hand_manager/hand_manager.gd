extends MainGameSubManager
## 管理手持角色（植物、僵尸）及战斗道具。
## 类似状态机
class_name HandManager

@onready var hm_character: HM_Character = $HM_Character
@onready var hm_item: HM_Item = $HM_Item
@onready var hm_null: HM_NUll = $HM_Null

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
	## 如果当前在植物格子中
	if curr_plant_cell:
		_on_cell_mouse_enter(curr_plant_cell)

## 点击ui铲子
func _click_shovel() -> void:
	SoundManager.play_other_SFX("shovel")
	curr_hm_status = E_HandManagerStatus.Item
	hm_item.click_shovel()
	## 如果当前在植物格子中
	if curr_plant_cell:
		_on_cell_mouse_enter(curr_plant_cell)

## 点击图标切换手套；同一局中卡片、铲子和手套由同一个手持状态互斥管理。
func _click_glove() -> void:
	if not main_game.has_battle_glove() or main_game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME \
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

## 返回当前手持道具是否是手套，供取消操作和玉米加农炮输入分流。
func is_holding_glove() -> bool:
	return curr_hm_status == E_HandManagerStatus.Item and hm_item.curr_hm_item_status == HM_Item.E_HmItemStatus.Glove

## 结束手套交互并撤销其高亮；其他道具和卡片沿用原手持状态。
func cancel_glove() -> void:
	if is_holding_glove():
		curr_hm_status = E_HandManagerStatus.Null

## 鼠标点击cell
func _on_click_cell(plant_cell:PlantCell):
	_refresh_board_hover()
	if plant_cell != curr_plant_cell or not is_instance_valid(plant_cell):
		return
	match curr_hm_status:
		E_HandManagerStatus.Null:
			hm_null.click_cell(plant_cell)
		E_HandManagerStatus.Character:
			hm_character.click_cell(plant_cell)
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

## 取消角色和道具
func _input(event):
	if event is InputEventMouseButton:
		_refresh_board_hover()
	## 当前手持状态不为空且鼠标点击事件
	if curr_hm_status != E_HandManagerStatus.Null and event is InputEventMouseButton:
		var on_glove_button: bool = is_holding_glove() \
			and get_viewport().gui_get_hovered_control() == main_game.battle_glove_button # 再点图标由按钮自己的切换入口取消。
		## 右键点击 或左鍵点击空白
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed or\
		event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not curr_plant_cell and not on_glove_button:
			SoundManager.play_other_SFX("tap2")
			curr_hm_status = E_HandManagerStatus.Null


## 移动平台经过静止鼠标时同样重新拾取；菜单/卡槽等 GUI 优先，不穿透界面种植。
func _refresh_board_hover(force_refresh: bool = false) -> void:
	if not is_instance_valid(main_game) or main_game.board == null or not main_game.board.configured:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control() # GUI 遮挡优先。
	var candidate: PlantCell = main_game.board.pick_cell(main_game.get_global_mouse_position()) # 与按钮一致的地块顺序。
	if hovered != null and not hovered.get_parent() is PlantCell and not hovered is PlantCell:
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
