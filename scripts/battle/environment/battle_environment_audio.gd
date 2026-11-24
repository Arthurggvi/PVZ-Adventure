## 场景拥有的水下音效处理；可覆盖整个 SFX，总线音量设置与音乐始终独立。
extends Node
class_name BattleEnvironmentAudio

## 当前环境的只读参数。
var profile: BattleEnvironmentProfile
## 按近战、远声、环境声顺序记录临时总线名。
var _buses: Array[StringName] = []
## 逐帧平滑的低通实例，不修改全局音频资源。
var _filters: Array[AudioEffectLowPassFilter] = []
## 独立混响实例，接入时从零湿声渐变。
var _reverbs: Array[AudioEffectReverb] = []
## 只供远方氛围声使用的微弱合唱。
var _chorus: AudioEffectChorus
## 安装到共享 SFX 的本场效果实例，退出时按身份移除，保留其他组件的效果。
var _shared_effects: Array[AudioEffect] = []
## 全部音效共同使用的响度补偿，不修改 SFX 总线本身的音量。
var _shared_gain: AudioEffectAmplify
## 循环压力层播放器。
var _pressure: AudioStreamPlayer
## 偶发共鸣播放器。
var _resonance: AudioStreamPlayer
## 防止重复释放总线。
var _disposed: bool = false

## 用 [param next_profile] 建立本场唯一的三个音效通道，重复调用不叠加总线。
func configure(next_profile: BattleEnvironmentProfile) -> void:
	if _disposed or not _buses.is_empty() or next_profile == null:
		return
	profile = next_profile
	var suffix: String = str(get_instance_id()) # 所有权后缀避免场景交接期间重名。
	for label: String in ["Combat", "Distant", "Ambience"]: # 原版前三条总线索引保持不变。
		var index: int = AudioServer.bus_count # 新总线追加，发送方向始终指向左侧的 SFX。
		var bus_name := StringName("Environment%s_%s" % [label, suffix]) # 当前场景专有名字。
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"SFX")
		_buses.append(bus_name)
		var effect_bus: int = AudioServer.get_bus_index(&"SFX") if label == "Combat" and profile.filter_all_sfx else index # 全局模式下近战基础链只运行一次，所有音效都经过它。
		var reverb := AudioEffectReverb.new() # 短预延迟、无早期回声反馈，避免洞穴感。
		reverb.room_size = 0.52 if label == "Ambience" else 0.40
		reverb.predelay_msec = 12.0
		reverb.predelay_feedback = 0.0
		reverb.damping = 0.85
		reverb.spread = 0.65
		reverb.wet = 0.0
		AudioServer.add_bus_effect(effect_bus, reverb)
		if effect_bus != index:
			_shared_effects.append(reverb)
		_reverbs.append(reverb)
		if label == "Ambience":
			_chorus = AudioEffectChorus.new()
			_chorus.wet = 0.0
			_chorus.voice_count = 2
			_chorus.set_voice_rate_hz(0, 0.08)
			_chorus.set_voice_rate_hz(1, 0.11)
			_chorus.set_voice_depth_ms(0, 1.6)
			_chorus.set_voice_depth_ms(1, 2.1)
			AudioServer.add_bus_effect(index, _chorus)
		var lowpass := AudioEffectLowPassFilter.new() # 最后滤除干声与混响尾音中的高频。
		lowpass.cutoff_hz = 20500.0
		lowpass.db = profile.combat_filter_db if label == "Combat" else AudioEffectFilter.FILTER_12DB
		lowpass.resonance = 0.35
		AudioServer.add_bus_effect(effect_bus, lowpass)
		if effect_bus != index:
			_shared_effects.append(lowpass)
			_shared_gain = AudioEffectAmplify.new()
			AudioServer.add_bus_effect(effect_bus, _shared_gain)
			_shared_effects.append(_shared_gain)
		_filters.append(lowpass)
	_pressure = _make_player(profile.pressure_stream)
	_resonance = _make_player(profile.resonance_stream)
	SoundManager.set_environment_routes(self, _buses[0], _buses[1])

## 为 [param stream] 创建场景私有播放器；先静音，避免第一帧响度跳变。
func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new() # 只有两个环境播放器，不加入全局音效池。
	player.stream = stream
	player.bus = _buses[2]
	player.volume_db = -80.0
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player

## [param strength] 为环境渐变；[param event_energy] 与画面共用包络；[param suspended] 只暂停本场音效。
func apply_state(strength: float, event_energy: float, suspended: bool) -> void:
	if _buses.is_empty() or _disposed:
		return
	var cutoffs := Vector3(profile.combat_cutoff_hz, profile.distant_cutoff_hz, profile.ambience_cutoff_hz) # 三类声音分别保留可辨识度。
	for i: int in range(3): # 每类只维护一组效果，和发声对象数量无关。
		_filters[i].cutoff_hz = exp(lerpf(log(20500.0), log(cutoffs[i] * (1.0 - event_energy * 0.10)), strength))
		var inherited_wet: float = profile.reverb_wet.x if profile.filter_all_sfx and i > 0 else 0.0 # 远声与氛围已经过基础混响，只补足各自额外湿声。
		_reverbs[i].wet = maxf(0.0, profile.reverb_wet[i] - inherited_wet) * strength
		AudioServer.set_bus_mute(AudioServer.get_bus_index(_buses[i]), suspended)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(_buses[i]), profile.combat_gain_db * strength if i == 0 and not profile.filter_all_sfx else 0.0)
	if _shared_gain != null:
		_shared_gain.volume_db = profile.combat_gain_db * strength
	_chorus.wet = 0.065 * strength
	_pressure.stream_paused = suspended
	_resonance.stream_paused = suspended
	_pressure.volume_db = profile.pressure_db + linear_to_db(maxf(strength, 0.0001)) + event_energy * 4.0
	_resonance.volume_db = profile.resonance_db + linear_to_db(maxf(strength * event_energy, 0.0001))
	if strength > 0.001 and _pressure.stream != null and not _pressure.playing and not suspended:
		_pressure.play()

## 同一次环境事件触发远方共鸣；[param pitch] 只有极小随机偏差，不影响攻击或音乐。
func begin_event(pitch: float) -> void:
	if is_instance_valid(_resonance) and _resonance.stream != null:
		_resonance.pitch_scale = pitch
		_resonance.play()

## 先撤销路由并停止环境声，再移除自己的总线；允许提前离场与重复调用。
func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	SoundManager.clear_environment_routes(self)
	if is_instance_valid(_pressure):
		_pressure.stop()
	if is_instance_valid(_resonance):
		_resonance.stop()
	var shared_bus: int = AudioServer.get_bus_index(&"SFX") # 共享总线不删除、不改音量，只撤销本场实例。
	if shared_bus >= 0:
		for index: int in range(AudioServer.get_bus_effect_count(shared_bus) - 1, -1, -1): # 倒序移除，其他效果索引可以变化。
			if _shared_effects.has(AudioServer.get_bus_effect(shared_bus, index)):
				AudioServer.remove_bus_effect(shared_bus, index)
	_shared_effects.clear()
	_shared_gain = null
	for bus_name: StringName in _buses: # 使用名字重新查索引，其他音频组件的总线不受影响。
		var index: int = AudioServer.get_bus_index(bus_name) # 删除前确认自己的总线仍存在。
		if index >= 0:
			AudioServer.remove_bus(index)
	_buses.clear()

## 场景退出时同步清理，不将湿声或临时总线留到菜单与其他关卡。
func _exit_tree() -> void:
	dispose()
