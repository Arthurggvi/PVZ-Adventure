## 阶段系统驱动的场景环境导演；声画共享时钟与事件，没有独立阶段判断。
extends Node
class_name BattleEnvironmentController

## 当前只读的环境资源，空资源通过离场渐变撤销。
var profile: BattleEnvironmentProfile
## 独立渲染器只处理表现，不持有棋盘或单位。
var renderer: BattleEnvironmentRenderer
## 场景独占的音效处理与氛围声。
var audio: BattleEnvironmentAudio
## 真实秒数，暂停和游戏倍速不会使声画不同步。
var elapsed_seconds: float = 0.0
## 环境最终混合量，用平滑曲线避免进入或退出时跳变。
var strength: float = 0.0
## 声画共用的流光方向、进度和强度。
var current_event := Vector4.ZERO
## 事件宽度与偏移，整次事件保持连续。
var event_shape := Vector2(0.42, 0.0)
## 当前场景专属随机序列，不干扰战斗随机结果。
var _random := RandomNumberGenerator.new()
## 线性阶段权重，输出时转为平滑曲线。
var _blend: float = 0.0
## 正在退出环境时目标为零。
var _leaving: bool = false
## 仅阶段演出可在战斗暂停锁内推进，普通暂停始终冻结。
var _cinematic: bool = false
## 距离下一次候选环境事件的秒数。
var _wait_seconds: float = 4.0
## 当前事件剩余进度所使用的已过秒数；负值表示没有事件。
var _event_elapsed: float = -1.0
## 本次事件总长，避免事件期间重复随机。
var _event_duration: float = 7.0
## 环境流光消退后的短暂视觉余辉，缓慢恢复水体对比，暂停冻结。
var _afterglow: float = 0.0

## [param next_profile] 由已有阶段入口传入；[param background]、[param sky] 只用于渲染绑定。
## [param cinematic] 允许转场持有暂停锁时推进；同一资源重入不重启声音或事件。
func configure(next_profile: BattleEnvironmentProfile, background: Sprite2D, sky: Sprite2D, cinematic: bool = false) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cinematic = cinematic
	_leaving = next_profile == null
	if next_profile == null or next_profile == profile:
		return
	profile = next_profile
	_wait_seconds = profile.first_event_delay
	_random.randomize()
	if is_instance_valid(renderer):
		renderer.queue_free()
	if is_instance_valid(audio):
		audio.dispose()
		audio.queue_free()
	renderer = BattleEnvironmentRenderer.new()
	add_child(renderer)
	renderer.configure(profile, background, sky)
	audio = BattleEnvironmentAudio.new()
	add_child(audio)
	audio.configure(profile)
	apply_environment()

## [param delta] 去除战斗倍速；普通暂停冻结事件并静音本场湿声尾音。
func _process(delta: float) -> void:
	if profile == null:
		return
	if get_tree().paused and not _cinematic:
		apply_environment(true)
		return
	var seconds: float = delta / maxf(Engine.time_scale, 0.001) # 所有听觉、雾场和事件按同一个真实秒数推进。
	elapsed_seconds += seconds
	_blend = move_toward(_blend, 0.0 if _leaving else 1.0, seconds / (profile.exit_seconds if _leaving else profile.enter_seconds))
	strength = smoothstep(0.0, 1.0, _blend)
	if _event_elapsed >= 0.0:
		_event_elapsed += seconds
		var progress: float = clampf(_event_elapsed / _event_duration, 0.0, 1.0) # 缓升、短暂停留、较长消退。
		current_event.z = progress
		current_event.w = smoothstep(0.0, 0.24, progress) * (1.0 - smoothstep(0.47, 1.0, progress))
		if progress >= 1.0:
			_event_elapsed = -1.0
			_wait_seconds = _random.randf_range(profile.event_interval.x, profile.event_interval.y)
	elif not _leaving:
		_wait_seconds -= seconds
		if _wait_seconds <= 0.0:
			if elapsed_seconds < 7.0 or _random.randf() < profile.event_probability:
				begin_current_event()
			else:
				_wait_seconds = _random.randf_range(profile.event_interval.x, profile.event_interval.y)
	_afterglow = lerpf(_afterglow, current_event.w, 1.0 - exp(-seconds / (1.2 if current_event.w > _afterglow else 5.0)))
	apply_environment()
	if _leaving and _blend <= 0.0:
		audio.dispose()
		queue_free()

## 启动一片遥远洋流；同一事件同时触发声场和光场，可供阶段演出复用。
func begin_current_event() -> void:
	if profile == null or _leaving:
		return
	_event_elapsed = 0.0
	_event_duration = _random.randf_range(profile.event_duration.x, profile.event_duration.y)
	var angle: float = _random.randf_range(-0.55, 0.55) + (PI if _random.randf() < 0.5 else 0.0) # 主要横向经过，倾角轻微不同。
	current_event = Vector4(cos(angle), sin(angle), 0.0, 0.0)
	event_shape = Vector2(_random.randf_range(0.34, 0.56), _random.randf_range(-0.12, 0.12))
	audio.begin_event(_random.randf_range(0.97, 1.03))

## 将当前声画状态一起提交；[param suspended] 仅影响环境通道与雾场更新。
func apply_environment(suspended: bool = false) -> void:
	if is_instance_valid(renderer):
		renderer.apply_state(elapsed_seconds, strength, current_event, event_shape, suspended, _afterglow)
	if is_instance_valid(audio):
		audio.apply_state(strength, current_event.w, suspended)
