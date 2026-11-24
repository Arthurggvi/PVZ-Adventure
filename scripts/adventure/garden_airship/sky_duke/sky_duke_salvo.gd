## 花园飞艇天空层的苍穹公爵齐射，按战斗时钟调度远处的纯视觉弹体和发射声。
extends Node2D

## 单发记录和可复用的绘制缓冲，仅由正式花园飞艇实例持有。
const Visuals := preload("res://scripts/adventure/garden_airship/sky_duke/sky_duke_salvo_visual.gd")
## 关卡原有单声道爆压瞬态，约 0.30 秒，位于现有 SFX 空间声池中。
const LAUNCH_AUDIO: AudioStream = preload("res://assets/adventure/wonderland/battle/garden_airship/audio/burst_impact_r7.ogg")
## 敌舰一侧的可见天空。X/Y 为视口比例，Z 为伪深度，越大越远。
const FLEET: Array[Vector3] = [
	Vector3(0.792, 0.287, 0.63), Vector3(0.871, 0.322, 0.24), Vector3(0.726, 0.321, 0.46),
	Vector3(0.664, 0.294, 0.83), Vector3(0.902, 0.368, 0.37), Vector3(0.756, 0.381, 0.32),
	Vector3(0.833, 0.349, 0.60),
]
## 本局同时持有的发射记录预算，包含尚未点火和已离场的尾迹。
const CAPACITY: int = 7
## 卡顿后允许发射声稍晚补播的战斗秒数。
const AUDIO_GRACE: float = 0.13

## 同一关内一直复用的发射记录池。
var _launches: Array[Visuals.Launch] = []
## 仅供演出布局使用的局内随机数，种子来自号令。
var _rng := RandomNumberGenerator.new()
## 发射光、真导弹纹理和尾迹的绘制缓冲。
var _visuals := Visuals.new()
## 可选的本关现有定位音效入口。
var _audio: GardenAirshipSpatialAudio
## 当前待发射和持有剩余画面尾迹的记录总数。
var _pending_count: int = 0
## 最近一次驱动帧的绝对战斗秒。
var _seconds: float = 0.0
## 最近一次从花园飞艇真实风场取样的世界速度。
var _wind_world := Vector2.ZERO


## 预分配齐射的硬上限，后续每次指天号令只重用空闲记录。
func _init() -> void:
	for _index: int in CAPACITY: # 每个舰队位置都有对应的池容量。
		_launches.append(Visuals.Launch.new())


## 注入 [param audio] 的可听位置映射及 SFX 短声池。
func setup(audio: GardenAirshipSpatialAudio) -> void:
	_audio = audio


## 在 [param seconds] 战斗秒收到指天号令。[param phase] 越高齐射越密。
## [param seed_value] 固定这一轮的时序扰动，[param reduced] 降低二阶段数量和绘制精度。
## 场景同时存在多个事件时，空闲槽优先接纳新点火，旧尾迹可自然散去。
func start(seconds: float, phase: int, seed_value: int, reduced: bool) -> void:
	_rng.seed = seed_value
	var phase_two := phase >= 2 # 一阶段三处短齐射，二阶段分开编队远近。
	var count := 3 # 低画质保留完整的一阶段和较明显的二阶段变化。
	if phase_two:
		count = 5 if reduced else CAPACITY
	var cadence := 0.410 / float(count - 1) if phase_two else 0.096 # 各轮首发约在 E+80ms，二阶段尾发约在 E+500ms。
	var launch_index := 0 # 用成功占用的发射次序读取编队布局。
	for launch: Visuals.Launch in _launches: # 有界扫描，避免重叠时主动删掉前一轮尾迹。
		if launch.active and not launch.is_expired(seconds):
			continue
		if not launch.active:
			_pending_count += 1
		var layout := FLEET[launch_index] # 固定间距上做轻微的 seeded 漂移。
		var bend := _rng.randf_range(-0.83, 0.96) # 上升轨迹的横向推力比例。
		if layout.x >= 0.92:
			bend = -absf(bend) - 0.42 # 敌舰后的航道略向左倾，露出外侧尾流。
		launch.origin_uv = Vector2(layout.x, layout.y) + Vector2(_rng.randf_range(-0.008, 0.008), _rng.randf_range(-0.022, 0.022))
		launch.depth = layout.z
		launch.velocity = Vector2(28.0 * bend, -lerpf(191.0, 134.0, layout.z))
		launch.acceleration = Vector2(169.0 * bend, -lerpf(830.0, 640.0, layout.z))
		launch.ignition_at = seconds + 0.086 + cadence * launch_index + _rng.randf_range(-0.006, 0.009)
		# 远方装饰声错峰减量，真实预警和关卡冲击继续使用自己的保留声部。
		var has_sound := count <= 3 or launch_index % 2 == 0 # 二阶段选择各前后队列的部分发射。
		launch.sound_at = launch.ignition_at + lerpf(0.055, 0.220, layout.z) if has_sound else INF
		launch.phase_two = phase_two
		launch.reduced = reduced
		launch.active = true
		launch_index += 1
		if launch_index == count:
			break


## 按 [param seconds] 战斗秒重算整轮位置；[param wind_world] 是战斗世界像素每秒。
## 落后的声音超过容忍窗口直接丢弃，同一帧最多提交一个远景爆鸣。
func update_frame(seconds: float, wind_world: Vector2) -> void:
	if _pending_count == 0:
		return
	_seconds = seconds
	_wind_world = wind_world
	var audible: Visuals.Launch # 同一帧重叠的声音优先留下较近的一处。
	for launch: Visuals.Launch in _launches: # 到期即回池，不再有音效或绘制活动。
		if not launch.active:
			continue
		if launch.is_expired(seconds):
			launch.active = false
			_pending_count -= 1
			continue
		if seconds >= launch.sound_at:
			if seconds - launch.sound_at <= AUDIO_GRACE and (audible == null or launch.depth < audible.depth):
				audible = launch
			launch.sound_at = INF
	if audible != null and is_instance_valid(_audio):
		_play_launch(audible)
	queue_redraw()


## 返回待发射和还在活动的远景齐射记录数，供导演休眠和预算采样。
func active_count() -> int:
	return _pending_count


## 回收所有发射记录及未发生的声音，已交给局内音频池的短声自然回收。
func clear() -> void:
	for launch: Visuals.Launch in _launches: # 池容量和绘制缓冲仍供本关后续动作复用。
		launch.active = false
	_pending_count = 0
	queue_redraw()


## 用真正的天空画布反变换绘制，保留云和战斗层的原有遮挡。
func _draw() -> void:
	if _pending_count == 0:
		return
	var viewport := get_viewport() # 天空与战斗共用视口，分别使用各自的 Canvas 变换。
	var visible_rect := viewport.get_visible_rect() # 有效逻辑区域，忽略窗口边框。
	var to_sky := get_global_transform_with_canvas().affine_inverse() # 从屏幕回到跟随镜头的天空局部空间。
	var world_to_view := viewport.get_global_canvas_transform() * viewport.get_canvas_transform() # 风量取自实际战斗坐标。
	var wind_on_view := world_to_view.basis_xform(_wind_world).limit_length(220.0) # 仅转换方向和长度，不包含世界平移。
	for launch: Visuals.Launch in _launches: # 未到点火时间的记录只用于排程。
		if launch.active and _seconds >= launch.ignition_at:
			_visuals.draw_launch(self, launch, visible_rect, to_sky, wind_on_view, _seconds - launch.ignition_at)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## 用 [param launch] 的可见发射点提交定位短声，远端更柔和且始终低于实际战斗音效。
func _play_launch(launch: Visuals.Launch) -> void:
	var viewport := get_viewport() # 通过原战斗视口映射回原有声场所接受的世界坐标。
	var screen_to_world := (viewport.get_global_canvas_transform() * viewport.get_canvas_transform()).affine_inverse() # 保留实际听者的声像。
	var source := screen_to_world * launch.on_view(viewport.get_visible_rect()) # 先按视觉锚点定位，再加虚拟声学纵深。
	var gain := lerpf(-16.0, -24.0, launch.depth) # 让远景能量低于正常击毁和攻击音效。
	var pitch := lerpf(0.96, 0.78, launch.depth) # 模拟远端的沉闷小爆压。
	_audio.play_at(LAUNCH_AUDIO, source, gain, pitch, &"sky_duke_far_launch", 4.0 + 9.0 * launch.depth)
