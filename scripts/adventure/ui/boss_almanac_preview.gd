## Boss 图鉴舞台；仅运行纯视觉场景，子视口隔离白爵士的屏幕特效。
extends SubViewportContainer

## 本页的 Boss 身份与纯视觉场景映射。
const Data = preload("res://scripts/adventure/ui/boss_almanac_data.gd")
## 共用可见精灵的边界计算。
const Portrait = preload("res://scripts/adventure/ui/almanac_preview.gd")
## 黑将军举旗时沿用实战的纯视觉黑焰。
const FlagFlame = preload("res://scripts/character/zombie_boss/002_black_general/black_general_flag_flame.gd")
## 预览视口尺寸，不随图鉴整体缩放而改变动画坐标。
const STAGE_SIZE := Vector2i(390, 300)
## 当前阶段，始终为 1 或 2。
var _phase: int = 1
## 独立视口，屏幕采样只覆盖此区域。
var _viewport: SubViewport
## 角色及一次性视觉特效的共同容器。
var _world: Node2D
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
## 待机基准位置，动画切换后回到该位置。
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
	var background := TextureRect.new() # 背景和角色一起进入子视口，供屏幕特效正确采样。
	background.z_index = -1000
	background.texture = AlmanacCharacterShowPanel.CHARACTER_BG_MAP["Night"]
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.size = Vector2(STAGE_SIZE)
	_viewport.add_child(background)
	_world = Node2D.new()
	_viewport.add_child(_world)
	set_process(false)

## 切换到 [param type_id]、[param phase]；销毁上一位 Boss 的全部预览和待播序列。
func show_boss(type_id: int, phase: int) -> void:
	stop()
	for child: Node in _world.get_children(): # 当前帧移除，避免旧角色和特效短暂重叠。
		_world.remove_child(child)
		child.queue_free()
	_phase = clampi(phase, 1, 2)
	_visual = (Data.VISUALS[type_id] as PackedScene).instantiate() as Node2D
	# 保持视觉节点的两级父结构，适配白爵士传送时的可选影子查找。
	var body := Node2D.new() # 只容纳视觉节点，不挂任何角色脚本。
	_world.add_child(body)
	body.add_child(_visual)
	_player = _visual.get_node("AnimationPlayer") as AnimationPlayer
	_player.animation_finished.connect(_on_clip_finished)
	if _visual is BlackGeneralVisual:
		_visual.flag_raised.connect(_raise_flame)
	_visual.set_phase2(_phase == 2)
	_idle()
	_frame_character()
	set_process(true)

## 在待机首帧计算本体边界，为高举旗帜和位移预留空间。
func _frame_character() -> void:
	var rectangles: Array[Rect2] = [] # 不把聚光灯、传送画布或粒子纳入本体边界。
	Portrait._collect_bounds(_visual.get_node("Body"), Transform2D.IDENTITY, rectangles)
	if rectangles.is_empty():
		return
	var extent: Rect2 = rectangles[0] # 角色原生坐标内可见身体的包围盒。
	for index: int in range(1, rectangles.size()): # 包含盔甲、披风和手持旗帜。
		extent = extent.merge(rectangles[index])
	var factor: float = minf(230.0 / maxf(extent.size.x, 1.0), 205.0 / maxf(extent.size.y, 1.0)) # 上方保留举旗空间。
	_visual.scale = Vector2.ONE * factor
	_home = Vector2(STAGE_SIZE.x * 0.5, 268.0) - Vector2(extent.get_center().x, extent.end.y) * factor
	_visual.position = _home

## 从头播放 [param clips]；重复点击会取消旧动作、清理残留特效并立即重播。
func play_skill(clips: Array[StringName]) -> void:
	stop()
	for child: Node in _world.get_children(): # 只有角色容器需要保留，一次性黑焰立即撤销。
		if child != _visual.get_parent():
			_world.remove_child(child)
			child.queue_free()
	if _visual is WhiteDukeVisual:
		(_visual.get_node("Phase2FX") as WhiteFlameSpotlightEffect).suspend_for_teleport()
		(_visual.get_node("TeleportFX") as BossTeleportEffect).finish()
	_idle()
	_clips.assign(clips)
	_next_clip()
	set_process(true)

## 取消动作队列并停止时钟；父页面关闭时也可立即调用。
func stop() -> void:
	_clips.clear()
	_remaining = -1.0
	set_process(false)
	if is_instance_valid(_player):
		_player.stop()

## 恢复本阶段的原生待机，确保传送中断不会留下透明或隐藏的身体。
func _idle() -> void:
	_visual.position = _home
	var body := _visual.get_node("Body") as Node2D # 动画改变的可见性只属于这个副本。
	body.visible = true
	body.modulate.a = 1.0
	body.scale = Vector2.ONE
	if _visual is BlackGeneralVisual:
		(_visual.get_node("TeleportBlink") as AnimatedSprite2D).hide()
		(_visual.get_node("TeleportRipple") as AnimatedSprite2D).hide()
		_visual.play_action(&"idle")
	else:
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
	_visual.position = _home
	_player.stop()
	if _visual is BlackGeneralVisual:
		_visual.play_action(_clip)
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

## 用 [param delta] 推进演示；仅改变舞台位置，不调用实战移动或命中代码。
func _process(delta: float) -> void:
	if _remaining < 0.0:
		return
	_remaining = maxf(0.0, _remaining - delta)
	var progress: float = clampf(1.0 - _remaining / _duration, 0.0, 1.0) # 当前段归一化进度。
	if _clip == &"charge":
		_visual.position.x = _home.x + lerpf(50.0, -50.0, progress)
	elif _clip in [&"run", &"walk"]:
		_visual.position.y = _home.y - sin(progress * PI) * 25.0
	if _looping and _remaining <= 0.0:
		_next_clip()

## 黑将军的原生举旗关键帧只触发本视口里的黑焰，不连接实战释放函数。
func _raise_flame() -> void:
	FlagFlame.new().ignite(_world, _visual.global_position, 1)

## 离开页面时取消尚未播放的动作；所有视觉与粒子随父节点释放。
func _exit_tree() -> void:
	stop()
