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
## 与主菜单共用左上角档案头像框。
const ProfileHud = preload("res://scripts/adventure/ui/adventure_profile_hud.gd")
## 悬停预览面板，挂在画布上随地图一起缩放。
const PreviewPanel = preload("res://scripts/adventure/ui/stage_preview_panel.gd")
## 预览视图模型，把已解析关卡投影成纯展示字典。
const PreviewData = preload("res://scripts/adventure/ui/stage_preview_data.gd")
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
## 悬停关卡的敌人与掉落预览，作为画布上唯一的面板覆盖层。
var preview: Control
## 已解析的关卡配置，首次悬停时读取；解析结果已深拷贝，不污染共享资源。
var _stage_definitions: Dictionary = {}
## 地图上没有难度分流弹窗，挑战总从普通阶段开始。
func is_adventure_toolbar_blocked() -> bool:
	return is_instance_valid(canvas) and canvas.has_node("Intro")

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
	preview = PreviewPanel.new() # 建按钮期间只持有引用，面板最后加入以覆盖节点。
	for stage: Dictionary in layout.stages: # 六个关卡共用同一实现。
		var node := StageButton.new() # 独立贴图按钮与动态文字层。
		node.name = "Stage%d" % stage.id
		canvas.add_child(node)
		var unlocked: bool = AdventureSession.is_unlocked(stage.id)
		var cleared: bool = AdventureStageCatalog.is_cleared(
			Global.global_game_state.adventure_state, AdventureStageRegistry.stage_id(stage.id),
			StagePhaseDefinition.Kind.NORMAL)
		node.configure(stage, unlocked, cleared, _select_stage.bind(stage.id))
		if unlocked: # 未解锁关卡不参与悬停预览，按钮自身也不可按下。
			node.mouse_entered.connect(_hover_stage.bind(stage, node, cleared))
			node.mouse_exited.connect(preview.cancel)
	preview.name = "StagePreview"
	canvas.add_child(preview)
	var profile_hud := ProfileHud.new() # 直接贴在视口左上角，返回按钮随头像框定位。
	add_child(profile_hud)
	profile_hud.add_action("返回主菜单", _return_menu)
	resized.connect(_fit_canvas)
	_fit_canvas()
	if AdventureSession.progress.started and not AdventureSession.progress.intro_completed:
		var intro := Intro.new() # 首次未完成的引导覆盖层。
		intro.name = "Intro"
		profile_hud.hide()
		intro.tree_exited.connect(profile_hud.show)
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

## 单一关卡入口；解锁与入场条件由按钮状态和会话入口判定。
func _select_stage(stage_id: int) -> void:
	if AdventureSession.is_unlocked(stage_id):
		AdventureSession.enter_stage(stage_id)

## 悬停节点时投影本关配置；未通关的关卡由视图模型降级为问号占位。
## [param stage] 为 layout.json 条目，[param node] 提供面板锚点，[param cleared] 来自本轮已算好的进度。
func _hover_stage(stage: Dictionary, node: Control, cleared: bool) -> void:
	var definition: StageDefinition = _stage_definition(int(stage.id))
	preview.request(PreviewData.build(definition, str(stage.name), cleared),
		Rect2(node.position, node.size))

## 首次悬停才解析关卡；失败结果同样缓存，避免每次悬停重复读盘与重复报错。
func _stage_definition(stage_number: int) -> StageDefinition:
	if not _stage_definitions.has(stage_number):
		_stage_definitions[stage_number] = AdventureStageCatalog.load_stage(stage_number)
	return _stage_definitions[stage_number]

## 经复用遮幕返回原有菜单；只增加表现时序，保留进度、音乐和原返回目的地。
func _return_menu() -> void:
	AdventureSession.adventure_active = false
	$SceneTransition.change_scene("res://scenes/main/01StartMenuV8.tscn")
