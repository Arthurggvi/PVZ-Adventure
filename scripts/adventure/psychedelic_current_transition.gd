## 致幻洋流阶段表现：巨浪、镜头下沉和陆地布局交接；阶段权威始终属于 Session。
extends AdventurePhasePresentation

## 真实秒数，与战斗倍速无关；全覆盖期间同步换图和地形。
@export var duration: float = 4.8
## 预先随本场景加载的噩梦棋盘，不在浪峰时同步读盘。
@export var nightmare_board: BoardDefinition
## 原始噩梦战场底图。
@export var nightmare_texture: Texture2D
## 原始噩梦天空，始终保留独立图层。
@export var nightmare_sky: Texture2D
## 噩梦地面裂隙、投影和拼接材质。
@export var nightmare_material: ShaderMaterial
## 分层天幕的云缝与翻卷材质。
@export var nightmare_sky_material: ShaderMaterial
## 本场景独占的屏幕折射材质。
@export var wave_material: ShaderMaterial
## 随本场景释放的浪声，遵循现有 SFX 音量总线。
@export var wave_sound: AudioStream
## 巨浪演出是否正在播放，用于预热、续战预检和离场时的画面还原。
var _playing: bool = false
## 同一局战斗及其实际相机。
var game: MainGameManager
## 经过纯预检的布局计划。
var _layout: BoardPhaseLayout
## 全屏折射层，仅演出期间显示。
var _screen: ColorRect
## 每次浪幕读屏前显式复制，兼容背景折射和亮部合成各自的屏幕缓存。
var _screen_copy: BackBufferCopy
## 本地音效播放器。
var _sound: AudioStreamPlayer
## 真实时间演出进度。
var elapsed: float = 0.0
## 当前演出是否已经提交布局，防止重复清列。
var _committed: bool = false
## 开演前的相机偏移，结束或退出时还原。
var _camera_offset := Vector2.ZERO
## 开演前的相机缩放。
var _camera_zoom := Vector2.ONE
## 开演前的相机处理模式，演出期间临时允许暂停时更新。
var _camera_process: Node.ProcessMode
## 统一续战控制器等待此信号，结束后才启动下一阶段敌人。
signal finished

## 构造一次性演出层，保持常态零帧开销。
func _ready() -> void:
	game = get_parent() as MainGameManager
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_screen_copy = BackBufferCopy.new()
	_screen_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_screen_copy)
	_screen = ColorRect.new()
	_screen.name = "WaveScreen"
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.material = wave_material
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	_sound = AudioStreamPlayer.new()
	_sound.stream = wave_sound
	_sound.bus = AudioServer.get_bus_name(SoundManager.Bus.SFX)
	add_child(_sound)
	wave_material.set_shader_parameter("duration", duration)
	set_process(false)
	if AdventureSession.active_phase_kind in [StagePhaseDefinition.Kind.NIGHTMARE, StagePhaseDefinition.Kind.TERMINAL]:
		_apply_nightmare_art() # 正式重开当前阶段时直接使用对应画面，不重播浪卷或重复清列。
	_warm_shader.call_deferred()

## 入场遮幕期间预热屏幕材质，时间零输出原画，避免真正浪峰时首次编译。
func _warm_shader() -> void:
	var warmup := CanvasLayer.new() # 放在两张正式背景背后，首帧遮幕期间完成纹理和材质上传。
	warmup.layer = -12
	game.add_child(warmup)
	for texture: Texture2D in [nightmare_texture, nightmare_sky]: # 不隐藏、不放到视口外，确保实际经过绘制。
		var sprite := Sprite2D.new() # 小尺寸只用于 GPU 首次上传，不修改原图。
		sprite.texture = texture
		sprite.material = nightmare_material if texture == nightmare_texture else nightmare_sky_material
		sprite.scale = Vector2(0.015, 0.015)
		sprite.position = Vector2(32.0, 32.0)
		warmup.add_child(sprite)
	await get_tree().process_frame
	await get_tree().process_frame
	warmup.queue_free()
	if not _playing:
		_screen.hide()
		_screen_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED

## [param phase] 由已有续战控制器传入；资源及布局失败时不消费钥匙、不改场景。
func prepare_phase(phase: StagePhaseDefinition) -> bool:
	if _playing:
		return false
	if phase.kind != StagePhaseDefinition.Kind.NIGHTMARE:
		return true
	if nightmare_texture == null or nightmare_sky == null or nightmare_material == null or nightmare_sky_material == null:
		return false
	_layout = BoardPhaseLayout.prepare(game.board, nightmare_board)
	return _layout != null

## [param phase] 已由 Session 提交；暂停由统一续战控制器持有，本节点只等待演出。
func play_phase(phase: StagePhaseDefinition) -> void:
	if phase.kind != StagePhaseDefinition.Kind.NIGHTMARE:
		return
	_playing = true
	elapsed = 0.0
	_committed = false
	_camera_offset = game.camera_2d.offset
	_camera_zoom = game.camera_2d.zoom
	_camera_process = game.camera_2d.process_mode
	game.camera_2d.process_mode = Node.PROCESS_MODE_ALWAYS
	game.background_manager.transition_phase_environment(phase.environment_profile, true)
	game.hand_manager.curr_hm_status = HandManager.E_HandManagerStatus.Null
	game.hand_manager.curr_plant_cell = null
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.show()
	_screen_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_sound.bus = SoundManager.spatial_sfx_bus(SoundManager.SFXSpace.DISTANT)
	_sound.play()
	set_process(true)
	await finished

## [param delta] 去除战斗倍速，镜头和水幕共享连续真实时间。
func _process(delta: float) -> void:
	elapsed = minf(elapsed + delta / maxf(Engine.time_scale, 0.001), duration)
	wave_material.set_shader_parameter("elapsed", elapsed)
	var swell: float = sin(PI * clampf(elapsed / 2.25, 0.0, 1.0)) # 压下与回稳共用零速端点。
	var plunge: float = smoothstep(0.75, 1.55, elapsed) * (1.0 - smoothstep(1.8, 2.25, elapsed)) # 浪头击中时的下沉权重。
	game.camera_2d.offset = _camera_offset + Vector2(sin(elapsed * 2.0) * 4.0 * swell, -9.0 * swell + plunge * 28.0)
	game.camera_2d.zoom = _camera_zoom * (1.0 + swell * 0.024)
	if not _committed and elapsed >= 2.15:
		_commit_nightmare()
	if elapsed >= duration:
		_screen.hide()
		_screen_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_restore_presentation()
		_playing = false
		set_process(false)
		finished.emit()

## 水墙完全覆盖时同步换图；保留全部有效格子的实体，不重新初始化卡槽或阳光。
func _commit_nightmare() -> void:
	_committed = true
	game.get_node("CurrentEffect").set_process(false)
	_layout.commit()
	_layout = null
	_apply_nightmare_art()
	game.refresh_battle_bgm()

## 续战与当前阶段重开共用夜景表现；棋盘布局由各自的正式入口安装。
func _apply_nightmare_art() -> void:
	game.get_node("CurrentEffect").set_process(false)
	var sea: Sprite2D = game.get_node("CanvasLayerBG/BoardArt") # 子节点就绪早于主管理器，直接取场景内已绑定的美术节点。
	var sky: Sprite2D = game.get_node("CanvasLayerSkybox/Skybox") # 天空保持独立图层。
	sea.texture = nightmare_texture
	sea.material = nightmare_material
	sky.texture = nightmare_sky
	sky.material = nightmare_sky_material
	sky.position = Vector2.ZERO
	game.get_node("NightmareEffect").activate(nightmare_board)
	game.game_para.battle_background_texture = nightmare_texture
	game.get_node("CanvasLayerBG/Background/Home/Area2DHome/CollisionShape2D").position = Vector2(15.07, 500.0)

## 完成或离场均恢复镜头；音乐只由原有阶段曲目选择流程控制。
func _restore_presentation() -> void:
	if is_instance_valid(game) and is_instance_valid(game.camera_2d):
		game.camera_2d.offset = _camera_offset
		game.camera_2d.zoom = _camera_zoom
		game.camera_2d.process_mode = _camera_process

## 离场只回收表现，阶段和暂停由原有退出路径处理。
func _exit_tree() -> void:
	if _playing:
		_restore_presentation()
