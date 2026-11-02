## 六节点世界地图，背景与节点共享 1920×1080 等比坐标系。
extends Control

## 固定设计尺寸，不随窗口改变节点的归一化中心。
const DESIGN_SIZE := Vector2(1920, 1080)
## 地图素材根路径。
const ASSET_ROOT := "res://assets/adventure/zombie_island/"
## 地图节点实现。
const StageButton = preload("res://scripts/adventure/island_stage_button.gd")
## 引导实现。
const Intro = preload("res://scripts/adventure/island_intro.gd")
## UI 构造工具。
const UI = preload("res://scripts/adventure/island_ui.gd")
## 背景、按钮和引导共同挂载的设计画布。
var canvas: Control
## 一次性结果和锁定提示。
var notice_label: Label
## 持有初始卡的界面提示。
var cards_label: Label

## 读取素材布局，建立独立显示层并恢复首次引导。
func _ready() -> void:
	# 编辑器直接运行地图也不得绕过原生档案入口。
	if AdventureSession.progress == null:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main/01StartMenu.tscn")
		return
	AdventureSession.adventure_active = true
	theme = UI.make_theme()
	canvas = Control.new()
	canvas.name = "MapCanvas"
	canvas.size = DESIGN_SIZE
	add_child(canvas)
	# 背景纹理与节点都在同一设计空间，由外层等比缩放。
	var background := TextureRect.new()
	background.texture = load(ASSET_ROOT + "map/zombie_island_background_1920x1080.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background.size = DESIGN_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	# 只读取布局配置，不改动原 PNG，也不画节点路线。
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSET_ROOT + "layout.json"))
	for stage: Dictionary in layout.stages: # 六个关卡共用同一实现。
		var node := StageButton.new() # 独立贴图按钮与动态文字层。
		node.name = "Stage%d" % stage.id
		canvas.add_child(node)
		node.configure(stage, AdventureSession.is_unlocked(stage.id), stage.id == 1 and AdventureSession.progress.stage_1_cleared, _select_stage.bind(stage.id))
	UI.button(canvas, "返回主菜单", Rect2(40, 30, 270, 66), _return_menu)
	cards_label = UI.label(canvas, "", Rect2(1090, 32, 780, 60), 30)
	# 底部提示独立面板，避免白色文字压在复杂背景上。
	var footer := Panel.new()
	footer.position = Vector2(340, 988)
	footer.size = Vector2(1240, 70)
	footer.add_theme_stylebox_override("panel", UI.panel_style(Color("1f332ded")))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(footer)
	notice_label = UI.label(footer, AdventureSession.notice, Rect2(15, 0, 1210, 70), 28)
	AdventureSession.notice = ""
	_update_cards()
	resized.connect(_fit_canvas)
	_fit_canvas()
	if AdventureSession.progress.started and not AdventureSession.progress.intro_completed:
		var intro := Intro.new() # 首次未完成的引导覆盖层。
		intro.name = "Intro"
		canvas.add_child(intro)
		intro.completed.connect(_update_cards)

## 整个画布一起缩放并居中，非16:9窗口留边，不拉伸背景。
func _fit_canvas() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y) # 统一缩放比例。
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - DESIGN_SIZE * factor) / 2

## [param stage_id] 为配置中的关卡编号；锁定和待实现节点只给提示。
func _select_stage(stage_id: int) -> void:
	if not AdventureSession.is_unlocked(stage_id):
		notice_label.text = "通关草坪后开放没落营地。" if stage_id == 2 else "此区域尚未开放，后续章节继续探索。"
	elif stage_id != 1:
		notice_label.text = "没落营地已开放，战斗将在后续阶段实装。"
	else:
		AdventureSession.enter_lawn()

## 状态提示只显示当前所有权，不重复赠卡。
func _update_cards() -> void:
	cards_label.text = "初始卡：向日葵 ×1   豌豆射手 ×1" if not AdventureSession.progress.cards.is_empty() else ""
	if notice_label.text.is_empty():
		notice_label.text = "点击草坪，开始冒险。"

## 返回原有菜单，保留已完成或进行中的独立进度。
func _return_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main/01StartMenu.tscn")
