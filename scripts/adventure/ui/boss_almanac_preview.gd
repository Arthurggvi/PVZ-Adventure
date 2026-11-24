## Boss 图鉴舞台；仅运行纯视觉场景，子视口隔离白爵士的屏幕特效。
extends SubViewportContainer

## 本页的 Boss 身份与纯视觉场景映射。
const Data = preload("res://scripts/adventure/ui/boss_almanac_data.gd")
## 共用可见精灵的边界计算。
const Portrait = preload("res://scripts/adventure/ui/almanac_preview.gd")
## 救主的纯原画动画及传送材质接口。
const SaviorVisual = preload("res://scripts/character/zombie_boss/savior/savior_visual.gd")
## 预览视口尺寸，不随图鉴整体缩放而改变动画坐标。
const STAGE_SIZE := Vector2i(390, 300)
## 图鉴跑道的世界长度，约够播放一轮实战冲锋步态。
const CHARGE_DISTANCE: float = 360.0
## 图鉴的一格长度，决定拖影和分路出发间距。
const STAGE_CELL_WIDTH: float = 72.0
## 当前阶段，始终为 1 或 2。
var _phase: int = 1
## 独立视口，屏幕采样只覆盖此区域。
var _viewport: SubViewport
## 角色及一次性视觉特效的共同容器。
var _world: Node2D
## 按角色切换夜间草坪、终末海域或教堂底图。
var _background: TextureRect
## 角色脚底坐标，用于在同一世界比例下移动角色、烟带和拖影。
var _actor: Node2D
## 本次演出的临时特效，重播时整组清理。
var _effects: Node2D
## 沿用实战震动算法的独立镜头。
var _camera: MainGameCamera
## 无位移时的镜头中心，跟随期间保留适量前景和身后拖影。
var _camera_home: Vector2
## 黑将军使用的实战演出组件，白爵士展示时为 null。
var _general: BlackGeneralVisual
## 明灯使用可带召唤物和光圈的实战演出。
var _lantern: MingLanternPresentation
## 救主在第二阶段展示本体及两名分身，共用祷告起手时机。
var _saviors: Array[SaviorVisual] = []
## 本次传送显形，重播、切阶段或离开页面时取消。
var _savior_arrival: Tween
## 读取实战配置的冲锋速度，单位为世界像素每秒。
var _charge_speed: float = 0.0
## 冲锋段的世界停止线。
var _charge_end_x: float = 0.0
## 是否在预览转阶段，第一次传送后应用二阶段外观并启动分路残影。
var _transition := false
## 仍在等待或移动的转阶段分身，急停后交还其原有淡出演出。
var _shadows: Array[BlackGeneralChargeShadow] = []
## 当前纯视觉实例，没有生命组件或技能执行器。
var _visual: Node2D
## 视觉场景自带的原生动画播放器。
var _player: AnimationPlayer
## 当前技能的剩余动作，按顺序播放。
var _clips: Array[StringName] = []
## 当前动作剩余秒数；负值代表待机。
var _remaining: float = -1.0
## 当前动作总秒数，供预览位移使用。
var _duration: float = 1.0
## 只有循环动作由舞台计时结束；单次动作等待原生 animation_finished。
var _looping: bool = false
## 当前动作名，用于有限的舞台位移。
var _clip: StringName = &""
## 白爵士在默认镜头中的待机位置。
var _home := Vector2.ZERO

## 建立不接收游戏输入的独立二维视口。
func _ready() -> void:
	custom_minimum_size = Vector2(STAGE_SIZE)
	size = Vector2(STAGE_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_viewport = SubViewport.new()
	_viewport.size = STAGE_SIZE
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var background_layer := CanvasLayer.new() # 背景固定在视口，同时保留角色部件原有的负层级。
	background_layer.layer = -1
	_viewport.add_child(background_layer)
	_background = TextureRect.new()
	_background.texture = AlmanacCharacterShowPanel.CHARACTER_BG_MAP["Night"]
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.size = Vector2(STAGE_SIZE)
	background_layer.add_child(_background)
	_world = Node2D.new()
	_viewport.add_child(_world)
	_camera = MainGameCamera.new()
	_camera.listen_for_battle_shake = false
	_camera.position = Vector2(STAGE_SIZE) * 0.5
	_world.add_child(_camera)
	set_process(false)

## 切换到 [param type_id]、[param phase]，使用 [param info] 中的实战比例和参数。
func show_boss(type_id: int, phase: int, info: Dictionary) -> void:
	var next_phase: int = clampi(phase, 1, 2) # 按需加载所选阶段，尤其是凯莱赫的全屏图集。
	var path: String = Data.VISUALS[type_id] # 默认沿用该 Boss 的主原画场景。
	if type_id == Data.CAILLEACH and next_phase == 2:
		path = ZB006Cailleach.PHASE_TWO_SCENE_PATH
	var scene := load(path) as PackedScene # 展示场景仅含原画和预览演出。
	if scene == null:
		return
	stop()
	_saviors.clear()
	if is_instance_valid(_actor):
		_world.remove_child(_actor)
		_actor.queue_free()
		_world.remove_child(_effects)
		_effects.queue_free()
	_phase = next_phase
	_visual = scene.instantiate() as Node2D
	_general = _visual as BlackGeneralVisual
	_lantern = _visual as MingLanternPresentation
	_actor = Node2D.new()
	_effects = Node2D.new()
	_world.add_child(_actor)
	_world.add_child(_effects)
	_actor.add_child(_visual)
	if type_id == Data.SAVIOR:
		_show_savior(scene)
		return
	if type_id == Data.CAILLEACH:
		_show_cailleach()
		return
	if _lantern != null:
		_player = null
		_background.texture = load(Data.LANTERN_STAGE) as Texture2D
		_camera.zoom = Vector2(0.5, 0.5)
		_camera_home = Vector2(STAGE_SIZE)
		_camera.position = _camera_home
		_actor.position = Vector2(799, 322)
		_lantern.configure(null, null, Rect2(76, 137, 665, 405))
		_lantern.reset(_phase)
		return
	_background.texture = AlmanacCharacterShowPanel.CHARACTER_BG_MAP["Night"]
	_player = _visual.get_node("AnimationPlayer") as AnimationPlayer
	_player.animation_finished.connect(_on_clip_finished)
	if _general != null:
		_visual.transform = info.visual_transform
		_charge_speed = (info.config as BlackGeneralConfig).charge_speed
		# 剪影、烟带和分路残影需要位于本体后方。
		_actor.z_index = 16
		_general.bind_effects(_actor, _effects, _effects, _camera.shake_once)
		_general.flag_raised.connect(_general.play_flag_flame)
	_visual.set_phase2(_phase == 2)
	_home = Vector2.ZERO
	_idle()
	_frame_character()

## 等比取景；一阶段保留脚点，二阶段完整显示现有半身原画。
func _show_cailleach() -> void:
	_player = null # 两阶段都由 AnimatedSprite2D 播放。
	_background.texture = AlmanacCharacterShowPanel.CHARACTER_BG_MAP["Night"]
	_camera.zoom = Vector2.ONE
	_camera_home = Vector2(STAGE_SIZE) * 0.5
	_camera.position = _camera_home
	var sprite: AnimatedSprite2D = _visual as AnimatedSprite2D # 与实战共用原画场景。
	var frame_size: Vector2 = sprite.sprite_frames.get_frame_texture(&"idle", 0).get_size() # 当前阶段原画单帧尺寸。
	if _phase == 2:
		_actor.position = _camera_home
		_visual.scale = Vector2.ONE * minf(STAGE_SIZE.x / frame_size.x, STAGE_SIZE.y / frame_size.y)
	else:
		_actor.position = Vector2(_camera_home.x, 269.0)
		_visual.scale = Vector2.ONE * (250.0 / frame_size.y)
	sprite.play(&"idle")

## 播放妇人的单次杖击。连点时让当前动作自然回到待机。
func play_staff_tap() -> void:
	var sprite: CailleachVisual = _visual as CailleachVisual # 仅一阶段原画提供杖击。
	if not is_instance_valid(sprite):
		return
	sprite.play_staff_tap()

## 在教堂舞台摆放救主。[param scene] 只含原画，第二阶段用它呈现三位同时施法。
func _show_savior(scene: PackedScene) -> void:
	_player = null # 救主使用 AnimatedSprite2D 的帧信号。
	_background.texture = AlmanacCharacterShowPanel.CHARACTER_BG_MAP["Night"]
	if ResourceLoader.exists(Data.SAVIOR_STAGE): # 发行包未带奇境地图时沿用夜间草坪。
		_background.texture = load(Data.SAVIOR_STAGE) as Texture2D
	_camera.zoom = Vector2.ONE
	_camera_home = Vector2(STAGE_SIZE) * 0.5
	_camera.position = _camera_home
	_actor.position = Vector2(205, 256)
	_saviors.append(_visual as SaviorVisual)
	_visual.scale = Vector2.ONE * (0.65 if _phase == 1 else 0.56)
	if _phase == 1:
		return
	for foot_offset: Vector2 in [Vector2(-118, -16), Vector2(118, 16)]: # 错开分身的脚点，在舞台内保留每张原画的完整轮廓。
		var clone := scene.instantiate() as SaviorVisual # 只创建独立的原画播放节点。
		clone.scale = _visual.scale
		clone.position = foot_offset
		_actor.add_child(clone)
		_saviors.append(clone)

## 黑将军以本体高度取景，战旗只用来限制镜头宽度；本体和特效共用镜头比例。
func _frame_character() -> void:
	var extent: Rect2 = _visual_extent() # 待机全幅，包括可见的旗布。
	if extent.size.x <= 0.0 or extent.size.y <= 0.0:
		return
	if _general != null:
		var body: Rect2 = _visual_extent(func(node: Node) -> bool: return String(node.name).begins_with("HeldFlag")) # 去掉战旗后用于取景的身体。
		var zoom_factor: float = minf(215.0 / maxf(body.size.y, 1.0), 358.0 / extent.size.x) # 尽量用满高度，同时保住旗面。
		var half_width: float = 182.0 / zoom_factor # 预留少量边距，避免旗帜被木框遮住。
		_camera.zoom = Vector2.ONE * zoom_factor
		_camera_home = Vector2(clampf(body.get_center().x, extent.end.x - half_width, extent.position.x + half_width),
			body.get_center().y - 16.0 / zoom_factor)
	else:
		var factor: float = minf(230.0 / extent.size.x, 205.0 / extent.size.y) # 白爵士保留原有构图。
		_visual.scale = Vector2.ONE * factor
		_home = Vector2(STAGE_SIZE.x * 0.5, 268.0) - Vector2(extent.get_center().x, extent.end.y) * factor
		_visual.position = _home
		_camera.zoom = Vector2.ONE
		_camera_home = Vector2(STAGE_SIZE) * 0.5
	_camera.position = _camera_home

## 返回当前骨架在主体坐标中的包围盒，[param skip_branch] 可排除大件道具。
func _visual_extent(skip_branch: Callable = Callable()) -> Rect2:
	var rectangles: Array[Rect2] = [] # 只合并可见骨架精灵的绘制范围。
	Portrait._collect_bounds(_visual.get_node("Body"), _visual.transform, rectangles, skip_branch)
	var extent := Rect2() # 无可见部件时保持空边界。
	for rect: Rect2 in rectangles: # 合并各部件，避免将世界原点算进身体尺寸。
		extent = extent.merge(rect) if extent.has_area() else rect
	return extent

## 从头播放 [param clips]；[param skill_id] 标识需要切换外观和分路出击的转阶段演出。
func play_skill(clips: Array[StringName], skill_id: String = "") -> void:
	if _visual is CailleachVisual:
		if clips.has(&"staff"):
			play_staff_tap()
		else:
			stop()
		return
	stop()
	if not _saviors.is_empty():
		if clips.has(&"teleport_in"):
			_set_savior_arrival(0.0)
			_savior_arrival = create_tween()
			_savior_arrival.tween_method(_set_savior_arrival, 0.0, 1.0, 0.65)
			_savior_arrival.tween_callback(_play_savior_prayer.bind(1.0))
		elif clips.has(&"pray"):
			_play_savior_prayer(0.5 if skill_id == "transition" else 1.0)
		return
	if is_instance_valid(_lantern):
		if not clips.is_empty():
			var change_form: bool = _phase == 2 and skill_id == "tidal" # 从黑暗形态起手，在回场时首次显露星空。
			_lantern.reset(1 if change_form else _phase)
			_lantern.play_action(clips[0], change_form)
		return
	for child: Node in _effects.get_children(): # 重播前清理场地上的旧黑焰、烟带和剪影。
		_effects.remove_child(child)
		child.queue_free()
	_actor.position = Vector2.ZERO
	_camera.position = _camera_home
	_transition = skill_id == "transition"
	if _general != null:
		_general.set_phase2(_phase == 2 and not _transition)
	if _visual is WhiteDukeVisual:
		(_visual.get_node("Phase2FX") as WhiteFlameSpotlightEffect).suspend_for_teleport()
		(_visual.get_node("TeleportFX") as BossTeleportEffect).finish()
	_idle()
	_clips.assign(clips)
	_next_clip()
	set_process(true)

## 以 [param presence]（零至一）推进图鉴显形，沿用实战原画材质。
func _set_savior_arrival(presence: float) -> void:
	var glow: float = maxf(0.0, sin(presence * PI)) * 0.7 # 白光随显形淡入再收束。
	for savior: SaviorVisual in _saviors: # 同步舞台上的所有分身。
		savior.set_teleport_pose(presence, glow)

## 以 [param rate] 倍速播放一次原画祷告，动作结束由原画自行返回待机。
func _play_savior_prayer(rate: float) -> void:
	for savior: SaviorVisual in _saviors: # 同帧开始祷告，复用战斗中的起手和收手。
		if savior.cast_prayer([]) and rate != 1.0:
			savior.play(&"pray", rate)

## 取消动作队列并停止时钟；父页面关闭时也可立即调用。
func stop() -> void:
	_clips.clear()
	_shadows.clear()
	_remaining = -1.0
	set_process(false)
	if _savior_arrival != null:
		_savior_arrival.kill()
		_savior_arrival = null
	for savior: SaviorVisual in _saviors: # 取消尚未完成的祷告并归还传送材质。
		savior.cancel_prayer()
		savior.set_teleport_pose(1.0)
	if is_instance_valid(_visual) and _visual is CailleachVisual:
		(_visual as CailleachVisual).cancel_staff_tap()
	if is_instance_valid(_player):
		_player.stop()
	if is_instance_valid(_general):
		_general.retire_charge_effects()
	if is_instance_valid(_lantern):
		_lantern.reset(_phase)
	if is_instance_valid(_camera):
		_camera.stop_shake()

## 恢复本阶段的原生待机，确保传送中断不会留下透明或隐藏的身体。
func _idle() -> void:
	if _general != null:
		_general.reset_to_idle()
	else:
		_visual.position = _home
		var body := _visual.get_node("Body") as Node2D # 传送中断后恢复身体。
		body.visible = true
		body.modulate.a = 1.0
		body.scale = Vector2.ONE
		var effects := _visual.get_node("Phase2FX") as Node2D # 传送淡出之后恢复阶段特效。
		effects.modulate.a = 1.0
		effects.visible = _phase == 2
		_visual.play_idle()
	_player.advance(0.0)
	_clip = &""

## 播放下一段动作；循环动作在图鉴中演示固定时长，序列结束后回待机。
func _next_clip() -> void:
	if _clips.is_empty():
		_remaining = -1.0
		_idle()
		return
	_clip = _clips.pop_front()
	_player.stop()
	if _general != null:
		if _clip == &"teleport_in":
			_actor.position = Vector2.ZERO
			_camera.position = _camera_home
			_general.set_phase2(_phase == 2)
		_general.play_action(_clip)
		if _clip == &"charge":
			_charge_end_x = _actor.global_position.x - CHARGE_DISTANCE
			_general.begin_charge_effects(_charge_end_x)
			if _transition and _charge_speed > 0.0:
				_begin_charge_shadows()
	elif _clip == &"teleport_in":
		_visual.play_teleport_in()
	elif _clip == &"teleport_out":
		_visual.play_teleport_out()
	elif _clip == &"point":
		_visual.play_summon()
	else:
		_player.play(_clip)
	_player.advance(0.0)
	var animation: Animation = _player.get_animation(_clip) # 动作时长直接取实战资源。
	_looping = animation.loop_mode != Animation.LOOP_NONE
	_duration = 1.6 if _looping else animation.length / maxf(absf(_player.get_playing_speed()), 0.01)
	_remaining = _duration

## [param animation] 已完整结束；让视觉场景先完成传送清理，再推进本次技能序列。
func _on_clip_finished(animation: StringName) -> void:
	if _remaining >= 0.0 and not _looping and animation == _clip:
		_next_clip()

## 用 [param delta] 推进舞台路线和共用演出，单次动画仍由原生结束信号串联。
func _process(delta: float) -> void:
	for index: int in range(_shadows.size() - 1, -1, -1): # 已到终点的分身继续自己的急停与瓦解动画。
		var shadow: BlackGeneralChargeShadow = _shadows[index] # 当前分路的演出实例。
		if shadow.advance_visual(delta, _move_charge_actor):
			_shadows.remove_at(index)
			shadow.finish()
	if _remaining < 0.0:
		set_process(not _shadows.is_empty())
		return
	if _general != null and _clip == &"charge":
		_step_charge(delta)
		return
	_remaining = maxf(0.0, _remaining - delta)
	var progress: float = clampf(1.0 - _remaining / _duration, 0.0, 1.0) # 当前段归一化进度。
	if _clip in [&"run", &"walk"]:
		_actor.position.y = -sin(progress * PI) * 25.0
	if _looping and _remaining <= 0.0:
		_next_clip()

## 用 [param delta] 推进黑将军，以和实战一致的顺序采样、移动、更新烟带、急停。
func _step_charge(delta: float) -> void:
	_general.sample_charge_trail(STAGE_CELL_WIDTH)
	var feet: Vector2 = _actor.global_position # 移动前的脚底位置，用于烟带和起步冲击。
	var reached_end: bool = _move_charge_actor(_actor, delta) # 空跑道只提供停止线。
	_general.advance_charge_effects(feet)
	_camera.position.x = _camera_home.x + _actor.position.x * 0.85
	if reached_end:
		_general.finish_charge_effects()
		_next_clip()

## 以实战速度移动 [param actor]，用 [param step] 个游戏秒接近舞台停止线。
func _move_charge_actor(actor: Node2D, step: float) -> bool:
	actor.global_position.x = move_toward(actor.global_position.x, _charge_end_x, maxf(_charge_speed, 0.0) * step)
	return _charge_speed <= 0.0 or is_equal_approx(actor.global_position.x, _charge_end_x)

## 复用实战分路影子的出场顺序、样式和退场，舞台只提供压缩后的行距。
func _begin_charge_shadows() -> void:
	var interval: float = STAGE_CELL_WIDTH / _charge_speed # 与实战一致，前组每次领先约一格。
	for group: int in range(BlackGeneralChargeShadow.ROWS.size()): # 内侧两路领先外侧两路。
		for row: int in BlackGeneralChargeShadow.ROWS[group]: # 使用实战分组和零起始行号。
			var shadow := BlackGeneralChargeShadow.new() # 原有分路残影脚本。
			var origin: Vector2 = _actor.global_position + Vector2(0.0, (row - 2) * 24.0) # 舞台内压缩分路间距。
			shadow.setup_visual(_actor, _general, _effects, row, origin, (group + 1) * interval)
			_shadows.append(shadow)

## 离开页面时取消尚未播放的动作；所有视觉与粒子随父节点释放。
func _exit_tree() -> void:
	stop()
