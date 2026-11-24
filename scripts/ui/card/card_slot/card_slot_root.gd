extends Control
class_name CardSlotRoot

## 卡片
var curr_cards:Array[Card]
## 铲子
@onready var ui_shovel: UIShovel = %UIShovel
## 手套按钮同时维护点击、冷却和选中状态。
@onready var _glove_button: Button = %BattleGloveButton
## 铲子槽右下角显示当前绑定。
@onready var _shovel_key: Label = %UIShovel/Label
## 手套槽右下角显示当前绑定。
@onready var _glove_key: Label = %BattleGloveButton/ShortcutKey
## 实战的阳光槽、卡槽和工具排成一行；选卡容器仍使用各自的布局。
@onready var _battle_bar: HBoxContainer = $BattleBar
## 选卡和准备阶段的场景原点，单位为战斗画布像素。
var _selection_x: float = 0.0
## 进入正式战斗时，为头像框预留空间后的卡栏最小左边界。
var _combat_left: float = 0.0
## 右侧速度按钮的左边缘，为长卡栏保留操作空间。
var _right_tool: Control
## 是否正在使用实战卡栏布局。
var _combat_layout: bool = false

## 仅桌面战斗栏读取实体键盘布局；移动端保留可触摸的工具图标。
func _ready() -> void:
	if OS.has_feature("mobile"):
		_shovel_key.hide()
		_glove_key.hide()
		ui_shovel.get_node("Button").tooltip_text = ""
		_glove_button.tooltip_text = ""
		return
	Global.config_service.tool_shortcuts_changed.connect(_refresh_tool_keys)
	_refresh_tool_keys()

## [param left_edge] 为实战卡栏最小起点，[param right_tool] 提供长卡栏的右端限位。
## 在卡槽装配前由战斗宿主调用一次，选卡阶段保留场景原点和原始缩放。
func configure_battle_layout(left_edge: float, right_tool: Control) -> void:
	_selection_x = position.x
	_combat_left = left_edge
	_right_tool = right_tool
	_battle_bar.minimum_size_changed.connect(_fit_battle_bar)
	_right_tool.item_rect_changed.connect(_fit_battle_bar)

## [param active] 表示进入正式战斗，向右避开头像；选卡和准备阶段恢复原始位置。
func use_combat_layout(active: bool) -> void:
	_combat_layout = active
	position.x = maxf(_selection_x, _combat_left) if active else _selection_x
	if active:
		_fit_battle_bar()
	else:
		_battle_bar.scale = Vector2.ONE

## 卡槽或工具超出剩余宽度时等比缩放整排，保留全部卡位与点击热区。
func _fit_battle_bar() -> void:
	if not _combat_layout or not is_instance_valid(_right_tool):
		return
	var available: float = maxf(1.0, _right_tool.global_position.x - _battle_bar.global_position.x - 6.0) # 战斗逻辑像素，右端留空。
	var natural: float = maxf(1.0, _battle_bar.get_combined_minimum_size().x) # 动态涵盖满卡位、翻页按钮和可见工具。
	_battle_bar.scale = Vector2.ONE * minf(1.0, available / natural)

## 跟随当前档案更新两项工具的键帽和鼠标提示。
func _refresh_tool_keys() -> void:
	_shovel_key.text = Global.config_service.get_tool_shortcut_label(ConfigService.SHOVEL_ACTION)
	_glove_key.text = Global.config_service.get_tool_shortcut_label(ConfigService.GLOVE_ACTION)
	ui_shovel.get_node("Button").tooltip_text = "铲子（%s）" % _shovel_key.text
	_glove_button.tooltip_text = "手套（%s）" % _glove_key.text

## 用界面未消耗的键盘事件 [param event] 操作战斗工具或选择数字卡槽。
func _unhandled_key_input(event: InputEvent) -> void:
	if handle_tool_shortcut(event):
		return
	for slot: int in range(1, 11): # 数字 1 到 0 依次对应十个出战卡位。
		if event.is_action_pressed("ShortcutKeys_Card%d" % slot):
			if slot <= curr_cards.size():
				curr_cards[slot - 1]._on_button_pressed()
			return

## 将键盘或鼠标侧键 [param event] 交给工具按钮；匹配工具动作时返回 true，可使用时消费输入。
func handle_tool_shortcut(event: InputEvent) -> bool:
	if event.is_action_pressed(ConfigService.SHOVEL_ACTION, false, true):
		if _can_use_tool_shortcuts() and ui_shovel.is_visible_in_tree() and ui_shovel.shovel.visible:
			ui_shovel._on_button_pressed()
			get_viewport().set_input_as_handled()
		return true
	if event.is_action_pressed(ConfigService.GLOVE_ACTION, false, true):
		if _can_use_tool_shortcuts() and _glove_button.is_visible_in_tree() and not _glove_button.disabled:
			_glove_button.pressed.emit()
			get_viewport().set_input_as_handled()
		return true
	return false

## 仅在当前战斗可操作时接收工具键，避免轮间过渡或暂停期间选中道具。
func _can_use_tool_shortcuts() -> bool:
	var game: MainGameManager = Global.main_game # 卡栏所属的当前战斗。
	return is_instance_valid(game) and get_tree().current_scene == game \
		and game.main_game_progress == MainGameManager.E_MainGameProgress.MAIN_GAME \
		and not get_tree().paused and not PVZCheat.is_open()
