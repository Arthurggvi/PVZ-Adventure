## 融合体专属声音；动作组件只发事件，循环与短音效均遵守原战场暂停和音量总线。
extends Node2D
class_name LargeFusionAudio

## 自带交叠接缝的低声滚动素材，运行时仅复制它的循环标记。
const ROLL_STREAM: AudioStreamOggVorbis = preload("res://assets/adventure/zombies/large_fusion/sfx/roll_loop.ogg")
## 事件使用现有音源加工出的短素材，不加载原版完整巨人动作。
const EVENTS: Dictionary[StringName, AudioStream] = {
	&"impact": preload("res://assets/adventure/zombies/large_fusion/sfx/impact.ogg"),
	&"launch": preload("res://assets/adventure/zombies/large_fusion/sfx/launch.ogg"),
	&"land": preload("res://assets/adventure/zombies/large_fusion/sfx/land.ogg"),
	&"split": preload("res://assets/adventure/zombies/large_fusion/sfx/split.ogg"),
	&"death": preload("res://assets/adventure/zombies/large_fusion/sfx/death.ogg"),
	&"exhaust": preload("res://assets/adventure/zombies/large_fusion/sfx/exhaust.ogg"),
}
## 事件音量只影响本次播放器，不修改用户设置或全局总线。
const EVENT_VOLUME: Dictionary[StringName, float] = {
	&"impact": -3.0, &"launch": -9.0, &"land": -3.0,
	&"split": -6.0, &"death": -4.0, &"exhaust": -8.0,
}
## 同类声音的短门禁以真实毫秒计，多个融合体同时分裂也只产生一次清晰反馈。
const EVENT_GAP: Dictionary[StringName, int] = {
	&"impact": 70, &"launch": 90, &"land": 100,
	&"split": 150, &"death": 180, &"exhaust": 160,
}
## 各事件最近一次真正发声的时刻；固定六个键不会随角色数增长。
static var _event_time: Dictionary[StringName, int] = {}
## 声音所属本体，不改变其移动、受击或出生规则。
var _source: Zombie000Base
## 配置时的战场，阻止旧角色声音串入下一局。
var _game: MainGameManager
## 配置时的轮次，续战切换后不再发声。
var _round: int = -1
## 配置时的阶段，跨阶段清场时不再发声。
var _phase: StagePhaseDefinition
## 本体持有的循环播放器，离树时立即停止。
var _roll: AudioStreamPlayer
## 至多三个角色短音效播放器，死亡尾音不在此数组。
var _voices: Array[AudioStreamPlayer] = []
## 同时发声已满时轮换覆盖旧短音，不无限增加声音实例。
var _voice_cursor: int = 0
## 当前循环线性音量，用短淡入淡出避免起停点击。
var _roll_gain: float = 0.0
## 行走状态给出的目标线性音量，空中和耗尽时为零。
var _roll_target: float = 0.0
## 实际移动相对于正常速度的比例，轻微影响滚动声高低。
var _speed_ratio: float = 0.0
## 同一母体只播放一次死亡音，独立于其删除顺序。
var _death_played: bool = false

## 展示实例在明确配置为战斗对象前不创建声音。
func _ready() -> void:
	set_process(false)

## [param source] 是已完成战斗初始化的母体；只保存战局身份，不添加任何游戏计时器。
func configure(source: Zombie000Base) -> void:
	_source = source
	_game = Global.main_game
	if not is_instance_valid(_game) or not is_instance_valid(_source):
		return
	_round = _game.curr_game_round
	_phase = AdventureSession.get_active_phase(_game.game_para)
	if not is_instance_valid(_roll):
		_roll = AudioStreamPlayer.new()
		_roll.name = "FusionRollVoice"
		_roll.stream = ROLL_STREAM.duplicate() as AudioStreamOggVorbis
		(_roll.stream as AudioStreamOggVorbis).loop = true
		_roll.volume_db = -80.0
		add_child(_roll)
	set_process(true)

## [param speed_ratio] 为实测地面速度比例；[param airborne] 和 [param exhausted] 均只关闭滚动声。
func update_roll(speed_ratio: float, airborne: bool, exhausted: bool) -> void:
	_speed_ratio = clampf(absf(speed_ratio), 0.0, 1.6)
	_roll_target = 0.0 if airborne or exhausted else minf(1.0, sqrt(_speed_ratio))
	if _death_played or not is_instance_valid(_source) or _source.is_death:
		_roll_target = 0.0
	elif is_instance_valid(_roll):
		set_process(true)

## [param delta] 使用继承的战斗时间，树暂停时不推进淡入淡出。
func _process(delta: float) -> void:
	if not _active_battle():
		stop_all()
		return
	if _source.is_death or _death_played:
		_roll_target = 0.0
	_roll_gain = move_toward(_roll_gain, _roll_target, delta * 6.0)
	_roll.bus = SoundManager.spatial_sfx_bus()
	_roll.pitch_scale = lerpf(0.88, 1.04, minf(_speed_ratio, 1.0))
	_roll.volume_db = -12.0 + linear_to_db(maxf(_roll_gain, 0.0001))
	if _roll_gain > 0.005 and not _roll.playing:
		_roll.play()
	elif _roll_gain <= 0.005 and _roll.playing:
		_roll.stop()

## [param event] 为六个既定动作键；死亡可以在 is_death 已设定后播放，短门禁防止成批轰炸。
func play_event(event: StringName) -> void:
	if not EVENTS.has(event) or not _active_battle():
		return
	if event == &"death":
		if _death_played:
			return
		_death_played = true
		stop_all()
	elif _source.is_death or _death_played:
		return
	var now: int = Time.get_ticks_msec() # 仅限制同类听觉反馈，不参与游戏伤害与召唤时序。
	if now - int(_event_time.get(event, -10000)) < EVENT_GAP[event]:
		return
	_event_time[event] = now
	if event == &"death":
		# 母体即刻释放后声音继续，由原有池和战场 SFX 路由收尾。
		SoundManager.play_sfx_with_pool(EVENTS[event], EVENT_VOLUME[event], 1.0, false)
		return
	var voice: AudioStreamPlayer = _event_voice() # 私有播放器不会被别的角色重用。
	voice.bus = SoundManager.spatial_sfx_bus()
	voice.stream = EVENTS[event]
	voice.volume_db = EVENT_VOLUME[event]
	voice.pitch_scale = 1.0
	voice.play()

## 停止本体拥有的声音；死亡已交给共享池，不能在此截断或改写其他角色声音。
func stop_all() -> void:
	_roll_gain = 0.0
	_roll_target = 0.0
	if is_instance_valid(_roll):
		_roll.stop()
	for voice: AudioStreamPlayer in _voices: # 只处理本组件创建的短音效播放器。
		voice.stop()
	set_process(false)

## 为下一次短音效复用空闲播放器；最多同时保留三个声音。
func _event_voice() -> AudioStreamPlayer:
	for voice: AudioStreamPlayer in _voices: # 优先保留仍在播放的事件尾音。
		if not voice.playing:
			return voice
	if _voices.size() < 3:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new() # 按需创建，不为每个角色预留三个空播放器。
		add_child(voice)
		_voices.append(voice)
		return voice
	var voice: AudioStreamPlayer = _voices[_voice_cursor] # 忙碌时覆盖最早轮换到的短音。
	_voice_cursor = (_voice_cursor + 1) % _voices.size()
	return voice

## 允许死亡瞬间发声，但拒绝清场、预览、旧轮次和旧阶段的角色。
func _active_battle() -> bool:
	return is_instance_valid(_source) and _source.is_inside_tree() \
		and _source.character_init_type == Character000Base.E_CharacterInitType.IsNorm \
		and not _source.get_tree().paused \
		and not _source.is_queued_for_deletion() and not _source.retiring_from_battle \
		and is_instance_valid(_game) and _game == Global.main_game and _game.is_inside_tree() \
		and not _game.is_queued_for_deletion() and _game.is_ancestor_of(_source) \
		and _game.curr_game_round == _round \
		and AdventureSession.get_active_phase(_game.game_para) == _phase \
		and is_instance_valid(_game.zombie_manager) and _game.zombie_manager.is_game_running()

## 场景清理同步停止循环和私有事件，不遗留看不见的声源。
func _exit_tree() -> void:
	stop_all()
