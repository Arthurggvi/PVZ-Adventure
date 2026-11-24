## 单路有界移动声部，平滑位置、增益、距离滤波和美术化多普勒。
extends RefCounted

## 场景空间标尺及距离滤波。
const Space := preload("res://scripts/adventure/garden_airship/garden_airship_audio_space.gd")
## 停止收到源位置后的释放阈值，单位真实秒。
const STALE_SECONDS: float = 0.20
## 取得、回收或替换循环声音的淡变长度，单位真实秒。
const FADE_SECONDS: float = 0.052
## 位置插值的时间常数，单位秒；比音高包络更快跟随高速锚点。
const POSITION_SECONDS: float = 0.024
## 音高、源音量与距离频谱平滑的时间常数，单位秒。
const MIX_SECONDS: float = 0.045
## 美术化声速，单位为虚拟距离每秒。按正常战斗机约 32 世界像素每秒的巡航标定。
const SOUND_SPEED: float = 12.0

## 本槽的原生位置播放节点；没有素材时为闲置。
var player: AudioStreamPlayer3D
## 由产生方绑定至本次生命周期的 ID，槽空闲时不匹配。
var key: int = 0
## 本槽正在淡出，直至节点可重新使用。
var releasing: bool = false
## 用于移动音排序的事件重要性；迭代源更新时可以调整。
var priority: int = 0
## 最新真实锚点对应的虚拟空间位置。
var target_position := Vector3.ZERO
## 当前调用方请求的声源增益，单位 dB。
var target_db: float = 0.0
## 叠加一次有界多普勒后，待平滑的音高倍数。
var _target_pitch: float = 1.0
## 平滑后的源音量，不含声部生命周期淡变，单位 dB。
var _mix_db: float = 0.0
## 当前淡变线性增益，范围 0～1。
var _envelope: float = 0.0
## 最近一次真实更新后经过的有效播放时间，单位秒。
var _age: float = 0.0
## 上次更新的真实世界锚点，用于排除相机位移对速度的影响。
var _previous_world := Vector2.ZERO
## 上次锚点的额外虚拟纵深。
var _previous_depth: float = 0.0
## 最近的有效视口代次，窗口改变时重置速度采样。
var _sample_layout: int = -1
## 上次速度采样的实时时钟，−1 表示新的声源。
var _sample_usec: int = -1
## 新分配时的流起点，单位秒；同一资产的多个推进器可以错开相位。
var _start_offset: float = 0.0
## 瞬态声源自然播完后保留租约直到显式结束，续约不能重新播放。
var _one_shot: bool = false


## 取得闲置槽，绑定 [param token] 对应的 [param stream]，首次播放时从 [param start_offset] 秒起步。
## [param one_shot] 禁止把已经播完的短暂移动余声重新起播。
## 下一次 [method update] 先设置位置、音高与音量，然后由本声部开始淡入。
func reserve(token: int, stream: AudioStream, start_offset: float, one_shot: bool = false) -> void:
	key = token
	_one_shot = one_shot
	player.stream = stream
	var duration := stream.get_length() # 长度已知的素材将起点折回循环范围。
	_start_offset = fposmod(start_offset, duration) if duration > 0.0 else 0.0
	_envelope = 0.0
	_sample_usec = -1
	releasing = false


## 依据 [param world_position]、[param depth] 和 [param space] 追踪可见位置及虚拟距离。
## [param audio_position] 为同帧已投影的位置，[param volume_db] 与 [param pitch] 来自真实源状态。
## [param doppler] 允许径向多普勒，[param source_priority] 供移动池选择当前有代表性的声源。
func update(space: Space, world_position: Vector2, audio_position: Vector3, depth: float,
		volume_db: float, pitch: float, doppler: bool, source_priority: int) -> void:
	var now := Time.get_ticks_usec() # 等效声速采用真实时间，不受引擎倍速反向补偿。
	var elapsed := (now - _sample_usec) * 0.000001 # 采样间隔，单位秒。
	var first := _sample_usec < 0 # 池复用或换流后必须先设置源参数再播放。
	var reset := first or _sample_layout != space.layout_version or elapsed > 0.16 \
		or _previous_world.distance_squared_to(world_position) > pow(maxf(180.0, elapsed * 6200.0), 2.0) \
		or absf(depth - _previous_depth) > 5.0 # 窗口变化、长停顿或非物理跳变不参与多普勒。
	_age = 0.0
	priority = source_priority
	target_position = audio_position
	target_db = volume_db
	if first:
		_mix_db = volume_db
		player.volume_db = volume_db - 70.0
	if reset:
		player.position = audio_position
		player.pitch_scale = pitch
		player.attenuation_filter_cutoff_hz = Space.filter_frequency(audio_position.length())
		_target_pitch = pitch
	elif not doppler:
		_target_pitch = pitch
	elif elapsed >= 0.003:
		var previous := space.project(_previous_world, _previous_depth) # 与最新锚点共享同一帧投影。
		var radial_speed := ((audio_position - previous) / elapsed).dot(audio_position.normalized()) # 正值远离。
		var ratio := SOUND_SPEED / (SOUND_SPEED + clampf(radial_speed, -0.35 * SOUND_SPEED, 0.55 * SOUND_SPEED)) # 分母远离零点。
		_target_pitch = pitch * clampf(ratio, 0.88, 1.15)
	if reset or elapsed >= 0.003:
		_previous_world = world_position
		_previous_depth = depth
		_sample_layout = space.layout_version
		_sample_usec = now
	if first:
		player.play(_start_offset)


## 以 [param delta] 秒推进淡变和平滑。过期或耗尽淡出包络时停止并清理素材。
func advance(delta: float) -> void:
	_age += delta
	if _age > STALE_SECONDS:
		releasing = true
	_envelope = move_toward(_envelope, 0.0 if releasing else 1.0, delta / FADE_SECONDS)
	if releasing and _envelope <= 0.0:
		clear()
		return
	var mix_step := 1.0 - exp(-delta / MIX_SECONDS) # 帧率变化时仍维持一致的听觉变化速率。
	var motion_step := 1.0 - exp(-delta / POSITION_SECONDS) # 连续移动保持声像跟随。
	player.position = player.position.lerp(target_position, motion_step)
	_mix_db = lerpf(_mix_db, target_db, mix_step)
	player.volume_db = _mix_db + linear_to_db(maxf(_envelope, 0.0001))
	player.pitch_scale = lerpf(player.pitch_scale, _target_pitch, mix_step)
	var cutoff := Space.filter_frequency(target_position.length()) # 距离频谱在单个源上变化。
	player.attenuation_filter_cutoff_hz = lerpf(player.attenuation_filter_cutoff_hz, cutoff, mix_step)
	if not _one_shot and not releasing and not player.playing:
		player.play()


## 返回按最新位置和音量估算的排序分数；较近、较重要的声音优先。
func score() -> float:
	return 8.0 * priority - target_position.length() + 0.33 * target_db


## 释放当前素材和播放状态；下一次分配会重置位置和音高采样。
func clear() -> void:
	player.stop()
	player.stream = null
