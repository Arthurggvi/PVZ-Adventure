## v6 美术装配继承原菜单，保留同一套玩家档案和辅助功能。
extends StartMenuRoot

## 美术与原生导航控件共享的设计尺寸。
const DESIGN_SIZE := Vector2(1920, 1080)
## 唯一的分层设计画布。
@onready var art_canvas: Control = $ArtCanvas

## 替换旧视觉并接入原控件；菜单音乐由正式V8入口负责，不调用旧版启动逻辑。
func _ready() -> void:
	AdventureSession.adventure_active = false
	Global.time_scale = 1.0
	Engine.time_scale = 1.0
	# 原玩家面板、设置和帮助弹窗始终绘制在美术画布上方。
	move_child(art_canvas, 0)
	for path: String in ["BG", "Cloud", "BG_Left", "BG_Right", "BG_Center"]: # 旧美术不再参与绘制或输入。
		get_node(path).hide()
	art_canvas.theme = preload("res://scripts/adventure/island_ui.gd").make_theme()
	# 玩家名牌及其原始按钮整体保留在安全区，既有信号连接保持不变。
	$WoodSign.reparent(art_canvas)
	_layout_native_profile()
	# 原设置、帮助、退出控件移至画布右下，保持其原有菜单处理方法。
	var options: Control = $BG_Right/Option
	options.reparent(art_canvas)
	options.set_anchors_preset(Control.PRESET_TOP_LEFT)
	options.position = Vector2(1510, 850)
	options.scale = Vector2(1.5, 1.5)
	options.show()
	SoundManager.setup_ui_start_menu_sound(self)
	resized.connect(_fit_canvas)
	_fit_canvas()

## 保留原档案按钮、玩家名 Label 及全部信号，仅将旧装饰紧凑排列在安全区。
func _layout_native_profile() -> void:
	var profile: Control = $ArtCanvas/WoodSign # 原生名牌，仍由其脚本更新玩家名。
	var name_label: Label = profile.label # 原生玩家名 Label，不复制身份状态。
	var button: TextureButton = profile.get_node("ButtonUserUpdate") # 原生档案选择按钮。
	for child: CanvasItem in profile.get_children(): # 隐藏原吊牌装饰，不删除其节点。
		child.hide()
	profile.position = Vector2(22, 12)
	button.position = Vector2.ZERO
	button.size = Vector2(430, 82)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.texture_normal = load("res://assets/image/ui/ui_main_game_menu/UI_BG/button_BG.png")
	button.texture_hover = button.texture_normal
	button.texture_pressed = button.texture_normal
	button.texture_click_mask = null
	button.tooltip_text = ""
	button.show()
	name_label.reparent(button)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_label.label_settings = name_label.label_settings.duplicate()
	name_label.label_settings.font_size = 32
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

## 按视口统一等比缩放，所有图层和原生控件共用同一变换。
func _fit_canvas() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y) # 16:9 设计画布的统一倍率。
	art_canvas.scale = Vector2.ONE * factor
	art_canvas.position = (size - DESIGN_SIZE * factor) / 2
