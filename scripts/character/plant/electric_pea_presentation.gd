## 电能豌豆的待机变体和原版声音；时间由植株唯一动作时钟提供。
extends RefCounted
class_name ElectricPeaPresentation

## 原版 Attack_Start 事件三选一且不连续重复。
const START_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/attack_start.tres")
## 原版 Attack_Fire 主体声音层三选一且不连续重复，混音中压低于电光层。
const FIRE_BODY_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/attack_fire_body.tres")
## 原版 Attack_Fire 电光声音层三选一且不连续重复，与主体层同时播放。
const FIRE_ZAP_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/attack_fire_zap.tres")
## 原版 Idle_01 的八选一不连续重复声音层。
const IDLE_RANDOM_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/idle.tres")
## 原版 Idle_01 与随机层叠播的固定声音。
const IDLE_FIXED_SOUND: AudioStream = preload("res://assets/adventure/plants/electric_peashooter/audio/idle_9.wav")
## 原版 idle 片段在第二帧播放声音；idle2、idle3的音频事件在原版音库中为空。
const IDLE_SOUND_TIME: float = 2.0 / 30.0

## 当前待机变体剩余的正常动作秒数。
var _idle_remaining: float = 0.0
## 距本次待机声音的正常动作秒数；负一表示该片段没有待播声音。
var _idle_sound_remaining: float = -1.0


## 在 [param animation] 播放待机变体，保留原版49:49:2权重；[param dead] 时不覆盖死亡演出。
func play_idle(animation: AnimationPlayer, dead: bool) -> void:
	if not is_instance_valid(animation) or dead:
		return
	var draw: int = randi_range(0, 99) # 原版 IdleAnimationWeights 的整数权重。
	var clip: StringName = &"idle" if draw < 49 else (&"idle2" if draw < 98 else &"idle3") # 三个原版片段。
	animation.stop()
	animation.play(clip)
	_idle_remaining = animation.get_animation(clip).length
	_idle_sound_remaining = IDLE_SOUND_TIME if clip == &"idle" else -1.0


## [param elapsed] 为正常动作秒；[param audible] 允许播放声音，[param animation] 在片段结束后重新抽取；[param dead] 时保留死亡演出。
func advance_idle(animation: AnimationPlayer, elapsed: float, audible: bool, dead: bool = false) -> void:
	if elapsed <= 0.0 or dead:
		return
	if _idle_sound_remaining >= 0.0:
		_idle_sound_remaining -= elapsed
		if _idle_sound_remaining <= 0.0:
			_idle_sound_remaining = -1.0
			if audible:
				# 待机电流声留在背景，避免多株待机盖过出手提示。
				SoundManager.play_sfx_with_pool(IDLE_RANDOM_SOUND, -30.0)
				SoundManager.play_sfx_with_pool(IDLE_FIXED_SOUND, -20.0)
	_idle_remaining -= elapsed
	if _idle_remaining <= 0.0:
		play_idle(animation, false)


## 播放原版蓄电起手声音。
static func play_start() -> void:
	SoundManager.play_sfx_with_pool(START_SOUND, -12.0)


## 同时播放原版发射主体与电光声音，近距离重叠由音效池处理。
static func play_fire() -> void:
	SoundManager.play_sfx_with_pool(FIRE_BODY_SOUND, -20.0)
	SoundManager.play_sfx_with_pool(FIRE_ZAP_SOUND, -14.0)
