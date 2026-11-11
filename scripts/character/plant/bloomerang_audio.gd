## 回旋镖投掷与命中使用各自的 PvZ2 5.8.1 采样，统一通过战斗音效池播放。
extends RefCounted

## 延迟 400 毫秒播放的投掷声，原 PlantBloomerangAudio 中三选一。
const THROW_SOUND: AudioStream = preload("res://assets/adventure/plants/bloomerang/sfx/attack.tres")
## 原 AudioCommon 的三种命中采样，使用不重复随机播放。
const IMPACT_SOUND: AudioStream = preload("res://assets/adventure/plants/bloomerang/sfx/impact.tres")
## 01、02、03 三个音色档的投掷声基础音高，单位为音分。
const THROW_CENTS := [300.0, 0.0, -300.0]
## 01、02、03 三个音色档的命中声基础音高，单位为音分。
const IMPACT_CENTS := [1010.0, 710.0, 110.0]


## 将 [param profile] 的 0～2、3～5、6 星及以上映射到原版三档；普通卡采用 01 档。
static func tier_for(profile: PlantSpawnProfile) -> int:
	# 冻结的出战星级；无冒险档案时按 0 星处理。
	var stars: int = int(profile.snapshot().get("stars", 0)) if profile != null else 0
	return clampi(floori(stars / 3.0), 0, 2)


## [param tier] 为出战时冻结的音色档。按原事件的延迟在发射前播放，音高浮动 ±150 音分。
static func play_throw(tier: int) -> void:
	SoundManager.play_sfx_with_pool(THROW_SOUND, -7.0,
		_pitch_scale(THROW_CENTS[tier] + randf_range(-150.0, 150.0)), false)


## [param tier] 为发射时冻结的音色档。每次完成伤害结算播放命中声，音高浮动 ±100 音分。
static func play_impact(tier: int) -> void:
	SoundManager.play_sfx_with_pool(IMPACT_SOUND, -6.0,
		_pitch_scale(IMPACT_CENTS[tier] + randf_range(-100.0, 100.0)), false)


## 将 [param cents] 表示的音分换算为 Godot 播放器的频率倍率。
static func _pitch_scale(cents: float) -> float:
	return pow(2.0, cents / 1200.0)
