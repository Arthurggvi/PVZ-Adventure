## 花园飞艇独占的定位音效入口，负责实际战斗画布投影与局内音频池。
class_name GardenAirshipSpatialAudio
extends Node3D

## 可见战斗画布到虚拟听者的映射及原生音效标尺。
const Space := preload("res://scripts/adventure/garden_airship/garden_airship_audio_space.gd")
## 有保留槽的定位瞬态池。
const ShortPool := preload("res://scripts/adventure/garden_airship/garden_airship_short_audio_pool.gd")
## 跟随可见锚点的移动声源池。
const MovingPool := preload("res://scripts/adventure/garden_airship/garden_airship_moving_audio_pool.gd")

## 整个关卡共用一个画布坐标采样。
var _space := Space.new()
## 花园飞艇中的瞬态声源。
var _short := ShortPool.new()
## 花园飞艇中的持续位置声源。
var _moving := MovingPool.new()
## SFX 总线可用并完成本局播放器初始化时置位。
var _pools_ready: bool = false
## 本局过程中同时占用的最大声源数，用于采集性能证据。
var _peak_voice_count: int = 0


## 创建音频专用监听视口。私有 World3D 使其它场景的监听器不参与本局混音。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	if AudioServer.get_bus_index(&"SFX") < 0:
		return
	var audio_viewport := SubViewport.new() # 仅用于 Godot 的原生 3D 音频混音，禁止渲染。
	audio_viewport.name = &"AudioSpace"
	audio_viewport.size = Vector2i(2, 2)
	audio_viewport.own_world_3d = true
	audio_viewport.disable_3d = true
	audio_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	audio_viewport.audio_listener_enable_3d = true
	add_child(audio_viewport)
	var camera := Camera3D.new() # 4.7.2 的 3D 音频先枚举活动相机；此节点仅用于登记监听视口。
	camera.cull_mask = 0
	audio_viewport.add_child(camera)
	camera.make_current()
	var listener := AudioListener3D.new() # 固定在音频空间原点并朝向 −Z。
	audio_viewport.add_child(listener)
	listener.make_current()
	_short.setup(audio_viewport)
	_moving.setup(audio_viewport)
	_pools_ready = true


## 场景离树时清除还在播放或等待接管的声音，监听视口随节点树退出。
func _exit_tree() -> void:
	set_process(false)
	_short.clear()
	_moving.clear()


## 用 [param stream] 在 [param world_position] 播放瞬态。该位置是可见锚点的战斗世界坐标。
## [param volume_db] 和 [param pitch] 是本次源增益和音高，[param family] 用于邻近合并。
## [param depth] 是额外虚拟纵深，[param priority] 大于零可占用关键瞬态保留槽。
func play_at(stream: AudioStream, world_position: Vector2, volume_db: float = 0.0,
		pitch: float = 1.0, family: StringName = &"attack", depth: float = 0.0, priority: int = 0) -> void:
	if not _can_play(stream, world_position, volume_db, pitch, depth):
		return
	_space.sample(get_viewport())
	var audio_position := _space.project(world_position, depth) # 一次性捕捉触发当帧位置。
	if audio_position.length_squared() >= Space.HEARING_RANGE * Space.HEARING_RANGE:
		return
	if _short.play(stream, world_position, audio_position, volume_db, pitch, family, priority):
		_note_activity()


## 续约 [param key] 对应的真实声源生命周期。每次更新提交 [param stream] 和实际 [param world_position]。
## [param volume_db] 与 [param pitch] 表达当前源状态，[param depth] 是额外虚拟纵深。
## [param doppler] 控制单路径径向多普勒，[param priority] 提高重要移动声音的选取权重。
## [param start_offset] 是分配新声部时的素材起点秒数；在已播放的声部上保持原进度。
## [param one_shot] 在同一租约只播放一次。[param allow_new] 为否时，已经退出的原身份不得重新占用槽位。
## 返回移动池的实际续约结果。
## 产生方停更、离场或调用 [method end_loop] 时，本池会淡出并释放声部。
func update_loop(key: int, stream: AudioStream, world_position: Vector2, volume_db: float,
		pitch: float = 1.0, depth: float = 0.0, doppler: bool = true, priority: int = 0,
		start_offset: float = 0.0, one_shot: bool = false, allow_new: bool = true) -> MovingPool.Lease:
	if stream == null:
		end_loop(key)
		return MovingPool.Lease.REJECTED
	if not _can_play(stream, world_position, volume_db, pitch, depth) or not is_finite(start_offset):
		return MovingPool.Lease.REJECTED
	_space.sample(get_viewport())
	var lease: MovingPool.Lease = _moving.update(key, stream, _space, world_position, volume_db, pitch, depth,
		doppler, priority, maxf(start_offset, 0.0), one_shot, allow_new) # 只有新获准的实际槽唤醒回收。
	if lease == MovingPool.Lease.STARTED:
		_note_activity()
	return lease


## 结束 [param key] 的生命周期，允许已开始的声音短淡出。
func end_loop(key: int) -> void:
	_moving.end(key)


## 返回当前活动的定位声源数，包括瞬态、持续与正在淡出的声音。
func get_active_voice_count() -> int:
	return _short.active_count() + _moving.active_count()


## 返回本局同时占用声源的峰值，包含瞬态和移动声源。
func get_peak_voice_count() -> int:
	return _peak_voice_count


## 按真实秒处理 [param delta] 内的音频淡变和生命周期；暂停时池跟随场景一同冻结。
func _process(delta: float) -> void:
	var step := minf(delta / maxf(Engine.time_scale, 0.01), 0.12) # 上限避免单次掉帧耗尽整段淡变。
	var active := _short.advance(step) + _moving.advance(step) # 声音自然结束后停止局内维护进程。
	_peak_voice_count = maxi(_peak_voice_count, active)
	if active == 0:
		set_process(false)


## 录入当前活动量，并唤醒有界的池维护。
func _note_activity() -> void:
	if not is_processing():
		set_process(true)
	_peak_voice_count = maxi(_peak_voice_count, get_active_voice_count())


## 确认 [param stream]、[param world_position]、[param volume_db]、[param pitch]、[param depth] 可安全提交给播放器。
func _can_play(stream: AudioStream, world_position: Vector2, volume_db: float, pitch: float, depth: float) -> bool:
	return _pools_ready and is_inside_tree() and can_process() and stream != null \
		and world_position.is_finite() and is_finite(volume_db) and is_finite(pitch) and pitch > 0.0 \
		and is_finite(depth)
