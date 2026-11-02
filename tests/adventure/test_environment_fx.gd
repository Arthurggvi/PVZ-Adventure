## 环境层的短时加载、开关与输入检查；仅允许在隔离APPDATA运行，不生成截图。
extends Node

## 内存进度只用于加载地图，不调用任何保存接口。
const Progress = preload("res://scripts/adventure/island_progress.gd")

## 保留驱动节点，使真实场景切换不会释放检查协程。
func _ready() -> void:
	assert(OS.get_user_data_dir().contains("fx-test-user"))
	get_tree().current_scene = null
	get_tree().create_timer(20).timeout.connect(func():
		push_error("FAIL: environment check timed out")
		get_tree().quit(1))
	_run.call_deferred()

## 各场景只短时运行；不验证美术观感，也不改写玩家进度。
func _run() -> void:
	get_tree().change_scene_to_file("res://scenes/main/01StartMenuV8.tscn")
	await _frames()
	var menu: Control = get_tree().current_scene # 正式主菜单。
	var layer: Node2D = menu.get_node("ArtCanvas/EnvironmentFX") # 环境层先于主体与按钮绘制。
	assert(layer.effects.size() == 17)
	assert(layer.get_index() < menu.art_canvas.get_node("ship").get_index())
	assert(menu.art_canvas.get_node("CrowFlyby") != null)
	_check_effects(layer)
	var ship: Control = menu.art_canvas.get_node("ship") # 只让现有船体美术浮动。
	var button: TextureButton = menu.art_canvas.get_node("ship_button") # 点击区域保持固定。
	var button_position := button.position # 动画前的按钮位置。
	layer._process(1.0)
	assert(ship.position != layer.ship_origin and button.position == button_position)
	menu.environment_fx_enabled = false
	assert(ship.position == layer.ship_origin and not layer.is_processing())
	for effect in layer.effects: # 总开关关闭后无可见粒子或内部帧动画。
		assert(not effect.visible and not effect.is_playing())
	menu.environment_fx_enabled = true
	menu.use_clean_sky = false
	assert(menu.art_canvas.get_node("coastal_yard").texture.resource_path.ends_with("v6/background/coastal_yard.png"))
	assert(not layer.get_node("Cloud0").visible)
	menu.use_clean_sky = true
	# 通过环境层上方的真实功能台输入确认其不截断GUI事件。
	var help: TextureButton = menu.art_canvas.get_node("help_button") # 原生帮助功能入口。
	var click := InputEventMouseButton.new() # 真实视口鼠标输入。
	click.position = help.get_global_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await _frames()
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await get_tree().create_timer(0.35).timeout
	assert(menu.get_node("Dialog_Help").visible)
	# 地图读取测试内存状态，不创建/迁移任何玩家文件。
	AdventureSession.progress = Progress.new("user://fx-unused/zombie_island_v1.json")
	AdventureSession.progress.started = true
	AdventureSession.progress.intro_completed = true
	AdventureSession.progress.cards = {"sunflower": 1, "peashooter": 1}
	get_tree().change_scene_to_file("res://scenes/adventure/zombie_island.tscn")
	await _frames()
	var island: Control = get_tree().current_scene # 正式地图与真实关卡按钮。
	layer = island.environment
	assert(layer.effects.size() == 22)
	assert(layer.get_index() < island.canvas.get_node("Stage1").get_index())
	_check_effects(layer)
	assert(not island.canvas.get_node("Stage1").disabled)
	for index: int in range(2, 7): # 锁定节点仍禁止鼠标与键盘触发。
		var stage: TextureButton = island.canvas.get_node("Stage%d" % index) # 当前关卡按钮。
		assert(stage.disabled and stage.focus_mode == Control.FOCUS_NONE)
	island.use_clean_sky = false
	assert(not layer.get_node("Cloud0").visible)
	assert(island.background.texture.resource_path.ends_with("map/zombie_island_background_1920x1080.png"))
	island.use_clean_sky = true
	island.environment_fx_enabled = false
	for effect in layer.effects: # 不留下仍运行的帧序列。
		assert(not effect.visible and not effect.is_playing())
	island.environment_fx_enabled = true
	assert(layer.get_node("Cloud0").visible)
	# 正式返回路径释放所有局部效果，不引入额外播放器。
	var old_layer: WeakRef = weakref(layer) # 场景回收后的弱引用。
	var player := SoundManager.bgm_play # 保留原有城镇音乐播放器。
	island._return_menu()
	await _frames()
	assert(old_layer.get_ref() == null)
	assert(SoundManager.bgm_play == player and player.stream.resource_path.ends_with("mus_town.wav"))
	assert(not FileAccess.file_exists("user://fx-unused/zombie_island_v1.json"))
	print("PASS: both FX scenes, textures/masks, switches, GUI input, locked stages, lifecycle and shared town player")
	get_tree().quit()

## [param layer] 为已加载环境层；校验资源、遮罩与无GUI命中的节点类型。
func _check_effects(layer: Node2D) -> void:
	for effect in layer.effects: # 每个固定实例都必须加载到有效贴图。
		assert(effect is AnimatedSprite2D and not effect is Control)
		assert(effect.sprite_frames.get_frame_count("default") > 0)
		assert(effect.sprite_frames.get_frame_texture("default", 0) != null)
		if effect.settings.has("mask"):
			assert(effect.material.get_shader_parameter("region_mask") != null)

## 等待少量帧让场景及GUI布局完成；不作长期动画观察。
func _frames() -> void:
	for index: int in range(3): # 仅覆盖延迟加载与画布布局。
		await get_tree().process_frame
