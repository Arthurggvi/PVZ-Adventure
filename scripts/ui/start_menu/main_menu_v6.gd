## v6 美术装配继承原菜单，保留同一套玩家档案和辅助功能。
extends StartMenuRoot

## 美术与原生导航控件共享的设计尺寸。
const DESIGN_SIZE := Vector2(1920, 1080)
## 与冒险地图共用的档案头像框。
const ProfileHud = preload("res://scripts/adventure/ui/adventure_profile_hud.gd")
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
	$WoodSign.hide()
	var profile_hud := ProfileHud.new() # 独立于居中的场景画布，存档面板仍显示在头像上方。
	profile_hud.theme = art_canvas.theme
	add_child(profile_hud)
	move_child(profile_hud, art_canvas.get_index() + 1)
	profile_hud.add_action("存档", _on_button_update_user_pressed)
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

## 按视口统一等比缩放，所有图层和原生控件共用同一变换。
func _fit_canvas() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y) # 16:9 设计画布的统一倍率。
	art_canvas.scale = Vector2.ONE * factor
	art_canvas.position = (size - DESIGN_SIZE * factor) / 2
