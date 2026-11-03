## 独立纸质地区选择界面，只展示目录、处理输入并向宿主发出导航意图。
extends Control

## [param destination_id] 为稳定地区 ID；宿主再次校验并调用既有安全入口。
signal destination_selected(destination_id: String)
## X 与 ESC 共用关闭意图，不主动切换到任何旧菜单。
signal close_requested
## 唯一布局适配器，不承担玩家或存档管理。
const Catalog = preload("res://scripts/adventure/destination_catalog.gd")
## 可编辑、可复用的单地区组件。
const CARD = preload("res://scenes/adventure/DestinationCard.tscn")
## 复用现有冒险中文主题。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 已加载的展示目录；失败时保持空并显示错误。
var layout: Dictionary = {}
## 在信号和场景切换间避免重复请求。
var _routing := false
## 等比变换的唯一设计画布。
@onready var canvas: Control = $DesignCanvas

## 装配场景现有图层，仅卡片列表按目录实例化；打开本页不加载或初始化进度。
func _ready() -> void:
	theme = UI.make_theme()
	var catalog := Catalog.new() # 本界面独立、无全局状态的配置读取器。
	layout = catalog.load_layout()
	if layout.is_empty():
		show_entry_error(catalog.error_message)
		return
	canvas.size = Vector2(layout.logical_canvas[0], layout.logical_canvas[1])
	_apply_rect($DesignCanvas/Paper, layout.paper.rect)
	$DesignCanvas/Paper.texture = load(Catalog.ROOT + layout.paper.asset)
	_apply_rect($DesignCanvas/Close, layout.close.rect)
	$DesignCanvas/Close.texture_normal = load(Catalog.ROOT + layout.close.assets.normal)
	$DesignCanvas/Close.texture_hover = load(Catalog.ROOT + layout.close.assets.hover)
	$DesignCanvas/Close.texture_pressed = load(Catalog.ROOT + layout.close.assets.pressed)
	$DesignCanvas/Close.texture_focused = $DesignCanvas/Close.texture_hover
	var focusable: Array[Control] = [] # 显式焦点环阻止 Tab 或方向键落入底层菜单。
	for destination: Dictionary in layout.destinations: # 新增地图只增加配置，复用同一场景。
		var card := CARD.instantiate() as TextureButton # 当前地区唯一组件。
		card.name = destination.id
		canvas.get_node("Cards").add_child(card)
		card.configure(destination, layout.card)
		card.pressed.connect(_select_destination.bind(destination.id))
		if not card.disabled:
			focusable.append(card)
	focusable.append($DesignCanvas/Close)
	for index: int in range(focusable.size()): # Tab、方向键和手柄都限制在开放卡片及关闭按钮内。
		var current: Control = focusable[index] # 当前焦点节点。
		var previous: NodePath = current.get_path_to(focusable[posmod(index - 1, focusable.size())]) # 前一个可用控件。
		var next: NodePath = current.get_path_to(focusable[(index + 1) % focusable.size()]) # 后一个可用控件。
		current.focus_previous = previous
		current.focus_next = next
		current.focus_neighbor_left = previous
		current.focus_neighbor_top = previous
		current.focus_neighbor_right = next
		current.focus_neighbor_bottom = next
	resized.connect(_fit_canvas)
	_fit_canvas()
	focusable[0].grab_focus()
	SoundManager.play_town_bgm()

## [param destination_id] 只有在加载目录和代码注册中同时开放才可选择。
func can_select(destination_id: String) -> bool:
	for destination: Dictionary in layout.get("destinations", []): # 不接受 JSON 外部或伪造地区。
		if destination.id == destination_id:
			return Catalog.can_enter(destination)
	return false

## [param destination_id] 为按钮配置的稳定 ID；只发出意图，绝不自行创建进度。
func _select_destination(destination_id: String) -> void:
	if _routing or not can_select(destination_id):
		return
	_routing = true
	destination_selected.emit(destination_id)

## [param message] 为布局或既有入口报告的真实错误；允许关闭后安全重试。
func show_entry_error(message: String) -> void:
	_routing = false
	$EntryError.dialog_text = message
	$EntryError.popup_centered(Vector2i(620, 160))

## 同时缩放所有视觉和交互矩形；非16:9视口自动留边。
func _fit_canvas() -> void:
	var factor := minf(size.x / canvas.size.x, size.y / canvas.size.y) # 全画布共享等比倍率。
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - canvas.size * factor) / 2

## 将 [param values] 指定的完整设计矩形应用到 [param control]。
func _apply_rect(control: Control, values: Array) -> void:
	control.position = Catalog.rect(values).position
	control.size = Catalog.rect(values).size

## X 和取消键共用同一路径，重复关闭请求由宿主管理生命周期。
func _close() -> void:
	if not _routing:
		close_requested.emit()

## [param event] 是未被按钮或错误窗口消费的输入；ESC/手柄取消返回原菜单。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
