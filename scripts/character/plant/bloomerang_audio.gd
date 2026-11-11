## PvZ2 5.8.1 的 Play_Plant_Bloomerange_Attack 与 Play_Plant_Bloomerange_Impact。
extends RefCounted

## 延迟 400 毫秒播放的投掷声，原 PlantBloomerangAudio 中三选一。
const ATTACK = preload("res://assets/adventure/plants/bloomerang/sfx/attack.tres")
## 原 AudioCommon 的三种命中采样，使用不重复随机播放。
const IMPACT = preload("res://assets/adventure/plants/bloomerang/sfx/impact.tres")
## Plant_Level_02 起手时播放的第一层采样。
const PREPARE_TIER_02 = preload("res://assets/adventure/plants/bloomerang/sfx/prepare_tier_02.tres")
## Plant_Level_03 起手时播放的第一层采样。
const PREPARE_TIER_03 = preload("res://assets/adventure/plants/bloomerang/sfx/prepare_tier_03.tres")
## 两个高阶起手事件共用的第二层采样。
const PREPARE_SHARED = preload("res://assets/adventure/plants/bloomerang/sfx/prepare_shared.tres")
## 01、02、03 三个音色档的投掷声基础音高，单位为音分。
const ATTACK_CENTS := [300.0, 0.0, -300.0]
## 01、02、03 三个音色档的命中声基础音高，单位为音分。
const IMPACT_CENTS := [1010.0, 710.0, 110.0]


## 将 [param profile] 的 0～2、3～5、6 星及以上映射到原版三档；普通卡采用 01 档。
static func tier_for(profile: PlantSpawnProfile) -> int:
	# 冻结的出战星级；无冒险档案时按 0 星处理。
	var stars: int = int(profile.snapshot().get("stars", 0)) if profile != null else 0
	return clampi(floori(stars / 3.0), 0, 2)


## [param tier] 为出战时冻结的音色档。02、03 档在开始预攻击时叠加两层音效。
static func play_prepare(tier: int) -> void:
	if tier == 0:
		return
	# 第三档将两层音效整体降低 300 音分。
	var pitch: float = _pitch_scale(ATTACK_CENTS[tier])
	SoundManager.play_sfx_with_pool(PREPARE_TIER_02 if tier == 1 else PREPARE_TIER_03, -5.0, pitch, false)
	SoundManager.play_sfx_with_pool(PREPARE_SHARED, -5.0, pitch, false)


## [param tier] 为出战时冻结的音色档。按原事件的延迟在发射前播放，音高浮动 ±150 音分。
static func play_attack(tier: int) -> void:
	SoundManager.play_sfx_with_pool(ATTACK, -7.0,
		_pitch_scale(ATTACK_CENTS[tier] + randf_range(-150.0, 150.0)), false)


## [param tier] 为发射时冻结的音色档。一次有效碰撞播放一层原版命中声，音高浮动 ±100 音分。
static func play_impact(tier: int) -> void:
	SoundManager.play_sfx_with_pool(IMPACT, -6.0,
		_pitch_scale(IMPACT_CENTS[tier] + randf_range(-100.0, 100.0)), false)


## 将 [param cents] 表示的音分换算为 Godot 播放器的频率倍率。
static func _pitch_scale(cents: float) -> float:
	return pow(2.0, cents / 1200.0)
