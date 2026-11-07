## Single entry-point scene for the laboratory. Owns a full-bleed animated
## background and the reusable research panel; no crafting data or save mutation.
extends Control
class_name AdventureResearchLabStage

signal closed

const Background = preload("res://scripts/adventure/research_lab_background.gd")
const ResearchWindow = preload("res://scripts/adventure/ui/research_window.gd")

var _background: Node2D
var _window: AdventureResearchWindow
var _closing := false

func _ready() -> void:
	name = "ResearchLabStage"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_background = Background.new()
	# Entire environment, including high-depth motes, stays behind the UI.
	_background.z_index = -20
	_background.name = "GreenhouseBackgroundFX"
	add_child(_background)
	_window = ResearchWindow.new()
	_window.name = "ResearchPanel"
	_window.with_background = true
	_window.transition_root = self # 背景和面板继承同一层的透明度，共用进出动画。
	add_child(_window)
	_window.closed.connect(_on_window_closed)
	resized.connect(_layout_background)
	get_viewport().size_changed.connect(_layout_background)
	_layout_background()

func _layout_background() -> void:
	if not is_instance_valid(_background):
		return
	var dimensions := get_viewport().get_visible_rect().size
	if dimensions.x <= 0.0 or dimensions.y <= 0.0:
		return
	var factor := maxf(dimensions.x / Background.CANVAS_SIZE.x,
		dimensions.y / Background.CANVAS_SIZE.y)
	_background.scale = Vector2.ONE * factor
	_background.position = (dimensions - Background.CANVAS_SIZE * factor) * 0.5

## 响应外部工具栏关闭请求，沿用入口已播放的按键音。
func request_close() -> void:
	if not _closing and is_instance_valid(_window):
		_window.request_close(false)

## 将教学的 [param recipe_id] 交给窗口选择，返回真实合成按钮。
func guide_recipe(recipe_id: String) -> Control:
	return _window.guide_recipe(recipe_id) if is_instance_valid(_window) else null

func _on_window_closed() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
