## 苍穹公爵的前景战斗机编队。按战斗时钟调度一组固定的纯表现槽。
extends Node2D

## [param world] 为经过中心时的真实世界位置，[param strength] 为视觉风压，范围 0 到 1。
signal passed(world: Vector2, strength: float)

## 单架的透视航迹、机体和凝结尾流。
const Aircraft := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_flyby_plane.gd")
## 沿用现有桌面后台及 Android 分帧资源读取。
const ArtBatch := preload("res://scripts/ui/transitions/resource_load_batch.gd")
## 复用真实战斗机的循环转声和本关已有的近身破风声。
const PROPELLER := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/engine_mono_r5.ogg")
## 近机使用短样本，每架仍只申请一个移动声部。
const PASS := preload("res://assets/adventure/wonderland/battle/garden_airship/audio/flyby_r5.ogg")
## 给演出移动声部分配独立的递减编号，避开常驻风声、载具爆炸和实际实体。
const FIRST_VOICE_KEY: int = -2000000

## 五个按由远至近排列的固定槽位，整场复用。
var _planes: Array[Aircraft] = []
## 只用于该次编队形状的随机序列，不参与战斗随机。
var _rng := RandomNumberGenerator.new()
## 本局现有的移动声部池和监听位置。
var _audio: GardenAirshipSpatialAudio
## 由本节点驱动、挂在正式世界画布的掠影画笔。
var _shadows: Node2D
## 原战斗机的单帧机体，从相同的原画坐标采样。
var _body: Texture2D
## 原战斗机独立的旋翼贴图。
var _rotor: Texture2D
## 只在首次入场时预取两张实际飞机零件纹理。
var _art_batch: ArtBatch
## 下一次租约分配时使用的唯一编号。
var _next_voice: int = FIRST_VOICE_KEY
## 当前视口的实际逻辑画幅，不包含操作系统边框。
var _view: Rect2
## 真实战斗世界到逻辑视口，用于采样脱离的尾流、声像和环境扰动。
var _view_from_world := Transform2D.IDENTITY
## 逻辑视口到实际跟随镜头的前景画布局部坐标。
var _air_from_view := Transform2D.IDENTITY
## 从当前编队启动起累计的世界风位移，单位为世界像素。
var _wind_travel := Vector2.ZERO
## 编队上帧的绝对战斗时间，用于累计实际风位移。
var _last_seconds: float = 0.0

## Boss 出场时预备 [param audio]、共享贴图和固定槽位。[param shadow_host] 位于正式战斗世界画布。
func setup(audio: GardenAirshipSpatialAudio, shadow_host: Node2D) -> void:
	_audio = audio
	if _planes.is_empty():
		_art_batch = ArtBatch.new()
		if _art_batch.start(PackedStringArray([Aircraft.BODY_PATH, Aircraft.ROTOR_PATH])) != OK:
			_art_batch = null
		for lane: int in Aircraft.LANE_Y.size(): # 每条虚拟纵深只占一个固定槽。
			_planes.append(Aircraft.new(lane))
		z_index = 8
	if is_instance_valid(shadow_host) and not is_instance_valid(_shadows):
		_shadows = Node2D.new()
		_shadows.name = &"SkyDukeFlybyShadows"
		_shadows.z_as_relative = false
		_shadows.z_index = -2
		_shadows.draw.connect(_draw_shadows)
		shadow_host.add_child(_shadows)
## [param _delta] 不推进战斗时钟。该节点只在预取期间独立轮询素材。
func _process(_delta: float) -> void:
	if _art_batch != null:
		var state: int = _art_batch.poll() # 多平台共用相同的加载状态。
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			_body = _art_batch.get_resource(Aircraft.BODY_PATH) as Texture2D
			_rotor = _art_batch.get_resource(Aircraft.ROTOR_PATH) as Texture2D
		_cancel_art_batch()
	set_process(false)

## 在绝对战斗时刻 [param seconds] 排定 [param phase] 对应的编队。
## [param seed_value] 固定当次轨迹和错峰，[param reduced] 降低并发和遮挡。
func start(seconds: float, phase: int, seed_value: int, reduced: bool) -> void:
	if (_body == null and _art_batch == null) or not is_finite(seconds):
		return
	if active_count() == 0:
		_wind_travel = Vector2.ZERO
		_last_seconds = seconds
	_rng.seed = seed_value
	var count: int = 1 # 一阶段只有一架。二阶段覆盖远近两端。
	if phase >= 2:
		count = _rng.randi_range(2, 3) if reduced else _rng.randi_range(4, 5)
	var first_lane: int = 1 if count == 2 else 0 # 两架回退档从画面下缘和上缘各经过一次。
	for order: int in count: # 依次从不同高度进入，活动槽不会被重叠的效果替换。
		var lane: int = first_lane + roundi(float(order * (_planes.size() - 1 - first_lane)) / maxi(1, count - 1)) # 均分所选虚拟纵深。
		var plane: Aircraft = _planes[lane] # 每条航迹复用对应的机位。
		if plane.active:
			continue
		var entry: float = seconds + 0.052 + 0.086 * order + _rng.randf_range(-0.008, 0.008) # 经过错峰由本次种子控制。
		plane.begin(entry, _next_voice, _rng, reduced)
		_next_voice -= 1

## 采样战斗时刻 [param seconds]，以 [param wind_world] 的世界像素/战斗秒推进脱离尾流。
func update_frame(seconds: float, wind_world: Vector2) -> void:
	if active_count() == 0 or not is_inside_tree() or not is_finite(seconds):
		return
	if seconds < _last_seconds:
		clear()
		return
	var viewport: Viewport = get_viewport() # 镜头、前景和空间声共用正式战斗视口。
	_view = viewport.get_visible_rect()
	if _view.size.x <= 0.0 or _view.size.y <= 0.0:
		return
	var canvas: Transform2D = viewport.get_global_canvas_transform() # 在不同画层共同应用的逻辑画布变换。
	_view_from_world = canvas * viewport.get_canvas_transform()
	_air_from_view = (canvas * get_global_transform_with_canvas()).affine_inverse()
	var world_from_view: Transform2D = _view_from_world.affine_inverse() # 喷口记录以及声像的反向投影。
	_wind_travel += wind_world * (seconds - _last_seconds)
	_last_seconds = seconds
	for plane: Aircraft in _planes: # 仅有五个候选槽，闲置槽无需求轨迹。
		if not plane.active:
			continue
		plane.sample_frame(seconds, _view, world_from_view, _wind_travel)
		if plane.finished():
			plane.active = false
		_update_audio_and_pass(plane, world_from_view)
	queue_redraw()
	if is_instance_valid(_shadows):
		_shadows.queue_redraw()

## 返回已占用的机位数，包括待入场和只剩脱离尾流的机位。
func active_count() -> int:
	var count: int = 0 # 当前占用量，硬上限为固定机位数。
	for plane: Aircraft in _planes: # 逐槽统计以同步外部调度诊断。
		count += int(plane.active)
	return count

## 清空本组画面和尚未进入的航迹，已获准声音由原移动池短淡出。
func clear() -> void:
	for plane: Aircraft in _planes: # 航迹和尾流缓冲保留供下一次命令复用。
		_end_voice(plane)
		plane.active = false
	queue_redraw()
	if is_instance_valid(_shadows):
		_shadows.queue_redraw()

## 退出时归还所有声部，移除挂在独立世界画布的掠影画笔。
func _exit_tree() -> void:
	clear()
	_cancel_art_batch()
	if is_instance_valid(_shadows):
		_shadows.draw.disconnect(_draw_shadows)
		_shadows.hide()
		_shadows.queue_free()
		_shadows = null
	_planes.clear()
	_audio = null
	_body = null
	_rotor = null

## 离场的结果不会再回灌到这个编队。
func _cancel_art_batch() -> void:
	if _art_batch != null:
		_art_batch.abandon()
		_art_batch = null

## 凝结尾先提交，后按虚拟深度从远到近绘制机体，始终低于官方 HUD。
func _draw() -> void:
	for plane: Aircraft in _planes: # 每架的喷口尾迹保持在机体后方。
		if plane.active:
			plane.draw_trail(self, _air_from_view, _view_from_world, _wind_travel)
	if _body == null:
		return
	for plane: Aircraft in _planes: # 近机可以短暂挡住较远机体。
		if plane.active and plane.crossing():
			plane.draw_plane(self, _air_from_view, _body, _rotor)

## 在正式战斗画布绘制压扁的短掠影。与前景各自使用自己的画布逆变换。
func _draw_shadows() -> void:
	if _body == null:
		return
	var canvas: Transform2D = get_viewport().get_global_canvas_transform() # 与前景采用同一逻辑像素坐标。
	var shadow_from_view: Transform2D = (canvas * _shadows.get_global_transform_with_canvas()).affine_inverse() # 掠影只写入世界图层。
	for plane: Aircraft in _planes: # 不为尾流和待出场的飞机投影。
		if plane.active and plane.crossing():
			plane.draw_shadow(_shadows, shadow_from_view, _body, _view)

## [param plane] 横越的时候更新声源，过中心只发出一次表现风压。[param world_from_view] 还原真实世界位置。
func _update_audio_and_pass(plane: Aircraft, world_from_view: Transform2D) -> void:
	if not plane.did_pass and plane.progress >= 0.5:
		plane.did_pass = true
		if plane.progress <= 1.15: # 超长掉帧只让位置追赶，不集中补播已经过去的冲击。
			passed.emit(world_from_view * plane.screen_pose(0.5, _view).origin, plane.pass_strength())
	if not plane.active or not plane.crossing():
		_end_voice(plane)
		return
	if not is_instance_valid(_audio):
		return
	var proximity: float = sin(PI * plane.progress) # 听点附近达到一次局部响度峰值。
	var near: bool = plane.depth >= 0.5 # 近机用现有短掠风，外围编队用正常战斗机桨声。
	var stream: AudioStream = PASS if near else PROPELLER # 一架仅租用一路。
	var gain: float = lerpf(-18.0, -7.5, plane.depth) - 24.0 * (1.0 - proximity) # 远侧入场离场自然收声。
	var pitch: float = plane.voice_pitch * lerpf(1.16, 0.91, smoothstep(0.34, 0.67, plane.progress)) # 高速镜前轨道直接取连续多普勒曲线。
	var depth: float = lerpf(3.5, 0.25, plane.depth) + 1.1 * (1.0 - proximity) # 随近距程度改变原池的声像和高频衰减。
	var offset: float = (0.036 if near else plane.voice_offset) + plane.progress * plane.duration # 跳帧时从对应年龄起播。
	var world: Vector2 = world_from_view * (plane.pose * Aircraft.ROTOR_CENTER) # 声源跟随机头，不使用 HUD 坐标。
	var lease: int = _audio.update_loop(plane.voice_key, stream, world, gain, pitch, depth, false, 0,
		offset, near, not plane.leased) # 使用解析多普勒时关闭池内速度估算，已接受的音色不重起。
	plane.leased = plane.leased or lease > 0

## 归还 [param plane] 的移动声部，池接管最后几十毫秒的音频淡出。
func _end_voice(plane: Aircraft) -> void:
	if plane.leased and is_instance_valid(_audio):
		_audio.end_loop(plane.voice_key)
		plane.leased = false
