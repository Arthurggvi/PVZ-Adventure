## 原版图鉴索引；Boss 入口复用冒险图鉴的独立 Boss 页面。
extends Control
class_name MainAlmanac

## 双阶段 Boss 图鉴窗口，与工具栏入口共用同一实现。
const BossAlmanac = preload("res://scripts/adventure/ui/almanac_window.gd")
## 当前 Boss 窗口；重复点击不创建叠加实例。
var _boss_almanac: Control

#region 主要页面
@onready var start_page: TextureRect = $StartPage
@onready var plant_page: AlmanacPlantPage = $PlantPage
@onready var zombie_page: AlmanacZombiePage = $ZombiePage

#endregion


func _ready() -> void:
	_on_return_button_pressed()
	_build_boss_entry()

	Global.global_read_data.ensure_almanac_loaded()

	plant_page.init_almanac_page()
	zombie_page.init_almanac_page()

## 在索引下方加入独立 Boss 入口，不移动原有植物与僵尸入口。
func _build_boss_entry() -> void:
	var button := Button.new() # 原版图鉴主题提供基础按钮样式。
	button.text = "查看 Boss"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 24)
	start_page.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	button.position += Vector2(-110, -145)
	button.size = Vector2(220, 48)
	button.pressed.connect(_on_boss_button_pressed)

## 打开 Boss 专页；关闭后留在当前索引，不切换主场景或发现记录。
func _on_boss_button_pressed() -> void:
	if is_instance_valid(_boss_almanac):
		return
	var window := BossAlmanac.new() # 入树前指定独立 Boss 模式。
	window.boss_only = true
	window.closed.connect(_on_boss_page_closed)
	_boss_almanac = window
	add_child(window)

## 窗口完成关闭时清除引用，允许再次从索引打开。
func _on_boss_page_closed() -> void:
	_boss_almanac = null

## 返回开始菜单
func _on_exit_button_pressed() -> void:
	## 如果当前场景为图鉴场景
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu])
	## 从其余场景进入图鉴场景
	else:
		queue_free()

## 查看植物图鉴
func _on_plant_button_pressed() -> void:
	start_page.visible = false
	plant_page.visible = true
	zombie_page.visible = false

## 查看僵尸图鉴
func _on_zombie_button_pressed() -> void:
	start_page.visible = false
	plant_page.visible = false
	zombie_page.visible = true

## 返回图鉴索引
func _on_return_button_pressed() -> void:
	start_page.visible = true
	plant_page.visible = false
	zombie_page.visible = false

