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
## 复用的环境场景，位于背景与关卡按钮之间。
const ENVIRONMENT = preload("res://scenes/environment/zombie_island_fx.tscn")
## 总环境开关，关闭后停止内部动画与气泡。
@export var environment_fx_enabled := true:
	set(value):
		environment_fx_enabled = value
		if is_node_ready() and is_instance_valid(environment):
			_apply_environment()
## 去云候选可随时回退到原背景；回退同时停云，保留其他效果。
@export var use_clean_sky := true:
	set(value):
		use_clean_sky = value
		if is_node_ready() and is_instance_valid(environment):
			_apply_environment()
## 与设计画布共享坐标的环境节点。
var environment: Node2D
## 背景节点引用，方便Inspector开关实时回退。
var background: TextureRect
## 背景、按钮和引导共同挂载的设计画布。
var canvas: Control
## 一次性结果和锁定提示。
var notice_label: Label
## 仅在实际有结果或点击提示时显示的底部面板。
var notice_panel: Panel
## 每次选择关卡时建立阶段窗口，属于地图 UI，不持久化。
var phase_dialog: ConfirmationDialog

## 读取素材布局，建立独立显示层并恢复首次引导。
func _ready() -> void:
	# 编辑器直接运行地图也不得绕过原生档案入口。
	if AdventureSession.progress == null:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main/01StartMenuV8.tscn")
		return
	AdventureSession.adventure_active = true
	SoundManager.play_town_bgm()
	theme = UI.make_theme()
	canvas = Control.new()
	canvas.name = "MapCanvas"
	canvas.size = DESIGN_SIZE
	add_child(canvas)
	# 背景纹理与节点都在同一设计空间，由外层等比缩放。
	background = TextureRect.new()
	background.texture = load(ASSET_ROOT + "map/zombie_island_background_1920x1080.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background.size = DESIGN_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(background)
	environment = ENVIRONMENT.instantiate()
	canvas.add_child(environment)
	_apply_environment()
	# 只读取布局配置，不改动原 PNG，也不画节点路线。
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSET_ROOT + "layout.json"))
	for stage: Dictionary in layout.stages: # 六个关卡共用同一实现。
		var node := StageButton.new() # 独立贴图按钮与动态文字层。
		node.name = "Stage%d" % stage.id
		canvas.add_child(node)
		var cleared: bool = AdventureStageCatalog.is_cleared(
			Global.global_game_state.adventure_state, AdventureStageRegistry.stage_id(stage.id),
			StagePhaseDefinition.Kind.NORMAL)
		node.configure(stage, AdventureSession.is_unlocked(stage.id), cleared, _select_stage.bind(stage.id))
	UI.official_button(canvas, "返回主菜单", Rect2(40, 30, 270, 66), _return_menu)
	# 底部提示独立面板，避免白色文字压在复杂背景上。
	notice_panel = Panel.new()
	notice_panel.position = Vector2(340, 988)
	notice_panel.size = Vector2(1240, 70)
	notice_panel.add_theme_stylebox_override("panel", UI.panel_style(Color("1f332ded")))
	notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(notice_panel)
	notice_label = UI.label(notice_panel, "", Rect2(15, 0, 1210, 70), 28)
	_show_notice(AdventureSession.notice)
	AdventureSession.notice = ""
	resized.connect(_fit_canvas)
	_fit_canvas()
	if AdventureSession.progress.started and not AdventureSession.progress.intro_completed:
		var intro := Intro.new() # 首次未完成的引导覆盖层。
		intro.name = "Intro"
		canvas.add_child(intro)

## 整个画布一起缩放并居中，非16:9窗口留边，不拉伸背景。
func _fit_canvas() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y) # 统一缩放比例。
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - DESIGN_SIZE * factor) / 2

## 在同一1920×1080空间中替换候选引用，不改变地图、按钮或存档状态。
func _apply_environment() -> void:
	background.texture = load("res://assets/adventure/environment_fx/v1/sky_cleanup_v1/backgrounds/zombie_island_sky_clean_1920x1080.png" if use_clean_sky else ASSET_ROOT + "map/zombie_island_background_1920x1080.png")
	environment.set_flags(environment_fx_enabled, use_clean_sky)

## [param stage_id] 为配置中的关卡编号；锁定和待实现节点只给提示。
func _select_stage(stage_id: int) -> void:
	if not AdventureSession.is_unlocked(stage_id):
		_show_notice("请先通关前一关普通阶段。")
	else:
		_open_phase_dialog(stage_id)

## 两阶段选择窗只负责交互，真实解锁条件由关卡目录统一验证。
func _open_phase_dialog(stage_id: int) -> void:
	if phase_dialog != null and is_instance_valid(phase_dialog):
		phase_dialog.queue_free()
	var state: AdventureState = Global.global_game_state.adventure_state
	var inventory: AdventureInventoryService = Global.adventure_inventory
	var normal_error := AdventureStageCatalog.entry_error(stage_id, StagePhaseDefinition.Kind.NORMAL, state, inventory)
	var nightmare_error := AdventureStageCatalog.entry_error(stage_id, StagePhaseDefinition.Kind.NIGHTMARE, state, inventory)
	phase_dialog = ConfirmationDialog.new()
	phase_dialog.title = AdventureStageRegistry.display_name(stage_id) + " · 挑战阶段"
	phase_dialog.dialog_text = "普通阶段：%s\n噩梦阶段：%s" % [
		"可进入" if normal_error.is_empty() else normal_error,
		"可进入" if nightmare_error.is_empty() else nightmare_error]
	phase_dialog.get_ok_button().text = "普通阶段"
	phase_dialog.get_ok_button().disabled = not normal_error.is_empty()
	var nightmare_button: Button = phase_dialog.add_button("噩梦阶段", true, "nightmare")
	nightmare_button.disabled = not nightmare_error.is_empty()
	add_child(phase_dialog)
	phase_dialog.confirmed.connect(func(): _enter_selected_phase(stage_id, StagePhaseDefinition.Kind.NORMAL))
	phase_dialog.custom_action.connect(_on_phase_custom_action.bind(stage_id))
	phase_dialog.popup_centered(Vector2i(640, 230))

func _on_phase_custom_action(action: StringName, stage_id: int) -> void:
	if action == &"nightmare":
		_enter_selected_phase(stage_id, StagePhaseDefinition.Kind.NIGHTMARE)

func _enter_selected_phase(stage_id: int, kind: int) -> void:
	if not AdventureSession.enter_stage(stage_id, kind):
		_show_notice(AdventureSession.error_message)

## [param message] 为实际结果或点击提示；空消息隐藏面板，不显示常驻说明。
func _show_notice(message: String) -> void:
	notice_label.text = message
	notice_panel.visible = not message.is_empty()

## 经复用遮幕返回原有菜单；只增加表现时序，保留进度、音乐和原返回目的地。
func _return_menu() -> void:
	$SceneTransition.change_scene("res://scenes/main/01StartMenuV8.tscn")
